-- TESTS/public_api_spec.lua — the plugin's own front door.
--
-- `diff.status()` was the only thing in `lua/diff/init.lua` with a test.
-- `setup()`/`enable()` (and their once-only guard), the five delegating
-- wrappers, `core.clear`, `core.valid_lists`, the view=/output= validation
-- messages, `features.exit.exit()`, `view=float`, and the quickfix targets
-- `output=stat` produces had none. All of them are reachable headlessly.
--
-- Runs late in the suite on purpose: `setup()` latches a module-local
-- `_setup_done` and registers real commands and keymaps, which is exactly what
-- it is supposed to do -- just not to the specs that come before it.

return function(H)
  local eq, ok = H.eq, H.ok
  local diff = require("diff")
  local core = require("diff.core")
  local config = require("diff.config")
  local scratch = require("diff.core.scratch")

  ---@param fn fun(): nil
  ---@return string[]
  local function notices(fn)
    local out = {}
    local saved = vim.notify
    -- Test double over a typed surface; restored before returning.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      out[#out + 1] = tostring(msg)
    end
    local call_ok, err = pcall(fn)
    vim.notify = saved
    ok(call_ok, "call did not throw: " .. tostring(err))
    return out
  end

  ---@return integer
  local function diffmode_window_count()
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and vim.wo[w].diff then
        n = n + 1
      end
    end
    return n
  end

  local function reset()
    scratch.cleanup_all()
    vim.cmd("silent! only")
  end

  -- core.valid_lists ---------------------------------------------------------
  -- The one accessor with no in-repo caller (health.lua and usrcmds.lua each
  -- re-declare the same two lists). It is public API, so it is pinned against
  -- what those duplicates actually accept -- if the lists drift apart, this is
  -- where it shows.
  do
    local views, outputs = core.valid_lists()
    eq(table.concat(views, ","), "vsplit,split,inline,tab,float", "the accepted view= values")
    eq(
      table.concat(outputs, ","),
      "buffer,prompt,file,clipboard,stat",
      "the accepted output= values"
    )
  end

  -- Invalid view=/output= ----------------------------------------------------
  do
    reset()
    for _, case in ipairs({
      { args = "view=sideways target=clipboard", key = "view", bad = "sideways" },
      { args = "output=telepathy target=clipboard", key = "output", bad = "telepathy" },
    }) do
      local seen, calls = nil, 0
      local msgs = notices(function()
        core.run(case.args, nil, {
          on_done = function(result, err)
            calls = calls + 1
            seen = { result = result, err = err }
          end,
        })
      end)
      eq(calls, 1, case.key .. ": on_done fires exactly once")
      eq(seen.result, nil, case.key .. ": nothing was produced")
      eq(seen.err, "invalid view= or output=", case.key .. ": the caller hears why")
      local joined = table.concat(msgs, "\n")
      ok(joined:find(case.bad, 1, true) ~= nil, case.key .. ": the rejected value is quoted back")
      ok(
        joined:find("valid:", 1, true) ~= nil,
        case.key .. ": with the list of accepted values (got: " .. joined .. ")"
      )
    end
  end

  -- core.clear ----------------------------------------------------------------
  do
    reset()
    local origin_win = vim.api.nvim_get_current_win()
    scratch.create({ "a" }, "[Diff] clear-a")
    scratch.create({ "b" }, "[Diff] clear-b")
    require("diff.util.diffmode").set(origin_win, true)

    local msgs = notices(core.clear)
    eq(scratch.active_count(), 0, "clear() empties the registry")
    eq(diffmode_window_count(), 0, "clear() leaves no diffmode behind")
    ok(table.concat(msgs, "\n"):find("Diff cleared", 1, true) ~= nil, "clear() says it is done")

    -- Clearing when nothing is active is inert, not an error.
    local again = notices(core.clear)
    ok(table.concat(again, "\n"):find("Diff cleared", 1, true) ~= nil, "clear() is idempotent")
  end

  -- features.exit.exit() ------------------------------------------------------
  do
    local exit = require("diff.features.exit")

    -- nothing in diffmode anywhere
    reset()
    local msgs = notices(exit.exit)
    ok(
      table.concat(msgs, "\n"):find("Not in diff mode", 1, true) ~= nil,
      "with no diff anywhere, exit() says so rather than staying silent"
    )

    -- the current window is in diffmode
    reset()
    local win = vim.api.nvim_get_current_win()
    require("diff.util.diffmode").set(win, true)
    local quiet = notices(exit.exit)
    eq(diffmode_window_count(), 0, "exit() turns diffmode off")
    eq(#quiet, 0, "and does so without a notification")

    -- a *different* window is in diffmode: exit() still offers to clear it,
    -- which is the whole point of the global-scope exit key.
    reset()
    local first = vim.api.nvim_get_current_win()
    vim.cmd("silent! vsplit")
    local second = vim.api.nvim_get_current_win()
    require("diff.util.diffmode").set(first, true)
    ok(not vim.wo[second].diff, "the window we are standing in is not in diffmode")
    notices(exit.exit)
    eq(diffmode_window_count(), 0, "exit() clears a stray diff in another window too")
    reset()
  end

  -- features.exit.attach_buffer before setup() --------------------------------
  -- The cached config is nil until exit.setup() ran; attaching then has to be
  -- a no-op rather than an index-a-nil-value.
  do
    package.loaded["diff.features.exit"] = nil
    local fresh_exit = require("diff.features.exit")
    local buf = H.scratch()
    local call_ok = pcall(fresh_exit.attach_buffer, buf)
    ok(call_ok, "attach_buffer() before setup() is inert, not an error")
    eq(#vim.api.nvim_buf_get_keymap(buf, "n"), 0, "and binds nothing")
  end

  -- view=float ----------------------------------------------------------------
  -- The one view the rest of the suite never opens. It shares the inline
  -- renderer but puts the buffer in a floating window with its own quit keys.
  do
    reset()
    config.setup({})
    local a = H.scratch()
    vim.api.nvim_buf_set_lines(a, 0, -1, false, { "one", "two" })
    local b = H.scratch()
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "one", "TWO" })

    local seen, calls = nil, 0
    notices(function()
      core.run(string.format("source=%d target=%d view=float", a, b), nil, {
        on_done = function(result, err)
          calls = calls + 1
          seen = { result = result, err = err }
        end,
      })
    end)
    eq(calls, 1, "view=float completes exactly once")
    ok(seen.result ~= nil, "and produces a result")
    eq(seen.result.view, "float", "which names its own view=")
    eq(#seen.result.buffers, 1, "one buffer: the unified diff itself")
    eq(#seen.result.windows, 1, "and one window")

    local win = seen.result.windows[1]
    ok(vim.api.nvim_win_is_valid(win), "the reported window handle is real")
    eq(
      vim.api.nvim_win_get_config(win).relative,
      "editor",
      "view=float really opens a floating window, not a split"
    )
    eq(vim.bo[seen.result.buffers[1]].filetype, "diff", "the float holds a ft=diff buffer")
    local text =
      table.concat(vim.api.nvim_buf_get_lines(seen.result.buffers[1], 0, -1, false), "\n")
    ok(text:find("@@", 1, true) ~= nil, "and a real unified diff")

    -- Closing everything reported takes the whole thing back down.
    for _, w in ipairs(seen.result.windows) do
      pcall(vim.api.nvim_win_close, w, true)
    end
    for _, buf in ipairs(seen.result.buffers) do
      scratch.discard(buf)
    end
    eq(scratch.active_count(), 0, "the reported handles are enough to undo a float diff")
    reset()
  end

  -- output=stat's quickfix targets -------------------------------------------
  -- `stat_list_target` decides whether a stat entry is jump-able. A file path
  -- resolves to an absolute filename, a buffer number to that buffer, and the
  -- specifiers with no on-disk identity of their own to nothing at all --
  -- still listed, just not jump-able.
  do
    reset()
    local src = H.scratch()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { "one", "two" })

    local file = H.tmpdir() .. "stat-target.txt"
    H.write_file(file, { "one", "TWO" })

    local function stat_entries(args)
      vim.fn.setqflist({}, "r", { items = {} })
      config.setup({ diff = { stat_list = "qf", stat_list_mode = "replace" } })
      notices(function()
        core.run(args)
      end)
      local qf = vim.fn.getqflist()
      config.setup({})
      return qf
    end

    local by_file = stat_entries(string.format("source=%d target=%s output=stat", src, file))
    ok(#by_file > 0, "a file target produces stat entries")
    eq(by_file[1].valid, 1, "a file target's entry is jump-able")
    -- Canonicalized on both sides, not just normalized: the buffer name is
    -- whatever spelling nvim settled on, `file` is the raw tempname() one,
    -- and on macOS those differ by /var vs /private/var. See H.canonical.
    eq(
      H.canonical(vim.api.nvim_buf_get_name(by_file[1].bufnr)),
      H.canonical(file),
      "and points at the file that was diffed -- both spellings canonicalized alike"
    )

    local tgt_buf = H.scratch()
    vim.api.nvim_buf_set_lines(tgt_buf, 0, -1, false, { "one", "TWO" })
    local by_buf = stat_entries(string.format("source=%d target=%d output=stat", src, tgt_buf))
    ok(#by_buf > 0, "a buffer-number target produces stat entries")
    eq(by_buf[1].bufnr, tgt_buf, "and the entry carries that exact buffer")

    vim.fn.setreg("+", "one\nTWO")
    local by_clip = stat_entries(string.format("source=%d target=clipboard output=stat", src))
    ok(#by_clip > 0, "a clipboard target is still listed")
    eq(by_clip[1].bufnr, 0, "but has no buffer of its own to jump to")
    ok(by_clip[1].text:find("@@", 1, true) ~= nil, "the hunk header is still in the entry text")

    vim.fn.setqflist({}, "r", { items = {} })
    reset()
  end

  -- The delegating wrappers ---------------------------------------------------
  do
    local saved = {
      run = core.run,
      run_buffers = core.run_buffers,
      clear = core.clear,
    }
    local calls = {}
    -- Test doubles over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core.run = function(raw, range, opts)
      calls.run = { raw = raw, range = range, opts = opts }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    core.run_buffers = function(raw, opts)
      calls.run_buffers = { raw = raw, opts = opts }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    core.clear = function()
      calls.clear = (calls.clear or 0) + 1
    end

    local marker = function() end
    diff.run("target=clipboard", { on_done = marker })
    eq(calls.run.raw, "target=clipboard", "diff.run forwards its args")
    eq(calls.run.range, nil, "diff.run never carries a range -- it is not a range command")
    eq(calls.run.opts.on_done, marker, "diff.run forwards on_done untouched")

    diff.run()
    eq(calls.run.raw, "", "diff.run() with no args forwards an empty string, not nil")

    diff.diff_buffers("view=tab", { on_done = marker })
    eq(calls.run_buffers.raw, "view=tab", "diff.diff_buffers forwards its args")
    eq(calls.run_buffers.opts.on_done, marker, "...and its on_done")
    diff.diff_buffers()
    eq(calls.run_buffers.raw, "", "diff.diff_buffers() with no args forwards an empty string")

    diff.clear()
    eq(calls.clear, 1, "diff.clear reaches core.clear")

    core.run, core.run_buffers, core.clear = saved.run, saved.run_buffers, saved.clear
  end

  do
    local origin = require("diff.features.origin")
    local exit = require("diff.features.exit")
    local saved_origin, saved_exit = origin.run, exit.exit
    local n_origin, n_exit = 0, 0
    -- Test doubles over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    origin.run = function()
      n_origin = n_origin + 1
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    exit.exit = function()
      n_exit = n_exit + 1
    end
    diff.diff_origin()
    diff.exit()
    eq(n_origin, 1, "diff.diff_origin reaches features.origin")
    eq(n_exit, 1, "diff.exit reaches features.exit")
    origin.run, exit.exit = saved_origin, saved_exit
  end

  -- status() edge cases -------------------------------------------------------
  do
    reset()
    eq(diff.status(), "", "status is empty with nothing tracked")
    scratch.create({ "x" }, "[Diff] status-probe")
    eq(diff.status(), "diff:1", "the default prefix")
    eq(
      diff.status({ prefix = "" }),
      "1",
      "an empty prefix is honoured, not replaced by the default"
    )
    ---@diagnostic disable-next-line: param-type-mismatch
    eq(diff.status({ prefix = 42 }), "diff:1", "a non-string prefix falls back to the default")
    ---@diagnostic disable-next-line: param-type-mismatch
    eq(diff.status("nonsense"), "diff:1", "a non-table opts falls back to the default")
    reset()
  end

  -- setup() -------------------------------------------------------------------
  -- Last, because it latches. `vim.g.loaded_diff` is the guard everything else
  -- (health, the plugin file) keys off.
  do
    vim.g.loaded_diff = nil
    notices(function()
      diff.setup({ diff = { ctxlen = 7 }, use_pickers_nvim = false })
    end)
    eq(vim.g.loaded_diff, 1, "setup() sets the loaded guard")
    eq(config.get().diff.ctxlen, 7, "setup() merged the user options")
    ok(vim.api.nvim_get_commands({}).Diff ~= nil, "setup() registered the commands")

    -- The first call wins: a second setup() (or enable(), its alias) must not
    -- re-merge, or a lazy-loaded caller could silently reset a user's config.
    notices(function()
      diff.setup({ diff = { ctxlen = 99 } })
    end)
    eq(config.get().diff.ctxlen, 7, "a second setup() is a no-op, the first call wins")
    notices(function()
      diff.enable({ diff = { ctxlen = 123 } })
    end)
    eq(config.get().diff.ctxlen, 7, "enable() is the same entry point and is latched too")

    config.setup({})
    eq(config.get().diff.ctxlen, 3, "config.setup itself is not latched -- only diff.setup() is")
  end

  reset()
  config.setup({})
end

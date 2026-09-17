-- TESTS/on_done_spec.lua — the `on_done` completion contract of the
-- programmatic entry points (`require("diff").run` / `.diff_buffers`).
--
-- The contract an integrating plugin relies on: on_done fires exactly once on
-- every path, success or not; `result.windows` lists only windows diff.nvim
-- opened, never the caller's own; and closing everything in `result.windows`
-- plus wiping `result.buffers` takes the diff back down.

return function(H)
  local eq, ok = H.eq, H.ok
  local core = require("diff.core")
  local render = require("diff.core.render")
  local scratch = require("diff.core.scratch")
  local config = require("diff.config")

  local saved_notify = vim.notify

  local function reset()
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    vim.cmd("silent! diffoff!")
  end

  local function silence()
    -- Test double over a typed surface; taken down again by `guarded`.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
  end

  ---Run `fn` with the doubles installed and always take them down again.
  ---A plain assign/restore pair leaves the double in place when something
  ---between them throws, and every later spec then runs against this spec's
  ---stub -- one real failure plus a page of unrelated noise.
  ---@param fn fun(): any
  ---@return any
  local function guarded(fn)
    local okc, res = pcall(fn)
    vim.notify = saved_notify
    if not okc then
      error(res, 0)
    end
    return res
  end

  ---Run `args` and collect what on_done was handed. Notifications are silenced
  ---for the duration and restored even when an assertion below throws.
  ---@param args string
  ---@param range? DiffNvim.Range
  ---@return table  # { calls = integer, result = DiffNvim.Result|nil, err = string|nil }
  local function run(args, range)
    local seen = { calls = 0 }
    local okc, err = pcall(function()
      -- Test double over a typed surface; restored right below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function() end
      core.run(args, range, {
        on_done = function(result, e)
          seen.calls = seen.calls + 1
          seen.result = result
          seen.err = e
        end,
      })
    end)
    vim.notify = saved_notify
    if not okc then
      error(err, 0)
    end
    return seen
  end

  local a = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(a, 0, -1, false, { "one", "two" })
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "one", "TWO" })

  -- Every output= reports completion, even the ones that open nothing -------
  for _, output in ipairs({ "prompt", "clipboard", "stat" }) do
    reset()
    H.scratch()
    local seen = run(string.format("source=%d target=%d output=%s", a, b, output))
    eq(seen.calls, 1, output .. ": on_done fired exactly once")
    ok(seen.result ~= nil, output .. ": reported a result, not a failure")
    eq(seen.result.output, output, output .. ": the result names its own output=")
    eq(#seen.result.buffers, 0, output .. ": created no buffers")
    eq(#seen.result.windows, 0, output .. ": opened no windows")
  end

  -- output=file hands back the path it wrote --------------------------------
  reset()
  H.scratch()
  local file_seen = run(string.format("source=%d target=%d output=file", a, b))
  eq(file_seen.calls, 1, "output=file: on_done fired exactly once")
  ok(type(file_seen.result.path) == "string", "output=file: the written path is reported")
  ok(vim.fn.filereadable(file_seen.result.path) == 1, "output=file: that path is readable")

  -- view=vsplit: both sides ours, the caller's window untouched -------------
  reset()
  local origin_buf = H.scratch()
  local origin_win = vim.api.nvim_get_current_win()
  local seen = run(string.format("source=%d target=%d view=vsplit", a, b))
  eq(seen.calls, 1, "vsplit: on_done fired exactly once")
  eq(seen.result.view, "vsplit", "vsplit: the result names its own view=")
  eq(#seen.result.buffers, 2, "vsplit: both materialized sides are reported")
  eq(#seen.result.windows, 2, "vsplit: both opened windows are reported")
  for _, win in ipairs(seen.result.windows) do
    ok(win ~= origin_win, "vsplit: the caller's own window is not in result.windows")
  end

  -- ...and the reported handles are enough to take the diff back down.
  for _, win in ipairs(seen.result.windows) do
    pcall(vim.api.nvim_win_close, win, true)
  end
  for _, buf in ipairs(seen.result.buffers) do
    scratch.discard(buf)
  end
  eq(#vim.api.nvim_list_wins(), 1, "vsplit: closing result.windows leaves one window")
  eq(vim.api.nvim_win_get_buf(origin_win), origin_buf, "vsplit: the caller's buffer survived")
  eq(scratch.active_count(), 0, "vsplit: discarding result.buffers leaves nothing tracked")

  -- source=current keeps the origin window out of the result ---------------
  reset()
  local live = H.scratch()
  vim.api.nvim_buf_set_lines(live, 0, -1, false, { "live" })
  local live_win = vim.api.nvim_get_current_win()
  local tgt_file = vim.fn.tempname()
  vim.fn.writefile({ "on disk" }, tgt_file)

  local cur = run(string.format("target=%s view=vsplit", tgt_file))
  eq(#cur.result.buffers, 1, "source=current: only the target side is ours")
  eq(#cur.result.windows, 1, "source=current: only the window we opened is reported")
  ok(cur.result.windows[1] ~= live_win, "source=current: the live window is not reported")
  ok(vim.wo[live_win].diff, "source=current: the live window is still part of the diff")
  scratch.cleanup_all()

  -- view=inline reports its single buffer and window ------------------------
  reset()
  H.scratch()
  local inline = run(string.format("source=%d target=%d view=inline", a, b))
  eq(inline.calls, 1, "inline: on_done fired exactly once")
  eq(#inline.result.buffers, 1, "inline: the unified-diff buffer is reported")
  eq(#inline.result.windows, 1, "inline: its window is reported")
  eq(vim.bo[inline.result.buffers[1]].filetype, "diff", "inline: that buffer is the diff buffer")
  scratch.cleanup_all()

  -- Identical sides: a result with nothing in it, not a failure -------------
  reset()
  H.scratch()
  local same = run(string.format("source=%d target=%d view=inline", a, a))
  eq(same.calls, 1, "identical sides: on_done still fired exactly once")
  ok(same.result ~= nil, "identical sides: reported as a result, not an error")
  eq(#same.result.buffers, 0, "identical sides: nothing was created")

  -- Failures report through on_done too ------------------------------------
  reset()
  H.scratch()
  local missing = run("target=/definitely/not/a/real/file.lua")
  eq(missing.calls, 1, "unresolvable target: on_done fired exactly once")
  eq(missing.result, nil, "unresolvable target: no result")
  ok(type(missing.err) == "string", "unresolvable target: a reason is given")

  reset()
  H.scratch()
  local rejected = run(string.format("source=%d base=%s target=%s", a, tgt_file, tgt_file))
  eq(rejected.calls, 1, "rejected combination: on_done fired exactly once")
  eq(rejected.result, nil, "rejected combination: no result")
  ok(
    rejected.err:find("source=current", 1, true) ~= nil,
    "rejected combination: the reason is the one that was notified"
  )

  -- A three-way diff reports its two scratch buffers and two windows --------
  reset()
  H.scratch()
  local base_file = vim.fn.tempname()
  vim.fn.writefile({ "base" }, base_file)
  local three = run(string.format("base=%s target=%s", base_file, tgt_file))
  eq(three.calls, 1, "three-way: on_done fired exactly once")
  eq(#three.result.buffers, 2, "three-way: base and target buffers are reported")
  eq(#three.result.windows, 2, "three-way: the origin window is not reported as ours")
  scratch.cleanup_all()

  -- A render that cannot happen fails loudly and leaves nothing behind -------
  -- side_by_side runs its splits under `silent!`, which suppresses the
  -- message but not the error: a wiped buffer handle raises E86 into Lua.
  -- That used to escape every cleanup path at once -- no scratch buffers
  -- discarded, no on_done, and for view=tab a fresh tabpage left open.
  reset()
  H.scratch()
  for _, view in ipairs({ "vsplit", "tab" }) do
    local tabs_before = #vim.api.nvim_list_tabpages()
    local tracked_before = scratch.active_count()
    local doomed = scratch.create({ "gone" }, "[Diff:target] doomed " .. view)
    vim.api.nvim_buf_delete(doomed, { force = true })

    local okc, windows = pcall(render.side_by_side, vim.api.nvim_get_current_win(), doomed, view)
    ok(okc, view .. ": a failed render returns instead of raising")
    eq(windows, nil, view .. ": a failed render reports nothing was opened")
    eq(#vim.api.nvim_list_tabpages(), tabs_before, view .. ": no tabpage is left behind")
    scratch.discard(doomed)
    eq(scratch.active_count(), tracked_before, view .. ": nothing stays tracked")
  end

  -- output=file distinguishes "nothing to write" from "could not write" ------
  reset()
  H.scratch()
  local real_tempname = vim.fn.tempname
  local write_fail = guarded(function()
    silence()
    -- Somewhere no file can be created, so writefile fails for real.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.tempname = function()
      return "Z:/definitely/not/writable/diff-nvim-probe"
    end
    local probe = { calls = 0 }
    core.execute(
      { source = tostring(a), target = tostring(b), view = "vsplit", output = "file" },
      { source_bufnr = vim.api.nvim_get_current_buf(), origin_win = vim.api.nvim_get_current_win() },
      function(result, e)
        probe.calls = probe.calls + 1
        probe.result, probe.err = result, e
      end
    )
    vim.fn.tempname = real_tempname
    return probe
  end)
  eq(write_fail.calls, 1, "output=file write failure: on_done fired exactly once")
  eq(write_fail.result, nil, "output=file write failure: reported as a failure, not a result")
  ok(type(write_fail.err) == "string", "output=file write failure: a reason is given")

  -- ...while identical sides stay a successful, empty result.
  reset()
  H.scratch()
  local no_diff = run(string.format("source=%d target=%d output=file", a, a))
  ok(no_diff.result ~= nil, "output=file with no differences: still a result, not a failure")
  eq(no_diff.result.path, nil, "output=file with no differences: no path was written")

  -- on_done fires once even when a picker calls back more than once ----------
  -- `select_fn` is third-party; kit_confirm_select already normalizes callback
  -- shapes for it. A picker that answers twice used to produce one `fail` from
  -- run()'s guard and one `done` from execute's -- two separate guards.
  reset()
  H.scratch()
  local cfg = config.get()
  local prev_select = cfg.select_fn
  local double_tgt = vim.fn.tempname()
  vim.fn.writefile({ "target" }, double_tgt)
  local double = { calls = 0 }
  guarded(function()
    silence()
    cfg.select_fn = function(items, _, cb)
      cb(nil, nil)
      cb(items[1], 1)
    end
    core.run("target=ask", nil, {
      on_done = function()
        double.calls = double.calls + 1
      end,
    })
  end)
  cfg.select_fn = prev_select
  eq(double.calls, 1, "a picker answering twice still produces exactly one on_done")
  scratch.cleanup_all()

  -- A throwing on_done is reported, not swallowed ---------------------------

  reset()
  H.scratch()
  local threw = false
  local notes = {}
  local okc = pcall(function()
    -- Test double over a typed surface; restored right below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m)
      notes[#notes + 1] = m
    end
    core.run(string.format("source=%d target=%d view=inline", a, b), nil, {
      on_done = function()
        threw = true
        error("caller blew up")
      end,
    })
  end)
  vim.notify = saved_notify
  ok(threw, "a throwing on_done was still called")
  ok(okc, "a throwing on_done does not propagate out of the diff")
  local reported = false
  for _, m in ipairs(notes) do
    if tostring(m):find("on_done failed", 1, true) then
      reported = true
    end
  end
  ok(reported, "a throwing on_done is reported rather than swallowed")
  scratch.cleanup_all()

  reset()
  for _, bufnr in ipairs({ a, b }) do
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end

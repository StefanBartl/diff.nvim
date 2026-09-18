-- TESTS/bindings_spec.lua — the wiring layer: bindings/usrcmds.lua,
-- bindings/autocmds.lua and the bindings/init.lua orchestrator.
--
-- keymaps_spec.lua covers the keymap half. The other three modules had no
-- assertions at all, which meant nothing checked that :Diff is actually
-- registered, that a switched-off feature really leaves its commands absent,
-- that a renamed command is the name that appears, that :Diff forwards a range
-- (and only a real one), or that the VimLeavePre cleanup fires exactly once
-- after repeated setup() calls.
--
-- Every command here is driven through the real `:` command line, so what is
-- asserted is what a user types -- not a direct call to the route's `run`.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")

  ---Delete any of diff.nvim's commands that currently exist, under any of the
  ---names this spec uses, so each case starts from a known state and nothing
  ---leaks into the specs that run after it.
  local ALL_NAMES = {
    "Diff",
    "DiffClear",
    "DiffBuffers",
    "DiffOrig",
    "DiffExit",
    "MyDiff",
    "MyDiffClear",
    "MyDiffBuffers",
    "MyDiffOrig",
    "MyDiffExit",
  }
  local function clear_commands()
    for _, n in ipairs(ALL_NAMES) do
      pcall(vim.api.nvim_del_user_command, n)
    end
  end

  ---@return table<string, boolean>
  local function existing()
    local cmds = vim.api.nvim_get_commands({})
    local out = {}
    for _, n in ipairs(ALL_NAMES) do
      out[n] = cmds[n] ~= nil
    end
    return out
  end

  ---Register with a config built on top of the real defaults.
  ---@param overrides table
  ---@return table cfg
  local function register(overrides)
    clear_commands()
    local cfg = config.setup(overrides)
    require("diff.bindings.usrcmds").register(cfg)
    return cfg
  end

  -- All five commands exist with the default config --------------------------
  do
    register({})
    local have = existing()
    for _, n in ipairs({ "Diff", "DiffClear", "DiffBuffers", "DiffOrig", "DiffExit" }) do
      ok(have[n], n .. " is registered with the default config")
    end
  end

  -- features.diff = false drops the three commands it gates ------------------
  -- ...and leaves the two independent ones alone: each feature gate owns its
  -- own commands, so switching one off must not take the others with it.
  do
    register({ features = { diff = false } })
    local have = existing()
    eq(have.Diff, false, "features.diff=false leaves :Diff unregistered")
    eq(have.DiffClear, false, "features.diff=false leaves :DiffClear unregistered")
    eq(have.DiffBuffers, false, "features.diff=false leaves :DiffBuffers unregistered")
    ok(have.DiffOrig, ":DiffOrig has its own gate and survives")
    ok(have.DiffExit, ":DiffExit has its own gate and survives")
  end

  do
    register({ features = { diff_origin = false } })
    eq(existing().DiffOrig, false, "features.diff_origin=false leaves :DiffOrig unregistered")
    ok(existing().Diff, "...without touching :Diff")
  end

  do
    register({ features = { diff_exit = false } })
    eq(existing().DiffExit, false, "features.diff_exit=false leaves :DiffExit unregistered")
    ok(existing().Diff, "...without touching :Diff")
  end

  -- Command names are configurable, one by one -------------------------------
  do
    register({
      commands = {
        diff = "MyDiff",
        diff_clear = "MyDiffClear",
        diff_buffers = "MyDiffBuffers",
        diff_orig = "MyDiffOrig",
        diff_exit = "MyDiffExit",
      },
    })
    local have = existing()
    for _, n in ipairs({ "MyDiff", "MyDiffClear", "MyDiffBuffers", "MyDiffOrig", "MyDiffExit" }) do
      ok(have[n], n .. " is registered under its configured name")
    end
    eq(have.Diff, false, "the default name is not registered alongside the configured one")
  end

  -- :Diff accepts a range, and forwards only a *real* one ---------------------
  -- `ctx.range.range` is 0 when no range was typed, in which case line1/line2
  -- both hold the cursor line and would silently narrow the source side to a
  -- single line. Driven through the real command line, since that is the only
  -- place `range` gets its 0/1/2 value from.
  do
    register({})
    local core = require("diff.core")
    local saved_run = core.run
    local seen
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core.run = function(raw, range)
      seen = { raw = raw, range = range }
    end

    vim.cmd("silent! only")
    vim.cmd("silent! enew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "l1", "l2", "l3", "l4", "l5" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    vim.cmd("Diff target=clipboard")
    eq(seen.range, nil, "no range typed -> core.run gets nil, not the cursor line")
    eq(seen.raw, "target=clipboard", "the raw args reach core.run verbatim")

    vim.cmd("2,4Diff target=clipboard view=inline")
    ok(seen.range ~= nil, "a typed range reaches core.run")
    eq(seen.range.line1, 2, "range start")
    eq(seen.range.line2, 4, "range end")
    eq(seen.raw, "target=clipboard view=inline", "args and range arrive together")

    -- No args at all still dispatches, with an empty string.
    seen = nil
    vim.cmd("Diff")
    ok(seen ~= nil, ":Diff with no arguments still dispatches")
    eq(seen.raw, "", "an argument-less :Diff hands core.run an empty string")

    core.run = saved_run
  end

  -- :DiffBuffers forwards its args; :DiffClear calls clear ------------------
  do
    register({})
    local core = require("diff.core")
    local saved_buffers, saved_clear = core.run_buffers, core.clear
    local seen_args, cleared = nil, 0
    -- Test doubles over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core.run_buffers = function(raw)
      seen_args = raw
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    core.clear = function()
      cleared = cleared + 1
    end

    vim.cmd("DiffBuffers view=tab output=stat")
    eq(seen_args, "view=tab output=stat", ":DiffBuffers forwards its raw args")
    vim.cmd("DiffClear")
    eq(cleared, 1, ":DiffClear reaches core.clear exactly once")

    core.run_buffers = saved_buffers
    core.clear = saved_clear
  end

  -- :DiffOrig and :DiffExit reach their features -----------------------------
  do
    register({})
    local origin = require("diff.features.origin")
    local exit = require("diff.features.exit")
    local saved_origin, saved_exit = origin.run, exit.exit
    local origin_calls, exit_calls = 0, 0
    -- Test doubles over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    origin.run = function()
      origin_calls = origin_calls + 1
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    exit.exit = function()
      exit_calls = exit_calls + 1
    end

    vim.cmd("DiffOrig")
    vim.cmd("DiffExit")
    eq(origin_calls, 1, ":DiffOrig reaches features.origin.run")
    eq(exit_calls, 1, ":DiffExit reaches features.exit.exit")

    origin.run = saved_origin
    exit.exit = saved_exit
  end

  -- register() is re-runnable ------------------------------------------------
  do
    register({})
    local before = vim.api.nvim_get_commands({}).Diff
    local again_ok = pcall(require("diff.bindings.usrcmds").register, config.get())
    ok(again_ok, "registering twice does not throw")
    ok(vim.api.nvim_get_commands({}).Diff ~= nil, ":Diff still exists after a second register()")
    ok(before ~= nil, "and existed before it")
  end

  -- bindings/autocmds.lua ----------------------------------------------------
  do
    local autocmds = require("diff.bindings.autocmds")
    local scratch = require("diff.core.scratch")

    ---@return integer
    local function count()
      local ok_get, got = pcall(vim.api.nvim_get_autocmds, { group = "diff_cleanup" })
      return ok_get and #got or 0
    end

    autocmds.register()
    eq(count(), 1, "register() installs exactly one VimLeavePre autocmd")

    -- The whole reason the augroup is created with clear=true by hand rather
    -- than through lib.nvim's cached `autocmd.group()`: re-running setup()
    -- must not stack a second copy of the same cleanup.
    autocmds.register()
    autocmds.register()
    eq(count(), 1, "re-registering does not stack duplicate autocmds")

    local got = vim.api.nvim_get_autocmds({ group = "diff_cleanup" })
    eq(got[1].event, "VimLeavePre", "the event is VimLeavePre")

    -- Firing it really does wipe the tracked buffers, without touching
    -- diffmode (Neovim tears that down on exit itself).
    scratch.cleanup_all()
    vim.cmd("silent! only")
    local origin_win = vim.api.nvim_get_current_win()
    require("diff.util.diffmode").set(origin_win, true)
    local buf = scratch.create({ "x" }, "[Diff] autocmd-wipe")
    vim.api.nvim_exec_autocmds("VimLeavePre", { group = "diff_cleanup" })
    eq(vim.api.nvim_buf_is_valid(buf), false, "VimLeavePre wipes the tracked scratch buffer")
    eq(scratch.active_count(), 0, "and empties the registry")
    ok(vim.wo[origin_win].diff, "VimLeavePre does not touch diffmode")
    require("diff.util.diffmode").set(origin_win, false)
  end

  -- bindings/init.lua: the orchestrator wires all four layers ----------------
  do
    clear_commands()
    pcall(vim.api.nvim_del_augroup_by_name, "diff_cleanup")
    pcall(vim.api.nvim_del_augroup_by_name, "diff_native_diffthis")

    local cfg = config.setup({
      exit = { key = "<C-q><C-q>", scope = "global", native_diffthis = true },
      keymaps = { diff_clear = "<Plug>(diff-bindings-spec-clear)" },
    })
    require("diff.bindings").register(cfg)

    ok(vim.api.nvim_get_commands({}).Diff ~= nil, "register() registered the user commands")
    eq(
      #vim.api.nvim_get_autocmds({ group = "diff_cleanup" }),
      1,
      "register() installed the cleanup autocmd"
    )

    -- exit.setup() with scope="global" binds the exit key globally...
    local global_maps = vim.api.nvim_get_keymap("n")
    local found_exit, found_shortcut = false, false
    for _, m in ipairs(global_maps) do
      if m.lhs == "<C-Q><C-Q>" or m.lhs == "<C-q><C-q>" then
        found_exit = true
      end
      if m.lhs == "<Plug>(diff-bindings-spec-clear)" then
        found_shortcut = true
      end
    end
    ok(found_exit, "register() bound the global exit key")
    ok(found_shortcut, "register() bound the declared shortcut")

    -- ...and native_diffthis registers its OptionSet watcher, since
    -- scope="global" turns that one off, so this must be absent here.
    local nd_ok, nd = pcall(vim.api.nvim_get_autocmds, { group = "diff_native_diffthis" })
    ok((not nd_ok) or #nd == 0, "native_diffthis stays out of it while exit.scope is global")

    pcall(vim.keymap.del, "n", "<C-q><C-q>")
    pcall(vim.keymap.del, "n", "<Plug>(diff-bindings-spec-clear)")
  end

  -- features.diff_exit = false skips the exit wiring entirely ----------------
  do
    clear_commands()
    local cfg = config.setup({
      features = { diff_exit = false },
      exit = { key = "<C-u><C-u>", scope = "global" },
    })
    require("diff.bindings").register(cfg)
    local found = false
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if m.lhs == "<C-U><C-U>" or m.lhs == "<C-u><C-u>" then
        found = true
      end
    end
    eq(found, false, "features.diff_exit=false binds no exit key at all")
  end

  -- An unknown diff.diffopt_profile must not abort the rest of register() --
  -- regression: M.setup() flips _setup_done=true BEFORE calling
  -- bindings.register(), so an uncaught error from this one call used to
  -- skip register_shortcuts()/autocmds.register() below it AND make every
  -- later setup() call a silent no-op for the whole session (verified
  -- against the pre-fix code: nvim_get_autocmds({group='diff_cleanup'})
  -- raised "Invalid group" afterward, and a second, corrected setup() call
  -- still did not create it).
  do
    clear_commands()
    pcall(vim.api.nvim_del_augroup_by_name, "diff_cleanup")
    local cfg = config.setup({ diff = { diffopt_profile = "no_such_profile" } })

    local reg_ok = pcall(require("diff.bindings").register, cfg)
    ok(reg_ok, "register() itself must not throw on an unknown diffopt_profile")
    eq(
      #vim.api.nvim_get_autocmds({ group = "diff_cleanup" }),
      1,
      "the cleanup autocmd still gets installed after the bad profile"
    )
  end

  -- Leave the process with the default wiring in place, so later specs see
  -- the same commands a real session would.
  clear_commands()
  config.setup({})
  require("diff.bindings.usrcmds").register(config.get())
  require("diff.core.scratch").cleanup_all()
  vim.cmd("silent! only")
end

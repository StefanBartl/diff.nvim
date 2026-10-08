-- TESTS/setup_retry_spec.lua -- a setup() that raised does not latch diff.nvim.
--
-- diff/init.lua used to set its once-only `_setup_done` flag BEFORE it ran config.setup() and
-- bindings.register(). Any throw from either left the plugin half wired and made every later
-- setup() a silent no-op for the rest of the session (that is how `commands = 1` and a
-- non-table `keymaps` took the plugin down before their own fixes). The flag is now set after
-- both steps completed: the error is re-raised, a retry runs again from the start, and the first
-- call that COMPLETES is the one that wins.
--
-- The throw is injected, so the spec holds for whatever the next bad value turns out to be.
--
-- A fresh copy of `diff` per case, because the latch of the real module cannot be undone.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")
  local bindings = require("diff.bindings")

  -- The `gh` peek is not what this spec is about, and a second register() would only warn about it.
  local QUIET = { gitsigns_peek = false }

  local original_diff = package.loaded["diff"]
  local original_register = bindings.register
  local original_config_setup = config.setup
  local saved_first_run = vim.g.lib_nvim_deps_disable_first_run
  local saved_loaded = vim.g.loaded_diff

  ---@return table
  local function fresh_diff()
    package.loaded["diff"] = nil
    vim.g.loaded_diff = nil
    return require("diff")
  end

  local function has_command()
    return vim.api.nvim_get_commands({}).Diff ~= nil
  end

  local function clear()
    pcall(vim.api.nvim_del_user_command, "Diff")
    pcall(vim.api.nvim_del_user_command, "DiffClear")
    pcall(vim.api.nvim_del_user_command, "DiffBuffers")
    pcall(vim.api.nvim_del_user_command, "DiffOrig")
    pcall(vim.api.nvim_del_user_command, "DiffHistory")
    pcall(vim.api.nvim_del_user_command, "DiffExit")
    pcall(vim.api.nvim_del_user_command, "DiffProfile")
    pcall(vim.api.nvim_del_augroup_by_name, "diff_cleanup")
  end

  local function restore()
    bindings.register = original_register
    config.setup = original_config_setup
    package.loaded["diff"] = original_diff
    vim.g.lib_nvim_deps_disable_first_run = saved_first_run
    vim.g.loaded_diff = saved_loaded
    clear()
    config.setup({})
    require("diff.bindings.usrcmds").register(config.get())
  end

  vim.g.lib_nvim_deps_disable_first_run = true

  -- bindings.register() raises once ---------------------------------------------------------------
  do
    clear()
    local calls = 0
    bindings.register = function(cfg)
      calls = calls + 1
      if calls == 1 then
        error("injected failure in register", 0)
      end
      return original_register(cfg)
    end
    local diff = fresh_diff()

    local first_ok, first_err = pcall(diff.setup, { diff = { ctxlen = 7 }, features = QUIET })
    eq(first_ok, false, "the throw out of register() reaches the caller of setup()")
    ok(
      tostring(first_err):find("injected failure in register", 1, true) ~= nil,
      "and arrives unchanged, got: " .. tostring(first_err)
    )
    eq(calls, 1, "register() ran once")
    eq(vim.g.loaded_diff, nil, "the plugin is not marked as loaded")

    local second_ok, second_err = pcall(diff.setup, { diff = { ctxlen = 9 }, features = QUIET })
    ok(second_ok, "a later setup() is not a no-op and does not raise: " .. tostring(second_err))
    eq(calls, 2, "the later setup() ran register() again")
    eq(vim.g.loaded_diff, 1, "and completed")
    eq(config.get().diff.ctxlen, 9, "with the options of the retry")
    ok(has_command(), "and registered the commands")

    -- the first call that completed wins from here on
    diff.setup({ diff = { ctxlen = 99 }, features = QUIET })
    eq(calls, 2, "after a completed setup() the next call is a no-op")
    eq(config.get().diff.ctxlen, 9, "and does not re-merge")
    diff.enable({ diff = { ctxlen = 123 }, features = QUIET })
    eq(calls, 2, "enable() is latched too")

    bindings.register = original_register
  end

  -- config.setup() raises once ---------------------------------------------------------------------
  do
    clear()
    local calls = 0
    config.setup = function(opts)
      calls = calls + 1
      if calls == 1 then
        error("injected failure in config.setup", 0)
      end
      return original_config_setup(opts)
    end
    local diff = fresh_diff()

    local first_ok = pcall(diff.setup, { features = QUIET })
    eq(first_ok, false, "a throw out of config.setup() reaches the caller of setup()")
    eq(has_command(), false, "nothing was registered on top of a failed merge")

    local second_ok, second_err = pcall(diff.setup, { features = QUIET })
    ok(second_ok, "the retry after a failed merge runs: " .. tostring(second_err))
    eq(calls, 2, "config.setup() ran again")
    ok(has_command(), "and the commands exist")

    config.setup = original_config_setup
  end

  -- a binding that calls setup() again does not recurse ----------------------------------------------
  do
    clear()
    local calls = 0
    local diff = fresh_diff()
    bindings.register = function(cfg)
      calls = calls + 1
      diff.setup({ features = QUIET })
      return original_register(cfg)
    end

    local setup_ok, err = pcall(diff.setup, { features = QUIET })
    ok(
      setup_ok,
      "a re-entrant setup() from a binding returns instead of looping: " .. tostring(err)
    )
    eq(calls, 1, "the nested call did not run register() again")
    ok(has_command(), "the outer call completed")

    bindings.register = original_register
  end

  restore()
end

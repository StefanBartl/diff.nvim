-- TESTS/prompt_file_spec.lua — core.init's prompt_file: migrated off
-- vim.ui.input({completion="file"}, cb) onto
-- lib.nvim.ui.kit.input({completion="file", on_submit, on_cancel}) now that
-- kit.input has a completion="file" equivalent (lib.nvim Phase 11). Same
-- external contract either way: callback(path) on a non-empty submit,
-- callback(nil) on cancel or an empty submit.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")

  local function fresh_core()
    package.loaded["diff.core"] = nil
    return require("diff.core")
  end

  -- select_fn always picks "file path …" (index 2 of the target/base choice
  -- list: clipboard, file, buffer), landing on prompt_file.
  local function pick_file_select_fn(items, _opts, on_choice)
    on_choice(items[2], 2)
  end

  -- non-empty submit -> the path reaches M.execute as target.
  do
    config.setup({ select_fn = pick_file_select_fn, use_pickers_nvim = false })
    package.loaded["lib.nvim.ui.kit"] = {
      input = function(opts)
        opts.on_submit("/tmp/foo.lua")
      end,
    }

    local diff_core = fresh_core()
    local executed
    diff_core.execute = function(opts)
      executed = opts
    end

    diff_core.run("target=ask source=current")

    ok(executed ~= nil, "a submitted path reaches M.execute")
    eq(executed.target, "/tmp/foo.lua", "the submitted path is used as-is for target")
  end

  -- <Esc> (on_cancel) -> whole diff cancelled, M.execute never runs.
  do
    config.setup({ select_fn = pick_file_select_fn, use_pickers_nvim = false })
    package.loaded["lib.nvim.ui.kit"] = {
      input = function(opts)
        opts.on_cancel()
      end,
    }

    local diff_core = fresh_core()
    local executed = false
    diff_core.execute = function()
      executed = true
    end

    diff_core.run("target=ask source=current")

    ok(not executed, "cancelling the file prompt aborts without running")
  end

  -- an empty submit (bare <CR>) behaves the same as a cancel.
  do
    config.setup({ select_fn = pick_file_select_fn, use_pickers_nvim = false })
    package.loaded["lib.nvim.ui.kit"] = {
      input = function(opts)
        opts.on_submit("")
      end,
    }

    local diff_core = fresh_core()
    local executed = false
    diff_core.execute = function()
      executed = true
    end

    diff_core.run("target=ask source=current")

    ok(not executed, "an empty path submit aborts, same as a cancel")
  end

  package.loaded["lib.nvim.ui.kit"] = nil
  config.setup({ select_fn = nil, use_pickers_nvim = true })
  package.loaded["diff.core"] = nil
end

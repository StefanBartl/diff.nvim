---@module 'diff.bindings'
--- Orchestrates diff.nvim's bindings: usrcmds, keymaps, autocmds.
---
--- Single entry point `require("diff.init")` calls into. Registers the
--- user commands, wires the exit keymap (global scope only — buffer scope is
--- attached per-diff by `features/exit.lua`), registers the optional
--- `cfg.keymaps` shortcuts (none by default), and installs the VimLeavePre
--- cleanup autocmd.

local M = {}

---Wire up every binding for the resolved config.
---@param cfg DiffNvim.Config
---@return nil
function M.register(cfg)
  require("diff.bindings.usrcmds").register(cfg)

  if cfg.features.diff_exit then
    require("diff.features.exit").setup(cfg.exit)
    require("diff.features.native_diffthis").register(cfg.exit)
  end

  -- After usrcmds: the shortcuts point at commands that must already exist,
  -- and they read the same features/commands config to decide what is even
  -- registrable.
  require("diff.bindings.keymaps").register_shortcuts(cfg)

  require("diff.bindings.autocmds").register()
end

return M

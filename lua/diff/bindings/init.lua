---@module 'diff.bindings'
---@brief Orchestrates diff.nvim's bindings: usrcmds, keymaps, autocmds.
---@description
--- Single entry point `require("diff.init")` calls into. Registers the
--- user commands, wires the exit keymap (global scope only — buffer scope is
--- attached per-diff by `features/exit.lua`), and installs the VimLeavePre
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

  require("diff.bindings.autocmds").register()
end

return M

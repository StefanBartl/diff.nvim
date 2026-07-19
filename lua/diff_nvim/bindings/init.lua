---@module 'diff_nvim.bindings'
---@brief Orchestrates diff.nvim's bindings: usrcmds, keymaps, autocmds.
---@description
--- Single entry point `require("diff_nvim.init")` calls into. Registers the
--- user commands, wires the exit keymap (global scope only — buffer scope is
--- attached per-diff by `features/exit.lua`), and installs the VimLeavePre
--- cleanup autocmd.

local M = {}

---Wire up every binding for the resolved config.
---@param cfg DiffNvim.Config
---@return nil
function M.register(cfg)
  require("diff_nvim.bindings.usrcmds").register(cfg)

  if cfg.features.diff_exit then
    require("diff_nvim.features.exit").setup(cfg.exit)
    require("diff_nvim.features.native_diffthis").register(cfg.exit)
  end

  require("diff_nvim.bindings.autocmds").register()
end

return M

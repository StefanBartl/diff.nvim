---@module 'diff_nvim.bindings.autocmds'
---@brief Autocommand registration for diff.nvim.
---@description
--- The only autocmd diff.nvim ships: wipe tracked scratch buffers on exit
--- without touching diffmode (native diffmode teardown on exit is Neovim's
--- own responsibility, not ours).

local autocmd = require("lib.nvim.autocmd")

local M = {}

---@type string  Augroup name for cleanup autocmds
local AUGROUP = "diff_nvim_cleanup"

---Register the VimLeavePre cleanup autocmd.
---@return nil
function M.register()
  -- Created directly via nvim_create_augroup(..., { clear = true }) rather
  -- than lib.nvim.autocmd.group(): that helper caches groups by name and
  -- skips the clear on subsequent calls, which would stack duplicate
  -- autocmds if register() ever re-runs.
  local aug = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  autocmd.create("VimLeavePre", function()
    require("diff_nvim.core.scratch").wipe_on_exit()
  end, {
    group = aug,
    desc = "[diff] Wipe scratch buffers on exit",
  })
end

return M

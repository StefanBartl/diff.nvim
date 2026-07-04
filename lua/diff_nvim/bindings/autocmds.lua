---@module 'diff_nvim.bindings.autocmds'
---@brief Autocommand registration for diff.nvim.
---@description
--- The only autocmd diff.nvim ships: wipe tracked scratch buffers on exit
--- without touching diffmode (native diffmode teardown on exit is Neovim's
--- own responsibility, not ours).

local M = {}

---@type string  Augroup name for cleanup autocmds
local AUGROUP = "diff_nvim_cleanup"

---Register the VimLeavePre cleanup autocmd.
---@return nil
function M.register()
  local aug = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function()
      require("diff_nvim.core.scratch").wipe_on_exit()
    end,
    desc = "[diff] Wipe scratch buffers on exit",
  })
end

return M

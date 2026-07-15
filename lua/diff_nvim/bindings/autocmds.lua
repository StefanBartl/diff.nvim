---@module 'diff_nvim.bindings.autocmds'
---@brief Autocommand registration for diff.nvim.
---@description
--- The always-on cleanup autocmd (wipe tracked scratch buffers on exit,
--- without touching diffmode — native diffmode teardown on exit is Neovim's
--- own responsibility, not ours), plus the two ambient, feature-gated
--- autocmd sets: `on_hold` (CursorHold line-diff preview) and
--- `conflict_marks` (conflict-marker highlighting).

local M = {}

---@type string  Augroup name for cleanup autocmds
local AUGROUP = "diff_nvim_cleanup"

---Register every autocmd-driven binding for the resolved config.
---@param cfg DiffNvim.Config
---@return nil
function M.register(cfg)
  local aug = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function()
      require("diff_nvim.core.scratch").wipe_on_exit()
    end,
    desc = "[diff] Wipe scratch buffers on exit",
  })

  if cfg.features.diff_on_hold then
    require("diff_nvim.features.on_hold").setup(cfg.on_hold)
  end

  if cfg.features.conflict_marks then
    require("diff_nvim.features.conflict_marks").setup(cfg.conflict_marks)
  end
end

return M

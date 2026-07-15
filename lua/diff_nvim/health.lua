---@module 'diff_nvim.health'
---@brief :checkhealth diff_nvim provider.

local M = {}

---@return nil
function M.check()
  vim.health.start("diff_nvim")

  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.warn("Neovim 0.9+ recommended")
  end

  if type(vim.diff) == "function" then
    vim.health.ok("vim.diff is available")
  else
    vim.health.error("vim.diff is missing — prompt/file/clipboard/inline output will fail")
  end

  if type(vim.ui) == "table" and type(vim.ui.select) == "function" then
    vim.health.ok("vim.ui.select is available (interactive target picker)")
  else
    vim.health.warn("vim.ui.select unavailable — :Diff without target= will not work")
  end

  if vim.fn.has("clipboard") == 1 then
    vim.health.ok("clipboard provider present (target=clipboard / output=clipboard)")
  else
    vim.health.warn("no clipboard provider — clipboard source/output unavailable")
  end

  if vim.fn.executable("git") == 1 then
    vim.health.ok("git executable found (required for diff_on_hold)")
  else
    vim.health.warn("git executable not found — diff_on_hold will be a silent no-op")
  end

  if pcall(require, "gitsigns") then
    vim.health.ok("gitsigns.nvim found (diff_on_hold prefers its inline hunk preview)")
  else
    vim.health.info("gitsigns.nvim not found — diff_on_hold falls back to previous-content preview")
  end

  if vim.g.loaded_diff_nvim then
    vim.health.ok("plugin loaded (vim.g.loaded_diff_nvim = " .. tostring(vim.g.loaded_diff_nvim) .. ")")
  else
    vim.health.warn("plugin guard not set — call require('diff_nvim').setup()")
  end
end

return M

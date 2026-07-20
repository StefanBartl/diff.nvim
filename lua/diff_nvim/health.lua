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

  if pcall(require, "lib.nvim.usercmd.composer") then
    vim.health.ok("lib.nvim detected (:Diff command layer available)")
  else
    vim.health.error(
      "lib.nvim not found — :Diff/:DiffClear/:DiffBuffers/:DiffOrig/:DiffExit will fail to register",
      { "Install \"StefanBartl/lib.nvim\" as a dependency" }
    )
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

  if type(vim.system) == "function" and vim.fn.executable("git") == 1 then
    vim.health.ok("git + vim.system available (target=git:<rev> / source=git:<rev>)")
  elseif type(vim.system) ~= "function" then
    vim.health.warn("vim.system missing (Neovim 0.10+) — git:<rev> source/target unavailable")
  else
    vim.health.warn("git executable not on PATH — git:<rev> source/target unavailable")
  end

  if type(vim.system) == "function" and vim.fn.executable("curl") == 1 then
    vim.health.ok("curl + vim.system available (target=http(s):// / source=http(s)://)")
  elseif type(vim.system) ~= "function" then
    vim.health.warn("vim.system missing (Neovim 0.10+) — http(s):// source/target unavailable")
  else
    vim.health.warn("curl executable not on PATH — http(s):// source/target unavailable")
  end

  if type(require("diff_nvim.core.pickers_bridge").resolve()) == "function" then
    vim.health.ok("pickers.nvim detected — used for the target/source picker")
  else
    vim.health.ok("pickers.nvim not detected — using vim.ui.select for the target/source picker")
  end

  if vim.g.loaded_diff_nvim then
    vim.health.ok("plugin loaded (vim.g.loaded_diff_nvim = " .. tostring(vim.g.loaded_diff_nvim) .. ")")
  else
    vim.health.warn("plugin guard not set — call require('diff_nvim').setup()")
  end
end

return M

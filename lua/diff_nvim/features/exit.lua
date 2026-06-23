---@module 'diff_nvim.features.exit'
---@brief :DiffExit and the context-aware "leave diffmode" keymap.
---@description
--- The original global `<Esc><Esc>` mapping noticeably delayed a normal <Esc>
--- because Neovim had to wait for a possible second key everywhere. This module
--- fixes that: by default the exit key is bound *buffer-locally* only on buffers
--- that diff.nvim itself puts into diffmode (scope="buffer"). A "global" scope is
--- still available for users who want the legacy behaviour, and `:DiffExit`
--- always works regardless of scope.

local api = vim.api

local notify   = require("diff_nvim.util.notify")
local validate = require("diff_nvim.util.validate")

local M = {}

---@type DiffNvim.Config.Exit|nil  Cached so on-diff hooks know the key/scope.
local _cfg = nil

---Turn off diffmode everywhere if the current window is part of a diff.
---@return nil
function M.exit()
  if vim.wo.diff then
    vim.cmd("diffoff!")
    return
  end
  -- Even when the *current* window isn't diffed, offer to clear a stray diff.
  for _, win in ipairs(api.nvim_list_wins()) do
    if validate.win_valid(win) and vim.wo[win].diff then
      vim.cmd("diffoff!")
      return
    end
  end
  notify.info("Not in diff mode")
end

---Bind the exit key buffer-locally on a buffer the plugin just diffed.
---No-op unless scope == "buffer".
---@param bufnr integer
---@return nil
function M.attach_buffer(bufnr)
  if not _cfg or _cfg.scope ~= "buffer" then
    return
  end
  if not validate.buf_valid(bufnr) then
    return
  end
  vim.keymap.set("n", _cfg.key, M.exit, {
    buffer = bufnr,
    silent = true,
    desc = "[diff] Exit diff mode",
  })
end

---Register the exit feature according to config.
---@param cfg DiffNvim.Config.Exit
---@return nil
function M.setup(cfg)
  _cfg = cfg

  if cfg.scope == "global" and type(cfg.key) == "string" and cfg.key ~= "" then
    vim.keymap.set("n", cfg.key, M.exit, {
      silent = true,
      desc = "[diff] Exit diff mode when active",
    })
  end
end

return M

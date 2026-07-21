---@module 'diff.features.exit'
---@brief :DiffExit logic and the context-aware "leave diffmode" behaviour.
---@description
--- The original global `<Esc><Esc>` mapping noticeably delayed a normal <Esc>
--- because Neovim had to wait for a possible second key everywhere. This module
--- fixes that: by default the exit key is bound *buffer-locally* only on buffers
--- that diff.nvim itself puts into diffmode (scope="buffer"). A "global" scope is
--- still available for users who want the legacy behaviour, and `:DiffExit`
--- always works regardless of scope. Actual `vim.keymap.set` calls live in
--- `bindings/keymaps.lua`; this module only owns the exit behaviour and the
--- active `exit` config.

local api = vim.api

local notify   = require("diff.util.notify")
local validate = require("diff.util.validate")

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
  if not _cfg then
    return
  end
  require("diff.bindings.keymaps").attach_buffer(_cfg, bufnr)
end

---Register the exit feature according to config (keymap wiring only; see
---`bindings/keymaps.lua`).
---@param cfg DiffNvim.Config.Exit
---@return nil
function M.setup(cfg)
  _cfg = cfg
  require("diff.bindings.keymaps").register_global(cfg)
end

return M

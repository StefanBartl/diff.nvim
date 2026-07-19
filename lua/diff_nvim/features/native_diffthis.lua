---@module 'diff_nvim.features.native_diffthis'
---@brief Mirrors the buffer-local exit key onto buffers a *native* :diffthis
---puts into diffmode, not just diff.nvim's own scratch buffers.
---@description
--- Opt-in via exit.native_diffthis (default false — see @types.lua for the
--- rationale: it changes buffer-local keymaps outside diff.nvim's own
--- workflow, which could surprise users who invoke :diffthis directly for
--- unrelated reasons). Watches the window-local 'diff' option via an
--- OptionSet autocmd and attaches/detaches the buffer-local exit mapping to
--- match. Only relevant when exit.scope == "buffer"; a no-op otherwise.
---
--- M.sync() (the attach/detach logic) is kept separate from M.register()
--- (the OptionSet wiring) so the logic itself stays directly unit-testable
--- without depending on the OptionSet event actually firing.

local validate = require("diff_nvim.util.validate")

local M = {}

---@type string
local AUGROUP = "diff_nvim_native_diffthis"

---Attach or detach the buffer-local exit key on `win`'s current buffer to
---match its current 'diff' window-option state.
---@param cfg DiffNvim.Config.Exit
---@param win integer
---@return nil
function M.sync(cfg, win)
  if not validate.win_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if not validate.buf_valid(buf) then
    return
  end

  if vim.wo[win].diff then
    require("diff_nvim.bindings.keymaps").attach_buffer(cfg, buf)
  else
    pcall(vim.keymap.del, "n", cfg.key, { buffer = buf })
  end
end

---Register the OptionSet watcher. No-op unless scope == "buffer" and
---native_diffthis == true.
---@param cfg DiffNvim.Config.Exit
---@return nil
function M.register(cfg)
  if cfg.scope ~= "buffer" or cfg.native_diffthis ~= true then
    return
  end

  local aug = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = aug,
    pattern = "diff",
    callback = function()
      M.sync(cfg, vim.api.nvim_get_current_win())
    end,
    desc = "[diff] Mirror the buffer-local exit key onto native :diffthis/:diffoff",
  })
end

return M

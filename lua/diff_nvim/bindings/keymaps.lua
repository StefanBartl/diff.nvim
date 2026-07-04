---@module 'diff_nvim.bindings.keymaps'
---@brief Keymap registration for diff.nvim.
---@description
--- The only keymap diff.nvim ships is the "leave diffmode" key. Registration
--- (this module) is kept separate from its logic (`features/exit.lua`) so
--- every `vim.keymap.set` call lives in one place, alongside
--- `bindings/usrcmds.lua` and `bindings/autocmds.lua`. Both keymaps carry a
--- `desc`, so which-key.nvim (if installed) picks them up with no further
--- wiring — diff.nvim has no leader-prefixed group to label.

local validate = require("diff_nvim.util.validate")

local M = {}

---Bind the exit key globally. No-op unless scope == "global".
---@param cfg DiffNvim.Config.Exit
---@return nil
function M.register_global(cfg)
  if cfg.scope ~= "global" or type(cfg.key) ~= "string" or cfg.key == "" then
    return
  end
  vim.keymap.set("n", cfg.key, require("diff_nvim.features.exit").exit, {
    silent = true,
    desc = "[diff] Exit diff mode when active",
  })
end

---Bind the exit key buffer-locally on a buffer diff.nvim just diffed.
---No-op unless scope == "buffer".
---@param cfg DiffNvim.Config.Exit
---@param bufnr integer
---@return nil
function M.attach_buffer(cfg, bufnr)
  if cfg.scope ~= "buffer" then
    return
  end
  if not validate.buf_valid(bufnr) then
    return
  end
  vim.keymap.set("n", cfg.key, require("diff_nvim.features.exit").exit, {
    buffer = bufnr,
    silent = true,
    desc = "[diff] Exit diff mode",
  })
end

return M

---@module 'diff.util.diffmode'
--- Turning Neovim's window-local `'diff'` option on and off, correctly.
---
--- The one rule this module exists to hold: `vim.wo[win].diff = v` behaves
--- like `:set`, not `:setlocal`. For a window-local option that writes the
--- *global* value as well, and `'diff'` is inherited from that global value by
--- every window opened fresh or switched to another buffer — so a plain
--- `vim.wo[...].diff = true` left the next `:tabnew` sitting in diffmode long
--- after the diff it came from. Every diffmode write in diff.nvim goes through
--- here so the rule is stated once instead of once per call site.

local api = vim.api

local M = {}

---Turn diffmode on or off for `win`, window-locally.
---Invalid windows are ignored rather than raising: callers are cleanup loops
---and render paths where a window may have been closed in the meantime.
---@param win integer
---@param on boolean
---@return nil
function M.set(win, on)
  pcall(api.nvim_set_option_value, "diff", on, { win = win, scope = "local" })
end

return M

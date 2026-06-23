---@module 'diff_nvim.util.validate'
---@brief Small, pure validation helpers shared across the core.
---@description
--- Pure functions only — no side effects, no notifications. Safe to call in
--- any layer and trivial to unit-test.

local api = vim.api

local M = {}

---Return true when `value` is contained in `allowed`.
---Linear scan; `allowed` is always a tiny fixed list here.
---@param value any
---@param allowed any[]
---@return boolean
function M.is_one_of(value, allowed)
  for i = 1, #allowed do
    if allowed[i] == value then
      return true
    end
  end
  return false
end

---Validate a buffer handle.
---@param bufnr any
---@return boolean
function M.buf_valid(bufnr)
  return type(bufnr) == "number" and api.nvim_buf_is_valid(bufnr)
end

---Validate a window handle.
---@param win any
---@return boolean
function M.win_valid(win)
  return type(win) == "number" and api.nvim_win_is_valid(win)
end

return M

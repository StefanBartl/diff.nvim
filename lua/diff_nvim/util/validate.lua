---@module 'diff_nvim.util.validate'
---@brief Small, pure validation helpers shared across the core.
---@description
--- Pure functions only — no side effects, no notifications. Safe to call in
--- any layer and trivial to unit-test. Delegates to lib.nvim.normalize
--- (this module's own versions were exact reimplementations).

local normalize = require("lib.nvim.normalize")

local M = {}

---Return true when a value is contained in an allowed-values list.
---@type fun(value: any, allowed: any[]): boolean
M.is_one_of = normalize.is_one_of

---Validate a buffer handle.
---@type fun(bufnr: any): boolean
M.buf_valid = normalize.buf_valid

---Validate a window handle.
---@type fun(win: any): boolean
M.win_valid = normalize.win_valid

return M

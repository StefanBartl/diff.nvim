---@module 'diff.config'
---@brief Runtime configuration store for diff.nvim.
---@description
--- Merges user options over the immutable DEFAULTS and exposes the active
--- config via `get()`. Keeps no global state — the active table is module-local.

local DEFAULTS = require("diff.config.DEFAULTS")

local M = {}

---@type DiffNvim.Config|nil
local _active = nil

---Merge user options over the defaults and store the result.
---Validates only the cheap, high-value fields; unknown keys are preserved.
---@param user_opts? DiffNvim.Config|table
---@return DiffNvim.Config
function M.setup(user_opts)
  if type(user_opts) ~= "table" then
    user_opts = {}
  end

  _active = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), user_opts)
  return _active
end

---Return the active configuration, falling back to defaults if `setup` was
---never called.
---@return DiffNvim.Config
function M.get()
  if _active == nil then
    _active = vim.deepcopy(DEFAULTS)
  end
  return _active
end

return M

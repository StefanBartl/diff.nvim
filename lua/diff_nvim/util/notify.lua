---@module 'diff_nvim.util.notify'
---@brief Prefixed wrapper around vim.notify so every message is traceable.
---@description
--- Only the UI layer should call this — keep low-level/core modules silent and
--- let them return `(value, err)` instead.

local PREFIX = "[diff] "

local M = {}

---@param msg string
---@return nil
function M.info(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.INFO)
end

---@param msg string
---@return nil
function M.warn(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.WARN)
end

---@param msg string
---@return nil
function M.error(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.ERROR)
end

return M

---@module 'diff_nvim.core.scratch'
---@brief Scratch-buffer lifecycle for diff.nvim.
---@description
--- Owns every scratch buffer the plugin creates and provides a single
--- `cleanup_all()` entry point. State is module-local (not a global) and the
--- buffer list acts as a small registry so `:DiffClear` and VimLeavePre can tear
--- everything down deterministically.

local api = vim.api

local validate = require("diff_nvim.util.validate")

local M = {}

---@type integer[]  Tracked scratch buffer handles
local _bufs = {}

---Create a non-modifiable scratch buffer, populate it, track it, and return it.
---@param lines string[]
---@param name string
---@param filetype? string  Optional filetype (e.g. "diff" for inline view)
---@return integer bufnr
function M.create(lines, name, filetype)
  local bufnr = api.nvim_create_buf(false, true)

  -- nvim_buf_set_name can throw on duplicate names; keep it non-fatal.
  pcall(api.nvim_buf_set_name, bufnr, name)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.bo[bufnr].buftype    = "nofile"
  vim.bo[bufnr].bufhidden  = "wipe"
  vim.bo[bufnr].swapfile   = false
  if type(filetype) == "string" and filetype ~= "" then
    vim.bo[bufnr].filetype = filetype
  end
  vim.bo[bufnr].modifiable = false

  _bufs[#_bufs + 1] = bufnr
  return bufnr
end

---Mark this buffer as one diff.nvim should clean up (for buffers it did not
---itself create, e.g. the origin snapshot).
---@param bufnr integer
---@return nil
function M.track(bufnr)
  if validate.buf_valid(bufnr) then
    _bufs[#_bufs + 1] = bufnr
  end
end

---Count the scratch buffers diff.nvim is currently tracking (valid handles
---only). Used by the statusline component to show whether a diff is active.
---@return integer count
function M.active_count()
  local n = 0
  for _, bufnr in ipairs(_bufs) do
    if validate.buf_valid(bufnr) then
      n = n + 1
    end
  end
  return n
end

---Turn off diffmode in every window currently showing one of our buffers,
---wipe those buffers, then disable any remaining stray diffmode windows.
---@return integer cleared  Number of buffers wiped
function M.cleanup_all()
  local cleared = 0

  for _, bufnr in ipairs(_bufs) do
    if validate.buf_valid(bufnr) then
      for _, win in ipairs(api.nvim_list_wins()) do
        if validate.win_valid(win) and api.nvim_win_get_buf(win) == bufnr then
          vim.wo[win].diff = false
        end
      end
      if pcall(api.nvim_buf_delete, bufnr, { force = true }) then
        cleared = cleared + 1
      end
    end
  end

  -- Disable diffmode left over in any other window (e.g. the origin buffer).
  for _, win in ipairs(api.nvim_list_wins()) do
    if validate.win_valid(win) and vim.wo[win].diff then
      vim.wo[win].diff = false
    end
  end

  _bufs = {}
  return cleared
end

---Wipe tracked buffers without touching diffmode (used on VimLeavePre).
---@return nil
function M.wipe_on_exit()
  for _, bufnr in ipairs(_bufs) do
    if validate.buf_valid(bufnr) then
      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end
  end
  _bufs = {}
end

return M

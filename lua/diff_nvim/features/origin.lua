---@module 'diff_nvim.features.origin'
---@brief :DiffOrig — diff the current buffer against its on-disk saved version.
---@description
--- Reimplemented on top of the core scratch/diff machinery (no raw :read heredoc)
--- so the snapshot buffer participates in `:DiffClear` and VimLeavePre cleanup.
--- Shows "what changed since the last save".

local api = vim.api
local fn  = vim.fn

local notify   = require("diff_nvim.util.notify")
local validate = require("diff_nvim.util.validate")
local scratch  = require("diff_nvim.core.scratch")

local M = {}

---Diff the current buffer against the file it is backed by on disk.
---@return nil
function M.run()
  local bufnr = api.nvim_get_current_buf()
  local origin_win = api.nvim_get_current_win()

  if not validate.buf_valid(bufnr) then
    notify.error("current buffer is not valid")
    return
  end

  local name = api.nvim_buf_get_name(bufnr)
  if name == "" then
    notify.error("current buffer is not backed by a file")
    return
  end

  local path = fn.expand(name)
  if fn.filereadable(path) ~= 1 then
    notify.error("file is not readable on disk: " .. path)
    return
  end

  local disk_lines = fn.readfile(path)

  -- Snapshot of the saved version as a tracked, read-only scratch buffer.
  local snap = scratch.create(disk_lines, string.format("[DiffOrig] %s (saved)", fn.fnamemodify(path, ":t")))

  -- Open the snapshot beside the working buffer and enable diffmode in both.
  if not validate.win_valid(origin_win) then
    notify.error("origin window is no longer valid")
    return
  end

  api.nvim_set_current_win(origin_win)
  vim.cmd(string.format("silent! vsplit | buffer %d", snap))

  local snap_win = api.nvim_get_current_win()
  if validate.win_valid(snap_win) then
    vim.wo[snap_win].diff = true
  end
  if validate.win_valid(origin_win) then
    api.nvim_set_current_win(origin_win)
    vim.wo[origin_win].diff = true
  end

  require("diff_nvim.features.exit").attach_buffer(snap)
end

return M

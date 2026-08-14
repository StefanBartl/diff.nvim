-- docs/TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by docs/TESTS/run.lua.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %q, got %q"):format(msg or "", tostring(b), tostring(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then
    error(("FAIL %s: expected truthy, got %q"):format(msg or "", tostring(v)), 2)
  end
end

--- Fresh scratch buffer, made current, with an optional filetype.
---@param ft string|nil
---@return integer bufnr
function H.scratch(ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  if ft then
    vim.bo[buf].filetype = ft
  end
  return buf
end

--- Create a fresh, empty scratch directory under vim.fn.tempname().
---@return string dir  Absolute path with a trailing slash.
function H.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return vim.fn.fnamemodify(dir, ":p")
end

--- Write `content` (a list of lines) to `path`, creating parent directories.
---@param path string
---@param lines string[]
function H.write_file(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

return H

-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.

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

--- Canonicalize `path` so two spellings of one file compare equal.
---
--- Both sides of such a comparison have to go through this, never just one.
--- vim.fs.normalize() rewrites separators but never symlinks, and the
--- platforms disagree about which spelling ends up in a buffer name:
---
---  * macOS resolves on the way in. /var is a symlink to /private/var, so
---    vim.fn.tempname() hands back /var/folders/…, while the buffer nvim
---    opens for a file underneath it is named /private/var/folders/…
---    (fix_fname() canonicalizes it). Comparing the two raw was the macOS
---    CI failure.
---  * Windows does not. A buffer name keeps whatever spelling it was given,
---    directory junction and 8.3 short name (C:\Users\RUNNER~1\…) included,
---    while fs_realpath() expands both.
---
--- So there is no single spelling to prefer, and pre-resolving the path a
--- spec was handed would only move the mismatch to the other platform.
--- Sending both sides through fs_realpath() is what holds everywhere: it
--- maps every spelling of one file onto the same one. It stays exact --
--- two different files cannot share a realpath -- so an assertion phrased
--- this way still discriminates, it just stops depending on which call
--- produced the path.
---@param path string
---@return string  Absolute, symlink-resolved, forward-slash path, no trailing slash.
function H.canonical(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p"))
end

--- Write `content` (a list of lines) to `path`, creating parent directories.
---@param path string
---@param lines string[]
function H.write_file(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

return H

---@module 'diff.core.resolve'
--- Resolve a target/source specifier to a flat list of lines.
---
--- Pure resolution layer: takes a specifier ("clipboard", a buffer number, or a
--- file path) and returns `(lines, err)`. Never notifies — callers decide how to
--- surface errors. Also parses the raw `key=value` argument string.

local fn = vim.fn
local expand_path = require("lib.nvim.cross.fs.expand_path")
local api = vim.api

local validate = require("diff.util.validate")

local M = {}

---Parse a raw argument string of the form `key=value key=value …`.
---Unknown keys are kept in the result so future options stay
---forward-compatible, but when `known` is given they are also listed in the
---second return value -- a misspelled key (`veiw=inline`) must not be
---indistinguishable from no key at all (ERR-10): the caller can warn instead
---of silently substituting a default for what looks like a typo.
---@param raw string
---@param known? string[]  Recognized keys for this call site; omit to skip the unknown-key check entirely
---@return table<string, string> kv
---@return string[] unknown  Keys present in `raw` but not in `known` (always empty when `known` is omitted)
function M.parse_args(raw, known)
  ---@type table<string, string>
  local out = {}
  ---@type string[]
  local unknown = {}
  if type(raw) ~= "string" then
    return out, unknown
  end
  ---@type table<string, boolean>|nil
  local known_set = nil
  if type(known) == "table" then
    known_set = {}
    for _, k in ipairs(known) do
      known_set[k] = true
    end
  end
  for key, value in raw:gmatch("(%a+)=([^%s]+)") do
    out[key] = value
    if known_set and not known_set[key] then
      unknown[#unknown + 1] = key
    end
  end
  return out, unknown
end

---Split raw text into diff lines, the way every other source in diff.nvim
---already produces them.
---
---A buffer's lines (`nvim_buf_get_lines`) and a file's (`readfile`) carry
---neither the line terminator nor a CR -- Neovim strips both and keeps the
---line ending in `'fileformat'` instead. Raw text does carry them: a
---clipboard register filled by a Windows application, a URL serving a
---CRLF file, `git show` in a repository with `core.autocrlf=true`. Left
---alone, a trailing "\r" makes two *identical* sides differ in every single
---line, and the empty element a trailing newline leaves behind shows up as
---one added blank line. Both render as a plausible diff rather than as a
---bug, which is the worst way for this to fail, so raw text is normalized
---to the same shape the other sources have.
---@param raw string
---@return string[]
function M.split_lines(raw)
  local lines = vim.split(raw, "\n", { plain = true })
  -- One scan to answer "is there anything to strip at all", rather than a
  -- per-line sub() on payloads that have none -- which is every source on
  -- Linux and macOS, and on Windows with core.autocrlf=input.
  if raw:find("\r", 1, true) then
    for i = 1, #lines do
      if lines[i]:sub(-1) == "\r" then
        lines[i] = lines[i]:sub(1, -2)
      end
    end
  end
  -- A trailing newline terminates the last line, it does not begin a new one.
  -- Guarded on #lines > 1 so empty input stays a one-empty-line list rather
  -- than becoming an empty one.
  if #lines > 1 and lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

---Split a `git:<rev1>..<rev2>` range specifier into its two revisions.
---Not itself a git operation — pure string splitting, so it stays testable
---without a git executable and reusable anywhere a target= spec needs
---checking (currently just `core.init`'s `M.run`, which expands a matching
---target= into `source=git:<rev1> target=git:<rev2>`, bypassing whatever
---source= would otherwise resolve to). The first `..` is the split point,
---since a revision name could itself contain further dots (e.g. `v1.2.3`).
---@param spec any
---@return string|nil rev_a, string|nil rev_b  Both nil when `spec` isn't a git range
function M.split_git_range(spec)
  if type(spec) ~= "string" then
    return nil, nil
  end
  local rev_a, rev_b = spec:match("^git:(.-)%.%.(.+)$")
  if rev_a and rev_b and rev_a ~= "" and rev_b ~= "" then
    return rev_a, rev_b
  end
  return nil, nil
end

---Classify a specifier as a buffer number, the way every consumer of the
---specifier grammar must agree to classify it. Kept here, next to
---`resolve_lines` (its first consumer), so the rule lives in one place:
---`core.init`'s labelling and `stat_list_target` both have to reach the same
---verdict for the same string, or a side resolves as a buffer while labelling
---itself as a file path.
---@param spec any
---@return integer|nil bufnr  nil when `spec` is not a buffer number
function M.as_bufnr(spec)
  local as_num = tonumber(spec)
  if as_num == nil then
    return nil
  end
  return math.floor(as_num)
end

---Resolve a specifier to its content lines.
---@param spec string|integer  "clipboard", a file path, or a buffer number
---@param label string         "target"|"source" — used only in error text
---@return string[]|nil lines, string|nil err
function M.resolve_lines(spec, label)
  -- clipboard ----------------------------------------------------------------
  if spec == "clipboard" then
    local raw = fn.getreg("+")
    if type(raw) ~= "string" or raw == "" then
      return nil, "clipboard is empty"
    end
    return M.split_lines(raw), nil
  end

  -- buffer number ------------------------------------------------------------
  local bufnr = M.as_bufnr(spec)
  if bufnr ~= nil then
    if not validate.buf_valid(bufnr) then
      return nil, string.format("%s: buffer %d does not exist or is invalid", label, bufnr)
    end
    return api.nvim_buf_get_lines(bufnr, 0, -1, false), nil
  end

  -- file path ----------------------------------------------------------------
  -- expand_path, not fn.expand (SEC-34): `spec` may be the raw diff-target
  -- argument the user typed -- fn.expand() would run a backtick span
  -- through &shell.
  local path = expand_path(tostring(spec))
  if fn.filereadable(path) ~= 1 then
    return nil, string.format("%s: file not readable: %s", label, path)
  end
  return fn.readfile(path), nil
end

return M

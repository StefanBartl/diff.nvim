---@module 'diff.core.git'
--- Resolve a `git:<rev>` specifier to the file's content at that revision.
---
--- Resolution layer for git-backed sources/targets. A specifier of the form
--- `git:HEAD`, `git:HEAD~1`, `git:<sha>`, or `git:<branch>` resolves to the
--- content of the *current file* at that revision. A specifier of the form
--- `git:<rev>:<path>` instead resolves an explicit path (relative to the repo
--- root), regardless of the buffer :Diff was invoked from -- `core/history.lua`
--- is the one caller that needs this: a revision from before a rename tracked
--- a different path than the one the current buffer holds. The actual `git
--- show` runs through `lib.nvim.git.show_async` (GS-14): byte-exact, not
--- text-mode, but `resolve.split_lines` below already strips a trailing `\r`
--- per line itself, so a CRLF file still ends up LF-split either way. `M.resolve`
--- delivers the result through `cb`, like `core/url.lua`; everything up to the
--- spawn stays synchronous. Never notifies — hands back `(lines, err)`.

local fn = vim.fn
local git = require("lib.nvim.git")

local M = {}

---Is `spec` a git specifier (`git:<rev>`)?
---@param spec any
---@return boolean
function M.is_git_spec(spec)
  return type(spec) == "string" and spec:sub(1, 4) == "git:"
end

---Find the git repository root by walking up from `start_dir`.
---Handles both a `.git` directory and a `.git` file (submodules/worktrees).
---Exported for `core/history.lua`, which needs the same root-finding walk to
---resolve `git log`'s `-C` argument before any commit has been picked.
---@param start_dir string
---@return string|nil root  Normalized repo root, or nil when not in a repo
function M.repo_root(start_dir)
  local hit = vim.fs.find(".git", { path = start_dir, upward = true })[1]
  if not hit then
    return nil
  end
  return vim.fs.normalize(vim.fs.dirname(hit))
end

---Resolve a `git:<rev>` specifier against the file backing `bufname`.
---
---Asynchronous: the result arrives through `cb`, never as a return value.
---`git show` used to run through `vim.system(...):wait()`, which froze the
---editor for the round-trip -- and a three-way diff resolves two sides, so it
---could be two of them back to back. Everything up to the spawn stays
---synchronous, so an invalid specifier still reports through `cb` in the same
---tick, exactly as before.
---@param spec string   A `git:<rev>` or `git:<rev>:<path>` specifier
---@param bufname string The name (path) of the buffer :Diff was invoked from -- only used to locate the repo root when `spec` carries no explicit path
---@param label string  "target"|"source" — used only in error text
---@param cb fun(lines: string[]|nil, err: string|nil)  invoked on the main loop
---@return nil
function M.resolve(spec, bufname, label, cb)
  label = label or "target"

  if fn.executable("git") ~= 1 then
    return cb(nil, label .. ": git executable not found on PATH")
  end

  local rev = spec:sub(5) -- strip the "git:" prefix
  if rev == "" then
    return cb(nil, label .. ": empty git revision (use git:HEAD, git:<sha>, …)")
  end

  -- git:<rev>:<path> carries its own path, relative to the repo root --
  -- core/history.lua's way of asking for a revision at a path other than the
  -- current buffer's (a rename may mean the file lived under a different
  -- name at that revision). The first ":" is the split point: a revision
  -- name cannot itself contain one.
  local explicit_path = nil
  local colon = rev:find(":", 1, true)
  if colon then
    explicit_path = rev:sub(colon + 1)
    rev = rev:sub(1, colon - 1)
    if rev == "" then
      return cb(nil, label .. ": empty git revision before ':' in " .. spec)
    end
    if explicit_path == "" then
      return cb(nil, label .. ": empty path after git:" .. rev .. ":")
    end
  end

  if type(bufname) ~= "string" or bufname == "" then
    return cb(nil, label .. ": git:" .. rev .. " needs a file-backed buffer")
  end

  local abspath = vim.fs.normalize(fn.fnamemodify(bufname, ":p"))
  local root = M.repo_root(vim.fs.dirname(abspath))
  if not root then
    return cb(nil, label .. ": not inside a git repository")
  end

  local rel
  if explicit_path then
    rel = explicit_path
  else
    -- Path relative to the repo root, with forward slashes (git wants those).
    if abspath:sub(1, #root + 1) ~= root .. "/" then
      return cb(nil, label .. ": file is outside the git repo root")
    end
    rel = abspath:sub(#root + 2)
  end

  -- `dir = root`, `rel` already repo-root-relative: lib.nvim.git's `show_argv`
  -- resolves a relative path against `-C <dir>` via `rev:./<path>`, which
  -- names the same file `rev:<rel>` (the bare, repo-root form this used to
  -- build by hand) does when `dir` is the repo root itself.
  --
  -- lib.nvim.git's error message on failure does not carry git's own stderr
  -- (its blocking/async runners only capture stdout, which a failed `git
  -- show` never writes to) -- generic ("unknown revision, path not in that
  -- revision, or not a repository") rather than git's specific complaint.
  git.show_async(rev, rel, { dir = root }, function(content, err)
    -- callback already runs via vim.schedule (lib.nvim.git's own contract):
    -- safe to touch buffers/windows here, same guarantee this module's
    -- docstring makes about `cb`.
    if not content then
      return cb(nil, label .. ": " .. (err or ("git show " .. rev .. ":" .. rel .. " failed")))
    end
    cb(require("diff.core.resolve").split_lines(content), nil)
  end)
end

return M

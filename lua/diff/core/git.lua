---@module 'diff.core.git'
---@brief Resolve a `git:<rev>` specifier to the file's content at that revision.
---@description
--- Pure-ish resolution layer for git-backed sources/targets. A specifier of the
--- form `git:HEAD`, `git:HEAD~1`, `git:<sha>`, or `git:<branch>` resolves to the
--- content of the *current file* at that revision. Uses `vim.system(...):wait()`
--- (synchronous, cross-platform — no shell) so it slots into the otherwise
--- synchronous resolve pipeline. Never notifies — returns `(lines, err)`.

local fn = vim.fn

local M = {}

---Is `spec` a git specifier (`git:<rev>`)?
---@param spec any
---@return boolean
function M.is_git_spec(spec)
  return type(spec) == "string" and spec:sub(1, 4) == "git:"
end

---Find the git repository root by walking up from `start_dir`.
---Handles both a `.git` directory and a `.git` file (submodules/worktrees).
---@param start_dir string
---@return string|nil root  Normalized repo root, or nil when not in a repo
local function repo_root(start_dir)
  local hit = vim.fs.find(".git", { path = start_dir, upward = true })[1]
  if not hit then
    return nil
  end
  return vim.fs.normalize(vim.fs.dirname(hit))
end

---Resolve a `git:<rev>` specifier against the file backing `bufname`.
---@param spec string   A `git:<rev>` specifier
---@param bufname string The name (path) of the buffer :Diff was invoked from
---@param label string  "target"|"source" — used only in error text
---@return string[]|nil lines, string|nil err
function M.resolve(spec, bufname, label)
  label = label or "target"

  if type(vim.system) ~= "function" then
    return nil, label .. ": git revisions require Neovim 0.10+ (vim.system)"
  end
  if fn.executable("git") ~= 1 then
    return nil, label .. ": git executable not found on PATH"
  end

  local rev = spec:sub(5) -- strip the "git:" prefix
  if rev == "" then
    return nil, label .. ": empty git revision (use git:HEAD, git:<sha>, …)"
  end

  if type(bufname) ~= "string" or bufname == "" then
    return nil, label .. ": git:" .. rev .. " needs a file-backed buffer"
  end

  local abspath = vim.fs.normalize(fn.fnamemodify(bufname, ":p"))
  local root = repo_root(vim.fs.dirname(abspath))
  if not root then
    return nil, label .. ": not inside a git repository"
  end

  -- Path relative to the repo root, with forward slashes (git wants those).
  if abspath:sub(1, #root + 1) ~= root .. "/" then
    return nil, label .. ": file is outside the git repo root"
  end
  local rel = abspath:sub(#root + 2)

  local object = rev .. ":" .. rel
  local ok, res = pcall(function()
    return vim.system({ "git", "-C", root, "show", object }, { text = true }):wait()
  end)
  if not ok then
    return nil, label .. ": git invocation failed: " .. tostring(res)
  end
  if res.code ~= 0 then
    local msg = (type(res.stderr) == "string" and res.stderr ~= "")
      and vim.trim(res.stderr)
      or ("git show " .. object .. " failed")
    return nil, label .. ": " .. msg
  end

  local out = res.stdout or ""
  local lines = vim.split(out, "\n", { plain = true })
  -- git output ends with a trailing newline; drop the empty final element so
  -- line counts match readfile()/buffer content.
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines, nil
end

return M

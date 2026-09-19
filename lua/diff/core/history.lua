---@module 'diff.core.history'
--- File history: list the commits that touched a file, and diff any one of
--- them against its parent.
---
--- The "missing half" diffview offered and diff.nvim did not: side-by-side
--- diffing against a single revision (`core.git`, `core.init`) already covers
--- "show me this file at git:HEAD", but not "show me every revision this file
--- went through, and let me pick one". `M.log` walks that history with
--- `git log --follow --name-status`, which also hands back the path a rename
--- gave the file at each point -- so `M.diff_entry` can diff the right two
--- paths across a rename, not just the current one. The actual diffing is not
--- new code: it reuses `core.execute` with two `git:<rev>:<path>` targets
--- (`core.git`'s explicit-path spec), the same renderer every other :Diff
--- view/output combination already goes through.

local fn = vim.fn
local api = vim.api

local git = require("diff.core.git")
local notify = require("diff.util.notify")

local M = {}

-- Field/record separators for `git log`'s custom --pretty=format:. Neither
-- byte occurs in a commit hash, a short date, an author name, or a subject
-- line in practice, and unlike a printable delimiter (","," "|") there is no
-- real value to escape against.
local RS = "\1"
local FS = "\31"

---Parse `git log --name-status --pretty=format:"<RS><H><FS><h><FS><ad><FS><an><FS><s>"`
---output into entries. Pure string work, kept separate from `M.log` so it is
---testable without a git executable.
---
---Each block's body lists the changed paths under the log's own pathspec
---restriction -- normally exactly one line. A plain change ("M path", "A
---path", ...) has one field after the status letter; a rename/copy ("R100
---old<TAB>new") has two, and `path` is the new one (the name the file had
---*at this commit*) while `parent_path` is the old one (the name it had *at
---the parent*, i.e. what the diff's source side must ask for). A merge
---commit's diff is omitted by git log's own defaults (no body line at all),
---so both come back nil here -- `M.log` fills them in with the pathspec that
---found the commit in the first place, the only path guaranteed correct for
---an entry with no body line to read one from.
---@param raw string
---@return DiffNvim.HistoryEntry[]
function M.parse(raw)
  local entries = {}
  if type(raw) ~= "string" or raw == "" then
    return entries
  end

  for block in (raw .. RS):gmatch("(.-)" .. RS) do
    if block ~= "" then
      local nl = block:find("\n", 1, true)
      local header = nl and block:sub(1, nl - 1) or block
      local body = nl and block:sub(nl + 1) or ""

      local sha, short, date, author, subject =
        header:match("^([^\31]*)\31([^\31]*)\31([^\31]*)\31([^\31]*)\31(.*)$")

      if sha and sha ~= "" then
        local path, parent_path = nil, nil
        for line in body:gmatch("[^\n]+") do
          local trimmed = vim.trim(line)
          if trimmed ~= "" then
            local status, rest = trimmed:match("^(%u%d*)%s+(.*)$")
            if status then
              if status:sub(1, 1) == "R" or status:sub(1, 1) == "C" then
                local old, new = rest:match("^(.-)\t(.+)$")
                parent_path = old
                path = new
              else
                path = rest
              end
            end
          end
        end
        entries[#entries + 1] = {
          sha = sha,
          short = short,
          date = date,
          author = author,
          subject = subject,
          path = path,
          parent_path = parent_path or path,
        }
      end
    end
  end
  return entries
end

---List the commits that touched `bufname`'s file, newest first (git log's
---own order) -- asynchronous, since `git log` is a subprocess (same reasoning
---as `core.git.resolve`).
---@param bufname string  A path -- need not be an open buffer's name
---@param max_entries integer  `--max-count`, caps how many commits are walked
---@param cb fun(entries: DiffNvim.HistoryEntry[]|nil, err: string|nil): nil
---@return nil
function M.log(bufname, max_entries, cb)
  if type(vim.system) ~= "function" then
    return cb(nil, "file history requires Neovim 0.10+ (vim.system)")
  end
  if fn.executable("git") ~= 1 then
    return cb(nil, "git executable not found on PATH")
  end
  if type(bufname) ~= "string" or bufname == "" then
    return cb(nil, "file history needs a file path")
  end

  local abspath = vim.fs.normalize(fn.fnamemodify(bufname, ":p"))
  local root = git.repo_root(vim.fs.dirname(abspath))
  if not root then
    return cb(nil, "not inside a git repository")
  end
  if abspath:sub(1, #root + 1) ~= root .. "/" then
    return cb(nil, "file is outside the git repo root")
  end
  local rel = abspath:sub(#root + 2)

  local fmt = RS .. "%H" .. FS .. "%h" .. FS .. "%ad" .. FS .. "%an" .. FS .. "%s"
  local argv = {
    "git",
    "-C",
    root,
    "log",
    "--follow",
    "--name-status",
    "--date=short",
    "--max-count=" .. tostring(max_entries),
    "--pretty=format:" .. fmt,
    "--",
    rel,
  }

  local ok = pcall(function()
    vim.system(argv, { text = true }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          local msg = (type(res.stderr) == "string" and res.stderr ~= "") and vim.trim(res.stderr)
            or "git log failed"
          return cb(nil, msg)
        end

        local entries = M.parse(res.stdout or "")
        -- A merge commit's entry has no body line to parse a path from (see
        -- M.parse) -- fall back to the pathspec that found it in the first
        -- place, the only path guaranteed to be correct for that one entry.
        for _, entry in ipairs(entries) do
          entry.path = entry.path or rel
          entry.parent_path = entry.parent_path or rel
        end

        if #entries == 0 then
          return cb(nil, "no history found for this file")
        end
        cb(entries, nil)
      end)
    end)
  end)
  if not ok then
    cb(nil, "git invocation failed")
  end
end

---Diff one history entry against its parent, through the exact same pipeline
---(`core.execute`) every other :Diff view/output combination uses -- the only
---new part is naming the two sides as `git:<sha>:<path>` (see
---`core.git.resolve`'s explicit-path spec).
---
---A root commit (no parent) fails here the same way `:Diff target=git:<rev
---with-no-parent>` always has: `git show <sha>^:...` reports an invalid
---revision, surfaced through the ordinary error path. Diffing a root commit
---against an empty tree is not built -- a rare enough case (the *first*
---commit of a file's whole history) that the plain error was judged not
---worth a second, empty-source code path.
---@param entry DiffNvim.HistoryEntry
---@param ctx DiffNvim.Context
---@param opts { view: DiffNvim.View, output: DiffNvim.Output }
---@param on_done? DiffNvim.RunOpts.OnDone
---@return nil
function M.diff_entry(entry, ctx, opts, on_done)
  require("diff.core").execute({
    target = "git:" .. entry.sha .. ":" .. entry.path,
    source = "git:" .. entry.sha .. "^:" .. entry.parent_path,
    view = opts.view,
    output = opts.output,
  }, ctx, on_done)
end

---One picker-list line per entry: short hash, date, author, subject.
---@internal
---@param entry DiffNvim.HistoryEntry
---@return string
local function format_entry(entry)
  return string.format("%s  %s  %-15s  %s", entry.short, entry.date, entry.author, entry.subject)
end

---Parse `raw_args` (`[path] [view=…] [output=…]`) and run the interactive
---file-history workflow: list commits touching the file, let the user pick
---one, then diff it against its parent.
---@param raw_args string
---@param run_opts? DiffNvim.RunOpts
---@return nil
function M.run(raw_args, run_opts)
  local core = require("diff.core")
  local config = require("diff.config")
  local resolve = require("diff.core.resolve")

  local cfg = config.get().diff
  local kv, unknown_kv = resolve.parse_args(type(raw_args) == "string" and raw_args or "", {
    "view",
    "output",
  })
  if #unknown_kv > 0 then
    notify.warn(
      string.format(
        "Unknown arg key(s): %s -- ignoring (accepted: view, output)",
        table.concat(unknown_kv, ", ")
      )
    )
  end

  local validate = require("diff.util.validate")
  local valid_views, valid_outputs = core.valid_lists()

  local view = kv.view or cfg.default_view
  if not validate.is_one_of(view, valid_views) then
    local err = string.format("Unknown view=%q  (valid: %s)", view, table.concat(valid_views, ", "))
    notify.error(err)
    if type(run_opts) == "table" and type(run_opts.on_done) == "function" then
      pcall(run_opts.on_done, nil, err)
    end
    return
  end

  local output = kv.output or cfg.default_output
  if not validate.is_one_of(output, valid_outputs) then
    local err =
      string.format("Unknown output=%q  (valid: %s)", output, table.concat(valid_outputs, ", "))
    notify.error(err)
    if type(run_opts) == "table" and type(run_opts.on_done) == "function" then
      pcall(run_opts.on_done, nil, err)
    end
    return
  end

  local source_bufnr = api.nvim_get_current_buf()
  local ctx = {
    source_bufnr = source_bufnr,
    origin_win = api.nvim_get_current_win(),
    range = nil,
  }

  -- Whatever is left after stripping every recognized key=value pair is the
  -- optional path positional -- same simple, non-quote-aware token model
  -- core.resolve.parse_args already uses for this grammar.
  local path = vim.trim((raw_args or ""):gsub("%a+=[^%s]+", ""))
  local bufname = (path ~= "") and path or api.nvim_buf_get_name(source_bufnr)

  local function fail(err)
    if type(run_opts) == "table" and type(run_opts.on_done) == "function" then
      local ok, caller_err = pcall(run_opts.on_done, nil, err)
      if not ok then
        notify.error("on_done failed: " .. tostring(caller_err))
      end
    end
  end

  M.log(bufname, cfg.history_max_entries, function(entries, err)
    if not entries then
      err = err or "could not list file history"
      notify.error(err)
      fail(err)
      return
    end

    -- Looked up by label text rather than relied on via the picker's `idx`
    -- return: pickers_bridge documents that its adapter can hand back a
    -- matched item with a nil index (an item it could not find its own
    -- position for), and run_buffers (core/init.lua) already established
    -- this by-label pattern for exactly that reason.
    local items, by_label = {}, {}
    for i, entry in ipairs(entries) do
      local label = format_entry(entry)
      items[i] = label
      by_label[label] = entry
    end

    core.select_fn()(items, { prompt = "File history:" }, function(choice)
      local entry = choice and by_label[choice]
      if not entry then
        notify.info("Diff cancelled")
        fail("Diff cancelled")
        return
      end
      M.diff_entry(entry, ctx, {
        view = view --[[@as DiffNvim.View]],
        output = output --[[@as DiffNvim.Output]],
      }, run_opts and run_opts.on_done)
    end)
  end)
end

return M

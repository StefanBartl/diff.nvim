---@module 'diff.core.directory'
--- Directory/recursive diff: `source=`/`target=` both pointing at real,
--- existing directories compares the two trees file-by-file and produces a
--- per-file summary instead of a single unified diff — feeding two whole
--- trees' concatenated bytes through `vim.diff` wouldn't mean anything, so
--- this is its own code path with its own (smaller) `output=` handling
--- rather than a variant of `core.init`'s normal two-lines-in dispatch.
---
--- Hidden path segments (anything starting with `.` — `.git`, `.hg`, …) are
--- always excluded, so pointing this at a real repository checkout doesn't
--- also diff its VCS internals.

local fn = vim.fn

local notify = require("diff.util.notify")
local render = require("diff.core.render")
local scratch = require("diff.core.scratch")
local list = require("lib.nvim.ui.list")

local M = {}

---Whether `spec` is usable as one side of a directory diff: a real, existing
---directory on disk. Deliberately excludes every other specifier kind
---("current"/"clipboard"/a buffer number/`git:<rev>`/`http(s)://…`) — none
---of those denote a directory.
---@param spec any
---@return boolean
function M.is_directory_spec(spec)
  if type(spec) ~= "string" or spec == "" then
    return false
  end
  if spec == "current" or spec == "clipboard" or tonumber(spec) ~= nil then
    return false
  end
  if spec:sub(1, 4) == "git:" or spec:find("^https?://") then
    return false
  end
  return fn.isdirectory(fn.expand(spec)) == 1
end

---@internal
---Whether any path segment of `rel` (forward-slash separated) starts with
---`.` — used to drop VCS/dotfile noise (`.git/…`, `.DS_Store`, …).
---@param rel string
---@return boolean
local function has_hidden_segment(rel)
  return rel:match("^%.") ~= nil or rel:find("/%.") ~= nil
end

---@internal
---Recursively list every file under `dir`, as slash-separated paths
---relative to `dir` (so the same file existing in both trees compares
---equal), hidden segments excluded, sorted. Capped at `max_files` — this is
---meant for a source tree someone deliberately pointed `:Diff` at, not for
---silently walking arbitrarily large directories.
---@param dir string  Absolute directory path.
---@param max_files integer
---@return string[]|nil rel_paths, string|nil err
local function list_files(dir, max_files)
  local abs = vim.fs.normalize(fn.fnamemodify(dir, ":p"))
  local rel_paths = {}
  for name, kind in vim.fs.dir(abs, { depth = math.huge }) do
    if kind == "file" and not has_hidden_segment(name) then
      rel_paths[#rel_paths + 1] = name
      if #rel_paths > max_files then
        return nil,
          string.format(
            "more than %d files under %s — narrow the directory or raise opts.diff.directory_max_files",
            max_files,
            abs
          )
      end
    end
  end
  table.sort(rel_paths)
  return rel_paths, nil
end

---@internal
---Union of two sorted string lists, sorted.
---@param a string[]
---@param b string[]
---@return string[]
local function union_sorted(a, b)
  local set = {}
  for _, v in ipairs(a) do
    set[v] = true
  end
  for _, v in ipairs(b) do
    set[v] = true
  end
  local out = {}
  for v in pairs(set) do
    out[#out + 1] = v
  end
  table.sort(out)
  return out
end

---@class DiffNvim.Directory.FileEntry
---@field rel     string   Path relative to both directory roots
---@field status  "M"|"A"|"D"  Modified / only-in-target (added) / only-in-source (deleted)
---@field added   integer
---@field removed integer

---@internal
---Compare two directory trees file-by-file.
---@param source_dir string
---@param target_dir string
---@param algorithm string
---@param ctxlen integer
---@param max_files integer
---@return DiffNvim.Directory.FileEntry[]|nil entries, string|nil err
local function diff_trees(source_dir, target_dir, algorithm, ctxlen, max_files)
  local src_files, src_err = list_files(source_dir, max_files)
  if not src_files then
    return nil, src_err
  end
  local tgt_files, tgt_err = list_files(target_dir, max_files)
  if not tgt_files then
    return nil, tgt_err
  end

  local src_set, tgt_set = {}, {}
  for _, v in ipairs(src_files) do
    src_set[v] = true
  end
  for _, v in ipairs(tgt_files) do
    tgt_set[v] = true
  end

  local entries = {}
  for _, rel in ipairs(union_sorted(src_files, tgt_files)) do
    local in_src, in_tgt = src_set[rel] == true, tgt_set[rel] == true
    if in_src and in_tgt then
      local a_lines = fn.readfile(source_dir .. "/" .. rel)
      local b_lines = fn.readfile(target_dir .. "/" .. rel)
      local stats = render.compute_stats(a_lines, b_lines, algorithm, ctxlen)
      if stats and (stats.added > 0 or stats.removed > 0) then
        entries[#entries + 1] =
          { rel = rel, status = "M", added = stats.added, removed = stats.removed }
      end
    elseif in_tgt then
      local n = #fn.readfile(target_dir .. "/" .. rel)
      entries[#entries + 1] = { rel = rel, status = "A", added = n, removed = 0 }
    else
      local n = #fn.readfile(source_dir .. "/" .. rel)
      entries[#entries + 1] = { rel = rel, status = "D", added = 0, removed = n }
    end
  end
  return entries, nil
end

---@internal
---Render `entries` as a flat list of summary lines, one per changed file.
---@param entries DiffNvim.Directory.FileEntry[]
---@param source_label string
---@param target_label string
---@return string[]
local function format_summary(entries, source_label, target_label)
  local lines = { string.format("%s -> %s", source_label, target_label), "" }
  if #entries == 0 then
    lines[#lines + 1] = "No differences found"
    return lines
  end
  local total_added, total_removed = 0, 0
  for _, e in ipairs(entries) do
    total_added = total_added + e.added
    total_removed = total_removed + e.removed
    lines[#lines + 1] = string.format("  %s  +%-5d -%-5d  %s", e.status, e.added, e.removed, e.rel)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format(
    "%d file%s changed, +%d -%d",
    #entries,
    (#entries == 1) and "" or "s",
    total_added,
    total_removed
  )
  return lines
end

---Run a directory diff and deliver it per `output` — the same values
---`core.init` accepts, minus the ones that only make sense for a single
---unified diff: `view=` is ignored (there is no native-diffmode notion of
---"diff these two trees"), and `output=buffer` always shows the summary in
---one scratch buffer rather than a side-by-side pair.
---@param source_dir string
---@param target_dir string
---@param source_label string
---@param target_label string
---@param output DiffNvim.Output
---@param cfg DiffNvim.Config.Diff
---@return nil
function M.run(source_dir, target_dir, source_label, target_label, output, cfg)
  local entries, err =
    diff_trees(source_dir, target_dir, cfg.algorithm, cfg.ctxlen, cfg.directory_max_files)
  if not entries then
    notify.error(err or "could not diff directories")
    return
  end

  if cfg.stat_list and cfg.stat_list ~= "off" then
    local items = {}
    for _, e in ipairs(entries) do
      local dir_for_path = (e.status == "D") and source_dir or target_dir
      items[#items + 1] = {
        filename = vim.fs.normalize(dir_for_path .. "/" .. e.rel),
        lnum = 1,
        text = string.format("%s  +%d -%d  %s", e.status, e.added, e.removed, e.rel),
      }
    end
    if #items > 0 then
      list.set({
        items = items,
        title = string.format("diff.nvim: %s -> %s", source_label, target_label),
        loclist = cfg.stat_list == "loc",
        action = (cfg.stat_list_mode == "replace") and " " or "a",
      })
    end
  end

  if output == "stat" then
    if #entries == 0 then
      notify.info("No differences found")
      return
    end
    local total_added, total_removed = 0, 0
    for _, e in ipairs(entries) do
      total_added = total_added + e.added
      total_removed = total_removed + e.removed
    end
    notify.info(
      string.format(
        "%s -> %s  %d file%s changed, +%d -%d",
        source_label,
        target_label,
        #entries,
        (#entries == 1) and "" or "s",
        total_added,
        total_removed
      )
    )
    return
  end

  local lines = format_summary(entries, source_label, target_label)

  if output == "prompt" then
    vim.api.nvim_echo({ { table.concat(lines, "\n"), "Normal" } }, true, {})
    return
  end
  if output == "file" then
    local tmp = fn.tempname() .. ".diffstat"
    local ok = pcall(fn.writefile, lines, tmp)
    if not ok then
      notify.error("could not write directory diff to: " .. tmp)
      return
    end
    notify.info(string.format("Directory diff written to: %s", tmp))
    return
  end
  if output == "clipboard" then
    fn.setreg("+", table.concat(lines, "\n"))
    notify.info("Directory diff summary copied to clipboard")
    return
  end

  -- output == "buffer" (default) — one scratch buffer, no native diffmode.
  local buf = scratch.create(lines, string.format("[DirDiff] %s -> %s", source_label, target_label))
  vim.cmd(string.format("silent! split | buffer %d", buf))
end

return M

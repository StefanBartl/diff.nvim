---@module 'diff_nvim.core.render'
---@brief Output renderers for diff.nvim (buffer / prompt / file / clipboard).
---@description
--- Each renderer takes already-resolved line arrays and produces a specific kind
--- of output. The unified-diff computation is shared via `compute_unified`.
--- Renderers may notify the user because this is the UI-facing layer.

local api = vim.api
local fn  = vim.fn

local notify   = require("diff_nvim.util.notify")
local validate = require("diff_nvim.util.validate")
local scratch  = require("diff_nvim.core.scratch")
local window   = require("lib.nvim.window")

local M = {}

---Compute a unified diff between two line arrays.
---@param a_lines string[]
---@param b_lines string[]
---@param algorithm string
---@param ctxlen integer
---@return string|nil unified, string|nil err
function M.compute_unified(a_lines, b_lines, algorithm, ctxlen)
  local ok, result = pcall(vim.diff,
    table.concat(a_lines, "\n") .. "\n",
    table.concat(b_lines, "\n") .. "\n",
    { result_type = "unified", algorithm = algorithm, ctxlen = ctxlen }
  )
  if not ok or type(result) ~= "string" then
    return nil, "vim.diff failed: " .. tostring(result)
  end
  return result, nil
end

---@class DiffNvim.Stats
---@field added   integer  Number of added lines (`^+`, excluding the `+++` header)
---@field removed integer  Number of removed lines (`^-`, excluding the `---` header)
---@field hunks   integer  Number of hunks (`^@@` markers)

---Derive `+N -M, K hunks` statistics from two line arrays.
---Pure: computes the unified diff internally and counts, never notifies.
---@param a_lines string[]
---@param b_lines string[]
---@param algorithm string
---@param ctxlen integer
---@return DiffNvim.Stats|nil stats, string|nil err
function M.compute_stats(a_lines, b_lines, algorithm, ctxlen)
  local unified, err = M.compute_unified(a_lines, b_lines, algorithm, ctxlen)
  if not unified then
    return nil, err
  end

  -- Raw vim.diff "unified" output has no "---"/"+++" file-header lines (those
  -- are only synthesized by with_header() below) — it starts directly at the
  -- first "@@" hunk. So classify purely by the first byte; a removed/added
  -- line whose own content happens to start with "--"/"++" (e.g. a Lua
  -- comment "-- foo") must still count, not be mistaken for a header.
  local added, removed, hunks = 0, 0, 0
  for _, line in ipairs(vim.split(unified, "\n", { plain = true })) do
    local first = line:sub(1, 1)
    if first == "@" and line:sub(1, 2) == "@@" then
      hunks = hunks + 1
    elseif first == "+" then
      added = added + 1
    elseif first == "-" then
      removed = removed + 1
    end
  end

  return { added = added, removed = removed, hunks = hunks }, nil
end

---Format a stats table as a compact human-readable summary.
---@param stats DiffNvim.Stats
---@return string
function M.format_stats(stats)
  return string.format("+%d -%d, %d hunk%s",
    stats.added, stats.removed, stats.hunks, (stats.hunks == 1) and "" or "s")
end

---Report `+N -M, K hunks` for the diff as a notification.
---@param a_lines string[]
---@param b_lines string[]
---@param a_label string
---@param b_label string
---@param algorithm string
---@param ctxlen integer
---@return nil
function M.stat(a_lines, b_lines, a_label, b_label, algorithm, ctxlen)
  local stats, err = M.compute_stats(a_lines, b_lines, algorithm, ctxlen)
  if not stats then
    notify.error(err or "could not compute diff")
    return
  end
  if stats.added == 0 and stats.removed == 0 then
    notify.info("No differences found")
    return
  end
  notify.info(string.format("%s -> %s  %s", a_label, b_label, M.format_stats(stats)))
end

---Build the unified-diff header lines + body as a flat list.
---@param unified string
---@param a_label string
---@param b_label string
---@return string[]
local function with_header(unified, a_label, b_label)
  local header = string.format("--- %s\n+++ %s\n", a_label, b_label) .. unified
  return vim.split(header, "\n", { plain = true })
end

---Open a split (or a new tab), load the scratch buffer, enable native
---diffmode in both windows.
---@param origin_win integer
---@param scratch_buf integer
---@param view DiffNvim.View  "vsplit"|"split"|"tab"
---@return nil
function M.side_by_side(origin_win, scratch_buf, view)
  if not validate.win_valid(origin_win) then
    notify.error("origin window is no longer valid")
    return
  end

  -- "tab" opens a fresh tab showing the origin buffer beside the scratch, so
  -- the diff never disturbs the existing window layout.
  if view == "tab" then
    local origin_buf = api.nvim_win_get_buf(origin_win)
    vim.cmd("tabnew")
    vim.cmd(string.format("silent! buffer %d", origin_buf))
    local left = api.nvim_get_current_win()
    vim.cmd(string.format("silent! vsplit | buffer %d", scratch_buf))
    local right = api.nvim_get_current_win()
    if validate.win_valid(left) then
      vim.wo[left].diff = true
    end
    if validate.win_valid(right) then
      vim.wo[right].diff = true
    end
    return
  end

  api.nvim_set_current_win(origin_win)
  local split_cmd = (view == "split") and "split" or "vsplit"
  vim.cmd(string.format("silent! %s | buffer %d", split_cmd, scratch_buf))

  local new_win = api.nvim_get_current_win()
  if validate.win_valid(new_win) then
    vim.wo[new_win].diff = true
  end
  if validate.win_valid(origin_win) then
    api.nvim_set_current_win(origin_win)
    vim.wo[origin_win].diff = true
  end
  if validate.win_valid(new_win) then
    api.nvim_set_current_win(new_win)
  end
end

---Open a three-way native diffmode: the origin window's live buffer (left,
---still editable — this is the point of a merge workflow: :diffget/:diffput
---write straight into the file you'll save) alongside `base_buf` (middle)
---and `target_buf` (right), or stacked/tabbed per `view`. Neovim's diffmode
---automatically diffs 3+ windows against each other; no extra logic is
---needed beyond opening the windows and setting 'diff' on each.
---@see docs/three-way-diff.md
---@param origin_win integer
---@param base_buf integer
---@param target_buf integer
---@param view "vsplit"|"split"|"tab"
---@return nil
function M.three_way(origin_win, base_buf, target_buf, view)
  if not validate.win_valid(origin_win) then
    notify.error("origin window is no longer valid")
    return
  end

  local split_cmd = (view == "split") and "split" or "vsplit"

  if view == "tab" then
    local origin_buf = api.nvim_win_get_buf(origin_win)
    vim.cmd("tabnew")
    vim.cmd(string.format("silent! buffer %d", origin_buf))
    local left = api.nvim_get_current_win()
    vim.cmd(string.format("silent! vsplit | buffer %d", base_buf))
    local mid = api.nvim_get_current_win()
    vim.cmd(string.format("silent! vsplit | buffer %d", target_buf))
    local right = api.nvim_get_current_win()
    for _, w in ipairs({ left, mid, right }) do
      if validate.win_valid(w) then
        vim.wo[w].diff = true
      end
    end
    return
  end

  api.nvim_set_current_win(origin_win)
  vim.cmd(string.format("silent! %s | buffer %d", split_cmd, base_buf))
  local mid_win = api.nvim_get_current_win()

  vim.cmd(string.format("silent! %s | buffer %d", split_cmd, target_buf))
  local right_win = api.nvim_get_current_win()

  for _, w in ipairs({ origin_win, mid_win, right_win }) do
    if validate.win_valid(w) then
      vim.wo[w].diff = true
    end
  end

  if validate.win_valid(origin_win) then
    api.nvim_set_current_win(origin_win)
  end
end

---Open the given scratch buffer in a centered floating window and map `q`
---(plus <Esc>) to close it.
---@param buf integer
---@param line_count integer  Number of lines in the buffer (for sizing)
---@return nil
local function open_float(buf, line_count)
  local width  = math.min(math.max(vim.o.columns - 8, 20), 120)
  local height = math.min(math.max(line_count, 1), math.max(vim.o.lines - 6, 3))
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = math.max((vim.o.lines - height) / 2 - 1, 0),
    col      = math.max((vim.o.columns - width) / 2, 0),
    style    = "minimal",
    border   = "rounded",
    title    = " Diff ",
  })
  -- Floats want an obvious close key; the split/inline views rely on :q or
  -- :DiffClear instead, which is why this is float-local.
  if validate.win_valid(win) then
    window.nice_quit(win, { keys = { "q", "<Esc>" } })
  end
end

---@type integer  Extmark namespace for inline-view word-level diff highlights
local WORD_DIFF_NS = api.nvim_create_namespace("diff_nvim_word_diff")

---Compute byte-range spans that changed between two single lines, using
---vim.diff at byte granularity (each byte of the line becomes one "line" of
---a synthetic multi-line document, fed through result_type="indices"). Byte-
---based rather than UTF-8-codepoint-aware: on non-ASCII lines a multi-byte
---codepoint may straddle a highlighted/unhighlighted boundary — an accepted
---simplification, since extmark columns are byte offsets anyway.
---@param a string  Old line content (without the unified-diff "-" prefix)
---@param b string  New line content (without the unified-diff "+" prefix)
---@param algorithm string
---@return { a: [integer, integer][], b: [integer, integer][] }|nil  0-based [start,end) byte ranges per side
local function word_diff_ranges(a, b, algorithm)
  if a == b then
    return { a = {}, b = {} }
  end

  local function explode(s)
    local bytes = {}
    for i = 1, #s do
      bytes[i] = s:sub(i, i)
    end
    return table.concat(bytes, "\n")
  end

  local ok, hunks = pcall(vim.diff, explode(a), explode(b), {
    result_type = "indices",
    algorithm = algorithm,
  })
  if not ok or type(hunks) ~= "table" then
    return nil
  end

  local ranges = { a = {}, b = {} }
  for _, h in ipairs(hunks) do
    local start_a, count_a, start_b, count_b = h[1], h[2], h[3], h[4]
    if count_a > 0 then
      ranges.a[#ranges.a + 1] = { start_a - 1, start_a - 1 + count_a }
    end
    if count_b > 0 then
      ranges.b[#ranges.b + 1] = { start_b - 1, start_b - 1 + count_b }
    end
  end
  return ranges
end

---Find runs of consecutive "-" lines immediately followed by an equal-length
---run of consecutive "+" lines in the unified-diff body, and highlight the
---changed byte spans within each paired (old, new) line using `DiffText` —
---the same group Neovim's native diffmode uses for intra-line changes.
---Skips the fixed two-line "---"/"+++" file header (by position, not content
---— a removed/added line's own text may start with "--"/"++") and any run
---where the removed/added counts differ (ambiguous pairing; still shown,
---just without word highlighting).
---@param buf integer
---@param lines string[]  The exact lines written into `buf` (from with_header)
---@param algorithm string
---@return nil
local function apply_word_diff(buf, lines, algorithm)
  local i = 3 -- lines[1]/[2] are always the "---"/"+++" file header
  local n = #lines
  while i <= n do
    if lines[i]:sub(1, 1) == "-" then
      local del_start = i
      local j = i
      while j <= n and lines[j]:sub(1, 1) == "-" do
        j = j + 1
      end
      local del_count = j - del_start

      local add_start = j
      local k = j
      while k <= n and lines[k]:sub(1, 1) == "+" do
        k = k + 1
      end
      local add_count = k - add_start

      if del_count == add_count and del_count > 0 then
        for off = 0, del_count - 1 do
          local a_line = lines[del_start + off]:sub(2)
          local b_line = lines[add_start + off]:sub(2)
          local ranges = word_diff_ranges(a_line, b_line, algorithm)
          if ranges then
            for _, r in ipairs(ranges.a) do
              pcall(api.nvim_buf_set_extmark, buf, WORD_DIFF_NS, del_start + off - 1, r[1],
                { end_col = r[2], hl_group = "DiffText" })
            end
            for _, r in ipairs(ranges.b) do
              pcall(api.nvim_buf_set_extmark, buf, WORD_DIFF_NS, add_start + off - 1, r[1],
                { end_col = r[2], hl_group = "DiffText" })
            end
          end
        end
      end
      i = k
    else
      i = i + 1
    end
  end
end

---Show the unified diff inside a single scratch buffer (ft=diff), either in a
---split (`layout="split"`, default) or a floating window (`layout="float"`).
---@param origin_win integer
---@param a_lines string[]
---@param b_lines string[]
---@param a_label string
---@param b_label string
---@param algorithm string
---@param ctxlen integer
---@param opts? { layout?: "split"|"float", word_diff?: boolean }
---@return integer|nil bufnr  The inline scratch buffer, or nil when nothing rendered
function M.inline(origin_win, a_lines, b_lines, a_label, b_label, algorithm, ctxlen, opts)
  opts = opts or {}

  local unified, err = M.compute_unified(a_lines, b_lines, algorithm, ctxlen)
  if not unified then
    notify.error(err or "could not compute diff")
    return nil
  end
  if unified == "" then
    notify.info("No differences found")
    return nil
  end

  local lines = with_header(unified, a_label, b_label)
  local buf = scratch.create(lines, string.format("[Diff] %s -> %s", a_label, b_label), "diff")

  if opts.word_diff ~= false then
    apply_word_diff(buf, lines, algorithm)
  end

  if opts.layout == "float" then
    open_float(buf, #lines)
    return buf
  end

  if validate.win_valid(origin_win) then
    api.nvim_set_current_win(origin_win)
  end
  vim.cmd(string.format("silent! split | buffer %d", buf))
  return buf
end

---Echo the unified diff to the message area.
---@param a_lines string[]
---@param b_lines string[]
---@param a_label string
---@param b_label string
---@param algorithm string
---@param ctxlen integer
---@return nil
function M.prompt(a_lines, b_lines, a_label, b_label, algorithm, ctxlen)
  local unified, err = M.compute_unified(a_lines, b_lines, algorithm, ctxlen)
  if not unified then
    notify.error(err or "could not compute diff")
    return
  end
  if unified == "" then
    notify.info("No differences found")
    return
  end
  api.nvim_echo(
    { { string.format("--- %s\n+++ %s\n", a_label, b_label) .. unified, "Normal" } },
    true, {}
  )
end

---Write the unified diff to a temp file and report its path.
---@param a_lines string[]
---@param b_lines string[]
---@param a_label string
---@param b_label string
---@param algorithm string
---@param ctxlen integer
---@return nil
function M.file(a_lines, b_lines, a_label, b_label, algorithm, ctxlen)
  local unified, err = M.compute_unified(a_lines, b_lines, algorithm, ctxlen)
  if not unified then
    notify.error(err or "could not compute diff")
    return
  end
  if unified == "" then
    notify.info("No differences found")
    return
  end
  local tmp = fn.tempname() .. ".diff"
  local ok = pcall(fn.writefile, with_header(unified, a_label, b_label), tmp)
  if not ok then
    notify.error("could not write diff to: " .. tmp)
    return
  end
  notify.info(string.format("Diff written to: %s", tmp))
end

---Copy the unified diff to the system clipboard register (+).
---@param a_lines string[]
---@param b_lines string[]
---@param a_label string
---@param b_label string
---@param algorithm string
---@param ctxlen integer
---@return nil
function M.clipboard(a_lines, b_lines, a_label, b_label, algorithm, ctxlen)
  local unified, err = M.compute_unified(a_lines, b_lines, algorithm, ctxlen)
  if not unified then
    notify.error(err or "could not compute diff")
    return
  end
  if unified == "" then
    notify.info("No differences found")
    return
  end
  local text = string.format("--- %s\n+++ %s\n", a_label, b_label) .. unified
  fn.setreg("+", text)
  notify.info("Unified diff copied to clipboard")
end

return M

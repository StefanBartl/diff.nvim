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

  local added, removed, hunks = 0, 0, 0
  for _, line in ipairs(vim.split(unified, "\n", { plain = true })) do
    local first = line:sub(1, 1)
    if first == "@" and line:sub(1, 2) == "@@" then
      hunks = hunks + 1
    elseif first == "+" and line:sub(1, 3) ~= "+++" then
      added = added + 1
    elseif first == "-" and line:sub(1, 3) ~= "---" then
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

---Open a split, load the scratch buffer, enable native diffmode in both windows.
---@param origin_win integer
---@param scratch_buf integer
---@param view DiffNvim.View  "vsplit"|"split"
---@return nil
function M.side_by_side(origin_win, scratch_buf, view)
  if not validate.win_valid(origin_win) then
    notify.error("origin window is no longer valid")
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

---Show the unified diff inside a single scratch buffer (ft=diff) in a split.
---@param origin_win integer
---@param a_lines string[]
---@param b_lines string[]
---@param a_label string
---@param b_label string
---@param algorithm string
---@param ctxlen integer
---@return integer|nil bufnr  The inline scratch buffer, or nil when nothing rendered
function M.inline(origin_win, a_lines, b_lines, a_label, b_label, algorithm, ctxlen)
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

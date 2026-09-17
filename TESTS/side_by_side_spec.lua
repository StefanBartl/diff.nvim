-- TESTS/side_by_side_spec.lua — the side-by-side views (view=vsplit|split|tab)
-- honouring source=/a range, and how a buffer specifier labels itself.
--
-- Both were found by an integrating plugin (data.nvim's filter preview) that
-- hands :Diff two scratch buffers via `source=<n> target=<n>`: the left-hand
-- pane used to show whatever the origin window happened to hold, and the
-- unified-diff header read "--- 7 / +++ 8".

return function(H)
  local eq, ok = H.eq, H.ok
  local core = require("diff.core")
  local render = require("diff.core.render")
  local scratch = require("diff.core.scratch")

  local saved_notify = vim.notify
  local function silence()
    -- Test double over a typed surface; restored by `restore()`.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
  end
  local function restore()
    vim.notify = saved_notify
  end

  ---One tab, one window, no diffmode — 'diff' is a *window* option, so a
  ---previous spec's leftover diffmode survives `tabonly`/`only` and would be
  ---counted as part of this spec's diff.
  local function reset()
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    vim.cmd("silent! diffoff!")
  end

  ---Buffers currently shown in a diffmode window, keyed by handle.
  local function diffed_bufs()
    local out = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.wo[w].diff then
        out[vim.api.nvim_win_get_buf(w)] = true
      end
    end
    return out
  end

  local function first_line(bufnr)
    return (vim.api.nvim_buf_get_lines(bufnr, 0, 1, false))[1]
  end

  -- source=<bufnr> is the left-hand side, not the origin window's buffer ----
  reset()
  local a = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(a, 0, -1, false, { "SIDE-A" })
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "SIDE-B" })
  local c = H.scratch()
  vim.api.nvim_buf_set_lines(c, 0, -1, false, { "UNRELATED-C" })
  local origin_win = vim.api.nvim_get_current_win()

  silence()
  core.run(string.format("source=%d target=%d view=vsplit", a, b))
  restore()

  local diffed = diffed_bufs()
  eq(vim.tbl_count(diffed), 2, "source=<bufnr>: exactly two windows are in diffmode")
  ok(not diffed[c], "source=<bufnr>: the unrelated origin buffer is not part of the diff")
  ok(not vim.wo[origin_win].diff, "source=<bufnr>: the origin window stays out of diffmode")
  eq(vim.api.nvim_win_get_buf(origin_win), c, "source=<bufnr>: origin window keeps its buffer")

  local contents = {}
  for bufnr in pairs(diffed) do
    contents[first_line(bufnr)] = true
  end
  ok(contents["SIDE-A"], "source=<bufnr>: the source side's content is diffed")
  ok(contents["SIDE-B"], "source=<bufnr>: the target side's content is diffed")

  scratch.cleanup_all()
  reset()

  -- source=current (no range) keeps the origin window live and editable ------
  local live = H.scratch()
  vim.api.nvim_buf_set_lines(live, 0, -1, false, { "LIVE" })
  local live_win = vim.api.nvim_get_current_win()
  local tgt_file = vim.fn.tempname()
  vim.fn.writefile({ "FROM-DISK" }, tgt_file)

  silence()
  core.run(string.format("target=%s view=vsplit", tgt_file))
  restore()

  eq(#vim.api.nvim_list_wins(), 2, "source=current: only the target gets a new window")
  ok(vim.wo[live_win].diff, "source=current: the origin window is part of the diff")
  eq(
    vim.api.nvim_win_get_buf(live_win),
    live,
    "source=current: origin window shows the live buffer"
  )
  ok(vim.bo[live].modifiable, "source=current: the left-hand side stays editable")

  scratch.cleanup_all()
  reset()

  -- A range narrows the left-hand side, for view=vsplit too ------------------
  local ranged = H.scratch()
  vim.api.nvim_buf_set_lines(ranged, 0, -1, false, { "one", "two", "three", "four" })
  local ranged_win = vim.api.nvim_get_current_win()
  local range_tgt = vim.fn.tempname()
  vim.fn.writefile({ "two", "CHANGED" }, range_tgt)

  silence()
  core.run(string.format("target=%s view=vsplit", range_tgt), { line1 = 2, line2 = 3 })
  restore()

  ok(not vim.wo[ranged_win].diff, "range: the whole-buffer origin window stays out of the diff")
  local range_sides = {}
  for bufnr in pairs(diffed_bufs()) do
    range_sides[table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), ",")] = true
  end
  ok(range_sides["two,three"], "range: only the selected lines form the left-hand side")
  ok(range_sides["two,CHANGED"], "range: the target is still taken in full")

  scratch.cleanup_all()
  reset()

  -- view=tab: a materialized source replaces the origin buffer in the new tab
  local tab_origin = H.scratch()
  vim.api.nvim_buf_set_lines(tab_origin, 0, -1, false, { "UNRELATED-C" })
  local tabs_before = #vim.api.nvim_list_tabpages()

  silence()
  core.run(string.format("source=%d target=%d view=tab", a, b))
  restore()

  eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "view=tab: opens exactly one new tab")
  local tab_contents = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.wo[w].diff then
      tab_contents[first_line(vim.api.nvim_win_get_buf(w))] = true
    end
  end
  eq(vim.tbl_count(tab_contents), 2, "view=tab: two diffmode windows in the new tab")
  ok(tab_contents["SIDE-A"], "view=tab: the source side is shown, not the origin buffer")
  ok(tab_contents["SIDE-B"], "view=tab: the target side is shown")

  scratch.cleanup_all()
  reset()

  -- render.side_by_side() without source_buf: unchanged two-window behaviour -
  local plain_buf = H.scratch()
  local plain_win = vim.api.nvim_get_current_win()
  local tgt_scratch = scratch.create({ "target" }, "[Diff] plain")
  render.side_by_side(plain_win, tgt_scratch, "vsplit")
  eq(#vim.api.nvim_list_wins(), 2, "no source_buf: two windows")
  eq(vim.api.nvim_win_get_buf(plain_win), plain_buf, "no source_buf: origin window untouched")
  ok(vim.wo[plain_win].diff, "no source_buf: origin window is diffed")

  scratch.cleanup_all()
  reset()

  -- A buffer specifier labels itself by name, falling back to buf:N ----------
  local named = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(named, 0, -1, false, { "named" })
  pcall(vim.api.nvim_buf_set_name, named, "data://scoped (before)")
  local unnamed = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { "unnamed" })

  H.scratch()
  local echoed = {}
  local saved_echo = vim.api.nvim_echo
  -- Test double over a typed surface; restored right after the case.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_echo = function(chunks)
    echoed[#echoed + 1] = chunks[1][1]
  end
  silence()
  core.run(string.format("source=%d target=%d output=prompt", named, unnamed))
  restore()
  vim.api.nvim_echo = saved_echo

  local header = echoed[#echoed] or ""
  ok(
    header:find("--- data://scoped (before)", 1, true) ~= nil,
    "a named buffer specifier is labelled by its name, not its number"
  )
  ok(
    header:find("+++ buf:" .. unnamed, 1, true) ~= nil,
    "an unnamed buffer specifier falls back to buf:N"
  )

  -- Diffmode stays window-local: no leak into windows opened later ---------
  reset()
  local leak_buf = H.scratch()
  vim.api.nvim_buf_set_lines(leak_buf, 0, -1, false, { "LIVE" })
  local leak_tgt = vim.fn.tempname()
  vim.fn.writefile({ "ON-DISK" }, leak_tgt)

  silence()
  core.run(string.format("target=%s view=vsplit", leak_tgt))
  restore()

  eq(
    vim.api.nvim_get_option_value("diff", { scope = "global" }),
    false,
    "a diff does not turn the global 'diff' value on"
  )
  vim.cmd("tabnew")
  ok(
    not vim.wo[vim.api.nvim_get_current_win()].diff,
    "a tab opened while a diff is up is not itself in diffmode"
  )

  scratch.cleanup_all()
  for _, bufnr in ipairs({ a, b, named, unnamed }) do
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  reset()
end

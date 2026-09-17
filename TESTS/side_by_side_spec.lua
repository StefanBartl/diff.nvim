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

  ---Run `fn` with the doubles installed and always take them down again.
  ---A plain assign/restore pair leaves the double in place when an assertion
  ---between them throws, and every later spec then runs against this spec's
  ---stub -- one real failure plus a page of unrelated noise.
  ---@param fn fun(): any
  ---@return any
  local function guarded(fn)
    local okc, res = pcall(fn)
    restore()
    if not okc then
      error(res, 0)
    end
    return res
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
  -- Run for both split directions: they take different `split_cmd` values
  -- through the same branch, and only one of them used to be covered.
  local a = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(a, 0, -1, false, { "SIDE-A" })
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "SIDE-B" })

  for _, view in ipairs({ "vsplit", "split" }) do
    reset()
    local c = H.scratch()
    vim.api.nvim_buf_set_lines(c, 0, -1, false, { "UNRELATED-C" })
    local origin_win = vim.api.nvim_get_current_win()

    guarded(function()
      silence()
      core.run(string.format("source=%d target=%d view=%s", a, b, view))
    end)

    local diffed = diffed_bufs()
    eq(vim.tbl_count(diffed), 2, view .. ": exactly two windows are in diffmode")
    ok(not diffed[c], view .. ": the unrelated origin buffer is not part of the diff")
    ok(not vim.wo[origin_win].diff, view .. ": the origin window stays out of diffmode")
    eq(vim.api.nvim_win_get_buf(origin_win), c, view .. ": origin window keeps its buffer")

    local contents = {}
    for bufnr in pairs(diffed) do
      contents[first_line(bufnr)] = true
    end
    ok(contents["SIDE-A"], view .. ": the source side's content is diffed")
    ok(contents["SIDE-B"], view .. ": the target side's content is diffed")

    scratch.cleanup_all()
  end
  reset()

  -- source=current (no range) keeps the origin window live and editable ------
  local live = H.scratch()
  vim.api.nvim_buf_set_lines(live, 0, -1, false, { "LIVE" })
  local live_win = vim.api.nvim_get_current_win()
  local tgt_file = vim.fn.tempname()
  vim.fn.writefile({ "FROM-DISK" }, tgt_file)

  guarded(function()
    silence()
    core.run(string.format("target=%s view=vsplit", tgt_file))
  end)

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

  guarded(function()
    silence()
    core.run(string.format("target=%s view=vsplit", range_tgt), { line1 = 2, line2 = 3 })
  end)

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

  guarded(function()
    silence()
    core.run(string.format("source=%d target=%d view=tab", a, b))
  end)

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
  local saved_echo = vim.api.nvim_echo

  ---The unified diff `output=prompt` echoes for `args`, as a string.
  ---@param args string
  ---@return string
  local function echoed_diff(args)
    local echoed = {}
    return guarded(function()
      silence()
      -- Test double over a typed surface; restored below / by `guarded`.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_echo = function(chunks)
        echoed[#echoed + 1] = chunks[1][1]
      end
      core.run(args)
      vim.api.nvim_echo = saved_echo
      return echoed[#echoed] or ""
    end)
  end

  local header = echoed_diff(string.format("source=%d target=%d output=prompt", named, unnamed))
  ok(
    header:find("--- data://scoped (before)", 1, true) ~= nil,
    "a named buffer specifier is labelled by its name, not its number"
  )
  ok(
    header:find("+++ buf:" .. unnamed, 1, true) ~= nil,
    "an unnamed buffer specifier falls back to buf:N"
  )

  -- A label never adds lines to the two-line unified-diff header ------------
  -- A buffer name may contain newlines (nvim accepts them, and a filename can
  -- carry one), while `with_header` writes exactly two header lines that
  -- `apply_word_diff` counts on -- so an unsanitised name could push a forged
  -- `+++`/`@@` line into a diff that output=file/clipboard hands to git apply.
  local evil = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(evil, 0, -1, false, { "x" })
  pcall(vim.api.nvim_buf_set_name, evil, "evil\n+++ FAKE\n@@ -1 +1 @@")
  local plain = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(plain, 0, -1, false, { "y" })

  local evil_lines = vim.split(
    echoed_diff(string.format("source=%d target=%d output=prompt", evil, plain)),
    "\n",
    { plain = true }
  )
  ok(evil_lines[1]:match("^%-%-%- ") ~= nil, "newline label: line 1 is still the --- header")
  ok(evil_lines[2]:match("^%+%+%+ ") ~= nil, "newline label: line 2 is still the +++ header")
  ok(
    evil_lines[2]:find("FAKE", 1, true) == nil,
    "newline label: the injected +++ line did not become the header"
  )
  ok(evil_lines[1]:find("evil", 1, true) ~= nil, "newline label: the name is still shown")

  scratch.cleanup_all()

  -- base= rejects a source= it cannot honour, instead of ignoring it --------
  reset()
  H.scratch()
  local base_file = vim.fn.tempname()
  vim.fn.writefile({ "base" }, base_file)
  local three_tgt = vim.fn.tempname()
  vim.fn.writefile({ "target" }, three_tgt)

  local msgs = {}
  guarded(function()
    -- Test double over a typed surface; restored by `guarded`.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m)
      msgs[#msgs + 1] = m
    end
    core.run(string.format("source=%d base=%s target=%s", a, base_file, three_tgt))
  end)
  ok(
    #msgs > 0 and msgs[#msgs]:find("only supports source=current", 1, true) ~= nil,
    "base= + an explicit source= is rejected rather than silently ignored"
  )
  eq(vim.tbl_count(diffed_bufs()), 0, "base= + source=: nothing was opened")

  -- ...but the default source= still reaches a three-way diff ---------------
  reset()
  H.scratch()
  guarded(function()
    silence()
    core.run(string.format("base=%s target=%s", base_file, three_tgt))
  end)
  eq(vim.tbl_count(diffed_bufs()), 3, "base= without source= still opens a three-way diff")
  scratch.cleanup_all()

  -- A failed render disposes of the scratch buffers it created --------------
  reset()
  H.scratch()
  local before_count = scratch.active_count()
  guarded(function()
    silence()
    -- An origin window that no longer exists: side_by_side cannot render, and
    -- the two scratch buffers it was handed would otherwise stay tracked (and
    -- counted by the statusline) without ever being displayed or wiped.
    core.execute(
      { source = tostring(a), target = tostring(b), view = "vsplit", output = "buffer" },
      { source_bufnr = vim.api.nvim_get_current_buf(), origin_win = 999999 }
    )
  end)
  eq(scratch.active_count(), before_count, "a failed render leaves no tracked scratch buffers")

  -- Diffmode stays window-local: no leak into windows opened later ---------
  reset()
  local leak_buf = H.scratch()
  vim.api.nvim_buf_set_lines(leak_buf, 0, -1, false, { "LIVE" })
  local leak_tgt = vim.fn.tempname()
  vim.fn.writefile({ "ON-DISK" }, leak_tgt)

  guarded(function()
    silence()
    core.run(string.format("target=%s view=vsplit", leak_tgt))
  end)

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
  for _, bufnr in ipairs({ a, b, named, unnamed, evil, plain }) do
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  reset()
end

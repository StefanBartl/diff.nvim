-- docs/TESTS/render_spec.lua — core.render: compute_stats + format_stats.

return function(H)
  local eq, ok = H.eq, H.ok
  local render = require("diff.core.render")

  -- compute_stats: additions + deletions --------------------------------
  local a = { "one", "two", "three" }
  local b = { "one", "TWO", "three", "four" }
  local stats, err = render.compute_stats(a, b, "histogram", 3)
  ok(err == nil, "compute_stats has no error")
  -- "two" -> "TWO" is a delete + add; "four" is a pure add.
  eq(stats.added, 2, "added count")
  eq(stats.removed, 1, "removed count")
  ok(stats.hunks >= 1, "at least one hunk")

  -- identical inputs -> no changes --------------------------------------
  local same, same_err = render.compute_stats(a, a, "histogram", 3)
  ok(same_err == nil, "identical compute_stats has no error")
  eq(same.added, 0, "identical: zero added")
  eq(same.removed, 0, "identical: zero removed")
  eq(same.hunks, 0, "identical: zero hunks")

  -- format_stats: singular vs plural hunk -------------------------------
  eq(render.format_stats({ added = 2, removed = 1, hunks = 1 }), "+2 -1, 1 hunk", "singular hunk")
  eq(render.format_stats({ added = 5, removed = 0, hunks = 3 }), "+5 -0, 3 hunks", "plural hunks")

  -- compute_stats: lines whose own content starts with "--"/"++" must still
  -- count (raw vim.diff unified output has no real "---"/"+++" header lines
  -- to confuse them with — regression check for a content-vs-header bug).
  local dash_stats, dash_err = render.compute_stats(
    { "-- old comment", "keep" },
    { "-- new comment", "keep" },
    "histogram",
    3
  )
  ok(dash_err == nil, "dash-content compute_stats has no error")
  eq(dash_stats.added, 1, "dash-content: added counts a line starting with --")
  eq(dash_stats.removed, 1, "dash-content: removed counts a line starting with --")

  local plus_stats, plus_err = render.compute_stats(
    { "++i", "keep" },
    { "++j", "keep" },
    "histogram",
    3
  )
  ok(plus_err == nil, "plus-content compute_stats has no error")
  eq(plus_stats.added, 1, "plus-content: added counts a line starting with ++")
  eq(plus_stats.removed, 1, "plus-content: removed counts a line starting with ++")

  -- inline(): word_diff=false must skip extmarks; word_diff=true (default)
  -- must place at least one DiffText extmark on the changed line pair.
  local WORD_DIFF_NS = vim.api.nvim_get_namespaces()["diff_word_diff"]
  ok(type(WORD_DIFF_NS) == "number", "word-diff namespace is registered")

  local buf_off = render.inline(
    0,
    { "hello world" },
    { "hello there" },
    "a",
    "b",
    "histogram",
    3,
    { layout = "split", word_diff = false }
  )
  ok(type(buf_off) == "number", "inline() returns a buffer with word_diff=false")
  local marks_off = vim.api.nvim_buf_get_extmarks(buf_off, WORD_DIFF_NS, 0, -1, {})
  eq(#marks_off, 0, "word_diff=false places no extmarks")
  vim.cmd("silent! only")

  local buf_on = render.inline(
    0,
    { "hello world" },
    { "hello there" },
    "a",
    "b",
    "histogram",
    3,
    { layout = "split", word_diff = true }
  )
  ok(type(buf_on) == "number", "inline() returns a buffer with word_diff=true")
  local marks_on = vim.api.nvim_buf_get_extmarks(buf_on, WORD_DIFF_NS, 0, -1, {})
  ok(#marks_on > 0, "word_diff=true places at least one extmark")
  vim.cmd("silent! only")

  -- word-diff extmarks must highlight the CHANGED text itself, not text
  -- shifted by the "-"/"+" prefix byte the buffer line carries at column 0
  -- (regression check: every extmark used to land one byte too early, e.g.
  -- highlighting " w"/"rl" instead of "world").
  do
    local buf_pos = render.inline(
      0,
      { "hello world" },
      { "hello there" },
      "a",
      "b",
      "histogram",
      3,
      { layout = "split", word_diff = true }
    )
    local marks_pos = vim.api.nvim_buf_get_extmarks(buf_pos, WORD_DIFF_NS, 0, -1, { details = true })
    ok(#marks_pos > 0, "word-diff position check: at least one extmark")
    local highlighted = {}
    for _, m in ipairs(marks_pos) do
      local row, col, details = m[2], m[3], m[4]
      local line = vim.api.nvim_buf_get_lines(buf_pos, row, row + 1, false)[1]
      highlighted[#highlighted + 1] = line:sub(col + 1, details.end_col)
    end
    table.sort(highlighted)
    eq(table.concat(highlighted, ","), "e,ld,the,wo", "word-diff highlights the changed text exactly")
    vim.cmd("silent! only")
  end

  -- UTF-8 codepoint-aware word diff: a single non-ASCII codepoint changing
  -- must highlight exactly that codepoint on each side, never a byte that
  -- straddles it (regression check for the byte-granularity version, which
  -- would highlight a partial multi-byte sequence on a line like this).
  do
    local buf_utf = render.inline(
      0,
      { "héllo wörld" },
      { "hXllo wörld" },
      "a",
      "b",
      "histogram",
      3,
      { layout = "split", word_diff = true }
    )
    local marks_utf = vim.api.nvim_buf_get_extmarks(buf_utf, WORD_DIFF_NS, 0, -1, { details = true })
    eq(#marks_utf, 2, "utf8 word-diff: one extmark per side")
    local by_row = {}
    for _, m in ipairs(marks_utf) do
      local row, col, details = m[2], m[3], m[4]
      local line = vim.api.nvim_buf_get_lines(buf_utf, row, row + 1, false)[1]
      by_row[row] = line:sub(col + 1, details.end_col)
    end
    -- row 3 = "-héllo wörld" (the "-" side), row 4 = "+hXllo wörld"
    eq(by_row[3], "é", "utf8 word-diff: old side highlights exactly 'é'")
    eq(by_row[4], "X", "utf8 word-diff: new side highlights exactly 'X'")
    vim.cmd("silent! only")
  end

  -- compute_hunks: hunk headers parsed into structured old/new start+count
  do
    local ha = { "one", "two", "three", "four" }
    local hb = { "one", "TWO", "three", "four" }
    local hunks, herr = render.compute_hunks(ha, hb, "histogram", 3)
    ok(herr == nil, "compute_hunks has no error")
    eq(#hunks, 1, "compute_hunks: one hunk for one changed line")
    eq(hunks[1].old_start, 1, "compute_hunks: old_start (ctxlen=3 keeps whole file in one hunk)")
    eq(hunks[1].new_start, 1, "compute_hunks: new_start")
    ok(hunks[1].header:match("^@@ .* @@$") ~= nil, "compute_hunks: header looks like a hunk marker")

    local same_hunks = render.compute_hunks(ha, ha, "histogram", 3)
    eq(#same_hunks, 0, "compute_hunks: identical inputs produce zero hunks")
  end

  -- push_stat_list: qf/loc accumulation ("add") vs reset ("replace")
  do
    vim.fn.setqflist({}, "r", { title = "", items = {} })
    render.push_stat_list(
      { "a" },
      { "b" },
      "src1",
      "tgt1",
      "histogram",
      3,
      { list = "qf", mode = "add", target = { filename = "/tmp/does-not-matter-1.txt" } }
    )
    render.push_stat_list(
      { "c" },
      { "d" },
      "src2",
      "tgt2",
      "histogram",
      3,
      { list = "qf", mode = "add", target = { filename = "/tmp/does-not-matter-2.txt" } }
    )
    local qf_added = vim.fn.getqflist()
    eq(#qf_added, 2, "push_stat_list mode=add: entries accumulate across calls")

    render.push_stat_list(
      { "e" },
      { "f" },
      "src3",
      "tgt3",
      "histogram",
      3,
      { list = "qf", mode = "replace", target = nil }
    )
    local qf_replaced = vim.fn.getqflist()
    eq(#qf_replaced, 1, "push_stat_list mode=replace: resets the list to just this diff")
    eq(qf_replaced[1].bufnr, 0, "push_stat_list: no target -> text-only entry (no filename/bufnr)")
    vim.fn.setqflist({}, "r", { title = "", items = {} })
  end

  -- stat(): with list_opts.list ~= "off"/nil, also calls push_stat_list
  do
    vim.fn.setqflist({}, "r", { title = "", items = {} })
    render.stat({ "one" }, { "two" }, "src", "tgt", "histogram", 3, { list = "qf", mode = "add" })
    eq(#vim.fn.getqflist(), 1, "stat(): list=qf pushes the diff's hunk(s) to the quickfix list")
    vim.fn.setqflist({}, "r", { title = "", items = {} })

    -- default (no list_opts / list="off"): must NOT touch the quickfix list
    render.stat({ "one" }, { "two" }, "src", "tgt", "histogram", 3)
    eq(#vim.fn.getqflist(), 0, "stat(): no list_opts leaves the quickfix list untouched")
  end
end

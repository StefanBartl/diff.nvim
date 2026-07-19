-- docs/TESTS/render_spec.lua — core.render: compute_stats + format_stats.

return function(H)
  local eq, ok = H.eq, H.ok
  local render = require("diff_nvim.core.render")

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
    { "-- old comment", "keep" }, { "-- new comment", "keep" }, "histogram", 3)
  ok(dash_err == nil, "dash-content compute_stats has no error")
  eq(dash_stats.added, 1, "dash-content: added counts a line starting with --")
  eq(dash_stats.removed, 1, "dash-content: removed counts a line starting with --")

  local plus_stats, plus_err = render.compute_stats(
    { "++i", "keep" }, { "++j", "keep" }, "histogram", 3)
  ok(plus_err == nil, "plus-content compute_stats has no error")
  eq(plus_stats.added, 1, "plus-content: added counts a line starting with ++")
  eq(plus_stats.removed, 1, "plus-content: removed counts a line starting with ++")

  -- inline(): word_diff=false must skip extmarks; word_diff=true (default)
  -- must place at least one DiffText extmark on the changed line pair.
  local WORD_DIFF_NS = vim.api.nvim_get_namespaces()["diff_nvim_word_diff"]
  ok(type(WORD_DIFF_NS) == "number", "word-diff namespace is registered")

  local buf_off = render.inline(0, { "hello world" }, { "hello there" }, "a", "b", "histogram", 3,
    { layout = "split", word_diff = false })
  ok(type(buf_off) == "number", "inline() returns a buffer with word_diff=false")
  local marks_off = vim.api.nvim_buf_get_extmarks(buf_off, WORD_DIFF_NS, 0, -1, {})
  eq(#marks_off, 0, "word_diff=false places no extmarks")
  vim.cmd("silent! only")

  local buf_on = render.inline(0, { "hello world" }, { "hello there" }, "a", "b", "histogram", 3,
    { layout = "split", word_diff = true })
  ok(type(buf_on) == "number", "inline() returns a buffer with word_diff=true")
  local marks_on = vim.api.nvim_buf_get_extmarks(buf_on, WORD_DIFF_NS, 0, -1, {})
  ok(#marks_on > 0, "word_diff=true places at least one extmark")
  vim.cmd("silent! only")
end

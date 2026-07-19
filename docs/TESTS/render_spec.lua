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
end

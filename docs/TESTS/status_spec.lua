-- docs/TESTS/status_spec.lua — diff.status + scratch.active_count.

return function(H)
  local eq = H.eq
  local diff    = require("diff")
  local scratch = require("diff.core.scratch")

  -- No diff active yet -> empty status, zero count.
  scratch.cleanup_all()
  eq(scratch.active_count(), 0, "no tracked buffers to start")
  eq(diff.status(), "", "status empty when inactive")

  -- Track a couple of scratch buffers.
  scratch.create({ "a" }, "[Diff] test-1")
  scratch.create({ "b" }, "[Diff] test-2")
  eq(scratch.active_count(), 2, "two tracked buffers")
  eq(diff.status(), "diff:2", "default prefix")
  eq(diff.status({ prefix = "D" }), "D2", "custom prefix")

  -- Cleanup drops the count back to zero.
  scratch.cleanup_all()
  eq(scratch.active_count(), 0, "cleanup clears the count")
  eq(diff.status(), "", "status empty after cleanup")
end

-- TESTS/scratch_spec.lua — core.scratch's registry, directly.
--
-- status_spec.lua exercises `create`/`active_count`/`cleanup_all` as far as
-- the statusline needs them; the registry's other half -- `track`, `discard`,
-- `wipe_on_exit`, and what `cleanup_all` does to a buffer that is currently
-- *displayed* -- had no assertions of its own. Buffer bookkeeping during
-- teardown is where a diff plugin raises E937 ("attempt to delete a buffer
-- that is in use"), so it is asserted rather than assumed.

return function(H)
  local eq, ok = H.eq, H.ok
  local scratch = require("diff.core.scratch")

  scratch.cleanup_all()
  vim.cmd("silent! only")

  -- create() -----------------------------------------------------------------
  do
    local buf = scratch.create({ "one", "two" }, "[Diff] create-probe")
    eq(vim.bo[buf].buftype, "nofile", "a scratch buffer is nofile")
    eq(vim.bo[buf].bufhidden, "wipe", "a scratch buffer wipes itself when its window goes")
    eq(vim.bo[buf].swapfile, false, "a scratch buffer has no swapfile")
    eq(vim.bo[buf].modifiable, false, "a scratch buffer is read-only")
    eq(vim.bo[buf].filetype, "", "no filetype unless one was asked for")
    eq(
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "|"),
      "one|two",
      "the lines land in the buffer"
    )
    eq(scratch.active_count(), 1, "create() tracks the buffer it made")

    local typed = scratch.create({ "@@" }, "[Diff] create-probe-ft", "diff")
    eq(vim.bo[typed].filetype, "diff", "an explicit filetype is applied")

    -- A duplicate name must not throw: nvim_buf_set_name refuses it, and the
    -- buffer is still perfectly usable without the cosmetic name.
    local dup_ok = pcall(scratch.create, { "x" }, "[Diff] create-probe")
    ok(dup_ok, "a duplicate buffer name is survivable, not fatal")

    scratch.cleanup_all()
    eq(scratch.active_count(), 0, "cleanup_all clears the registry")
  end

  -- discard() ---------------------------------------------------------------
  do
    local a = scratch.create({ "a" }, "[Diff] discard-a")
    local b = scratch.create({ "b" }, "[Diff] discard-b")
    eq(scratch.active_count(), 2, "two tracked")

    scratch.discard(a)
    eq(scratch.active_count(), 1, "discard() drops exactly one")
    eq(vim.api.nvim_buf_is_valid(a), false, "discard() wipes the buffer too")
    ok(vim.api.nvim_buf_is_valid(b), "discard() leaves the other one alone")

    -- Discarding twice, or discarding something never tracked, must be inert:
    -- both happen on the render-failure path, where a caller cleans up
    -- defensively without knowing what got that far.
    local twice_ok = pcall(scratch.discard, a)
    ok(twice_ok, "discarding an already-discarded buffer is inert")
    local untracked_ok = pcall(scratch.discard, 999999)
    ok(untracked_ok, "discarding an untracked/invalid handle is inert")
    eq(scratch.active_count(), 1, "neither changed the count")

    scratch.cleanup_all()
  end

  -- cleanup_all() on a *displayed* buffer -------------------------------------
  -- This is the E937 shape: the buffer is in a window, it is bufhidden=wipe,
  -- and we delete it from the outside while it is still on screen.
  do
    vim.cmd("silent! only")
    local buf = scratch.create({ "shown" }, "[Diff] displayed")
    vim.cmd(string.format("silent! vsplit | buffer %d", buf))
    ok(vim.api.nvim_get_current_buf() == buf, "the scratch really is displayed")

    local cleared_ok, cleared = pcall(scratch.cleanup_all)
    ok(
      cleared_ok,
      "wiping a displayed scratch buffer does not raise (got: " .. tostring(cleared) .. ")"
    )
    eq(cleared, 1, "cleanup_all reports the one buffer it wiped")
    eq(vim.api.nvim_buf_is_valid(buf), false, "and the buffer is gone")
    eq(scratch.active_count(), 0, "registry emptied")
    vim.cmd("silent! only")
  end

  -- cleanup_all() also turns diffmode off, including in windows it does not own
  do
    vim.cmd("silent! only")
    local origin_win = vim.api.nvim_get_current_win()
    local buf = scratch.create({ "right" }, "[Diff] diffmode-off")
    vim.cmd(string.format("silent! vsplit | buffer %d", buf))
    local right = vim.api.nvim_get_current_win()
    require("diff.util.diffmode").set(origin_win, true)
    require("diff.util.diffmode").set(right, true)
    ok(vim.wo[origin_win].diff, "origin window is in diffmode before cleanup")

    scratch.cleanup_all()
    eq(vim.wo[origin_win].diff, false, "cleanup_all leaves no stray diffmode behind")
    vim.cmd("silent! only")
  end

  -- cleanup_all() counts only what it actually wiped --------------------------
  do
    local a = scratch.create({ "a" }, "[Diff] count-a")
    scratch.create({ "b" }, "[Diff] count-b")
    -- Delete one out from under the registry, the way a `:bwipeout` would.
    vim.api.nvim_buf_delete(a, { force = true })
    eq(scratch.active_count(), 1, "active_count skips handles that went invalid")
    eq(scratch.cleanup_all(), 1, "cleanup_all counts the wipes it performed, not the entries")
  end

  -- wipe_on_exit() ------------------------------------------------------------
  -- The VimLeavePre path: wipe the buffers, leave diffmode alone (Neovim tears
  -- that down itself on exit).
  do
    vim.cmd("silent! only")
    local origin_win = vim.api.nvim_get_current_win()
    require("diff.util.diffmode").set(origin_win, true)
    local buf = scratch.create({ "bye" }, "[Diff] exit-wipe")

    scratch.wipe_on_exit()
    eq(vim.api.nvim_buf_is_valid(buf), false, "wipe_on_exit wipes tracked buffers")
    eq(scratch.active_count(), 0, "and empties the registry")
    ok(vim.wo[origin_win].diff, "wipe_on_exit does NOT touch diffmode")
    require("diff.util.diffmode").set(origin_win, false)

    -- Idempotent: VimLeavePre can be reached after a :DiffClear.
    local again_ok = pcall(scratch.wipe_on_exit)
    ok(again_ok, "wipe_on_exit on an empty registry is inert")
  end

  -- track() -------------------------------------------------------------------
  -- The documented way to hand the registry a buffer diff.nvim did not create.
  do
    scratch.cleanup_all()
    local foreign = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(foreign, 0, -1, false, { "foreign" })

    scratch.track(foreign)
    eq(scratch.active_count(), 1, "track() adopts a foreign buffer")
    scratch.cleanup_all()
    eq(vim.api.nvim_buf_is_valid(foreign), false, "an adopted buffer is torn down like our own")

    -- An invalid handle is refused rather than parked in the registry, where
    -- it would be a permanent no-op entry.
    scratch.track(999999)
    eq(scratch.active_count(), 0, "track() refuses an invalid handle")
    ---@diagnostic disable-next-line: param-type-mismatch
    scratch.track("nonsense")
    eq(scratch.active_count(), 0, "track() refuses a non-number")

    -- track() de-duplicates: adopting the same handle twice (or adopting a
    -- buffer create() already registered) must not inflate active_count()
    -- beyond the number of distinct live buffers, since that count is what
    -- diff.status() prints in the statusline.
    local buf = scratch.create({ "x" }, "[Diff] dup-track")
    scratch.track(buf)
    scratch.track(buf)
    eq(scratch.active_count(), 1, "tracking the same buffer twice still counts as one")
    eq(require("diff").status(), "diff:1", "and the statusline reports it as one")
    eq(scratch.cleanup_all(), 1, "cleanup_all wipes it exactly once")
    eq(scratch.active_count(), 0, "and the registry ends up empty either way")
  end

  scratch.cleanup_all()
  vim.cmd("silent! only")
end

-- TESTS/origin_spec.lua — features.origin (:DiffOrig).
--
-- "What changed since the last save" had no assertions at all: not the
-- snapshot's content, not that both windows end up in diffmode, not that the
-- snapshot joins the registry :DiffClear tears down, and not its two refusal
-- paths. All of it is testable headlessly -- it only reads a file and opens a
-- split.

return function(H)
  local eq, ok = H.eq, H.ok
  local origin = require("diff.features.origin")
  local scratch = require("diff.core.scratch")
  local config = require("diff.config")

  ---Capture the notifications a call produced.
  ---@param fn fun(): nil
  ---@return string[]
  local function notices(fn)
    local out = {}
    local saved = vim.notify
    -- Test double over a typed surface; restored before returning.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      out[#out + 1] = tostring(msg)
    end
    local call_ok, err = pcall(fn)
    vim.notify = saved
    ok(call_ok, "call did not throw: " .. tostring(err))
    return out
  end

  ---@return integer
  local function diffmode_window_count()
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and vim.wo[w].diff then
        n = n + 1
      end
    end
    return n
  end

  local function reset()
    scratch.cleanup_all()
    vim.cmd("silent! only")
    vim.cmd("silent! enew")
  end

  config.setup({})
  reset()

  -- Refusal: a buffer with no name is not backed by a file -------------------
  do
    reset()
    local before = scratch.active_count()
    local msgs = notices(origin.run)
    ok(
      table.concat(msgs, "\n"):find("not backed by a file", 1, true) ~= nil,
      "an unnamed buffer is refused by name (got: " .. table.concat(msgs, " | ") .. ")"
    )
    eq(scratch.active_count(), before, "a refused :DiffOrig tracks nothing")
  end

  -- Refusal: a named buffer whose file does not exist on disk ----------------
  -- The common shape of this is a brand-new `:edit newfile.lua` that has never
  -- been written -- there is no saved version to diff against yet.
  do
    reset()
    local ghost = H.tmpdir() .. "never-written.txt"
    vim.cmd("silent! edit " .. vim.fn.fnameescape(ghost))
    local before = scratch.active_count()
    local msgs = notices(origin.run)
    ok(
      table.concat(msgs, "\n"):find("not readable on disk", 1, true) ~= nil,
      "an unsaved file is refused by name (got: " .. table.concat(msgs, " | ") .. ")"
    )
    eq(scratch.active_count(), before, "a refused :DiffOrig tracks nothing")
  end

  -- Happy path: vsplit (the default) -----------------------------------------
  do
    reset()
    local path = H.tmpdir() .. "saved.txt"
    H.write_file(path, { "disk one", "disk two", "disk three" })
    vim.cmd("silent! edit " .. vim.fn.fnameescape(path))
    local work_buf = vim.api.nvim_get_current_buf()
    local work_win = vim.api.nvim_get_current_win()
    -- Unsaved modifications: the whole point of :DiffOrig.
    vim.api.nvim_buf_set_lines(work_buf, 0, -1, false, { "disk one", "CHANGED", "disk three" })

    local wins_before = #vim.api.nvim_list_wins()
    notices(origin.run)

    eq(#vim.api.nvim_list_wins(), wins_before + 1, "vsplit opens exactly one window")
    eq(scratch.active_count(), 1, "the snapshot joins the registry :DiffClear tears down")
    eq(diffmode_window_count(), 2, "both the working buffer and the snapshot are in diffmode")
    eq(
      vim.api.nvim_get_current_win(),
      work_win,
      "the cursor ends up back in the buffer you were editing, not in the snapshot"
    )

    -- The snapshot holds the *saved* version, not the modified buffer.
    local snap_buf
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if b ~= work_buf then
        snap_buf = b
      end
    end
    ok(snap_buf ~= nil, "a snapshot buffer was opened")
    eq(
      table.concat(vim.api.nvim_buf_get_lines(snap_buf, 0, -1, false), "|"),
      "disk one|disk two|disk three",
      "the snapshot holds what is on disk, not what is in the buffer"
    )
    eq(vim.bo[snap_buf].modifiable, false, "the snapshot is read-only")
    ok(
      vim.api.nvim_buf_get_name(snap_buf):find("[DiffOrig]", 1, true) ~= nil,
      "the snapshot is labelled [DiffOrig] <basename> (saved)"
    )
    ok(
      vim.api.nvim_buf_get_name(snap_buf):find("saved.txt", 1, true) ~= nil,
      "and names the file it snapshotted"
    )

    -- :DiffClear takes the whole thing back down.
    eq(scratch.cleanup_all(), 1, "cleanup wipes the snapshot")
    eq(diffmode_window_count(), 0, "and leaves no window in diffmode")
    reset()
  end

  -- default_orig_view = "split" uses a horizontal split ----------------------
  -- Verified by the window's geometry rather than by the command string: a
  -- horizontal split keeps the full width and halves the height.
  do
    reset()
    local path = H.tmpdir() .. "hsplit.txt"
    H.write_file(path, { "a" })
    vim.cmd("silent! edit " .. vim.fn.fnameescape(path))
    local work_win = vim.api.nvim_get_current_win()
    local width_before = vim.api.nvim_win_get_width(work_win)

    config.setup({ diff = { default_orig_view = "split" } })
    notices(origin.run)
    eq(
      vim.api.nvim_win_get_width(work_win),
      width_before,
      'default_orig_view="split" splits horizontally -- the width is unchanged'
    )
    eq(diffmode_window_count(), 2, "both windows are still in diffmode")
    config.setup({})
    reset()
  end

  -- Any other value falls back to vsplit, so a typo never breaks :DiffOrig ---
  do
    reset()
    local path = H.tmpdir() .. "typo.txt"
    H.write_file(path, { "a" })
    vim.cmd("silent! edit " .. vim.fn.fnameescape(path))
    local work_win = vim.api.nvim_get_current_win()
    local width_before = vim.api.nvim_win_get_width(work_win)

    config.setup({ diff = { default_orig_view = "vsplitt" } })
    notices(origin.run)
    ok(
      vim.api.nvim_win_get_width(work_win) < width_before,
      "an unrecognized default_orig_view falls back to vsplit rather than failing"
    )
    config.setup({})
    reset()
  end

  -- The exit key is attached to the snapshot, exactly as a :Diff would -------
  do
    reset()
    config.setup({ exit = { key = "<C-y><C-y>", scope = "buffer" } })
    require("diff.features.exit").setup(config.get().exit)

    local path = H.tmpdir() .. "exitkey.txt"
    H.write_file(path, { "a" })
    vim.cmd("silent! edit " .. vim.fn.fnameescape(path))
    local work_buf = vim.api.nvim_get_current_buf()
    notices(origin.run)

    local snap_buf
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if b ~= work_buf then
        snap_buf = b
      end
    end
    local found = false
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(snap_buf, "n")) do
      if m.lhs == "<C-Y><C-Y>" or m.lhs == "<C-y><C-y>" then
        found = true
      end
    end
    ok(found, "the buffer-local exit key is bound on the snapshot")

    config.setup({})
    reset()
  end

  -- :DiffOrig twice in a row tracks both snapshots ---------------------------
  -- Nothing dedupes here on purpose -- each invocation is its own diff -- but
  -- :DiffClear still has to take all of it down in one go.
  do
    reset()
    local path = H.tmpdir() .. "twice.txt"
    H.write_file(path, { "a", "b" })
    vim.cmd("silent! edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "B" })
    notices(origin.run)
    -- :DiffOrig leaves the cursor in the working buffer, so a second
    -- invocation is a plain repeat rather than a diff *of* the snapshot.
    eq(
      vim.api.nvim_get_current_buf(),
      vim.fn.bufnr(vim.fn.fnamemodify(path, ":p")),
      "still in the working buffer after the first invocation"
    )
    notices(origin.run)
    eq(scratch.active_count(), 2, "two invocations track two snapshots")
    eq(scratch.cleanup_all(), 2, "one :DiffClear takes both down")
    eq(diffmode_window_count(), 0, "and no diffmode is left anywhere")
  end

  config.setup({})
  reset()
end

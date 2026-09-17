-- TESTS/render_edge_spec.lua — core.render's failure and no-op paths.
--
-- render_spec.lua covers the successful shapes (stats, hunks, word-diff
-- highlighting, the quickfix push). What had no assertions is what each
-- renderer does when there is nothing to render or when the diff cannot be
-- computed at all: every one of the five has its own "no differences" arm and
-- its own error arm, and `M.file` additionally has to survive an unwritable
-- destination rather than throwing E482 at the user.

return function(H)
  local eq, ok = H.eq, H.ok
  local render = require("diff.core.render")

  ---Run `fn`, capturing the notifications it produced and *all* of its return
  ---values (`M.file` answers with two, and the second one is the whole point).
  ---@param fn fun(): any
  ---@return string[] msgs, any first, any second
  local function notices(fn)
    local out = {}
    local saved = vim.notify
    -- Test double over a typed surface; restored before returning.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      out[#out + 1] = tostring(msg)
    end
    local call_ok, first, second = pcall(fn)
    vim.notify = saved
    ok(call_ok, "call did not throw: " .. tostring(first))
    return out, first, second
  end

  local A = { "one", "two" }
  local B = { "one", "TWO" }
  local BAD = "no-such-algorithm"

  -- The three pure computations all report the same failure ------------------
  do
    local unified, err = render.compute_unified(A, B, BAD, 3)
    eq(unified, nil, "compute_unified returns nil on a failed diff")
    ok(err and err:find("diff failed", 1, true) == 1, "and an error prefixed 'diff failed'")

    local stats, serr = render.compute_stats(A, B, BAD, 3)
    eq(stats, nil, "compute_stats propagates the failure")
    ok(serr and serr:find("diff failed", 1, true) == 1, "with the same message")

    local hunks, herr = render.compute_hunks(A, B, BAD, 3)
    eq(hunks, nil, "compute_hunks propagates the failure")
    ok(herr and herr:find("diff failed", 1, true) == 1, "with the same message")
  end

  -- "Nothing was delivered" and "something went wrong" are different answers --
  -- The three err-returning text renderers (`stat`, `prompt`, `clipboard`) and
  -- `file`'s second return value all answer nil for two identical sides and
  -- the reason for a diff that could not be computed. A caller needs opposite
  -- handling for those two, so the distinction is asserted per renderer rather
  -- than only through the notification text.
  do
    ---@type { name: string, fn: fun(a: string[], b: string[], algo: string): any, err_at: integer }[]
    local text_renderers = {
      {
        name = "stat",
        err_at = 1,
        fn = function(a, b, algo)
          return render.stat(a, b, "src", "tgt", algo, 3)
        end,
      },
      {
        name = "prompt",
        err_at = 1,
        fn = function(a, b, algo)
          return render.prompt(a, b, "src", "tgt", algo, 3)
        end,
      },
      {
        name = "clipboard",
        err_at = 1,
        fn = function(a, b, algo)
          return render.clipboard(a, b, "src", "tgt", algo, 3)
        end,
      },
      -- file answers (path, err): the path is the delivery, the err is the
      -- failure, and nil/nil is "there was nothing to write".
      {
        name = "file",
        err_at = 2,
        fn = function(a, b, algo)
          return render.file(a, b, "src", "tgt", algo, 3)
        end,
      },
    }

    for _, r in ipairs(text_renderers) do
      local saved_reg = vim.fn.getreg("+")
      vim.fn.setreg("+", "SENTINEL")

      -- identical sides: nothing delivered, nothing wrong
      local msgs, first, second = notices(function()
        return r.fn(A, A, "histogram")
      end)
      local returned_err = (r.err_at == 1) and first or second
      eq(returned_err, nil, r.name .. ": identical sides are not an error")
      if r.name == "file" then
        eq(first, nil, "file: identical sides write no file")
      end
      if r.name == "clipboard" then
        eq(vim.fn.getreg("+"), "SENTINEL", "clipboard: and the register is left alone")
      end
      ok(
        table.concat(msgs, "\n"):find("No differences found", 1, true) ~= nil,
        r.name .. ": identical sides report 'No differences found'"
      )

      -- a diff that cannot be computed: the reason comes back
      msgs, first, second = notices(function()
        return r.fn(A, B, BAD)
      end)
      returned_err = (r.err_at == 1) and first or second
      ok(
        type(returned_err) == "string" and returned_err:find("diff failed", 1, true) == 1,
        r.name .. ": a failed diff returns the reason (got: " .. tostring(returned_err) .. ")"
      )
      if r.name == "file" then
        eq(first, nil, "file: a failed diff writes no file")
      end
      ok(
        table.concat(msgs, "\n"):find("diff failed", 1, true) ~= nil,
        r.name .. ": and the user is told too"
      )

      vim.fn.setreg("+", saved_reg)
    end

    -- inline answers with a buffer handle instead, so both arms are nil --
    -- and the notification is the only thing that distinguishes them.
    local msgs, buf = notices(function()
      return render.inline(vim.api.nvim_get_current_win(), A, A, "src", "tgt", "histogram", 3)
    end)
    eq(buf, nil, "inline: identical sides open no buffer")
    ok(table.concat(msgs, "\n"):find("No differences found", 1, true) ~= nil, "inline: and say so")

    msgs, buf = notices(function()
      return render.inline(vim.api.nvim_get_current_win(), A, B, "src", "tgt", BAD, 3)
    end)
    eq(buf, nil, "inline: a failed diff opens no buffer")
    ok(table.concat(msgs, "\n"):find("diff failed", 1, true) ~= nil, "inline: and reports why")
  end

  -- The two-line header is the same for every text output --------------------
  do
    local saved_reg = vim.fn.getreg("+")
    notices(function()
      render.clipboard(A, B, "the source", "the target", "histogram", 3)
    end)
    local text = vim.fn.getreg("+")
    eq(
      text:sub(1, #"--- the source\n+++ the target\n"),
      "--- the source\n+++ the target\n",
      "clipboard: the unified diff is prefixed with exactly the two header lines"
    )
    ok(text:find("@@", 1, true) ~= nil, "clipboard: and the body follows")
    vim.fn.setreg("+", saved_reg)

    local _, path = notices(function()
      return render.file(A, B, "the source", "the target", "histogram", 3)
    end)
    ok(type(path) == "string", "file: returns the path it wrote")
    eq(vim.fn.filereadable(path), 1, "file: and that path is readable")
    local written = vim.fn.readfile(path)
    eq(written[1], "--- the source", "file: header line 1")
    eq(written[2], "+++ the target", "file: header line 2")
    ok(written[3]:sub(1, 2) == "@@", "file: the body starts at line 3, as apply_word_diff assumes")
  end

  -- An unwritable destination is reported, not thrown -------------------------
  -- `writefile` raises E482 on a path it cannot open; the renderer wraps it so
  -- `output=file` fails with its own message instead of a raw Vim error -- and
  -- returns that message, so a caller can tell a failed write apart from
  -- "there were no differences to write", which also produces no path.
  do
    local blocker = vim.fn.tempname()
    vim.fn.writefile({ "I am a file, not a directory" }, blocker)
    local saved_tempname = vim.fn.tempname
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.tempname = function()
      return blocker .. "/impossible"
    end
    local msgs, path, write_err = notices(function()
      return render.file(A, B, "src", "tgt", "histogram", 3)
    end)
    vim.fn.tempname = saved_tempname

    eq(path, nil, "an unwritable destination returns no path")
    ok(
      type(write_err) == "string" and write_err:find("could not write diff to", 1, true) == 1,
      "and returns the reason, so it is not mistaken for 'nothing to write' (got: "
        .. tostring(write_err)
        .. ")"
    )
    local joined = table.concat(msgs, "\n")
    ok(
      joined:find("could not write diff to", 1, true) ~= nil,
      "and is reported as our own message (got: " .. joined .. ")"
    )
    eq(joined:find("E482"), nil, "with Vim's raw E482 kept out of the user's face")
  end

  -- push_stat_list with nothing to push ---------------------------------------
  do
    vim.fn.setqflist({}, "r", { title = "SENTINEL", items = { { text = "pre-existing" } } })
    render.push_stat_list(A, A, "src", "tgt", "histogram", 3, { list = "qf", mode = "add" })
    eq(#vim.fn.getqflist(), 1, "identical sides push no hunks, leaving the list untouched")
    render.push_stat_list(A, B, "src", "tgt", BAD, 3, { list = "qf", mode = "add" })
    eq(#vim.fn.getqflist(), 1, "a failed diff pushes nothing either")
    vim.fn.setqflist({}, "r", { items = {} })
  end

  -- stat only touches a list when one was actually asked for ------------------
  do
    vim.fn.setqflist({}, "r", { items = {} })
    notices(function()
      render.stat(A, B, "src", "tgt", "histogram", 3, { list = "off", mode = "add" })
    end)
    eq(#vim.fn.getqflist(), 0, 'list="off" pushes nothing')
    notices(function()
      render.stat(A, B, "src", "tgt", "histogram", 3, nil)
    end)
    eq(#vim.fn.getqflist(), 0, "a missing list_opts pushes nothing")
    vim.fn.setqflist({}, "r", { items = {} })
  end

  -- A location list is a different list from the quickfix list ---------------
  do
    vim.cmd("silent! only")
    vim.fn.setqflist({}, "r", { items = {} })
    vim.fn.setloclist(0, {}, "r", { items = {} })
    notices(function()
      render.stat(A, B, "src", "tgt", "histogram", 3, { list = "loc", mode = "replace" })
    end)
    ok(#vim.fn.getloclist(0) > 0, 'list="loc" fills the window\'s location list')
    eq(#vim.fn.getqflist(), 0, "and leaves the quickfix list alone")
    vim.fn.setloclist(0, {}, "r", { items = {} })
  end

  -- format_stats' pluralization ----------------------------------------------
  do
    eq(
      render.format_stats({ added = 0, removed = 0, hunks = 0 }),
      "+0 -0, 0 hunks",
      "zero is plural"
    )
    eq(
      render.format_stats({ added = 1, removed = 1, hunks = 1 }),
      "+1 -1, 1 hunk",
      "one is singular"
    )
  end

  -- compute_hunks accepts the count-omitted `@@ -N +N @@` spelling ------------
  -- With ctxlen=0 a single-line change can come back without an explicit
  -- count, which unified-diff format defines as 1.
  do
    local hunks = render.compute_hunks({ "a", "b", "c" }, { "a", "B", "c" }, "histogram", 0)
    ok(hunks and #hunks == 1, "a one-line change at ctxlen=0 is one hunk")
    eq(hunks[1].old_count, 1, "an omitted count reads as 1 (old side)")
    eq(hunks[1].new_count, 1, "an omitted count reads as 1 (new side)")
    eq(hunks[1].old_start, 2, "and the start line is the changed one")
    eq(hunks[1].new_start, 2, "on both sides")
    ok(hunks[1].header:sub(1, 2) == "@@", "the raw header is kept for the list entry text")
  end

  -- An unbalanced -/+ run is shown, just without word highlighting ------------
  -- `apply_word_diff` only pairs runs of equal length; anything else is
  -- ambiguous, and guessing a pairing would highlight the wrong bytes.
  do
    local buf = render.inline(
      vim.api.nvim_get_current_win(),
      { "one", "two", "three" },
      { "ONE" },
      "src",
      "tgt",
      "histogram",
      3
    )
    ok(buf ~= nil, "an unbalanced change still renders")
    local marks =
      vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("diff_word_diff"), 0, -1, {})
    eq(#marks, 0, "but an unbalanced -/+ run gets no word-level highlights")
    require("diff.core.scratch").cleanup_all()
    vim.cmd("silent! only")
  end

  -- word_diff = false suppresses the highlighting entirely --------------------
  do
    local buf = render.inline(
      vim.api.nvim_get_current_win(),
      { "hello world" },
      { "hello there" },
      "src",
      "tgt",
      "histogram",
      3,
      { word_diff = false }
    )
    ok(buf ~= nil, "word_diff=false still renders the diff")
    local marks =
      vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("diff_word_diff"), 0, -1, {})
    eq(#marks, 0, "word_diff=false places no extmarks")
    require("diff.core.scratch").cleanup_all()
    vim.cmd("silent! only")
  end

  require("diff.core.scratch").cleanup_all()
  vim.cmd("silent! only")
end

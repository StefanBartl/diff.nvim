-- TESTS/directory_edge_spec.lua — core.directory's edges.
--
-- directory_spec.lua covers the happy paths per `output=`. This spec adds the
-- parts that only show up when something goes wrong or when the tree is not
-- flat: nested hidden segments, the quickfix entries actually resolving to
-- real files (a path-separator question on Windows), the end-to-end route
-- through `core.run`, and an unreadable file mid-walk -- which is where the
-- module's own error contract breaks.

return function(H)
  local eq, ok = H.eq, H.ok
  local directory = require("diff.core.directory")

  local cfg = {
    algorithm = "histogram",
    ctxlen = 3,
    directory_max_files = 2000,
    stat_list = "off",
    stat_list_mode = "add",
  }

  ---Strip the trailing slash H.tmpdir() adds, so paths read like a user's.
  ---@return string
  local function tmproot()
    return (H.tmpdir():gsub("/$", ""))
  end

  ---Collect the lines `output=buffer` rendered, then close its window again.
  ---@param src string
  ---@param tgt string
  ---@return string
  local function summary_of(src, tgt)
    vim.cmd("silent! only")
    directory.run(src, tgt, "src", "tgt", "buffer", cfg)
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    vim.cmd("silent! only")
    require("diff.core.scratch").cleanup_all()
    return text
  end

  -- Hidden segments are excluded at *every* depth, not just the top ----------
  -- `has_hidden_segment` tests for a leading "." or a "/." anywhere, which
  -- only works because vim.fs.dir yields forward-slash relative names on every
  -- platform -- including Windows, where the rest of the world would hand back
  -- "sub\.hidden\x". Pinned here because it is a silent failure either way:
  -- the wrong answer is a summary full of .git internals, not an error.
  do
    local src, tgt = tmproot(), tmproot()
    for _, d in ipairs({ src, tgt }) do
      H.write_file(d .. "/visible.txt", { "same" })
      H.write_file(d .. "/sub/nested.txt", { "same" })
      H.write_file(d .. "/.git/HEAD", { "ref: refs/heads/main" })
      H.write_file(d .. "/sub/.cache/blob.txt", { "same" })
      H.write_file(d .. "/.hidden_top/deep/x.txt", { "same" })
    end
    -- Make every excluded file differ, so any of them leaking in would show.
    H.write_file(tgt .. "/.git/HEAD", { "ref: refs/heads/other" })
    H.write_file(tgt .. "/sub/.cache/blob.txt", { "different" })
    H.write_file(tgt .. "/.hidden_top/deep/x.txt", { "different" })
    -- ...and one visible file at depth, so the walk is proven to be recursive.
    H.write_file(tgt .. "/sub/nested.txt", { "changed" })

    local text = summary_of(src, tgt)
    ok(text:match("nested%.txt") ~= nil, "a nested visible file is compared")
    eq(text:find("%.git"), nil, "a top-level hidden directory is excluded")
    eq(text:find("%.cache"), nil, "a hidden directory nested one level down is excluded")
    eq(text:find("%.hidden_top"), nil, "a hidden top-level directory is excluded with its subtree")
    ok(text:match("1 file changed") ~= nil, "exactly one file differs (got: " .. text .. ")")
  end

  -- The quickfix entries point at files that really open ----------------------
  -- `filename` is built as `vim.fs.normalize(dir .. "/" .. rel)`, i.e. a
  -- forward-slash path -- on Windows that is a different spelling from the
  -- backslash one nvim stores in a buffer name. Asserting `#qf` alone (as
  -- directory_spec does) would pass even if every entry were unopenable.
  do
    local src, tgt = tmproot(), tmproot()
    H.write_file(src .. "/mod.txt", { "one" })
    H.write_file(src .. "/gone.txt", { "bye" })
    H.write_file(tgt .. "/mod.txt", { "two" })
    H.write_file(tgt .. "/new.txt", { "hi" })

    vim.fn.setqflist({}, "r", { items = {} })
    local qf_cfg = vim.tbl_extend("force", cfg, { stat_list = "qf", stat_list_mode = "replace" })
    directory.run(src, tgt, "src", "tgt", "stat", qf_cfg)

    local qf = vim.fn.getqflist()
    eq(#qf, 3, "one quickfix entry per changed file")
    local by_status = {}
    for _, e in ipairs(qf) do
      ok(e.valid == 1, "quickfix entry is valid (resolvable): " .. tostring(e.text))
      ok(e.bufnr and e.bufnr > 0, "quickfix entry resolved to a real buffer")
      ok(
        vim.fn.filereadable(vim.api.nvim_buf_get_name(e.bufnr)) == 1,
        "the buffer it resolved to is a readable file on disk"
      )
      by_status[e.text:sub(1, 1)] = vim.api.nvim_buf_get_name(e.bufnr)
    end
    -- A deleted file only exists on the source side; its entry must point
    -- there, or it would resolve to nothing at all.
    --
    -- Both sides go through H.canonical, not vim.fs.normalize: the buffer
    -- name nvim resolved and the tempname() path this spec holds can be two
    -- spellings of one directory (see H.canonical for which platform spells
    -- it which way).
    --
    -- The prefix also carries a trailing separator, which H.canonical strips
    -- and so has to be re-appended: tempname() numbers its directories
    -- sequentially within a session, so a bare prefix lets `…/3` match
    -- `…/33`, and a D entry pointing at the *target* tree would pass.
    local function under(path, dir)
      return H.canonical(path):find(H.canonical(dir) .. "/", 1, true) == 1
    end
    ok(by_status["D"] ~= nil, "the deleted file got an entry")
    ok(
      under(by_status["D"], src),
      "a D entry points into the source tree, the only one that still has the file"
    )
    ok(under(by_status["A"], tgt), "an A entry points into the target tree")
    vim.fn.setqflist({}, "r", { items = {} })
  end

  -- stat_list_mode="add" accumulates across runs -----------------------------
  do
    local src, tgt = tmproot(), tmproot()
    H.write_file(src .. "/a.txt", { "one" })
    H.write_file(tgt .. "/a.txt", { "two" })
    local add_cfg = vim.tbl_extend("force", cfg, { stat_list = "qf", stat_list_mode = "add" })

    vim.fn.setqflist({}, "r", { items = {} })
    directory.run(src, tgt, "src", "tgt", "stat", add_cfg)
    eq(#vim.fn.getqflist(), 1, "first run lists its one file")
    directory.run(src, tgt, "src", "tgt", "stat", add_cfg)
    eq(#vim.fn.getqflist(), 2, 'mode="add" accumulates rather than replacing')
    vim.fn.setqflist({}, "r", { items = {} })
  end

  -- A directory diff with no differences still produces a result, not an error
  do
    local same = tmproot()
    H.write_file(same .. "/x.txt", { "same" })
    local res, err = directory.run(same, same, "src", "tgt", "stat", cfg)
    ok(res ~= nil, "identical trees produce a result")
    eq(err, nil, "identical trees are not an error")
    eq(#res.buffers, 0, "output=stat opens no buffers")
    eq(#res.windows, 0, "output=stat opens no windows")
    eq(res.view, nil, "a directory diff never claims a view= -- there is no diffmode pair")
  end

  -- output=prompt echoes the summary rather than opening anything ------------
  do
    local src, tgt = tmproot(), tmproot()
    H.write_file(src .. "/p.txt", { "one" })
    H.write_file(tgt .. "/p.txt", { "two" })
    vim.cmd("silent! only")
    local wins_before = #vim.api.nvim_list_wins()
    local res = directory.run(src, tgt, "src", "tgt", "prompt", cfg)
    ok(res ~= nil, "output=prompt produces a result")
    eq(#vim.api.nvim_list_wins(), wins_before, "output=prompt opens no window")
  end

  -- End-to-end: two directory specs reach core.directory through core.run ----
  do
    local src, tgt = tmproot(), tmproot()
    H.write_file(src .. "/e2e.txt", { "one" })
    H.write_file(tgt .. "/e2e.txt", { "two" })

    local core = require("diff.core")
    local seen, calls = nil, 0
    local msgs = {}
    local saved_notify = vim.notify
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m)
      msgs[#msgs + 1] = tostring(m)
    end
    core.run(string.format("source=%s target=%s output=stat", src, tgt), nil, {
      on_done = function(result, err)
        calls = calls + 1
        seen = { result = result, err = err }
      end,
    })
    vim.notify = saved_notify

    eq(calls, 1, "a directory diff fires on_done exactly once")
    ok(seen.result ~= nil, "and reports a result, not a failure")
    eq(seen.result.output, "stat", "the result names its own output=")
    ok(
      table.concat(msgs, "\n"):find("1 file changed", 1, true) ~= nil,
      "the summary notification names the changed file count"
    )
  end

  -- BUG: a file that cannot be read escapes as a raw E484 --------------------
  -- `list_files` walks the tree, then `diff_trees` reads every entry with a
  -- bare `fn.readfile`. Anything that makes a listed file unreadable between
  -- those two steps -- a build directory being rewritten, a checkout switching
  -- branches, a permission or lock problem, a file removed by another process
  -- -- throws out of `diff_trees`, out of `directory.run` (past its own
  -- `notify.error(...)`/`return nil, err` contract) and out of `core.execute`,
  -- so the user sees Vim's `E484: Can't open file ...` instead of the
  -- plugin's "could not diff directories". The same throw also means the
  -- caller's `on_done` never fires at all, so an integrating plugin waits
  -- forever for a diff that already died. Same family as the guarded
  -- `pcall(fn.writefile, ...)` twelve lines below it in this very module --
  -- and the same failure `render.side_by_side`'s `split_into` was pcall'd to
  -- close, for exactly the reason given there ("an error would escape
  -- core.execute and take every cleanup path with it"). The directory
  -- dispatch in `core.execute` is the one route that still has it.
  --
  -- The failure is injected through `vim.fn.readfile` (which `directory.lua`
  -- reaches through a captured `vim.fn` *table*, so the patch lands) rather
  -- than by manufacturing a locked file, so the pin is deterministic on every
  -- platform.
  do
    local src, tgt = tmproot(), tmproot()
    H.write_file(src .. "/doomed.txt", { "one" })
    H.write_file(tgt .. "/doomed.txt", { "two" })

    local saved_readfile = vim.fn.readfile
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.readfile = function(path, ...)
      if tostring(path):find("doomed.txt", 1, true) then
        error("Vim:E484: Can't open file " .. tostring(path))
      end
      return saved_readfile(path, ...)
    end

    local run_ok, run_err = pcall(directory.run, src, tgt, "src", "tgt", "stat", cfg)

    -- And the same through the public entry point, where it also swallows
    -- the completion callback.
    local calls = 0
    local core_ok =
      pcall(require("diff.core").run, string.format("source=%s target=%s", src, tgt), nil, {
        on_done = function()
          calls = calls + 1
        end,
      })

    vim.fn.readfile = saved_readfile

    eq(
      run_ok,
      false,
      "BUG: an unreadable file throws out of directory.run instead of being reported"
    )
    ok(
      tostring(run_err):find("E484", 1, true) ~= nil,
      "BUG: what escapes is Vim's raw E484, not the module's own message (got: "
        .. tostring(run_err)
        .. ")"
    )
    eq(core_ok, false, "BUG: and it escapes core.run the same way, reaching :Diff unhandled")
    eq(calls, 0, "BUG: on_done never fires, so an API caller waits forever")
  end

  require("diff.core.scratch").cleanup_all()
  vim.cmd("silent! only")
end

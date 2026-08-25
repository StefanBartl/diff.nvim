-- TESTS/directory_spec.lua — core.directory: source=/target= both real
-- directories compares the two trees file-by-file instead of a single
-- unified diff.

return function(H)
  local eq, ok = H.eq, H.ok
  local directory = require("diff.core.directory")

  -- is_directory_spec ------------------------------------------------------
  local dir = H.tmpdir()
  ok(directory.is_directory_spec(dir), "a real directory is a directory spec")
  ok(not directory.is_directory_spec("current"), '"current" is never a directory spec')
  ok(not directory.is_directory_spec("clipboard"), '"clipboard" is never a directory spec')
  ok(not directory.is_directory_spec("42"), "a buffer number is never a directory spec")
  ok(not directory.is_directory_spec("git:HEAD"), "git:<rev> is never a directory spec")
  ok(not directory.is_directory_spec("https://example.com/x"), "a URL is never a directory spec")
  ok(
    not directory.is_directory_spec("/does/not/exist"),
    "a nonexistent path is not a directory spec"
  )

  -- Build two small trees:
  --   source: a.txt (2 lines), removed_only.txt
  --   target: a.txt (1 line changed), added_only.txt
  -- .git/ in each is planted to prove hidden segments are excluded.
  local source_dir = H.tmpdir()
  local target_dir = H.tmpdir()
  H.write_file(source_dir .. "a.txt", { "one", "two" })
  H.write_file(source_dir .. "removed_only.txt", { "gone" })
  H.write_file(source_dir .. ".git/HEAD", { "ref: refs/heads/main" })
  H.write_file(target_dir .. "a.txt", { "one", "TWO" })
  H.write_file(target_dir .. "added_only.txt", { "new" })
  H.write_file(target_dir .. ".git/HEAD", { "ref: refs/heads/main" })

  local cfg = {
    algorithm = "histogram",
    ctxlen = 3,
    directory_max_files = 2000,
    stat_list = "off",
    stat_list_mode = "add",
  }

  -- output=buffer: opens a scratch buffer listing one line per changed file,
  -- and none for the two identical .git/HEAD files (hidden-segment exclusion).
  do
    vim.cmd("silent! only")
    directory.run(source_dir, target_dir, "src", "tgt", "buffer", cfg)
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    ok(text:match("M%s+%+1%s+%-1%s+a%.txt") ~= nil, "buffer summary: a.txt shown as modified +1 -1")
    ok(
      text:match("A%s+%+1%s+%-0%s+added_only%.txt") ~= nil,
      "buffer summary: added_only.txt shown as added"
    )
    ok(
      text:match("D%s+%+0%s+%-1%s+removed_only%.txt") ~= nil,
      "buffer summary: removed_only.txt shown as deleted"
    )
    ok(not text:match("%.git"), "buffer summary: hidden .git/ segment excluded from both trees")
    ok(text:match("3 files changed"), "buffer summary: file-count total")
    vim.cmd("silent! only")
  end

  -- output=clipboard: same summary, copied to the "+" register.
  do
    local saved = vim.fn.getreg("+")
    directory.run(source_dir, target_dir, "src", "tgt", "clipboard", cfg)
    local reg = vim.fn.getreg("+")
    ok(reg:match("a%.txt") ~= nil, "clipboard summary contains a.txt")
    vim.fn.setreg("+", saved)
  end

  -- output=file: summary written to a temp file, end-to-end without error.
  do
    local ok_run = pcall(directory.run, source_dir, target_dir, "src", "tgt", "file", cfg)
    ok(ok_run, "output=file runs without error")
  end

  -- output=stat with stat_list="qf": one quickfix entry per changed file,
  -- each carrying a real filename (target's path for M/A, source's for D).
  do
    vim.fn.setqflist({}, "r", { title = "", items = {} })
    local qf_cfg = vim.tbl_extend("force", cfg, { stat_list = "qf", stat_list_mode = "replace" })
    directory.run(source_dir, target_dir, "src", "tgt", "stat", qf_cfg)
    local qf = vim.fn.getqflist()
    eq(#qf, 3, "directory stat: one qf entry per changed file")
    vim.fn.setqflist({}, "r", { title = "", items = {} })
  end

  -- No differences: two identical trees produce an empty (not error) result.
  do
    local same_dir = H.tmpdir()
    H.write_file(same_dir .. "x.txt", { "same" })
    vim.cmd("silent! only")
    directory.run(same_dir, same_dir, "src", "tgt", "buffer", cfg)
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ok(
      table.concat(lines, "\n"):match("No differences found") ~= nil,
      "identical trees: no differences"
    )
    vim.cmd("silent! only")
  end

  -- directory_max_files: a cap of 0 must error rather than silently truncate.
  do
    local tiny_cfg = vim.tbl_extend("force", cfg, { directory_max_files = 0 })
    -- Route through notify (no return value), so just assert it doesn't
    -- throw and doesn't open a buffer (still on whatever window we had).
    local win_before = vim.api.nvim_get_current_win()
    local ok_run = pcall(directory.run, source_dir, target_dir, "src", "tgt", "buffer", tiny_cfg)
    ok(ok_run, "directory_max_files=0 does not throw, just reports an error")
    eq(vim.api.nvim_get_current_win(), win_before, "directory_max_files=0: no buffer/window opened")
  end
end

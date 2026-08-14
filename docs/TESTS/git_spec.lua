-- docs/TESTS/git_spec.lua — core.git: is_git_spec + resolve against HEAD.
--
-- Runs from the repo root (see run.lua), so the working directory is a real
-- git repository and a committed file can be resolved for real.

return function(H)
  local eq, ok = H.eq, H.ok
  local git = require("diff.core.git")

  -- is_git_spec ----------------------------------------------------------
  ok(git.is_git_spec("git:HEAD"), "git:HEAD is a git spec")
  ok(git.is_git_spec("git:abc123"), "git:<sha> is a git spec")
  ok(not git.is_git_spec("clipboard"), "clipboard is not a git spec")
  ok(not git.is_git_spec("path/to/file"), "path is not a git spec")
  ok(not git.is_git_spec(42), "number is not a git spec")

  -- Skip the live resolution when git is unavailable (keeps CI portable).
  if vim.fn.executable("git") ~= 1 or type(vim.system) ~= "function" then
    return
  end

  -- resolve: a committed file at HEAD -----------------------------------
  local abspath = vim.fs.normalize(vim.fn.getcwd() .. "/lua/diff/init.lua")
  local lines, err = git.resolve("git:HEAD", abspath, "target")
  ok(err == nil, "git:HEAD resolves without error (" .. tostring(err) .. ")")
  ok(type(lines) == "table" and #lines > 0, "git:HEAD returns content lines")

  -- empty revision -------------------------------------------------------
  local no_rev, rev_err = git.resolve("git:", abspath, "target")
  eq(no_rev, nil, "empty revision resolves to nil")
  ok(rev_err ~= nil, "empty revision reports an error")

  -- no file-backed buffer ------------------------------------------------
  local no_buf, buf_err = git.resolve("git:HEAD", "", "source")
  eq(no_buf, nil, "git:HEAD without a file resolves to nil")
  ok(buf_err ~= nil, "git:HEAD without a file reports an error")

  -- unknown revision -----------------------------------------------------
  local bad, bad_err =
    git.resolve("git:def0000000000000000000000000000000000000", abspath, "target")
  eq(bad, nil, "unknown revision resolves to nil")
  ok(bad_err ~= nil, "unknown revision reports an error")

  -- end-to-end: target=git:<rev1>..<rev2> bypasses the working buffer -----
  -- core.run()'s split_git_range expansion (docs/TESTS/resolve_spec.lua unit-
  -- tests the split itself) wired all the way through to a real diff: the
  -- current buffer holds content that appears in NEITHER revision, so a
  -- successful stat proves the range — not the buffer — was diffed, and a
  -- "current"-ish source= alongside it must be silently overridden.
  do
    local core = require("diff.core")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "this text is in neither git revision" })
    vim.api.nvim_buf_set_name(buf, abspath)

    local out = {}
    local saved_notify = vim.notify
    vim.notify = function(m)
      out[#out + 1] = m
    end
    core.run("target=git:HEAD~1..HEAD source=clipboard output=stat")
    vim.notify = saved_notify

    ok(#out > 0, "git range end-to-end: produced a notification")
    local last = out[#out]
    ok(
      not last:find("could not resolve", 1, true) and not last:find("clipboard is empty", 1, true),
      "git range end-to-end: no resolution error (got: " .. tostring(last) .. ")"
    )
  end
end

-- docs/TESTS/git_spec.lua — core.git: is_git_spec + resolve against HEAD.
--
-- Runs from the repo root (see run.lua), so the working directory is a real
-- git repository and a committed file can be resolved for real.

return function(H)
  local eq, ok = H.eq, H.ok
  local git = require("diff_nvim.core.git")

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
  local abspath = vim.fs.normalize(vim.fn.getcwd() .. "/lua/diff_nvim/init.lua")
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
  local bad, bad_err = git.resolve("git:def0000000000000000000000000000000000000", abspath, "target")
  eq(bad, nil, "unknown revision resolves to nil")
  ok(bad_err ~= nil, "unknown revision reports an error")
end

-- TESTS/git_argv_spec.lua — core.git without a real `git` process.
--
-- git_spec.lua drives the happy path against this repo's own history, which
-- proves the feature works but says nothing about *what* was spawned: the
-- revision spelling, the repo root, the `-C` flag, or the path separator git
-- is handed. This spec replaces `vim.system` before the module under test is
-- required and asserts the argv itself, plus every branch around the spawn
-- (non-zero exit with and without stderr, empty output, a throwing spawn, and
-- each guard clause).
--
-- The repository is a *fixture*: `repo_root` only looks for a `.git` entry, it
-- never runs git, so a bare directory named `.git` is a complete stand-in and
-- the whole spec stays deterministic and process-free.

return function(H)
  local eq, ok = H.eq, H.ok

  local saved_system = vim.system
  local saved_executable = vim.fn.executable

  ---Load a fresh `diff.core.git` bound to whatever `vim.system` currently is.
  ---The module captures `vim.fn` (a table, so a field patch reaches it) but
  ---reads `vim.system` through `vim` itself, so re-requiring is belt and
  ---braces rather than strictly needed -- it also guarantees no state from an
  ---earlier case survives into the next one.
  ---@return table
  local function fresh_git()
    package.loaded["diff.core.git"] = nil
    return require("diff.core.git")
  end

  ---Run `git.resolve` and block until its callback fired (the runner is not
  ---async-aware), the same way git_spec/url_spec await theirs.
  ---@param git table
  ---@param spec string
  ---@param bufname string
  ---@param label string|nil
  ---@return string[]|nil lines, string|nil err, boolean done
  local function await(git, spec, bufname, label)
    local done, lines, err = false, nil, nil
    git.resolve(spec, bufname, label or "target", function(l, e)
      lines, err, done = l, e, true
    end)
    vim.wait(5000, function()
      return done
    end, 5)
    return lines, err, done
  end

  ---Pretend `git` is (or is not) on PATH, leaving every other probe alone.
  ---@param present boolean
  local function stub_executable(present)
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      if name == "git" then
        return present and 1 or 0
      end
      return saved_executable(name)
    end
  end

  ---Install a `vim.system` double that records its argv and replies with
  ---`res`. Returns a getter for the recorded call.
  ---@param res table  The SystemCompleted-shaped table to hand the callback
  ---@return fun(): table|nil
  local function stub_system(res)
    local captured = nil
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts, cb)
      captured = { cmd = cmd, opts = opts }
      vim.schedule(function()
        cb(res)
      end)
      return {
        kill = function() end,
      }
    end
    return function()
      return captured
    end
  end

  -- A fake repository: `<root>/.git/` plus a tracked-looking file in a
  -- subdirectory, so the relative path git is handed has a separator in it.
  local root = H.tmpdir():gsub("/$", "")
  vim.fn.mkdir(root .. "/.git", "p")
  H.write_file(root .. "/src/deep/file.lua", { "fixture" })
  local file = root .. "/src/deep/file.lua"

  -- argv shape ---------------------------------------------------------------
  do
    stub_executable(true)
    local get = stub_system({ code = 0, stdout = "alpha\nbeta\n", stderr = "" })
    local git = fresh_git()
    local lines, err = await(git, "git:HEAD~2", file)

    local call = get()
    ok(call ~= nil, "resolve() spawned something")
    local argv = call.cmd
    eq(argv[1], "git", "argv[1] is the bare binary name, not a shell string")
    eq(argv[2], "-C", "argv[2] is -C (git is run in the repo, never via cd)")
    eq(argv[4], "show", "argv[4] is the show subcommand")
    eq(#argv, 5, "argv has exactly five elements -- nothing is concatenated")
    eq(call.opts.text, true, "spawned with text=true so stdout arrives as a string")

    -- The two path-bearing elements are the ones a separator mismatch would
    -- silently corrupt: git only understands forward slashes inside a
    -- <rev>:<path> object, and a backslash there is a *filename character*,
    -- not a separator -- so it fails as "path does not exist in HEAD~2"
    -- rather than as anything a user could act on.
    eq(argv[3]:find("\\", 1, true), nil, "the repo root passed to -C has no backslash")
    eq(argv[5]:find("\\", 1, true), nil, "the <rev>:<path> object has no backslash")
    eq(argv[5], "HEAD~2:src/deep/file.lua", "object is <rev>:<path-relative-to-root>")
    eq(argv[3], vim.fs.normalize(root), "-C gets the normalized repo root")

    eq(err, nil, "a clean exit reports no error")
    eq(table.concat(lines or {}, "|"), "alpha|beta", "stdout becomes the content lines")
  end

  -- A path containing spaces stays one argv element -------------------------
  -- There is no shell in this pipeline, so a space must not need quoting and
  -- must not split; asserting it here is what keeps it that way.
  do
    local spaced_root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(spaced_root .. "/.git", "p")
    H.write_file(spaced_root .. "/my dir/my file.lua", { "x" })

    stub_executable(true)
    local get = stub_system({ code = 0, stdout = "x\n", stderr = "" })
    local git = fresh_git()
    await(git, "git:HEAD", spaced_root .. "/my dir/my file.lua")

    local argv = get().cmd
    eq(#argv, 5, "a path with spaces does not add argv elements")
    eq(argv[5], "HEAD:my dir/my file.lua", "spaces are passed through unquoted and unsplit")
  end

  -- A revision name that itself contains a colon/slash ----------------------
  -- `git:` is stripped by prefix length, not by matching up to the next
  -- colon, so a refspec like `refs/heads/x` survives intact.
  do
    stub_executable(true)
    local get = stub_system({ code = 0, stdout = "y\n", stderr = "" })
    local git = fresh_git()
    await(git, "git:refs/heads/feature", file)
    eq(get().cmd[5], "refs/heads/feature:src/deep/file.lua", "a full refspec survives the strip")
  end

  -- Windows: a backslash-spelled buffer name must reach the same argv -------
  -- Two spellings of one path comparing unequal is the failure mode this
  -- campaign keeps finding; here it would show up as "file is outside the git
  -- repo root" for a file that plainly is not.
  if vim.fn.has("win32") == 1 then
    stub_executable(true)
    local get = stub_system({ code = 0, stdout = "z\n", stderr = "" })
    local git = fresh_git()
    local backslashed = file:gsub("/", "\\")
    local _, err = await(git, "git:HEAD", backslashed)
    eq(err, nil, "a backslash-spelled buffer name still resolves inside the repo")
    local argv = get().cmd
    eq(argv[5], "HEAD:src/deep/file.lua", "backslash spelling yields the same <rev>:<path>")
    eq(argv[3], vim.fs.normalize(root), "backslash spelling yields the same repo root")
  end

  -- A `.git` *file* (worktree/submodule) is a repo root too ------------------
  do
    local wt = H.tmpdir():gsub("/$", "")
    H.write_file(wt .. "/.git", { "gitdir: " .. root .. "/.git/worktrees/wt" })
    H.write_file(wt .. "/a.lua", { "x" })

    stub_executable(true)
    local get = stub_system({ code = 0, stdout = "x\n", stderr = "" })
    local git = fresh_git()
    local _, err = await(git, "git:HEAD", wt .. "/a.lua")
    eq(err, nil, "a .git file (worktree/submodule) is accepted as a repo root")
    eq(get().cmd[3], vim.fs.normalize(wt), "-C points at the worktree directory")
  end

  -- Failure branches around the spawn ----------------------------------------
  do
    stub_executable(true)

    -- non-zero exit, stderr present: git's own message is surfaced, trimmed
    stub_system({ code = 128, stdout = "", stderr = "fatal: invalid object name\n" })
    local _, err1 = await(fresh_git(), "git:nope", file, "source")
    eq(err1, "source: fatal: invalid object name", "git's stderr is reported verbatim and trimmed")

    -- non-zero exit, no stderr: a synthesized message that still names the object
    stub_system({ code = 1, stdout = "", stderr = "" })
    local _, err2 = await(fresh_git(), "git:HEAD", file)
    ok(
      err2 and err2:find("git show HEAD:src/deep/file.lua", 1, true) ~= nil,
      "a silent failure still names the object that failed (got: " .. tostring(err2) .. ")"
    )

    -- clean exit, empty stdout: an empty file at that revision is content,
    -- not an error -- one empty line, matching what readfile() would give.
    stub_system({ code = 0, stdout = "", stderr = "" })
    local lines3, err3 = await(fresh_git(), "git:HEAD", file)
    eq(err3, nil, "an empty file at a revision is not an error")
    eq(#(lines3 or {}), 1, "empty output is one empty line, like readfile()")
    eq(lines3 and lines3[1], "", "that one line is empty")

    -- stdout carrying CRLF (core.autocrlf=true) must normalize like a buffer
    stub_system({ code = 0, stdout = "one\r\ntwo\r\n", stderr = "" })
    local lines4 = await(fresh_git(), "git:HEAD", file)
    eq(
      table.concat(lines4 or {}, "|"),
      "one|two",
      "CRLF from git is stripped, like split_lines does"
    )

    -- the spawn itself throwing (ENOENT) is reported, never propagated
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function()
      error("ENOENT")
    end
    local lines5, err5, done5 = await(fresh_git(), "git:HEAD", file)
    ok(done5, "a throwing spawn still calls back")
    eq(lines5, nil, "a throwing spawn produces no lines")
    eq(err5, "target: git invocation failed", "a throwing spawn is reported as our own error")
  end

  -- Guard clauses, all of which must report *before* anything is spawned ----
  do
    local spawned = false
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function()
      spawned = true
      return { kill = function() end }
    end

    stub_executable(true)
    local git = fresh_git()

    local _, e_rev = await(git, "git:", file)
    ok(e_rev and e_rev:find("empty git revision", 1, true) ~= nil, "an empty revision is refused")

    local _, e_buf = await(git, "git:HEAD", "")
    ok(e_buf and e_buf:find("file-backed buffer", 1, true) ~= nil, "an unnamed buffer is refused")

    ---@diagnostic disable-next-line: param-type-mismatch
    local _, e_nonstr = await(git, "git:HEAD", nil)
    ok(e_nonstr ~= nil, "a non-string buffer name is refused")

    local outside = H.tmpdir() .. "loose.lua"
    H.write_file(outside, { "x" })
    local _, e_repo = await(git, "git:HEAD", outside)
    ok(
      e_repo and e_repo:find("not inside a git repository", 1, true) ~= nil,
      "a file outside any repository is refused (got: " .. tostring(e_repo) .. ")"
    )

    -- git missing from PATH
    stub_executable(false)
    local _, e_exe = await(fresh_git(), "git:HEAD", file)
    ok(e_exe and e_exe:find("git executable", 1, true) ~= nil, "a missing git binary is refused")

    -- vim.system missing entirely (Neovim < 0.10)
    stub_executable(true)
    vim.system = nil
    local _, e_sys = await(fresh_git(), "git:HEAD", file)
    ok(e_sys and e_sys:find("vim.system", 1, true) ~= nil, "no vim.system is refused by name")

    eq(spawned, false, "none of the guard clauses reached the spawn")
  end

  -- label defaults to "target" when the caller omits it ----------------------
  do
    vim.system = saved_system
    stub_executable(true)
    local git = fresh_git()
    local done, err = false, nil
    ---@diagnostic disable-next-line: param-type-mismatch
    git.resolve("git:", "", nil, function(_, e)
      err, done = e, true
    end)
    vim.wait(2000, function()
      return done
    end, 5)
    ok(err and err:sub(1, 7) == "target:", "an omitted label defaults to 'target'")
  end

  vim.system = saved_system
  vim.fn.executable = saved_executable
  package.loaded["diff.core.git"] = nil
end

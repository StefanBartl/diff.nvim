-- TESTS/history_spec.lua — core.history: parse(), log() argv/guards, and
-- diff_entry()'s explicit-path wiring into core.execute.
--
-- Same fixture-repo + stubbed-vim.system pattern as git_argv_spec.lua: a bare
-- directory named ".git" is a complete stand-in for repo_root's own walk,
-- and nothing here spawns a real git process, so the spec stays
-- deterministic and platform-independent.

return function(H)
  local eq, ok = H.eq, H.ok
  local history = require("diff.core.history")

  -- M.parse -- pure, no stubbing needed ---------------------------------------
  do
    local RS, FS = "\1", "\31"

    ---@param sha string
    ---@param short string
    ---@param date string
    ---@param author string
    ---@param subject string
    ---@param body string  Lines after the header, e.g. "M src/x.lua"
    ---@return string
    local function block(sha, short, date, author, subject, body)
      return RS .. table.concat({ sha, short, date, author, subject }, FS) .. "\n" .. (body or "")
    end

    eq(#history.parse(""), 0, "empty input parses to no entries")
    ---@diagnostic disable-next-line: param-type-mismatch
    eq(#history.parse(nil), 0, "nil input parses to no entries")

    -- A plain modify -----------------------------------------------------------
    local one = history.parse(block("aaa111", "aaa", "2026-01-01", "Ada", "fix: x", "M src/x.lua"))
    eq(#one, 1, "one commit block parses to one entry")
    eq(one[1].sha, "aaa111", "sha")
    eq(one[1].short, "aaa", "short")
    eq(one[1].date, "2026-01-01", "date")
    eq(one[1].author, "Ada", "author")
    eq(one[1].subject, "fix: x", "subject")
    eq(one[1].path, "src/x.lua", "a plain modify's path is the M line's own path")
    eq(one[1].parent_path, "src/x.lua", "parent_path matches path outside a rename")

    -- Added / deleted status letters carry a digit-free prefix -----------------
    local added = history.parse(block("b1", "b", "2026-01-02", "Bob", "add: y", "A src/y.lua"))
    eq(added[1].path, "src/y.lua", "A status parses the same as M")

    -- A rename: R<score> old<TAB>new --------------------------------------------
    local renamed = history.parse(
      block("c1", "c", "2026-01-03", "Cy", "rename", "R100\told/name.lua\tnew/name.lua")
    )
    eq(renamed[1].path, "new/name.lua", "rename: path is the new name (at this commit)")
    eq(
      renamed[1].parent_path,
      "old/name.lua",
      "rename: parent_path is the old name (at the parent)"
    )

    -- A copy: C<score> old<TAB>new behaves the same way as a rename ------------
    local copied =
      history.parse(block("d1", "d", "2026-01-04", "Di", "copy", "C100\tsrc/a.lua\tsrc/b.lua"))
    eq(copied[1].path, "src/b.lua", "copy: path is the new (copied-to) name")
    eq(copied[1].parent_path, "src/a.lua", "copy: parent_path is the source of the copy")

    -- A merge commit has no body line at all -- both fields come back nil, not
    -- the pathspec fallback (that fallback is M.log's job, not M.parse's).
    local merged = history.parse(block("e1", "e", "2026-01-05", "Eve", "Merge branch 'x'", ""))
    eq(merged[1].path, nil, "a merge commit's path is nil from parse() alone")
    eq(merged[1].parent_path, nil, "a merge commit's parent_path is nil from parse() alone")

    -- Extra blank lines around a commit (git's own format: separator) must not
    -- confuse the block boundary or the single real path line.
    local padded = history.parse(
      RS
        .. table.concat({ "f1", "f", "2026-01-06", "Fi", "pad" }, FS)
        .. "\n\nM src/z.lua\n\n"
        .. RS
        .. table.concat({ "g1", "g", "2026-01-07", "Gi", "second" }, FS)
        .. "\nM src/w.lua\n"
    )
    eq(#padded, 2, "two commits separated by blank lines parse to two entries")
    eq(padded[1].path, "src/z.lua", "first entry's path survives the blank-line padding")
    eq(padded[1].sha, "f1", "commit order is preserved (git log's own newest-first order)")
    eq(padded[2].sha, "g1", "second entry parses independently of the first")
    eq(padded[2].path, "src/w.lua", "second entry's path")
  end

  -- M.log -- argv shape, guard clauses, stdout parsing, error surfacing ------
  do
    local saved_system = vim.system
    local saved_executable = vim.fn.executable

    ---@return table
    local function fresh_history()
      package.loaded["diff.core.history"] = nil
      package.loaded["diff.core.git"] = nil
      return require("diff.core.history")
    end

    ---@param present boolean
    local function stub_executable(present)
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.executable = function(name)
        if name == "git" then
          return present and 1 or 0
        end
        return saved_executable(name)
      end
    end

    ---@param res table
    ---@return fun(): table|nil
    local function stub_system(res)
      local captured = nil
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, opts, cb)
        captured = { cmd = cmd, opts = opts }
        vim.schedule(function()
          cb(res)
        end)
        return { kill = function() end }
      end
      return function()
        return captured
      end
    end

    ---@param h table
    ---@param bufname string
    ---@param max_entries integer
    ---@return table|nil entries, string|nil err, boolean done
    local function await_log(h, bufname, max_entries)
      local done, entries, err = false, nil, nil
      h.log(bufname, max_entries, function(e, er)
        entries, err, done = e, er, true
      end)
      vim.wait(5000, function()
        return done
      end, 5)
      return entries, err, done
    end

    local root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(root .. "/.git", "p")
    H.write_file(root .. "/src/deep/file.lua", { "fixture" })
    local file = root .. "/src/deep/file.lua"

    -- argv shape -----------------------------------------------------------
    do
      stub_executable(true)
      local get = stub_system({ code = 0, stdout = "", stderr = "" })
      local h = fresh_history()
      await_log(h, file, 50)

      local argv = get().cmd
      eq(argv[1], "git", "argv[1] is the bare binary name")
      eq(argv[2], "-c", "argv[2] is -c (a global option, before the subcommand)")
      eq(argv[3], "core.quotePath=false", "core.quotePath is forced off")
      eq(argv[4], "-C", "argv[4] is -C (no shell cd)")
      eq(argv[5], vim.fs.normalize(root), "-C gets the normalized repo root")
      eq(argv[6], "log", "argv[6] is the log subcommand")
      ok(vim.tbl_contains(argv, "--follow"), "--follow is passed (renames are tracked)")
      ok(vim.tbl_contains(argv, "--name-status"), "--name-status is passed (parse() needs it)")
      ok(vim.tbl_contains(argv, "--max-count=50"), "max_entries becomes --max-count")
      eq(argv[#argv - 1], "--", "second-to-last argv element is the pathspec separator")
      eq(argv[#argv], "src/deep/file.lua", "last argv element is the file, relative to root")
    end

    -- stdout parsing end-to-end, including the merge-commit fallback -------
    do
      stub_executable(true)
      local RS, FS = "\1", "\31"
      local stdout = RS
        .. table.concat({ "aaa", "aa", "2026-02-01", "Ada", "normal commit" }, FS)
        .. "\nM src/deep/file.lua\n"
        .. RS
        .. table.concat({ "bbb", "bb", "2026-02-02", "Bob", "Merge branch 'x'" }, FS)
        .. "\n"
      stub_system({ code = 0, stdout = stdout, stderr = "" })
      local h = fresh_history()
      local entries, err = await_log(h, file, 200)

      eq(err, nil, "a clean two-commit log reports no error")
      eq(#(entries or {}), 2, "both commits are parsed")
      eq(entries[1].path, "src/deep/file.lua", "the modify entry keeps its own path")
      eq(
        entries[2].path,
        "src/deep/file.lua",
        "the merge entry (no body line) falls back to the pathspec that found it"
      )
      eq(
        entries[2].parent_path,
        "src/deep/file.lua",
        "the merge entry's parent_path falls back the same way"
      )
    end

    -- empty history reports an error, not an empty list --------------------
    do
      stub_executable(true)
      stub_system({ code = 0, stdout = "", stderr = "" })
      local h = fresh_history()
      local entries, err = await_log(h, file, 200)
      eq(entries, nil, "no matching commits resolves to nil")
      ok(err and err:find("no history", 1, true) ~= nil, "empty history is reported by name")
    end

    -- non-zero exit surfaces git's stderr -----------------------------------
    do
      stub_executable(true)
      stub_system({ code = 128, stdout = "", stderr = "fatal: bad revision\n" })
      local h = fresh_history()
      local entries, err = await_log(h, file, 200)
      eq(entries, nil, "a failing git log resolves to nil")
      eq(err, "fatal: bad revision", "git's own stderr is surfaced, trimmed")
    end

    -- guard clauses, none of which spawn anything ---------------------------
    do
      local spawned = false
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function()
        spawned = true
        return { kill = function() end }
      end
      stub_executable(true)
      local h = fresh_history()

      local _, e_buf = await_log(h, "", 200)
      ok(e_buf and e_buf:find("file path", 1, true) ~= nil, "an empty bufname is refused")

      local outside = H.tmpdir() .. "loose.lua"
      H.write_file(outside, { "x" })
      local _, e_repo = await_log(h, outside, 200)
      ok(
        e_repo and e_repo:find("not inside a git repository", 1, true) ~= nil,
        "a file outside any repository is refused"
      )

      stub_executable(false)
      local _, e_exe = await_log(fresh_history(), file, 200)
      ok(e_exe and e_exe:find("git executable", 1, true) ~= nil, "a missing git binary is refused")

      stub_executable(true)
      vim.system = nil
      local _, e_sys = await_log(fresh_history(), file, 200)
      ok(e_sys and e_sys:find("vim.system", 1, true) ~= nil, "no vim.system is refused by name")

      eq(spawned, false, "none of the guard clauses reached the spawn")
    end

    vim.system = saved_system
    vim.fn.executable = saved_executable
    package.loaded["diff.core.history"] = nil
    package.loaded["diff.core.git"] = nil
  end

  -- git.resolve's explicit-path spec (git:<rev>:<path>) -- what diff_entry
  -- relies on to diff the right two paths across a rename. -------------------
  do
    local saved_system = vim.system
    local saved_executable = vim.fn.executable

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      if name == "git" then
        return 1
      end
      return saved_executable(name)
    end

    local captured = nil
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _, cb)
      captured = cmd
      vim.schedule(function()
        cb({ code = 0, stdout = "content\n", stderr = "" })
      end)
      return { kill = function() end }
    end

    local root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(root .. "/.git", "p")
    local file = root .. "/src/current/name.lua"
    H.write_file(file, { "x" })

    package.loaded["diff.core.git"] = nil
    local git = require("diff.core.git")

    local done, lines, err = false, nil, nil
    git.resolve("git:abc123:old/name.lua", file, "source", function(l, e)
      lines, err, done = l, e, true
    end)
    vim.wait(5000, function()
      return done
    end, 5)

    eq(err, nil, "git:<rev>:<path> resolves without error")
    eq(
      captured[#captured],
      "abc123:old/name.lua",
      "the explicit path wins over the buffer's own path"
    )
    eq(table.concat(lines or {}, "|"), "content", "stdout still becomes content lines")

    -- An empty explicit path is refused before anything is spawned.
    local spawned = false
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function()
      spawned = true
      return { kill = function() end }
    end
    local _, e_empty = nil, nil
    local done2 = false
    git.resolve("git:abc123:", file, "target", function(_, e)
      e_empty, done2 = e, true
    end)
    vim.wait(2000, function()
      return done2
    end, 5)
    ok(e_empty and e_empty:find("empty path", 1, true) ~= nil, "an empty explicit path is refused")
    eq(spawned, false, "the empty-path guard reports before spawning")

    vim.system = saved_system
    vim.fn.executable = saved_executable
    package.loaded["diff.core.git"] = nil
  end

  -- diff_entry -- wires an entry's two paths into core.execute as two
  -- git:<rev>:<path> targets, through the *real* core.execute (output=stat,
  -- so nothing needs a window) -- same "end-to-end via a stubbed spawn"
  -- pattern git_spec.lua's own range test uses. ------------------------------
  do
    local saved_system = vim.system
    local saved_executable = vim.fn.executable

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      if name == "git" then
        return 1
      end
      return saved_executable(name)
    end

    local objects = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _, cb)
      local object = cmd[#cmd]
      objects[#objects + 1] = object
      -- Echo the object string back as content, so target and source differ
      -- (their objects differ) and the diff has something real to report.
      vim.schedule(function()
        cb({ code = 0, stdout = object .. "\n", stderr = "" })
      end)
      return { kill = function() end }
    end

    local root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(root .. "/.git", "p")
    local file = root .. "/src/current/name.lua"
    H.write_file(file, { "x" })

    package.loaded["diff.core.git"] = nil
    package.loaded["diff.core.history"] = nil
    local h = require("diff.core.history")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_name(buf, file)
    local ctx = {
      source_bufnr = buf,
      origin_win = vim.api.nvim_get_current_win(),
      range = nil,
    }

    local out = {}
    local saved_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m)
      out[#out + 1] = m
    end

    local entry = {
      sha = "deadbeef",
      short = "dead",
      date = "2026-03-01",
      author = "Ada",
      subject = "x",
      path = "src/current/name.lua",
      parent_path = "src/old/name.lua",
    }
    h.diff_entry(entry, ctx, { view = "vsplit", output = "stat" })

    vim.wait(5000, function()
      return #out > 0
    end, 5)
    vim.notify = saved_notify

    ok(#out > 0, "diff_entry produced a notification")
    local last = out[#out]
    ok(
      not last:find("could not resolve", 1, true),
      "diff_entry: no resolution error (got: " .. tostring(last) .. ")"
    )
    eq(#objects, 2, "diff_entry resolved exactly two sides")
    ok(
      vim.tbl_contains(objects, "deadbeef:src/current/name.lua"),
      "target is <sha>:<path-at-this-commit>"
    )
    ok(
      vim.tbl_contains(objects, "deadbeef^:src/old/name.lua"),
      "source is <sha>^:<path-at-the-parent> -- the renamed name, not the current one"
    )

    vim.system = saved_system
    vim.fn.executable = saved_executable
    package.loaded["diff.core.git"] = nil
    package.loaded["diff.core.history"] = nil
  end

  -- diff_entry -- ctx.anchor, not ctx.source_bufnr, decides the repo root --
  -- The bug this guards: core.execute's git-spec resolution used to derive
  -- its repo-root anchor solely from ctx.source_bufnr's buffer name, even
  -- for M.diff_entry's fully-qualified git:<sha>:<path> specs, which carry
  -- everything git needs *except* a directory to run -C from. M.log never
  -- touches ctx.source_bufnr at all (it resolves its own root straight from
  -- the [path] argument or the current buffer, whichever ran the listing),
  -- so an unnamed current buffer -- or one that simply belongs to a
  -- *different* git repository than the file :DiffHistory was pointed at --
  -- made every picker selection fail (or, worse, resolve against the wrong
  -- repository) right after the listing step had already succeeded. ---------
  do
    local saved_system = vim.system
    local saved_executable = vim.fn.executable

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      if name == "git" then
        return 1
      end
      return saved_executable(name)
    end

    local right_root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(right_root .. "/.git", "p")
    local right_file = right_root .. "/src/current/name.lua"
    H.write_file(right_file, { "x" })

    -- An unrelated second repository -- only its existence matters: it
    -- proves *which* root a call used, by being the wrong one to pick.
    local wrong_root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(wrong_root .. "/.git", "p")
    local wrong_file = wrong_root .. "/other.lua"
    H.write_file(wrong_file, { "y" })

    ---Install a vim.system double that appends each call's argv to `into` and
    ---echoes the object (its last argv element) back as stdout.
    ---@param into string[][]
    ---@return nil
    local function stub_system_capturing(into)
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, cb)
        into[#into + 1] = cmd
        vim.schedule(function()
          cb({ code = 0, stdout = (cmd[#cmd] or "") .. "\n", stderr = "" })
        end)
        return { kill = function() end }
      end
    end

    package.loaded["diff.core.git"] = nil
    package.loaded["diff.core.history"] = nil
    local h = require("diff.core.history")

    local entry = {
      sha = "deadbeef",
      short = "dead",
      date = "2026-03-01",
      author = "Ada",
      subject = "x",
      path = "src/current/name.lua",
      parent_path = "src/current/name.lua",
    }

    -- Case 1: an UNNAMED current buffer, correct anchor -----------------------
    do
      local calls = {}
      stub_system_capturing(calls)
      local buf = vim.api.nvim_create_buf(false, true) -- deliberately unnamed
      local ctx = {
        source_bufnr = buf,
        origin_win = vim.api.nvim_get_current_win(),
        range = nil,
        anchor = right_file,
      }
      local out = {}
      local saved_notify = vim.notify
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(m)
        out[#out + 1] = m
      end
      h.diff_entry(entry, ctx, { view = "vsplit", output = "stat" })
      vim.wait(5000, function()
        return #out > 0
      end, 5)
      vim.notify = saved_notify

      ok(#out > 0, "unnamed buffer + anchor: still produced a notification")
      ok(
        not (out[#out]):find("needs a file", 1, true),
        "unnamed buffer + anchor: no 'needs a file-backed buffer' error (got: "
          .. tostring(out[#out])
          .. ")"
      )
      eq(#calls, 2, "unnamed buffer + anchor: resolved exactly two sides")
      for _, cmd in ipairs(calls) do
        eq(
          cmd[3],
          vim.fs.normalize(right_root),
          "unnamed buffer + anchor: -C uses the anchor's root, not the (nonexistent) buffer name's"
        )
      end
    end

    -- Case 2: current buffer belongs to a DIFFERENT repo than the anchor ------
    do
      local calls = {}
      stub_system_capturing(calls)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, wrong_file)
      local ctx = {
        source_bufnr = buf,
        origin_win = vim.api.nvim_get_current_win(),
        range = nil,
        anchor = right_file,
      }
      h.diff_entry(entry, ctx, { view = "vsplit", output = "stat" })
      vim.wait(5000, function()
        return #calls >= 2
      end, 5)

      eq(#calls, 2, "cross-repo buffer + anchor: resolved exactly two sides")
      for _, cmd in ipairs(calls) do
        eq(
          cmd[3],
          vim.fs.normalize(right_root),
          "cross-repo buffer + anchor: -C uses the anchor's repo, not the current buffer's unrelated one"
        )
      end
    end

    -- Case 3: no anchor set (plain :Diff/:DiffBuffers shape) still falls back
    -- to source_bufnr's own name, unchanged from before this fix. ------------
    do
      local calls = {}
      stub_system_capturing(calls)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, right_file)
      local ctx = {
        source_bufnr = buf,
        origin_win = vim.api.nvim_get_current_win(),
        range = nil,
        -- anchor omitted entirely
      }
      h.diff_entry(entry, ctx, { view = "vsplit", output = "stat" })
      vim.wait(5000, function()
        return #calls >= 2
      end, 5)

      eq(#calls, 2, "no anchor: resolved exactly two sides")
      -- nvim rewrites the path when it stores a buffer name (macOS resolves
      -- `/var` to `/private/var`, Windows keeps an 8.3 `RUNNER~1` segment), so
      -- the root is taken from the name the buffer actually carries: it is the
      -- buffer's own name minus the file's path below the root.
      local rel = right_file:sub(#right_root + 2)
      local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
      ok(bufname:sub(-#rel) == rel, "no anchor: the buffer name still ends in the file's own path")
      local buf_root = bufname:sub(1, #bufname - #rel - 1)
      for _, cmd in ipairs(calls) do
        eq(cmd[3], buf_root, "no anchor: falls back to source_bufnr's own name, as before")
      end
    end

    vim.system = saved_system
    vim.fn.executable = saved_executable
    package.loaded["diff.core.git"] = nil
    package.loaded["diff.core.history"] = nil
  end

  -- M.run -- the [path] positional survives a path containing "=" ------------
  -- The bug this guards: a blanket "%a+=[^%s]+" gsub matches that shape
  -- anywhere in raw_args, not just a whole key=value token -- "config=prod.lua"
  -- disappeared entirely (path fell back to the current buffer) and
  -- "src/a=b.lua" was truncated to the directory "src/".
  do
    local saved_system = vim.system
    local saved_executable = vim.fn.executable
    local saved_notify = vim.notify

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      if name == "git" then
        return 1
      end
      return saved_executable(name)
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end

    local root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(root .. "/.git", "p")

    ---Run `:DiffHistory <abs path>` and report the pathspec (last argv
    ---element) `M.log`'s `git log` invocation actually used.
    ---@param filename string  Created directly under `root`
    ---@return string|nil
    local function captured_pathspec(filename)
      local abs = root .. "/" .. filename
      H.write_file(abs, { "x" })

      local captured = nil
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, cb)
        captured = cmd[#cmd]
        -- Empty history: M.run reports "no history" and stops right there,
        -- well before the picker -- all that matters here is the argv.
        vim.schedule(function()
          cb({ code = 0, stdout = "", stderr = "" })
        end)
        return { kill = function() end }
      end

      package.loaded["diff.core.history"] = nil
      package.loaded["diff.core.git"] = nil
      local h = require("diff.core.history")

      local done = false
      h.run(abs, {
        on_done = function()
          done = true
        end,
      })
      vim.wait(5000, function()
        return done
      end, 5)

      return captured
    end

    eq(
      captured_pathspec("config=prod.lua"),
      "config=prod.lua",
      "a bare path shaped like key=value is not swallowed (falls back to the current buffer)"
    )
    eq(
      captured_pathspec("src/a=b.lua"),
      "src/a=b.lua",
      "a path with '=' past its first component is not truncated into a directory"
    )
    eq(
      captured_pathspec("plain/path.lua"),
      "plain/path.lua",
      "an ordinary path is unaffected by the fix"
    )

    vim.notify = saved_notify
    vim.system = saved_system
    vim.fn.executable = saved_executable
    package.loaded["diff.core.history"] = nil
    package.loaded["diff.core.git"] = nil
  end

  -- M.run -- on_done fires exactly once even when the picker answers twice --
  -- (see TESTS/on_done_spec.lua's identical scenario for core.run itself --
  -- core/init.lua's `reporters()` is the pattern this guard is meant to
  -- match). Before the fix, M.run's own unguarded `fail` and the raw
  -- `run_opts.on_done` handed straight into `M.diff_entry` -> `core.execute`
  -- (which wraps *that* in its own, separate guard) were two independent
  -- "fired" flags: a cancel from the first callback plus a real choice from
  -- the second produced one `fail` and one `done` -- two calls.
  do
    local saved_system = vim.system
    local saved_executable = vim.fn.executable
    local saved_notify = vim.notify
    local config = require("diff.config")

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      if name == "git" then
        return 1
      end
      return saved_executable(name)
    end

    local root = H.tmpdir():gsub("/$", "")
    vim.fn.mkdir(root .. "/.git", "p")
    local file = root .. "/double.lua"
    H.write_file(file, { "x" })

    local RS, FS = "\1", "\31"
    local log_stdout = RS
      .. table.concat({ "aaa111", "aaa", "2026-04-01", "Ada", "one commit" }, FS)
      .. "\nM double.lua\n"

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _, cb)
      local is_log = vim.tbl_contains(cmd, "log")
      vim.schedule(function()
        if is_log then
          cb({ code = 0, stdout = log_stdout, stderr = "" })
        else
          -- git show, for both sides diff_entry resolves.
          cb({ code = 0, stdout = "content\n", stderr = "" })
        end
      end)
      return { kill = function() end }
    end

    package.loaded["diff.core.history"] = nil
    package.loaded["diff.core.git"] = nil
    local h = require("diff.core.history")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_name(buf, file)

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end

    local cfg = config.get()
    local prev_select = cfg.select_fn
    cfg.select_fn = function(items, _, cb)
      cb(nil, nil) -- a cancel ...
      cb(items[1], 1) -- ... immediately followed by a real choice
    end

    local calls = 0
    -- output=stat: no window gets opened, so nothing here depends on the
    -- origin window/buffer still being current by the time it resolves.
    h.run("output=stat", {
      on_done = function()
        calls = calls + 1
      end,
    })
    vim.wait(5000, function()
      return calls >= 1
    end, 5)
    -- Give a second, buggy call (if the guard regressed) time to surface too.
    vim.wait(200, function()
      return false
    end, 5)

    cfg.select_fn = prev_select
    vim.notify = saved_notify
    vim.system = saved_system
    vim.fn.executable = saved_executable
    package.loaded["diff.core.history"] = nil
    package.loaded["diff.core.git"] = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    eq(calls, 1, "a picker answering twice still produces exactly one on_done from :DiffHistory")
  end
end

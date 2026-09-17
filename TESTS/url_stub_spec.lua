-- TESTS/url_stub_spec.lua — core.url without a real curl process.
--
-- url_spec.lua covers `is_url_spec` and two guard clauses, then does a
-- best-effort *live* round-trip. That last part is the only network access in
-- this suite and it is deliberately skipped rather than failed when offline --
-- which means everything it was meant to prove is unproven on a CI runner
-- without egress. This spec closes that: `vim.system` is replaced with a
-- double, so the argv curl would have been given, the byte limit, the timeout
-- kill, and every non-zero-exit branch are asserted deterministically and
-- without a single packet leaving the machine.

return function(H)
  local eq, ok = H.eq, H.ok

  local saved_system = vim.system
  local saved_executable = vim.fn.executable

  -- Test double over a typed surface; restored at the end of the spec.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.executable = function(name)
    if name == "curl" then
      return 1
    end
    return saved_executable(name)
  end

  ---@return table
  local function fresh_url()
    package.loaded["diff.core.url"] = nil
    return require("diff.core.url")
  end

  ---@param u string
  ---@param opts table|nil
  ---@return string[]|nil lines, string|nil err, boolean done
  local function await(u, opts, url)
    local mod = url or require("diff.core.url")
    local done, lines, err = false, nil, nil
    mod.fetch(u, "target", opts or {}, function(l, e)
      lines, err, done = l, e, true
    end)
    vim.wait(5000, function()
      return done
    end, 5)
    return lines, err, done
  end

  ---Install a `vim.system` double replying with `res`; returns an argv getter.
  ---@param res table
  ---@return fun(): string[]|nil
  local function stub_system(res)
    local captured = nil
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, _opts, cb)
      captured = cmd
      vim.schedule(function()
        cb(res)
      end)
      return { kill = function() end }
    end
    return function()
      return captured
    end
  end

  -- argv shape ---------------------------------------------------------------
  do
    local get = stub_system({ code = 0, stdout = "alpha\nbeta\n", stderr = "" })
    local url = fresh_url()
    local lines, err = await("https://example.invalid/a.txt", { max_bytes = 4321 }, url)

    local argv = get()
    ok(argv ~= nil, "fetch() spawned something")
    eq(argv[1], "curl", "argv[1] is the bare binary, never a shell string")
    eq(argv[#argv], "https://example.invalid/a.txt", "the URL is the last element, unquoted")

    local flags = {}
    for _, a in ipairs(argv) do
      flags[a] = true
    end
    ok(flags["--silent"], "--silent: curl's progress meter would corrupt stdout")
    ok(flags["--show-error"], "--show-error: keeps the reason when --silent is on")
    ok(flags["--fail"], "--fail: an HTTP error must be a non-zero exit, not a body")
    ok(flags["--location"], "--location: redirects are followed")

    -- The byte cap has to arrive as the *configured* value, not curl's own
    -- default -- an unbounded response is read entirely into memory.
    local max_idx
    for i, a in ipairs(argv) do
      if a == "--max-filesize" then
        max_idx = i
      end
    end
    ok(max_idx ~= nil, "--max-filesize is passed")
    eq(argv[max_idx + 1], "4321", "--max-filesize carries opts.max_bytes, as a string")

    eq(err, nil, "a clean exit reports no error")
    eq(table.concat(lines or {}, "|"), "alpha|beta", "stdout becomes the content lines")
  end

  -- Defaults when opts is absent or of the wrong shape ------------------------
  do
    local get = stub_system({ code = 0, stdout = "x\n", stderr = "" })
    local url = fresh_url()
    ---@diagnostic disable-next-line: param-type-mismatch
    await("https://example.invalid/b", "not a table", url)
    local argv = get()
    local max_idx
    for i, a in ipairs(argv) do
      if a == "--max-filesize" then
        max_idx = i
      end
    end
    eq(argv[max_idx + 1], tostring(10 * 1024 * 1024), "a junk opts falls back to the 10MiB default")
  end

  -- CRLF normalization -------------------------------------------------------
  -- A CRLF-served document left alone makes two identical sides differ in
  -- every single line, which renders as a plausible diff rather than a bug.
  do
    stub_system({ code = 0, stdout = "one\r\ntwo\r\n", stderr = "" })
    local url = fresh_url()
    local lines = await("https://example.invalid/crlf", {}, url)
    eq(table.concat(lines or {}, "|"), "one|two", "a CRLF response yields buffer-shaped lines")
  end

  -- Non-zero exits -----------------------------------------------------------
  do
    local url

    -- 63 is curl's own --max-filesize refusal; it gets a message naming the
    -- limit, because "exited with code 63" is unactionable.
    stub_system({ code = 63, stdout = "", stderr = "" })
    url = fresh_url()
    local _, e63 = await("https://example.invalid/big", { max_bytes = 99 }, url)
    eq(e63, "target: response exceeds max_bytes limit (99 bytes)", "code 63 names the byte limit")

    -- Anything else with stderr surfaces curl's own words, trimmed.
    stub_system({ code = 22, stdout = "", stderr = "curl: (22) The requested URL returned 404\n" })
    url = fresh_url()
    local _, e22 = await("https://example.invalid/missing", {}, url)
    eq(
      e22,
      "target: curl: (22) The requested URL returned 404",
      "an HTTP failure surfaces curl's message, trimmed"
    )

    -- Anything else without stderr still names the code.
    stub_system({ code = 7, stdout = "", stderr = "" })
    url = fresh_url()
    local _, e7 = await("https://example.invalid/down", {}, url)
    eq(e7, "target: curl exited with code 7", "a silent failure still names the exit code")
  end

  -- Timeout ------------------------------------------------------------------
  -- The timeout is enforced by a libuv timer that kills the process, not by
  -- curl's own --max-time (which can still hang on a stalled TLS handshake),
  -- so the double here never calls back at all: only the timer can end it.
  do
    local killed = false
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function()
      return {
        kill = function()
          killed = true
        end,
      }
    end
    local url = fresh_url()
    local lines, err, done = await("https://example.invalid/slow", { timeout_ms = 80 }, url)
    ok(done, "a process that never replies still ends, via the timer")
    eq(lines, nil, "a timed-out fetch produces no lines")
    ok(err and err:find("timed out after 80ms", 1, true) ~= nil, "the timeout names its own budget")
    ok(
      err and err:find("https://example.invalid/slow", 1, true) ~= nil,
      "and the URL it gave up on"
    )
    ok(killed, "the timer kills the process rather than leaving it running")
  end

  -- A late reply after a timeout must not call back twice --------------------
  -- Both the timer and curl's own callback route through `finish`; only the
  -- first may reach the caller, or a diff gets rendered from a response that
  -- was already reported as failed.
  do
    local late_cb
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(_cmd, _opts, cb)
      late_cb = cb
      return { kill = function() end }
    end
    local url = fresh_url()
    local calls, last_err = 0, nil
    url.fetch("https://example.invalid/late", "target", { timeout_ms = 60 }, function(_, e)
      calls = calls + 1
      last_err = e
    end)
    vim.wait(2000, function()
      return calls > 0
    end, 5)
    eq(calls, 1, "the timeout reported exactly once")
    ok(last_err and last_err:find("timed out", 1, true) ~= nil, "and it reported the timeout")

    -- Now let the killed process report its failure, as it really would.
    late_cb({ code = 2, stdout = "", stderr = "curl: (2) killed" })
    vim.wait(200, function()
      return calls > 1
    end, 5)
    eq(calls, 1, "curl's own late callback is swallowed, not delivered as a second result")
  end

  -- The spawn itself throwing is reported, never propagated -------------------
  do
    -- Test double over a typed surface; restored at the end of the spec.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function()
      error("ENOENT")
    end
    local url = fresh_url()
    local lines, err, done = await("https://example.invalid/x", {}, url)
    ok(done, "a throwing spawn still calls back")
    eq(lines, nil, "a throwing spawn produces no lines")
    ok(
      err and err:find("failed to start curl", 1, true) ~= nil,
      "a throwing spawn is reported as our own error"
    )
  end

  vim.system = saved_system
  vim.fn.executable = saved_executable
  package.loaded["diff.core.url"] = nil
end

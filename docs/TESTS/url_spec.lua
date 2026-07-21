-- docs/TESTS/url_spec.lua — core.url: is_url_spec + fetch() guard clauses and
-- a best-effort live round-trip. See docs/url-sources.md for the feature.

return function(H)
  local eq, ok = H.eq, H.ok
  local url = require("diff.core.url")

  -- is_url_spec ------------------------------------------------------------
  ok(url.is_url_spec("https://example.com/a.txt"), "https:// is a url spec")
  ok(url.is_url_spec("http://example.com/a.txt"), "http:// is a url spec")
  ok(not url.is_url_spec("clipboard"), "clipboard is not a url spec")
  ok(not url.is_url_spec("git:HEAD"), "git:HEAD is not a url spec")
  ok(not url.is_url_spec("path/to/file"), "plain path is not a url spec")
  ok(not url.is_url_spec(42), "number is not a url spec")
  ok(not url.is_url_spec(nil), "nil is not a url spec")

  -- fetch(): synchronously await the async callback via vim.wait, since the
  -- runner itself is not async-aware.
  local function await_fetch(u, opts)
    local done, lines, err = false, nil, nil
    url.fetch(u, "target", opts or {}, function(l, e)
      lines, err, done = l, e, true
    end)
    vim.wait(15000, function() return done end, 20)
    return lines, err, done
  end

  -- guard: vim.system missing ----------------------------------------------
  local saved_system = vim.system
  vim.system = nil
  local lines1, err1, done1 = await_fetch("https://example.com")
  vim.system = saved_system
  ok(done1, "fetch() calls back synchronously when vim.system is missing")
  eq(lines1, nil, "vim.system missing: no lines")
  ok(err1 and err1:find("vim.system", 1, true) ~= nil, "vim.system missing: error mentions vim.system")

  -- guard: curl not on PATH -------------------------------------------------
  local saved_executable = vim.fn.executable
  vim.fn.executable = function(name)
    if name == "curl" then return 0 end
    return saved_executable(name)
  end
  local lines2, err2, done2 = await_fetch("https://example.com")
  vim.fn.executable = saved_executable
  ok(done2, "fetch() calls back synchronously when curl is missing")
  eq(lines2, nil, "curl missing: no lines")
  ok(err2 and err2:find("curl", 1, true) ~= nil, "curl missing: error mentions curl")

  -- live round-trip: best-effort, skipped (not failed) without network -----
  if type(vim.system) ~= "function" or vim.fn.executable("curl") ~= 1 then
    return
  end
  local live_url = "https://raw.githubusercontent.com/StefanBartl/diff.nvim/main/README.md"
  local lines3, err3, done3 = await_fetch(live_url, { timeout_ms = 8000 })
  if not done3 or (not lines3 and err3 and err3:lower():find("timed out", 1, true)) then
    -- No network reachable within the timeout in this environment — skip the
    -- live assertions rather than fail CI on an offline runner.
    return
  end
  ok(err3 == nil, "live fetch has no error: " .. tostring(err3))
  ok(type(lines3) == "table" and #lines3 > 0, "live fetch returns content lines")

  -- a 404 must surface a curl error, not a crash
  local lines4, err4 = await_fetch(live_url .. "-does-not-exist-xyz", { timeout_ms = 8000 })
  eq(lines4, nil, "live 404 resolves to nil")
  ok(err4 ~= nil, "live 404 reports an error")
end

---@module 'diff.core.url'
--- Resolve a `http(s)://…` specifier to fetched content lines, async.
---
--- Fetches a URL via `curl` (a direct argv exec through `vim.system`, never a
--- shell string) without blocking the editor, and enforces a timeout via a
--- libuv timer since curl itself can hang past its own `--max-time` under
--- some network conditions (e.g. a stalled TLS handshake). Never notifies —
--- callers get `(lines, err)` through a callback, exactly like the synchronous
--- resolvers in `core/resolve.lua` and `core/git.lua`, just delivered later.
---
--- See docs/url-sources.md for requirements, configuration, and usage
--- examples (this is the one specifier type that talks to the network, so
--- it gets a dedicated write-up).

local M = {}

---Is `spec` an http(s):// URL specifier?
---@param spec any
---@return boolean
function M.is_url_spec(spec)
  if type(spec) ~= "string" then
    return false
  end
  return spec:sub(1, 7) == "http://" or spec:sub(1, 8) == "https://"
end

---Fetch a URL asynchronously and hand the result to `callback(lines, err)`.
---`callback` always runs on the main loop (scheduled), so it's safe to call
---notify/API functions from it directly.
---@param url string
---@param label string  "target"|"source" — used only in error text
---@param opts { timeout_ms: integer, max_bytes: integer }
---@param callback fun(lines: string[]|nil, err: string|nil): nil
---@return nil
function M.fetch(url, label, opts, callback)
  local timeout_ms = (type(opts) == "table" and type(opts.timeout_ms) == "number")
      and opts.timeout_ms
    or 10000
  -- A download needs both a timeout (above) and a byte limit, so an
  -- unexpectedly huge response can't be read entirely into memory. `curl`
  -- enforces this itself via `--max-filesize` (checked against a known
  -- Content-Length upfront where the server sends one -- true for every
  -- documented use case: raw.githubusercontent.com, gists, JSON APIs).
  local max_bytes = (type(opts) == "table" and type(opts.max_bytes) == "number")
      and opts.max_bytes
    or (10 * 1024 * 1024)

  if type(vim.system) ~= "function" then
    callback(nil, label .. ": URL sources require Neovim 0.10+ (vim.system)")
    return
  end
  if vim.fn.executable("curl") ~= 1 then
    -- The reason and this host's install command come out of
    -- docs/install.json. `lines`, not `check`: this module never notifies
    -- (see the header) -- the error travels back through `callback`, and a
    -- notification next to it would say the same thing twice.
    local ok_rt, rt = pcall(require, "lib.nvim.deps.require_tool")
    local why = ok_rt and table.concat(rt.lines("diff.nvim", "curl"), " ")
      or "curl executable not found on PATH"
    callback(nil, label .. ": " .. why)
    return
  end

  local done = false
  local timer = vim.uv.new_timer()
  local proc ---@type vim.SystemObj|nil

  ---@param lines string[]|nil
  ---@param err string|nil
  local function finish(lines, err)
    if done then
      return
    end
    done = true
    if timer then
      pcall(function()
        timer:stop()
      end)
      pcall(function()
        timer:close()
      end)
      timer = nil
    end
    vim.schedule(function()
      callback(lines, err)
    end)
  end

  local ok, result_or_err = pcall(
    vim.system,
    {
      "curl",
      "--silent",
      "--show-error",
      "--fail",
      "--location",
      "--max-filesize",
      tostring(max_bytes),
      url,
    },
    { text = true },
    function(res)
      if res.code ~= 0 then
        local msg
        if res.code == 63 then
          msg = string.format("response exceeds max_bytes limit (%d bytes)", max_bytes)
        elseif type(res.stderr) == "string" and res.stderr ~= "" then
          msg = vim.trim(res.stderr)
        else
          msg = "curl exited with code " .. tostring(res.code)
        end
        finish(nil, label .. ": " .. msg)
        return
      end
      local out = res.stdout or ""
      local lines = vim.split(out, "\n", { plain = true })
      -- curl output ends with a trailing newline for text content; drop the
      -- empty final element so line counts match readfile()/buffer content.
      if lines[#lines] == "" then
        lines[#lines] = nil
      end
      finish(lines, nil)
    end
  )
  if not ok then
    finish(nil, label .. ": failed to start curl: " .. tostring(result_or_err))
    return
  end
  proc = result_or_err

  if timer then
    timer:start(timeout_ms, 0, function()
      if proc then
        pcall(function()
          proc:kill("sigkill")
        end)
      end
      finish(nil, string.format("%s: timed out after %dms fetching %s", label, timeout_ms, url))
    end)
  end
end

return M

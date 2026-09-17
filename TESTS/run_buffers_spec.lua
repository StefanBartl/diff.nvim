-- TESTS/run_buffers_spec.lua — core.run_buffers, core.init's buffer-number
-- prompt, and the pickers.nvim adapter's own behaviour.
--
-- pick_specifier_spec/prompt_file_spec cover two of the four interactive
-- paths. `run_buffers` (the :DiffBuffers picker) had none at all, `prompt_buffer`
-- had none, and pickers_bridge_spec only asserted that `resolve()` degrades to
-- nil -- never what the function it returns actually does once pickers.nvim
-- *is* there. All three are covered here against doubles; no picker backend is
-- required.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")

  ---Re-require core so it re-binds whatever doubles are currently in
  ---`package.loaded` -- the module resolves `ui.kit` lazily, but re-requiring
  ---also drops any `M.execute` stub a previous case installed.
  ---@return table
  local function fresh_core()
    package.loaded["diff.core"] = nil
    return require("diff.core")
  end

  ---Capture notifications produced while `fn` runs.
  ---@param fn fun(): nil
  ---@return string[]
  local function notices(fn)
    local out = {}
    local saved = vim.notify
    -- Test double over a typed surface; restored before returning.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      out[#out + 1] = tostring(msg)
    end
    local call_ok, err = pcall(fn)
    vim.notify = saved
    ok(call_ok, "call did not throw: " .. tostring(err))
    return out
  end

  ---Wipe every listed buffer except the current one, so the candidate list is
  ---built from exactly what a case set up and nothing a previous spec left.
  ---@return integer current
  local function isolate_buffers()
    vim.cmd("silent! only")
    vim.cmd("silent! enew")
    local cur = vim.api.nvim_get_current_buf()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= cur then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
    return cur
  end

  ---A listed, loaded, named buffer -- the shape run_buffers collects.
  ---@param name string
  ---@param lines string[]
  ---@return integer
  local function listed_buffer(name, lines)
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(b, name)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].buftype = "nofile"
    vim.bo[b].bufhidden = "hide"
    return b
  end

  -- No other listed buffers -> a warning and a failed completion -------------
  do
    isolate_buffers()
    config.setup({ use_pickers_nvim = false })
    local core = fresh_core()
    local seen, calls = nil, 0
    local msgs = notices(function()
      core.run_buffers("", {
        on_done = function(result, err)
          calls = calls + 1
          seen = { result = result, err = err }
        end,
      })
    end)
    eq(calls, 1, "on_done fires even when there is nothing to pick")
    eq(seen.result, nil, "and reports no result")
    eq(seen.err, "No other listed buffers to diff against", "with the reason as its error")
    ok(
      table.concat(msgs, "\n"):find("No other listed buffers", 1, true) ~= nil,
      "and the user is told too"
    )
  end

  -- Unlisted / unloaded buffers are not candidates ---------------------------
  do
    isolate_buffers()
    -- scratch (nofile, unlisted) and an unloaded buffer must both be skipped
    vim.api.nvim_create_buf(false, true)
    local unloaded = vim.fn.bufadd(H.tmpdir() .. "never-loaded.txt")
    ok(vim.api.nvim_buf_is_loaded(unloaded) == false, "the bufadd'ed buffer really is unloaded")

    config.setup({ use_pickers_nvim = false })
    local core = fresh_core()
    local seen
    notices(function()
      core.run_buffers("", {
        on_done = function(_result, err)
          seen = err
        end,
      })
    end)
    eq(seen, "No other listed buffers to diff against", "unlisted and unloaded buffers are skipped")
  end

  -- The candidate list, and the choice reaching execute ----------------------
  do
    local cur = isolate_buffers()
    local other = listed_buffer(H.tmpdir() .. "other.txt", { "other side" })
    local unnamed = vim.api.nvim_create_buf(true, false)
    vim.bo[unnamed].buftype = "nofile"

    local items_seen, prompt_seen
    config.setup({
      use_pickers_nvim = false,
      select_fn = function(items, opts, on_choice)
        items_seen, prompt_seen = items, opts and opts.prompt
        for i, label in ipairs(items) do
          if label:find("other.txt", 1, true) then
            on_choice(label, i)
            return
          end
        end
        on_choice(nil, nil)
      end,
    })

    local core = fresh_core()
    local executed
    -- Test double over a typed surface; core is re-required per case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core.execute = function(opts, ctx)
      executed = { opts = opts, ctx = ctx }
    end
    notices(function()
      core.run_buffers("view=split output=stat")
    end)

    ok(items_seen ~= nil, "the picker was shown")
    eq(prompt_seen, "Diff against buffer:", "with its own prompt")
    eq(#items_seen, 2, "both other listed buffers are offered")
    local joined = table.concat(items_seen, "\n")
    ok(joined:find("other.txt", 1, true) ~= nil, "a named buffer is labelled by its path")
    ok(joined:find("[No Name]", 1, true) ~= nil, "an unnamed buffer is labelled [No Name]")
    eq(
      joined:find(tostring(cur) .. "  ") ~= nil and true or false,
      false,
      "the buffer you are diffing *from* is never offered as its own target"
    )

    ok(executed ~= nil, "the choice reaches execute")
    eq(executed.opts.target, tostring(other), "the chosen label maps back to its buffer number")
    eq(executed.opts.source, "current", "the source of :DiffBuffers is always the current buffer")
    eq(executed.opts.view, "split", "view= from the raw args is honoured")
    eq(executed.opts.output, "stat", "output= from the raw args is honoured")
    eq(executed.ctx.source_bufnr, cur, "the context carries the buffer it was invoked from")
    eq(executed.ctx.range, nil, ":DiffBuffers never carries a range")
  end

  -- Cancelling the picker is a reported non-result ---------------------------
  do
    isolate_buffers()
    listed_buffer(H.tmpdir() .. "cancel-me.txt", { "x" })
    config.setup({
      use_pickers_nvim = false,
      select_fn = function(_items, _opts, on_choice)
        on_choice(nil, nil)
      end,
    })
    local core = fresh_core()
    local seen, calls = nil, 0
    local msgs = notices(function()
      core.run_buffers("", {
        on_done = function(result, err)
          calls = calls + 1
          seen = { result = result, err = err }
        end,
      })
    end)
    eq(calls, 1, "a cancelled picker still completes the callback")
    eq(seen.err, "Diff cancelled", "cancelling is reported as 'Diff cancelled'")
    ok(table.concat(msgs, "\n"):find("Diff cancelled", 1, true) ~= nil, "and said out loud")
  end

  -- An invalid view=/output= is refused before the picker is even built ------
  do
    isolate_buffers()
    listed_buffer(H.tmpdir() .. "never-picked.txt", { "x" })
    local shown = false
    config.setup({
      use_pickers_nvim = false,
      select_fn = function()
        shown = true
      end,
    })
    local core = fresh_core()

    for _, args in ipairs({ "view=nonsense", "output=nonsense" }) do
      local seen, calls = nil, 0
      local msgs = notices(function()
        core.run_buffers(args, {
          on_done = function(result, err)
            calls = calls + 1
            seen = { result = result, err = err }
          end,
        })
      end)
      eq(calls, 1, args .. ": on_done fires once")
      eq(seen.err, "invalid view= or output=", args .. ": reported as an invalid combination")
      local joined = table.concat(msgs, "\n")
      ok(joined:find("nonsense", 1, true) ~= nil, args .. ": the rejected value is quoted back")
      ok(joined:find("valid:", 1, true) ~= nil, args .. ": and the accepted list is offered")
    end
    eq(shown, false, "an invalid view=/output= never opens the picker")
  end

  -- The kit.select fallback, when nothing else is configured ------------------
  -- run_buffers deliberately uses kit.select (a dynamic-length list) rather
  -- than the kit.confirm button row pick_specifier uses, and translates
  -- kit's separate on_cancel back into the vim.ui.select-shaped nil call.
  do
    isolate_buffers()
    local other = listed_buffer(H.tmpdir() .. "kit-pick.txt", { "x" })
    config.setup({ select_fn = nil, use_pickers_nvim = false })

    local opts_seen
    package.loaded["ui.kit"] = {
      select = function(opts)
        opts_seen = opts
        opts.on_select(opts.items[1], 1)
      end,
    }
    local core = fresh_core()
    local executed
    -- Test double over a typed surface; core is re-required per case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core.execute = function(opts)
      executed = opts
    end
    notices(function()
      core.run_buffers("")
    end)
    ok(opts_seen ~= nil, "kit.select is the fallback picker")
    eq(opts_seen.respect_override, true, "and still defers to a real vim.ui.select override")
    eq(opts_seen.title, "Diff against buffer:", "the prompt is passed as kit.select's title")
    eq(executed and executed.target, tostring(other), "its choice reaches execute")

    -- kit.select reports a cancel through on_cancel, not by calling
    -- on_select(nil) -- if that translation is dropped, the caller never
    -- hears that the diff was abandoned.
    package.loaded["ui.kit"] = {
      select = function(opts)
        opts.on_cancel()
      end,
    }
    local core2 = fresh_core()
    local seen, calls = nil, 0
    notices(function()
      core2.run_buffers("", {
        on_done = function(_r, e)
          calls = calls + 1
          seen = e
        end,
      })
    end)
    eq(calls, 1, "kit.select's on_cancel still completes the callback")
    eq(seen, "Diff cancelled", "and is translated into the same 'Diff cancelled'")
    package.loaded["ui.kit"] = nil
  end

  -- prompt_buffer: the "buffer number …" choice ------------------------------
  do
    isolate_buffers()
    local target_buf = listed_buffer(H.tmpdir() .. "by-number.txt", { "x" })

    ---Choose the "buffer number …" entry, whatever its index is.
    ---@param items string[]
    ---@param _opts table
    ---@param on_choice fun(item: string|nil, idx: integer|nil)
    local function pick_buffer_entry(items, _opts, on_choice)
      for i, label in ipairs(items) do
        if label:find("buffer number", 1, true) then
          on_choice(label, i)
          return
        end
      end
      on_choice(nil, nil)
    end

    -- a valid number is normalized and used
    config.setup({ select_fn = pick_buffer_entry, use_pickers_nvim = false })
    package.loaded["ui.kit"] = {
      input = function(opts)
        opts.on_submit("  " .. tostring(target_buf) .. "  ")
      end,
    }
    local core = fresh_core()
    local executed
    -- Test double over a typed surface; core is re-required per case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core.execute = function(opts)
      executed = opts
    end
    notices(function()
      core.run("target=ask")
    end)
    eq(
      executed and executed.target,
      tostring(target_buf),
      "a typed buffer number is normalized through tonumber before use"
    )

    -- a non-numeric answer warns and cancels
    package.loaded["ui.kit"] = {
      input = function(opts)
        opts.on_submit("not-a-number")
      end,
    }
    local core2 = fresh_core()
    local ran = false
    -- Test double over a typed surface; core is re-required per case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core2.execute = function()
      ran = true
    end
    local msgs = notices(function()
      core2.run("target=ask")
    end)
    eq(ran, false, "a non-numeric buffer answer aborts the diff")
    local joined = table.concat(msgs, "\n")
    ok(joined:find("Invalid buffer number", 1, true) ~= nil, "and says why")
    ok(joined:find("Diff cancelled", 1, true) ~= nil, "and reports the run as cancelled")

    -- cancelling the number prompt aborts too
    package.loaded["ui.kit"] = {
      input = function(opts)
        opts.on_cancel()
      end,
    }
    local core3 = fresh_core()
    local ran3 = false
    -- Test double over a typed surface; core is re-required per case.
    ---@diagnostic disable-next-line: duplicate-set-field
    core3.execute = function()
      ran3 = true
    end
    notices(function()
      core3.run("target=ask")
    end)
    eq(ran3, false, "cancelling the buffer-number prompt aborts the diff")

    package.loaded["ui.kit"] = nil
  end

  -- The pickers.nvim adapter itself ------------------------------------------
  -- pickers_bridge_spec asserts only that `resolve()` degrades to nil without
  -- pickers.nvim. Here a fake `pickers.engines` is put in `package.loaded`
  -- *before* the bridge runs, so the function it returns can be driven.
  do
    local bridge = require("diff.core.pickers_bridge")
    local saved_engines = package.loaded["pickers.engines"]

    local captured
    local engine = {
      pick_item = function(opts)
        captured = opts
        return true
      end,
    }
    package.loaded["pickers.engines"] = {
      load = function()
        return engine
      end,
    }

    local select_fn = bridge.resolve()
    ok(type(select_fn) == "function", "resolve() adapts a usable engine into a select_fn")

    -- the chosen item is mapped back to its 1-based index
    local got
    select_fn({ "alpha", "beta", "gamma" }, { prompt = "Pick:" }, function(item, idx)
      got = { item = item, idx = idx }
    end)
    eq(captured.prompt, "Pick:", "the caller's prompt is forwarded")
    eq(#captured.items, 3, "and so are the items")
    captured.on_select("beta")
    eq(got.item, "beta", "the chosen item comes back")
    eq(got.idx, 2, "mapped back to its index, which is what the caller dispatches on")

    -- an item the list does not contain still comes back, without an index
    got = nil
    select_fn({ "a" }, {}, function(item, idx)
      got = { item = item, idx = idx }
    end)
    captured.on_select("not in the list")
    eq(got.item, "not in the list", "an unknown item is still handed back")
    eq(got.idx, nil, "but with no index, so the caller treats it as a cancel")

    -- an explicit nil is a cancel
    got = nil
    select_fn({ "a" }, {}, function(item, idx)
      got = { item = item, idx = idx }
    end)
    captured.on_select(nil)
    eq(got.item, nil, "a nil selection is a cancel")
    eq(got.idx, nil, "with no index")

    -- a missing prompt gets a default rather than nil
    select_fn({ "a" }, nil, function() end)
    eq(captured.prompt, "Select:", "a missing prompt falls back to a default")

    -- an engine whose pick_item throws falls back to vim.ui.select
    package.loaded["pickers.engines"] = {
      load = function()
        return {
          pick_item = function()
            error("engine exploded")
          end,
        }
      end,
    }
    local throwing = bridge.resolve()
    local saved_select = vim.ui.select
    local fell_back = false
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function()
      fell_back = true
    end
    local call_ok = pcall(throwing, { "a" }, {}, function() end)
    vim.ui.select = saved_select
    ok(call_ok, "a throwing engine does not propagate")
    ok(fell_back, "it falls back to vim.ui.select instead")

    -- an engine without pick_item, and a load() that throws, both resolve to nil
    package.loaded["pickers.engines"] = {
      load = function()
        return {}
      end,
    }
    eq(bridge.resolve(), nil, "an engine without pick_item resolves to nil")
    package.loaded["pickers.engines"] = {
      load = function()
        error("no engine installed")
      end,
    }
    eq(bridge.resolve(), nil, "a load() that throws resolves to nil")
    package.loaded["pickers.engines"] = { load = "not a function" }
    eq(bridge.resolve(), nil, "a module without a callable load resolves to nil")

    package.loaded["pickers.engines"] = saved_engines
  end

  isolate_buffers()
  config.setup({ select_fn = nil, use_pickers_nvim = true })
  package.loaded["diff.core"] = nil
  require("diff.core.scratch").cleanup_all()
end

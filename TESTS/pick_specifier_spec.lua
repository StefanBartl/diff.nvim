-- TESTS/pick_specifier_spec.lua — core.init's pick_specifier: the
-- default fallback (no configured select_fn, pickers.nvim unavailable/opted
-- out) now renders via lib.nvim.ui.kit.confirm's button row instead of
-- vim.ui.select, since pick_specifier's choice lists are always ≤4 long. An
-- explicit select_fn must still win — pick_specifier shares that pluggable
-- resolution with run_buffers (dynamic-length buffer list, untouched here).

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")

  local function fresh_core()
    package.loaded["diff.core"] = nil
    return require("diff.core")
  end

  -- Default fallback: no select_fn, pickers.nvim opted out -> kit.confirm.
  do
    config.setup({ select_fn = nil, use_pickers_nvim = false })

    local captured
    package.loaded["lib.nvim.ui.kit.confirm"] = {
      open = function(opts)
        captured = opts
        opts.on_answer(opts.choices[1]) -- pick the first button ("clipboard")
      end,
    }

    local diff_core = fresh_core()
    local executed
    diff_core.execute = function(opts)
      executed = opts
    end

    diff_core.run("target=ask source=current")

    ok(captured ~= nil, "default fallback opens lib.nvim.ui.kit.confirm")
    eq(
      captured.choices[1],
      "clipboard",
      "target choices start with 'clipboard' (no 'current buffer' for target)"
    )
    ok(
      executed ~= nil and executed.target == "clipboard",
      "the chosen answer reaches M.execute as target"
    )

    package.loaded["lib.nvim.ui.kit.confirm"] = nil
  end

  -- An explicit select_fn still wins over the kit.confirm default.
  do
    local custom_called = false
    config.setup({
      select_fn = function(items, _opts, on_choice)
        custom_called = true
        on_choice(items[1], 1)
      end,
      use_pickers_nvim = false,
    })

    local diff_core = fresh_core()
    local executed
    diff_core.execute = function(opts)
      executed = opts
    end

    diff_core.run("target=ask source=current")

    ok(custom_called, "configured select_fn is used instead of the kit.confirm default")
    ok(executed ~= nil, "custom select_fn's choice still reaches M.execute")
  end

  config.setup({ select_fn = nil, use_pickers_nvim = true })
  package.loaded["diff.core"] = nil
end

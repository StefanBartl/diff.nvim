-- TESTS/health_spec.lua — :checkhealth diff.
--
-- The health provider had no tests: nothing checked that it reports the right
-- verdict for a given environment, and nothing checked that it survives the
-- environments it exists to describe. It is driven here against a recorded
-- `vim.health`, with each probe it consults faked one at a time -- so the
-- report is asserted for a full machine *and* for a bare one, without needing
-- either.

return function(H)
  local eq, ok = H.eq, H.ok

  local COMPOSER = "lib.nvim.bindings.usercmd.composer"

  ---Run health.check() against a recording `vim.health`, returning every call
  ---as "<level>: <message>" plus a joined blob for substring checks.
  ---@return { calls: string[], text: string, ok: boolean, err: any }
  local function record()
    local calls = {}
    local saved = vim.health
    -- Test double over a typed surface; restored before returning.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.health = setmetatable({}, {
      __index = function(_, level)
        return function(msg)
          calls[#calls + 1] = level .. ": " .. tostring(msg)
        end
      end,
    })
    local call_ok, err = pcall(require("diff.health").check)
    vim.health = saved
    return { calls = calls, text = table.concat(calls, "\n"), ok = call_ok, err = err }
  end

  -- A fully-equipped machine --------------------------------------------------
  do
    local saved_loaded = vim.g.loaded_diff
    vim.g.loaded_diff = 1
    local r = record()
    vim.g.loaded_diff = saved_loaded

    ok(r.ok, "check() runs to completion: " .. tostring(r.err))
    eq(r.calls[1], "start: diff", "the report opens its own section first")
    ok(r.text:find("Neovim >= 0.9", 1, true) ~= nil, "the Neovim version is reported")
    ok(r.text:find("lib.nvim detected", 1, true) ~= nil, "lib.nvim is reported as present")
    ok(
      r.text:find("vim.text.diff is available", 1, true) ~= nil
        or r.text:find("vim.diff is available", 1, true) ~= nil,
      "the diff primitive is reported under whichever name this Neovim has"
    )
    ok(r.text:find("vim.ui.select is available", 1, true) ~= nil, "vim.ui.select is reported")
    ok(
      r.text:find("plugin loaded (vim.g.loaded_diff = 1)", 1, true) ~= nil,
      "a set loaded guard is reported as loaded"
    )
    ok(
      r.text:find("declared tools (lib.nvim.deps)", 1, true) ~= nil,
      "the declared external tools get their own section"
    )
    -- The composer's own route report is the last thing it does.
    ok(r.text:find("Diff", 1, true) ~= nil, "the command layer is asked to report too")
  end

  -- vim.g.loaded_diff unset ---------------------------------------------------
  do
    local saved_loaded = vim.g.loaded_diff
    vim.g.loaded_diff = nil
    local r = record()
    vim.g.loaded_diff = saved_loaded
    ok(
      r.text:find("plugin guard not set", 1, true) ~= nil,
      "an unset guard is reported as 'not set up yet', with the call to make"
    )
    ok(r.text:find("require('diff').setup()", 1, true) ~= nil, "and names that call")
  end

  -- No diff primitive at all --------------------------------------------------
  do
    local saved_text, saved_diff = vim.text, vim.diff
    -- Emptied rather than set to nil: `vim` lazy-loads its submodules through
    -- an __index metamethod, so clearing `vim.text` would simply re-require it
    -- on the next read and the branch would never be reached.
    -- Test doubles over typed surfaces; restored right after the case.
    ---@diagnostic disable-next-line: assign-type-mismatch
    vim.text = {}
    ---@diagnostic disable-next-line: assign-type-mismatch
    vim.diff = false
    local r = record()
    vim.text, vim.diff = saved_text, saved_diff
    ok(r.ok, "check() survives a Neovim with no diff primitive")
    ok(
      r.text:find("error: no diff primitive", 1, true) ~= nil,
      "a missing diff primitive is an error, not a warning -- most outputs stop working"
    )
  end

  -- No vim.ui.select ----------------------------------------------------------
  do
    local saved_select = vim.ui.select
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: assign-type-mismatch
    vim.ui.select = nil
    local r = record()
    vim.ui.select = saved_select
    ok(
      r.text:find("vim.ui.select unavailable", 1, true) ~= nil,
      "a missing vim.ui.select is a warning about the interactive picker"
    )
  end

  -- No clipboard provider -----------------------------------------------------
  do
    local saved_has = vim.fn.has
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.has = function(what)
      if what == "clipboard" then
        return 0
      end
      return saved_has(what)
    end
    local r = record()
    vim.fn.has = saved_has
    ok(
      r.text:find("no clipboard provider", 1, true) ~= nil,
      "a missing clipboard provider is reported against the clipboard source/output"
    )
  end

  -- Neovim older than 0.9 -----------------------------------------------------
  do
    local saved_has = vim.fn.has
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.has = function(what)
      if what == "nvim-0.9" then
        return 0
      end
      return saved_has(what)
    end
    local r = record()
    vim.fn.has = saved_has
    ok(r.text:find("Neovim 0.9+ recommended", 1, true) ~= nil, "an old Neovim is reported")
  end

  -- git / curl missing from PATH ----------------------------------------------
  do
    local saved_exe = vim.fn.executable
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      if name == "git" or name == "curl" then
        return 0
      end
      return saved_exe(name)
    end
    local r = record()
    vim.fn.executable = saved_exe
    ok(
      r.text:find("git executable not on PATH", 1, true) ~= nil,
      "a missing git is reported against git:<rev>"
    )
    ok(
      r.text:find("curl executable not on PATH", 1, true) ~= nil,
      "a missing curl is reported against http(s)://"
    )
  end

  -- No vim.system (Neovim < 0.10) ----------------------------------------------
  -- Both the git and the curl checks have to fall to their "no vim.system"
  -- arm rather than blaming a binary that is right there on PATH.
  do
    local saved_system = vim.system
    -- Test double over a typed surface; restored right after the case.
    ---@diagnostic disable-next-line: assign-type-mismatch
    vim.system = nil
    local r = record()
    vim.system = saved_system
    local n = select(2, r.text:gsub("vim%.system missing", ""))
    eq(n, 2, "both the git and the curl check blame vim.system, not the binaries")
    eq(
      r.text:find("git executable not on PATH", 1, true),
      nil,
      "and neither of them blames a binary that is actually installed"
    )
  end

  -- pickers.nvim present ------------------------------------------------------
  do
    local saved_engines = package.loaded["pickers.engines"]
    package.loaded["pickers.engines"] = {
      load = function()
        return {
          pick_item = function() end,
        }
      end,
    }
    local r = record()
    package.loaded["pickers.engines"] = saved_engines
    ok(
      r.text:find("pickers.nvim detected", 1, true) ~= nil,
      "an installed pickers.nvim is reported as the picker backend"
    )
  end

  do
    local saved_engines = package.loaded["pickers.engines"]
    package.loaded["pickers.engines"] = nil
    local saved_preload = package.preload["pickers.engines"]
    package.preload["pickers.engines"] = function()
      error("pickers.nvim is not installed")
    end
    local r = record()
    package.preload["pickers.engines"] = saved_preload
    package.loaded["pickers.engines"] = saved_engines
    ok(
      r.text:find("pickers.nvim not detected", 1, true) ~= nil,
      "an absent pickers.nvim falls back to ui.kit, reported as an ok not a warning"
    )
  end

  -- setup() options: clean vs. rejected (ERR-50, ERR-22) ----------------------
  do
    local config = require("diff.config")
    config.setup({})
    local clean = record()
    ok(
      clean.text:find("No unknown or invalid setup() options", 1, true) ~= nil,
      "a clean setup() reports nothing to fix"
    )

    config.setup({ features = { diff_orgin = false }, diff = { algorithm = "bogus" } })
    local dirty = record()
    ok(
      dirty.text:find("warn: unknown option 'features.diff_orgin'", 1, true) ~= nil,
      "an unknown key from the last setup() call is surfaced as a warning"
    )
    ok(
      dirty.text:find("warn: option 'diff.algorithm' must be", 1, true) ~= nil,
      "an invalid value from the last setup() call is surfaced as a warning"
    )

    -- Leave config clean for whatever spec runs after this one.
    config.setup({})
  end

  -- Regression: lib.nvim missing -----------------------------------------
  -- `check()` has a dedicated branch for "lib.nvim not found", reports it as
  -- an error with an install hint, and used to end unconditionally with
  -- `require(COMPOSER).checkhealth("Diff")`. When lib.nvim really was absent,
  -- that require threw, so `:checkhealth diff` aborted with a stack trace
  -- partway through and the user never saw the very diagnosis the branch above
  -- was written to give them -- the one environment the check exists for was
  -- the one it could not survive. (`lib.nvim.deps.health` two lines earlier
  -- was already pcall'd for exactly this reason; now the last line is too.)
  do
    local saved_loaded = package.loaded[COMPOSER]
    local saved_preload = package.preload[COMPOSER]
    package.loaded[COMPOSER] = nil
    package.preload[COMPOSER] = function()
      error("module '" .. COMPOSER .. "' not found")
    end

    local r = record()

    package.preload[COMPOSER] = saved_preload
    package.loaded[COMPOSER] = saved_loaded

    ok(
      r.text:find("lib.nvim not found", 1, true) ~= nil,
      "the missing dependency is correctly diagnosed..."
    )
    ok(r.ok, "...and check() runs to completion instead of throwing on the same missing module")

    -- Make sure the sabotage really was undone.
    ok(pcall(require, COMPOSER), "the composer is requirable again afterwards")
  end

  require("diff.core.scratch").cleanup_all()
end

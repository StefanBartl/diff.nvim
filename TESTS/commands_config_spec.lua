-- TESTS/commands_config_spec.lua -- `commands` (the user-command names) is validated like
-- every other setup() leaf (ERR-22, ERR-50).
--
-- It used to be an unchecked leaf. A scalar for the whole group replaced the default name table
-- in the deep merge, config.setup() reported no issue, and bindings.register() then raised while
-- indexing it -- after diff/init.lua had latched `_setup_done`, so the plugin stayed without
-- commands and every later setup() was a no-op. A single name nvim refuses (lowercase first
-- letter, a dash, a space, an empty string, a non-string) raised the same way, from
-- nvim_create_user_command / composer.verb.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")
  local bindings = require("diff.bindings")

  ---@type table<string, string>
  local DEFAULT_NAMES = {
    diff = "Diff",
    diff_clear = "DiffClear",
    diff_buffers = "DiffBuffers",
    diff_orig = "DiffOrig",
    diff_history = "DiffHistory",
    diff_exit = "DiffExit",
    diff_profile = "DiffProfile",
  }
  local KEYS = vim.tbl_keys(DEFAULT_NAMES)
  table.sort(KEYS)

  -- The `gh` peek is not what this spec is about, and a second register() would only warn about it.
  local QUIET = { gitsigns_peek = false }

  ---@param name string
  ---@return boolean
  local function has(name)
    return vim.api.nvim_get_commands({})[name] ~= nil
  end

  ---Delete every command name this spec can have registered, so each case starts clean.
  local function clear()
    for _, name in pairs(DEFAULT_NAMES) do
      pcall(vim.api.nvim_del_user_command, name)
    end
    pcall(vim.api.nvim_del_user_command, "MyDiff")
  end

  ---@return string
  local function issue_text()
    return table.concat(config.issues(), "\n")
  end

  -- A scalar for the whole group is dropped with an issue, the default names apply -----------
  for _, bad in ipairs({ 1, 0, true, false, "x", function() end, vim.NIL }) do
    local label = vim.inspect(bad)
    local opts = { commands = bad, features = QUIET }
    local setup_ok, cfg = pcall(config.setup, opts)
    ok(setup_ok, "setup({ commands = " .. label .. " }) does not raise: " .. tostring(cfg))
    if setup_ok then
      for _, key in ipairs(KEYS) do
        eq(cfg.commands[key], DEFAULT_NAMES[key], "commands = " .. label .. " leaves " .. key)
      end
      ok(
        issue_text():find("option 'commands' must be a table", 1, true) ~= nil,
        "commands = " .. label .. " is recorded as an issue, got: " .. issue_text()
      )
      clear()
      local reg_ok, reg_err = pcall(bindings.register, cfg)
      ok(reg_ok, "bindings.register survives commands = " .. label .. ": " .. tostring(reg_err))
      ok(has("Diff"), "commands = " .. label .. " still registers :Diff")
    end
    eq(opts.commands, bad, "the caller's table is left as given")
  end

  -- One bad name degrades on its own: the default for it, the sibling rename still applies -------
  local BAD_NAMES = {
    1,
    0,
    true,
    false,
    "",
    "lower",
    "bad name",
    "Foo_bar",
    "Foo-bar",
    "1Foo",
    "\195\137a", -- a capital outside ASCII is not one nvim accepts
    {},
    function() end,
  }
  for _, bad in ipairs(BAD_NAMES) do
    local label = vim.inspect(bad)
    local setup_ok, cfg =
      pcall(config.setup, { commands = { diff = "MyDiff", diff_clear = bad }, features = QUIET })
    ok(
      setup_ok,
      "setup with commands.diff_clear = " .. label .. " does not raise: " .. tostring(cfg)
    )
    if setup_ok then
      eq(cfg.commands.diff, "MyDiff", "the valid sibling rename applies next to " .. label)
      eq(cfg.commands.diff_clear, "DiffClear", label .. " falls back to the default name")
      eq(#config.issues(), 1, label .. " is exactly one issue")
      ok(
        issue_text():find("option 'commands.diff_clear' must be a command name", 1, true) ~= nil,
        label .. " is reported under its own key, got: " .. issue_text()
      )
      clear()
      local reg_ok, reg_err = pcall(bindings.register, cfg)
      ok(
        reg_ok,
        "bindings.register survives commands.diff_clear = " .. label .. ": " .. tostring(reg_err)
      )
      ok(has("MyDiff"), "the valid rename is registered next to " .. label)
      ok(has("DiffClear"), label .. " registers the default name instead")
      eq(has("Diff"), false, "the renamed command is not also registered under its default")
    end
  end

  -- Every one of the seven names is checked, not just the first ------------------------------
  for _, key in ipairs(KEYS) do
    local cfg = config.setup({ commands = { [key] = "lower" }, features = QUIET })
    eq(cfg.commands[key], DEFAULT_NAMES[key], key .. " falls back to its default")
    ok(
      issue_text():find("option 'commands." .. key .. "' must be a command name", 1, true) ~= nil,
      key .. " is reported, got: " .. issue_text()
    )
  end

  -- A valid name is not an issue --------------------------------------------------------------
  local good = config.setup({
    commands = { diff = "Diff2", diff_clear = "X", diff_orig = "MyDiffOrig" },
    features = QUIET,
  })
  eq(good.commands.diff, "Diff2", "a name with a digit is accepted")
  eq(good.commands.diff_clear, "X", "a one-letter name is accepted")
  eq(good.commands.diff_orig, "MyDiffOrig", "a mixed-case name is accepted")
  eq(#config.issues(), 0, "valid names are not an issue")

  -- A typo in a key is reported like any other unknown option (ERR-50) --------------------------
  local typo = config.setup({ commands = { diff_histroy = "Hist" }, features = QUIET })
  eq(typo.commands.diff_history, "DiffHistory", "the real name keeps its default")
  eq(typo.commands.diff_histroy, nil, "the typo does not reach the merged config")
  ok(
    issue_text():find(
      "unknown option 'commands.diff_histroy' (did you mean 'commands.diff_history'?)",
      1,
      true
    ) ~= nil,
    "the typo is reported with the nearest name, got: " .. issue_text()
  )

  -- The reported failure, end to end: setup() completes and the commands exist ------------------
  -- A fresh copy of `diff`, because its once-only latch cannot be undone and public_api_spec
  -- exercises the real one.
  do
    local original = package.loaded["diff"]
    package.loaded["diff"] = nil
    local fresh = require("diff")
    local saved_first_run = vim.g.lib_nvim_deps_disable_first_run
    local saved_loaded = vim.g.loaded_diff
    vim.g.lib_nvim_deps_disable_first_run = true
    vim.g.loaded_diff = nil
    clear()
    local setup_ok, err = pcall(fresh.setup, { commands = 1, features = QUIET })
    vim.g.lib_nvim_deps_disable_first_run = saved_first_run
    package.loaded["diff"] = original
    ok(setup_ok, "require('diff').setup({ commands = 1 }) does not raise: " .. tostring(err))
    eq(vim.g.loaded_diff, 1, "setup() ran to its end")
    ok(has("Diff"), "and registered the commands")
    vim.g.loaded_diff = saved_loaded
  end

  -- reset for subsequent specs
  clear()
  config.setup({})
end

-- TESTS/keymaps_off_spec.lua -- `keymaps = false` (REL-20, conformance K3):
-- the switch binds no keymap at all, not the shortcuts, not the `gh` hunk
-- peek, not the exit key. `{ enable = false }` is the same thing spelled out.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")
  local bindings = require("diff.bindings")

  ---@return string[] lhs of every global normal-mode map with a "[diff]" or shortcut desc
  local function diff_maps()
    local found = {}
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if
        m.lhs == "gh"
        or m.lhs == "<Esc><Esc>"
        or m.lhs == " dd"
        or (m.desc or ""):find("Diff", 1, true)
      then
        found[#found + 1] = m.lhs
      end
    end
    return found
  end

  for _, off in ipairs({ false, { enable = false, diff = " dd" } }) do
    local cfg = config.setup({
      keymaps = off,
      exit = { scope = "global" },
    })
    eq(cfg.keymaps.enable, false, "normalized to { enable = false }")
    bindings.register(cfg)
    local left = diff_maps()
    ok(#left == 0, "nothing is bound with keymaps off, found: " .. table.concat(left, ", "))
  end

  -- true is the short form of the default group, the shortcuts stay opt-in
  local cfg_on = config.setup({ keymaps = true })
  ok(cfg_on.keymaps.enable ~= false, "keymaps = true keeps the keymaps on")
  eq(cfg_on.exit.scope, "buffer", "and leaves the exit scope alone")

  -- A value that is neither a table nor a boolean is dropped with an issue and
  -- the default group applies (ERR-22). It used to replace the default table in
  -- the deep merge, so `keymaps = 1` raised from setup() and, through
  -- diff/init.lua's already-latched `_setup_done`, left the plugin without
  -- commands for the rest of the session.
  for _, bad in ipairs({ 1, 0, "x", function() end, vim.NIL }) do
    local label = vim.inspect(bad)
    local opts = { keymaps = bad }
    local setup_ok, cfg_bad = pcall(config.setup, opts)
    ok(setup_ok, "setup({ keymaps = " .. label .. " }) does not raise: " .. tostring(cfg_bad))
    if setup_ok then
      eq(type(cfg_bad.keymaps), "table", "keymaps = " .. label .. " leaves the default group")
      ok(cfg_bad.keymaps.enable ~= false, "keymaps = " .. label .. " does not switch keymaps off")
      eq(cfg_bad.exit.scope, "buffer", "keymaps = " .. label .. " leaves the exit scope alone")
      local issues = table.concat(config.issues(), "\n")
      ok(
        issues:find("option 'keymaps' must be a table or boolean", 1, true) ~= nil,
        "keymaps = " .. label .. " is recorded as an issue, got: " .. issues
      )
      local reg_ok, reg_err = pcall(bindings.register, cfg_bad)
      ok(reg_ok, "bindings.register survives keymaps = " .. label .. ": " .. tostring(reg_err))
      -- the default group is on, so the gh peek is bound; free it for the next round
      pcall(vim.keymap.del, "n", "gh")
    end
    eq(opts.keymaps, bad, "the caller's table is left as given")
  end

  -- bindings.register() is also robust against a config it did not get from
  -- setup(): a non-table `keymaps` is not an "off" switch and is never indexed.
  local hand_built = vim.deepcopy(config.setup({}))
  hand_built.keymaps = 1
  local hb_ok, hb_err = pcall(bindings.register, hand_built)
  ok(hb_ok, "bindings.register tolerates a non-table keymaps: " .. tostring(hb_err))
  pcall(vim.keymap.del, "n", "gh")

  -- reset for subsequent specs
  config.setup({})
end

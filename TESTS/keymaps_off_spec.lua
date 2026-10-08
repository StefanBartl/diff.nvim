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
end

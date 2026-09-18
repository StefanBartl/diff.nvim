-- Test code: when something here comes back nil, this file must crash and
-- name it -- the nil guards LuaLS asks for below would hide that failure.
---@diagnostic disable: need-check-nil
-- TESTS/gitsigns_peek_spec.lua — the `gh` gitsigns hunk-preview keymap
-- (moved from my.nvim, cross-feature report finding F2).
--
-- gitsigns.nvim is not on this suite's runtimepath (see run.lua), so
-- invoking the installed callback naturally exercises the "gitsigns absent"
-- branch here -- exactly the environment most of this fleet's headless test
-- runs are, and the case the module degrades to a notification for rather
-- than erroring.

return function(H)
  local eq, ok = H.eq, H.ok
  local gitsigns_peek = require("diff.features.gitsigns_peek")

  pcall(vim.keymap.del, "n", "gh")

  ---@return table|nil
  local function gh_map()
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if m.lhs == "gh" then
        return m
      end
    end
    return nil
  end

  ok(gh_map() == nil, "no 'gh' map before register()")
  gitsigns_peek.register()
  local m = gh_map()
  ok(m ~= nil, "register() installs the 'gh' map")
  eq(m.desc, "[diff] Git hunk peek")
  eq(type(m.callback), "function", "bound to a Lua callback, not an expr string")

  -- gitsigns is not on the runtimepath in this suite, so calling the
  -- callback must degrade to a notification instead of erroring.
  local notified
  local notify = require("diff.util.notify")
  local saved_info = notify.info
  ---@diagnostic disable-next-line: duplicate-set-field
  notify.info = function(msg)
    notified = msg
  end

  local call_ok = pcall(m.callback)
  notify.info = saved_info

  ok(call_ok, "calling the callback without gitsigns does not error")
  ok(notified ~= nil and notified:find("gitsigns", 1, true) ~= nil, "and notifies instead")

  pcall(vim.keymap.del, "n", "gh")
end

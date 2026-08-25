-- TESTS/keymaps_spec.lua — bindings.keymaps: multi-key exit binding and
-- the optional cfg.keymaps shortcuts.
--
-- Both are about what does and does not get bound, so everything here reads
-- the real keymap tables back out of Neovim rather than trusting the call.

return function(H)
  local eq, ok = H.eq, H.ok
  local keymaps = require("diff.bindings.keymaps")

  ---Buffer-local normal-mode lhs set, normalized the way Neovim reports them
  ---(`<C-x>` comes back as `<C-X>`).
  ---@param buf integer
  ---@return table<string, boolean>
  local function buf_lhs(buf)
    local set = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      set[m.lhs:upper()] = true
    end
    return set
  end

  ---@param lhs string
  ---@return table|nil
  local function global_map(lhs)
    local m = vim.fn.maparg(lhs, "n", false, true)
    return (type(m) == "table" and next(m) ~= nil) and m or nil
  end

  -- ------------------------------------------------- exit key as a list
  --
  -- `<Esc><Esc>` collides with other plugins often enough that replacing it
  -- was the only option before; a list lets a second key coexist with it.

  local buf = H.scratch()
  local cfg_list = {
    key = { "<C-x><C-x>", "<C-y><C-y>" },
    scope = "buffer",
    native_diffthis = false,
  }

  keymaps.attach_buffer(cfg_list, buf)
  local after_attach = buf_lhs(buf)
  ok(after_attach["<C-X><C-X>"], "attach_buffer binds the first key in the list")
  ok(after_attach["<C-Y><C-Y>"], "attach_buffer binds the second key too")

  -- detach must mirror attach: it used to delete `cfg.key` directly, which
  -- removed nothing at all once the key could be a list.
  keymaps.detach_buffer(cfg_list, buf)
  local after_detach = buf_lhs(buf)
  ok(not after_detach["<C-X><C-X>"], "detach_buffer removes the first key")
  ok(not after_detach["<C-Y><C-Y>"], "detach_buffer removes the second key")

  -- A plain string still works exactly as before.
  local cfg_str = { key = "<C-x><C-x>", scope = "buffer", native_diffthis = false }
  keymaps.attach_buffer(cfg_str, buf)
  ok(buf_lhs(buf)["<C-X><C-X>"], "a plain string key still binds")
  keymaps.detach_buffer(cfg_str, buf)
  ok(not buf_lhs(buf)["<C-X><C-X>"], "and still unbinds")

  -- Degenerate values must not raise or bind anything.
  keymaps.attach_buffer({ key = "", scope = "buffer" }, buf)
  keymaps.attach_buffer({ key = {}, scope = "buffer" }, buf)
  keymaps.attach_buffer({ key = { "", 42 }, scope = "buffer" }, buf)
  eq(vim.tbl_count(buf_lhs(buf)), 0, "empty / non-string keys bind nothing")

  -- scope gating is unchanged.
  keymaps.attach_buffer({ key = "<C-x><C-x>", scope = "global" }, buf)
  eq(vim.tbl_count(buf_lhs(buf)), 0, "attach_buffer is a no-op when scope is global")

  -- ------------------------------------------------------- shortcuts
  --
  -- All opt-in: diff.nvim imposes no mappings, so an empty `keymaps` table
  -- must leave the keyspace untouched.

  local base = {
    features = { diff = true, diff_origin = true, diff_exit = true },
    commands = {
      diff = "Diff",
      diff_clear = "DiffClear",
      diff_buffers = "DiffBuffers",
      diff_orig = "DiffOrig",
      diff_exit = "DiffExit",
    },
  }

  local function with(keymaps_tbl)
    return vim.tbl_extend("force", vim.deepcopy(base), { keymaps = keymaps_tbl })
  end

  keymaps.register_shortcuts(with({}))
  eq(global_map("<C-x>1"), nil, "an empty keymaps table binds nothing")

  keymaps.register_shortcuts(with({
    diff = "<C-x>1",
    diff_head = "<C-x>2",
    diff_merge = "<C-x>3",
    diff_buffers = "<C-x>4",
    diff_orig = "<C-x>5",
    diff_clear = "<C-x>6",
  }))

  eq(global_map("<C-x>1").rhs, "<Cmd>Diff<CR>", "diff → the bare command")
  eq(
    global_map("<C-x>2").rhs,
    "<Cmd>Diff target=git:HEAD<CR>",
    "diff_head → :Diff target=git:HEAD"
  )
  eq(
    global_map("<C-x>3").rhs,
    "<Cmd>Diff base=git:HEAD target=git:MERGE_HEAD<CR>",
    "diff_merge → the merge-conflict invocation"
  )
  eq(global_map("<C-x>4").rhs, "<Cmd>DiffBuffers<CR>", "diff_buffers → :DiffBuffers")
  eq(global_map("<C-x>5").rhs, "<Cmd>DiffOrig<CR>", "diff_orig → :DiffOrig")
  eq(global_map("<C-x>6").rhs, "<Cmd>DiffClear<CR>", "diff_clear → :DiffClear")
  ok(
    global_map("<C-x>2").desc:find("[diff]", 1, true) == 1,
    "shortcuts carry a [diff]-prefixed desc for which-key"
  )

  for i = 1, 6 do
    pcall(vim.keymap.del, "n", "<C-x>" .. i)
  end

  -- Command names are configurable, so the rhs must follow them rather than
  -- hardcoding "Diff".
  local renamed = with({ diff_head = "<C-x>7" })
  renamed.commands.diff = "MyDiff"
  keymaps.register_shortcuts(renamed)
  eq(
    global_map("<C-x>7").rhs,
    "<Cmd>MyDiff target=git:HEAD<CR>",
    "the rhs follows a renamed command"
  )
  pcall(vim.keymap.del, "n", "<C-x>7")

  -- A shortcut for a command the user switched off must be refused, not
  -- bound to something that errors on the first press.
  local no_orig = with({ diff_orig = "<C-x>8" })
  no_orig.features.diff_origin = false
  keymaps.register_shortcuts(no_orig)
  eq(global_map("<C-x>8"), nil, "a shortcut whose feature is off is not registered")

  local no_diff = with({ diff_head = "<C-x>9" })
  no_diff.features.diff = false
  keymaps.register_shortcuts(no_diff)
  eq(global_map("<C-x>9"), nil, "features.diff = false disables the :Diff shortcuts too")

  -- Unknown names are ignored rather than bound.
  keymaps.register_shortcuts(with({ nonsense = "<C-x>0" }))
  eq(global_map("<C-x>0"), nil, "an unknown shortcut name binds nothing")

  -- A false/empty lhs is how you leave one unset.
  keymaps.register_shortcuts(with({ diff_head = false, diff_clear = "" }))
  eq(global_map("<C-x>0"), nil, "false and empty lhs values bind nothing")
end

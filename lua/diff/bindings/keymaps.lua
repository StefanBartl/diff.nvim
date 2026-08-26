---@module 'diff.bindings.keymaps'
--- Keymap registration for diff.nvim.
---
--- Registration (this module) is kept separate from the logic it triggers
--- (`features/exit.lua`, `core`) so every `vim.keymap.set` call lives in one
--- place, alongside `bindings/usrcmds.lua` and `bindings/autocmds.lua`. Every
--- keymap carries a `desc`, so which-key.nvim (if installed) picks them up
--- with no further wiring — diff.nvim has no leader-prefixed group to label.
---
--- **diff.nvim still imposes no mappings.** `cfg.keymaps` is empty by
--- default and every entry is opt-in; the exit key is the only thing bound
--- without being asked for, and even that is buffer-local by default. The
--- shortcuts exist because `:Diff target=git:HEAD` and the merge-conflict
--- invocation are long enough to be worth a key *if you want one* — not
--- because the plugin thinks you should have one.

local validate = require("diff.util.validate")
local map = require("lib.nvim.bindings.keymap")

local M = {}

---Normalize `exit.key` to a list.
---
--- It accepts a list as well as a single string so a second key can coexist
--- with the first: `<Esc><Esc>` is a fine default but collides with other
--- plugins often enough that "use something else instead" was the only
--- option, when "also accept `<C-c>`" is what people actually want.
---@internal
---@param key string|string[]|nil
---@return string[]
local function exit_keys(key)
  if type(key) == "string" then
    return key ~= "" and { key } or {}
  end
  if type(key) ~= "table" then
    return {}
  end

  local out = {}
  for _, k in ipairs(key) do
    if type(k) == "string" and k ~= "" then
      out[#out + 1] = k
    end
  end
  return out
end

---Bind the exit key(s) globally. No-op unless scope == "global".
---@param cfg DiffNvim.Config.Exit
---@return nil
function M.register_global(cfg)
  if cfg.scope ~= "global" then
    return
  end
  for _, key in ipairs(exit_keys(cfg.key)) do
    map("n", key, require("diff.features.exit").exit, {
      silent = true,
    }, "[diff] Exit diff mode when active")
  end
end

---Bind the exit key(s) buffer-locally on a buffer diff.nvim just diffed.
---No-op unless scope == "buffer".
---@param cfg DiffNvim.Config.Exit
---@param bufnr integer
---@return nil
function M.attach_buffer(cfg, bufnr)
  if cfg.scope ~= "buffer" then
    return
  end
  if not validate.buf_valid(bufnr) then
    return
  end
  for _, key in ipairs(exit_keys(cfg.key)) do
    map("n", key, require("diff.features.exit").exit, {
      buffer = bufnr,
      silent = true,
    }, "[diff] Exit diff mode")
  end
end

---Remove the exit key(s) from a buffer again.
---
--- The mirror of `attach_buffer`, and it exists so the key list is normalized
--- in exactly one place: `native_diffthis` used to delete `cfg.key` directly,
--- which silently stopped removing anything the moment `key` could be a list.
---@param cfg DiffNvim.Config.Exit
---@param bufnr integer
---@return nil
function M.detach_buffer(cfg, bufnr)
  if not validate.buf_valid(bufnr) then
    return
  end
  for _, key in ipairs(exit_keys(cfg.key)) do
    pcall(vim.keymap.del, "n", key, { buffer = bufnr })
  end
end

---The optional shortcuts, and what each one runs.
---
--- `command` names the `cfg.commands.*` field rather than a literal command,
--- because those names are user-configurable; `feature` names the
--- `cfg.features.*` gate that decides whether the command exists at all. A
--- shortcut for a command the user switched off is refused rather than bound
--- to something that would error on the first press.
---@internal
---@type table<string, { command: string, feature: string, args: string, label: string }>
local SHORTCUTS = {
  diff = {
    command = "diff",
    feature = "diff",
    args = "",
    label = "Diff (pick source and target)",
  },
  diff_head = {
    command = "diff",
    feature = "diff",
    args = "target=git:HEAD",
    label = "Diff against HEAD",
  },
  diff_merge = {
    command = "diff",
    feature = "diff",
    args = "base=git:HEAD target=git:MERGE_HEAD",
    label = "Diff the merge conflict",
  },
  diff_buffers = {
    command = "diff_buffers",
    feature = "diff",
    args = "",
    label = "Diff against another buffer",
  },
  diff_orig = {
    command = "diff_orig",
    feature = "diff_origin",
    args = "",
    label = "Diff against the version on disk",
  },
  diff_clear = {
    command = "diff_clear",
    feature = "diff",
    args = "",
    label = "Close all diff windows",
  },
}

---Register the optional `cfg.keymaps` shortcuts. Nothing is bound unless the
---user set an lhs for it.
---@param cfg DiffNvim.Config
---@return nil
---Declare and bind the `:Diff` shortcut keymaps.
---
--- Declared through `lib.nvim.bindings.keymap`'s registry, with the two
--- rejection reasons kept *here* rather than delegated to it: an unknown name
--- is answered with the full accepted list, and a name whose feature is
--- switched off says so by name. Both are worth more than the registry's
--- nearest-match guess, and a rejected name never reaches it, so nothing
--- warns twice.
---
--- Every shortcut stays *declared* even when its feature is off -- it is
--- forced to `false` instead of being left out -- because :checkhealth and the
--- generated docs ask what exists, and "off because features.X is off" is a
--- different answer from "there is no such shortcut".
---@param cfg Diff.Config
---@return Lib.Keymap.Registered[]|nil
function M.register_shortcuts(cfg)
  local keymaps = cfg.keymaps
  if type(keymaps) ~= "table" then
    return
  end

  local notify = require("lib.nvim.notify").create("[diff.keymaps]")
  local keymap = require("lib.nvim.bindings.keymap")

  -- Sorted, so the "accepted" list in a warning reads the same every time
  -- rather than in whatever order `pairs` happens to walk the table.
  local accepted = vim.tbl_keys(SHORTCUTS)
  table.sort(accepted)

  ---@type table<string, Lib.Keymap.Action>
  local actions = {}
  for name, spec in pairs(SHORTCUTS) do
    local cmd = cfg.commands[spec.command]
    if spec.args ~= "" then
      cmd = cmd .. " " .. spec.args
    end
    actions[name] = {
      rhs = ("<Cmd>%s<CR>"):format(cmd),
      desc = spec.label,
      opts = { silent = true },
    }
  end

  ---@type table<string, string|false>
  local user = {}
  for name, lhs in pairs(keymaps) do
    if lhs and lhs ~= "" then
      local spec = SHORTCUTS[name]
      if not spec then
        notify.warn(
          ("Unknown keymaps.%s — ignoring. Accepted: %s"):format(
            tostring(name),
            table.concat(accepted, ", ")
          )
        )
      elseif not cfg.features[spec.feature] then
        notify.warn(
          ("keymaps.%s needs features.%s, which is off — not registering"):format(
            name,
            spec.feature
          )
        )
        user[name] = false
      else
        user[name] = lhs
      end
    end
  end

  return keymap.register("diff", { order = accepted, actions = actions }, user)
end

return M

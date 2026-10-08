---@module 'diff.bindings'
--- Orchestrates diff.nvim's bindings: usrcmds, keymaps, autocmds.
---
--- Single entry point `require("diff.init")` calls into. Registers the
--- user commands, wires the exit keymap (global scope only — buffer scope is
--- attached per-diff by `features/exit.lua`), registers the optional
--- `cfg.keymaps` shortcuts (none by default), and installs the VimLeavePre
--- cleanup autocmd.

local M = {}

---Wire up every binding for the resolved config.
---@param cfg DiffNvim.Config
---@return nil
function M.register(cfg)
  require("diff.bindings.usrcmds").register(cfg)

  if cfg.features.diff_exit then
    require("diff.features.exit").setup(cfg.exit)
    require("diff.features.native_diffthis").register(cfg.exit)
  end

  -- Same shape test as register_shortcuts(): a non-table `keymaps` is not an
  -- "off" switch, so it never turns the gh peek off (and never gets indexed).
  local keymaps_off = type(cfg.keymaps) == "table" and cfg.keymaps.enable == false
  if cfg.features.gitsigns_peek and not keymaps_off then
    require("diff.features.gitsigns_peek").register()
  end

  if cfg.features.diffopt_profile and cfg.diff.diffopt_profile ~= nil then
    -- pcall'd: an uncaught error here would abort the two registration
    -- steps still below (keymap shortcuts, the VimLeavePre cleanup
    -- autocmd), and setup() would raise for what is only a mistyped value.
    -- An unknown profile name is exactly the kind of typo a user's own
    -- config can hand this at startup.
    local ok, err = pcall(require("diff.features.diffopt_profile").set, cfg.diff.diffopt_profile)
    if not ok then
      require("diff.util.notify").error(
        ("diff.diffopt_profile = %q: %s"):format(cfg.diff.diffopt_profile, tostring(err))
      )
    end
  end

  -- After usrcmds: the shortcuts point at commands that must already exist,
  -- and they read the same features/commands config to decide what is even
  -- registrable.
  require("diff.bindings.keymaps").register_shortcuts(cfg)

  require("diff.bindings.autocmds").register()
end

return M

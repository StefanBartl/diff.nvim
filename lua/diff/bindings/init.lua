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

  if cfg.features.gitsigns_peek then
    require("diff.features.gitsigns_peek").register()
  end

  if cfg.features.diffopt_profile and cfg.diff.diffopt_profile ~= nil then
    -- pcall'd: M.setup() flips its own _setup_done guard to true BEFORE
    -- calling this function (see diff/init.lua), so an uncaught error here
    -- would not just abort the two registration steps still below
    -- (keymap shortcuts, the VimLeavePre cleanup autocmd) -- it would make
    -- every LATER require("diff").setup() call a silent no-op for the rest
    -- of the session too, with no way to recover short of restarting
    -- Neovim. An unknown profile name is exactly the kind of typo a user's
    -- own config can hand this at startup.
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

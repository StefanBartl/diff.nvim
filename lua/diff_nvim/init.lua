---@module 'diff_nvim'
---@brief Public entry point for diff.nvim.
---@description
--- Bootstraps the diff subsystem: merges config, registers commands, sets up the
--- exit feature and the VimLeavePre cleanup autocmd. Idempotent — the first call
--- wins and later calls are no-ops.
---
--- Two equivalent entry points are provided:
---   require("diff_nvim").setup({ ... })   -- conventional plugin style
---   require("diff_nvim").enable({ ... })   -- alias matching the old custom.diff API
---
--- Example: >lua
---   require("diff_nvim").setup({
---     features = { diff = true, diff_origin = true, diff_exit = true },
---   })
--- <

local M = {}

---@type string  Augroup name for cleanup autocmds
local AUGROUP = "diff_nvim_cleanup"

---@type boolean
local _setup_done = false

---Configure and activate diff.nvim.
---@param user_opts? DiffNvim.Config|table
---@return nil
function M.setup(user_opts)
  if _setup_done then
    return
  end
  _setup_done = true

  local config = require("diff_nvim.config")
  local cfg = config.setup(user_opts)

  require("diff_nvim.commands").register(cfg)

  if cfg.features.diff_exit then
    require("diff_nvim.features.exit").setup(cfg.exit)
  end

  local aug = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function()
      require("diff_nvim.core.scratch").wipe_on_exit()
    end,
    desc = "[diff] Wipe scratch buffers on exit",
  })

  vim.g.loaded_diff_nvim = 1
end

---Alias for setup() — mirrors the legacy `require("custom.diff").enable(opts)`
---signature so existing call-sites keep working.
---@param user_opts? DiffNvim.Config|table
---@return nil
function M.enable(user_opts)
  M.setup(user_opts)
end

-- Public API ------------------------------------------------------------------

---Run a diff. `raw_args` uses the same `key=value` grammar as `:Diff`.
---@param raw_args? string
---@return nil
function M.run(raw_args)
  require("diff_nvim.core").run(raw_args or "")
end

---Close all diff windows and disable diffmode.
---@return nil
function M.clear()
  require("diff_nvim.core").clear()
end

---Diff the current buffer against its on-disk saved version.
---@return nil
function M.diff_origin()
  require("diff_nvim.features.origin").run()
end

---Leave diff mode from anywhere.
---@return nil
function M.exit()
  require("diff_nvim.features.exit").exit()
end

return M

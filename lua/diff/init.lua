---@module 'diff'
---@brief Public entry point for diff.nvim.
---@description
--- Bootstraps the diff subsystem: merges config, registers commands, sets up the
--- exit feature and the VimLeavePre cleanup autocmd. Idempotent — the first call
--- wins and later calls are no-ops.
---
--- Two equivalent entry points are provided:
---   require("diff").setup({ ... })   -- conventional plugin style
---   require("diff").enable({ ... })   -- alias matching the old custom.diff API
---
--- Example: >lua
---   require("diff").setup({
---     features = { diff = true, diff_origin = true, diff_exit = true },
---   })
--- <

local M = {}

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

  local config = require("diff.config")
  local cfg = config.setup(user_opts)

  require("diff.bindings").register(cfg)

  vim.g.loaded_diff = 1
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
  require("diff.core").run(raw_args or "")
end

---Close all diff windows and disable diffmode.
---@return nil
function M.clear()
  require("diff.core").clear()
end

---Diff the current buffer against another open buffer chosen from a picker.
---`raw_args` accepts the same `view=`/`output=` grammar as `:Diff`.
---@param raw_args? string
---@return nil
function M.diff_buffers(raw_args)
  require("diff.core").run_buffers(raw_args or "")
end

---Diff the current buffer against its on-disk saved version.
---@return nil
function M.diff_origin()
  require("diff.features.origin").run()
end

---Leave diff mode from anywhere.
---@return nil
function M.exit()
  require("diff.features.exit").exit()
end

---Statusline component: a short string describing whether a diff.nvim diff is
---active, or `""` when none is. Drop it into any statusline, e.g.
--- >lua
---   vim.o.statusline = "%f %{v:lua.require'diff'.status()}"
--- <
---@param opts? { prefix?: string }  `prefix` defaults to "diff:"
---@return string
function M.status(opts)
  local n = require("diff.core.scratch").active_count()
  if n == 0 then
    return ""
  end
  local prefix = (type(opts) == "table" and type(opts.prefix) == "string") and opts.prefix or "diff:"
  return prefix .. n
end

return M

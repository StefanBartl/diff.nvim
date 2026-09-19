---@module 'diff'
--- Public entry point for diff.nvim.
---
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
---@param user_opts? DiffNvim.Opts
---@return nil
function M.setup(user_opts)
  if _setup_done then
    return
  end
  _setup_done = true

  local config = require("diff.config")
  local cfg = config.setup(user_opts)

  require("diff.bindings").register(cfg)

  -- Report the declared external tools (docs/install.json) once, ever, on
  -- the first setup after installation. pcall'd because an older lib.nvim
  -- without lib.nvim.deps must not break setup() over an informational
  -- popup; `:Lib deps show diff.nvim` stays available either way. Turn it
  -- off with `vim.g.lib_nvim_deps_disable_first_run` (or the per-plugin
  -- `vim.g.lib_nvim_deps_disabled_plugins`).
  local ok_deps, deps = pcall(require, "lib.nvim.deps")
  if ok_deps then
    deps.show_once("diff.nvim")
  end

  vim.g.loaded_diff = 1
end

---Alias for setup() — mirrors the legacy `require("custom.diff").enable(opts)`
---signature so existing call-sites keep working.
---@param user_opts? DiffNvim.Opts
---@return nil
function M.enable(user_opts)
  M.setup(user_opts)
end

-- Public API ------------------------------------------------------------------

---Run a diff. `raw_args` uses the same `key=value` grammar as `:Diff`.
---
---`opts.on_done` is called once when the diff has finished, with a
---`DiffNvim.Result` describing the buffers and windows diff.nvim created --
---or `nil` plus a reason when nothing was produced. It fires on the
---asynchronous paths too (`http(s)://`, `git:<rev>`, the interactive picker),
---which is why this is a callback and not a return value: a return value
---could only be filled in for the synchronous specifiers, and would be
---silently empty for the rest.
---
---Only what diff.nvim opened is reported -- the window `:Diff` was invoked
---from is never in `result.windows`, even when it is part of the diff. See
---docs/api.md.
--- >lua
---   require("diff").run("source=7 target=8 view=vsplit", {
---     on_done = function(result, err)
---       if not result then return end
---       for _, win in ipairs(result.windows) do
---         vim.api.nvim_win_close(win, true)
---       end
---     end,
---   })
--- <
---@param raw_args? string
---@param opts? DiffNvim.RunOpts
---@return nil
function M.run(raw_args, opts)
  require("diff.core").run(raw_args or "", nil, opts)
end

---Close all diff windows and disable diffmode.
---@return nil
function M.clear()
  require("diff.core").clear()
end

---Diff the current buffer against another open buffer chosen from a picker.
---`raw_args` accepts the same `view=`/`output=` grammar as `:Diff`;
---`opts.on_done` works exactly as it does for `M.run`.
---@param raw_args? string
---@param opts? DiffNvim.RunOpts
---@return nil
function M.diff_buffers(raw_args, opts)
  require("diff.core").run_buffers(raw_args or "", opts)
end

---Diff the current buffer against its on-disk saved version.
---@return nil
function M.diff_origin()
  require("diff.features.origin").run()
end

---List the commits that touched a file (`git log --follow`) and, once one is
---picked, diff it against its parent. `raw_args` accepts an optional leading
---path (defaults to the current buffer) plus the same `view=`/`output=`
---grammar as `:Diff`; `opts.on_done` works exactly as it does for `M.run`.
---@param raw_args? string
---@param opts? DiffNvim.RunOpts
---@return nil
function M.diff_history(raw_args, opts)
  require("diff.core.history").run(raw_args or "", opts)
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
  local prefix = (type(opts) == "table" and type(opts.prefix) == "string") and opts.prefix
    or "diff:"
  return prefix .. n
end

return M

---@module 'diff.bindings.usrcmds'
---@brief User-command registration for :Diff, built via
--- lib.nvim.usercmd.composer.
---@description
--- Registers :Diff, :DiffClear, :DiffBuffers, :DiffOrig and :DiffExit using
--- the configured command names -- five separate top-level commands (not a
--- subcommand tree; each is independently name-configurable and has its own
--- distinct grammar), each its own composer verb. :Diff/:DiffBuffers use
--- Route.kv for their bare `key=value` grammar (the case that originally
--- motivated Phase 7's kv support); dispatch bypasses composer's own bound
--- ctx.kv and calls the ORIGINAL, unmodified core.run(raw_args, range) /
--- core.run_buffers(raw_args) with ctx.raw.args (composer's untouched
--- nvim-callback opts table has the exact same .args string the old
--- nvim_create_user_command callback received) -- so the declared kv schema
--- exists purely to drive <Tab> completion; core's own key=value parsing is
--- unchanged. VALUE_LISTS are completion HINTS, not a closed set (a real
--- filename is also a valid target=/source=/base=), so they're wired as
--- KvSpec.values (soft, unenforced) rather than KvSpec.enum (which would
--- reject any value not in the list -- a real behavior regression).

local composer = require("lib.nvim.usercmd.composer")

local core = require("diff.core")

local M = {}

---@type table<string, string[]>  Static value lists per completion key
local VALUE_LISTS = {
  view   = { "vsplit", "split", "inline", "tab", "float" },
  output = { "buffer", "prompt", "file", "clipboard", "stat" },
  source = { "current", "clipboard", "ask", "git:HEAD" },
  target = { "clipboard", "ask", "git:HEAD" },
  base   = { "clipboard", "ask", "git:HEAD" },
}

---@param key string
---@return table  KvSpec
local function kv(key)
  return { key = key, type = "STRING", values = VALUE_LISTS[key] }
end

---Register all commands. Idempotent at the nvim level (re-creates cleanly).
---@param cfg DiffNvim.Config
---@return nil
function M.register(cfg)
  local names = cfg.commands

  if cfg.features.diff then
    composer.verb(names.diff, {
      desc = "Diff sources  :[range]Diff [target=…] [source=…] [base=…] [view=…] [output=…]",
      range = true,
      routes = {
        { path = {},
          kv = { kv("target"), kv("source"), kv("base"), kv("view"), kv("output") },
          run = function(ctx)
            -- ctx.range.range is 0 when no real range was given; only then
            -- are line1/line2 meaningless (both default to the cursor line).
            local range = (ctx.range.range and ctx.range.range > 0)
              and { line1 = ctx.range.line1, line2 = ctx.range.line2 } or nil
            core.run(ctx.raw.args or "", range)
          end },
      },
    })

    composer.verb(names.diff_clear, {
      desc = "Close all :Diff windows and disable diffmode",
      routes = { { path = {}, run = function() core.clear() end } },
    })

    composer.verb(names.diff_buffers, {
      desc = "Diff current buffer against another open buffer (picker)  :DiffBuffers [view=…] [output=…]",
      routes = {
        { path = {},
          kv = { kv("view"), kv("output") },
          run = function(ctx) core.run_buffers(ctx.raw.args or "") end },
      },
    })
  end

  if cfg.features.diff_origin then
    composer.verb(names.diff_orig, {
      desc = "Diff current buffer against its on-disk saved version",
      routes = { { path = {}, run = function() require("diff.features.origin").run() end } },
    })
  end

  if cfg.features.diff_exit then
    composer.verb(names.diff_exit, {
      desc = "Leave diff mode (diffoff!) from anywhere",
      routes = { { path = {}, run = function() require("diff.features.exit").exit() end } },
    })
  end
end

return M

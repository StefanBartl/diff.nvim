---@module 'diff.bindings.usrcmds'
--- User-command registration for :Diff, built via lib.nvim.bindings.usercmd.composer.
---
--- Registers :Diff, :DiffClear, :DiffBuffers, :DiffOrig and :DiffExit using
--- the configured command names -- five separate top-level commands (not a
--- subcommand tree; each is independently name-configurable and has its own
--- grammar), each its own composer verb.
---
--- :Diff/:DiffBuffers declare a `Route.kv` schema, but dispatch bypasses
--- composer's parsed `ctx.kv` and hands `core.run` / `core.run_buffers` the
--- raw `ctx.raw.args` string -- core does its own `key=value` parsing, so the
--- kv schema exists purely to drive <Tab> completion. VALUE_LISTS are
--- completion HINTS, not a closed set (a real filename is also a valid
--- target=/source=/base=), so they are wired as `KvSpec.values` (soft) rather
--- than `KvSpec.enum` (which would reject anything off the list).

local composer = require("lib.nvim.bindings.usercmd.composer")

local core = require("diff.core")
local history = require("diff.core.history")

local M = {}

---@type table<string, string[]>  Static value lists per completion key
local VALUE_LISTS = {
  view = { "vsplit", "split", "inline", "tab", "float" },
  output = { "buffer", "prompt", "file", "clipboard", "stat" },
  source = { "current", "clipboard", "ask", "git:HEAD" },
  target = { "clipboard", "ask", "git:HEAD" },
  base = { "clipboard", "ask", "git:HEAD" },
}

---@type table<string, { desc: string, enum_desc: table<string, string> }>  Help-float text per key
local KV_HELP = {
  view = {
    desc = "Window layout of the diff (output=buffer only)",
    enum_desc = {
      vsplit = "Side by side in a vertical split",
      split = "Stacked in a horizontal split",
      inline = "Unified diff in one scratch buffer",
      tab = "Side by side in a new tab",
      float = "Unified diff in a floating window",
    },
  },
  output = {
    desc = "Where the result is delivered",
    enum_desc = {
      buffer = "Interactive diff windows (see view)",
      prompt = "Unified diff in the message area",
      file = "Unified diff written to a temp file",
      clipboard = "Unified diff copied to the clipboard",
      stat = "Only a notification: +N -M, K hunks",
    },
  },
  source = {
    desc = "Left side: current buffer, file, buffer number, URL or git:<rev>",
    enum_desc = {
      current = "The buffer you are in (a range narrows it)",
      clipboard = "The system clipboard",
      ask = "Pick the source interactively",
      ["git:HEAD"] = "The file as of the last commit",
    },
  },
  target = {
    desc = "Right side: file, buffer number, URL or git:<rev>",
    enum_desc = {
      clipboard = "The system clipboard",
      ask = "Pick the target interactively",
      ["git:HEAD"] = "The file as of the last commit",
    },
  },
  base = {
    desc = "Common ancestor, turns the diff into a three-way one",
    enum_desc = {
      clipboard = "The system clipboard",
      ask = "Pick the base interactively",
      ["git:HEAD"] = "The file as of the last commit",
    },
  },
}

---@internal
---@param key string
---@return table  KvSpec
local function kv(key)
  local help = KV_HELP[key]
  return {
    key = key,
    type = "STRING",
    values = VALUE_LISTS[key],
    desc = help.desc,
    enum_desc = help.enum_desc,
  }
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
        {
          path = {},
          kv = { kv("target"), kv("source"), kv("base"), kv("view"), kv("output") },
          run = function(ctx)
            -- ctx.range.range is 0 when no real range was given; only then
            -- are line1/line2 meaningless (both default to the cursor line).
            local range = (ctx.range.range and ctx.range.range > 0)
                and { line1 = ctx.range.line1, line2 = ctx.range.line2 }
              or nil
            core.run(ctx.raw.args or "", range)
          end,
        },
      },
    })

    composer.verb(names.diff_clear, {
      desc = "Close all :Diff windows and disable diffmode",
      routes = {
        {
          path = {},
          run = function()
            core.clear()
          end,
        },
      },
    })

    composer.verb(names.diff_buffers, {
      desc = "Diff current buffer against another open buffer (picker)  :DiffBuffers [view=…] [output=…]",
      routes = {
        {
          path = {},
          kv = { kv("view"), kv("output") },
          run = function(ctx)
            core.run_buffers(ctx.raw.args or "")
          end,
        },
      },
    })
  end

  if cfg.features.diff_history then
    composer.verb(names.diff_history, {
      desc = "List commits touching a file and diff one against its parent (picker)  :DiffHistory [path] [view=…] [output=…]",
      routes = {
        {
          path = {},
          args = { { name = "path", type = "FILE", optional = true } },
          kv = { kv("view"), kv("output") },
          run = function(ctx)
            history.run(ctx.raw.args or "")
          end,
        },
      },
    })
  end

  if cfg.features.diff_origin then
    composer.verb(names.diff_orig, {
      desc = "Diff current buffer against its on-disk saved version",
      routes = {
        {
          path = {},
          run = function()
            require("diff.features.origin").run()
          end,
        },
      },
    })
  end

  if cfg.features.diff_exit then
    composer.verb(names.diff_exit, {
      desc = "Leave diff mode (diffoff!) from anywhere",
      routes = {
        {
          path = {},
          run = function()
            require("diff.features.exit").exit()
          end,
        },
      },
    })
  end

  if cfg.features.diffopt_profile then
    local diffopt_profile = require("diff.features.diffopt_profile")
    local notify = require("diff.util.notify")

    composer.verb(names.diff_profile, {
      desc = "Apply a named 'diffopt' profile  :DiffProfile {name}",
      routes = {
        {
          path = {},
          args = {
            {
              name = "profile",
              type = "STRING",
              enum = diffopt_profile.names(),
              desc = "Profile to apply; it replaces 'diffopt' wholesale",
              -- One line per profile in `diffopt_profile/profiles.lua` (what it sets, not a nickname).
              enum_desc = {
                minimal = "Histogram algorithm, whitespace ignored, linematch 60",
                context = "Patience algorithm, 3 lines of context, whitespace ignored",
                review = "Histogram algorithm, 8 lines of context, whitespace ignored",
                strict = "Myers algorithm, whitespace changes shown, linematch 80",
              },
            },
          },
          run = function(ctx)
            local ok, err = pcall(diffopt_profile.set, ctx.args.profile)
            if not ok then
              notify.error(("diff profile '%s': %s"):format(ctx.args.profile, tostring(err)))
              return
            end
            notify.info(("diff profile: %s"):format(ctx.args.profile))
          end,
        },
      },
    })
  end
end

return M

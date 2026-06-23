---@module 'diff_nvim.commands'
---@brief User-command registration + context-aware tab completion for :Diff.
---@description
--- Registers :Diff, :DiffClear, :DiffOrig and :DiffExit using the configured
--- command names. Completion understands the `key=value` grammar and suggests
--- both keys and their valid values.

local api = vim.api

local core   = require("diff_nvim.core")
local config = require("diff_nvim.config")

local M = {}

---@type table<string, string[]>  Static value lists per completion key
local VALUE_LISTS = {
  view   = { "vsplit", "split", "inline" },
  output = { "buffer", "prompt", "file", "clipboard" },
  source = { "current", "clipboard" },
  target = { "clipboard" },
}

---@type string[]  The completable keys
local KEYS = { "target", "source", "view", "output" }

---Filter a list down to entries that start with `lead`.
---@param list string[]
---@param lead string
---@return string[]
local function starts_with(list, lead)
  if lead == "" then
    return list
  end
  local out = {}
  for i = 1, #list do
    local v = list[i]
    if v:sub(1, #lead) == lead then
      out[#out + 1] = v
    end
  end
  return out
end

---Tab completion for :Diff.
---@param arglead string  The partial token under the cursor
---@return string[]
local function complete(arglead)
  -- Completing the value half of `key=value`.
  local key, partial = arglead:match("^(%a+)=(.*)$")
  if key and VALUE_LISTS[key] then
    local vals = starts_with(VALUE_LISTS[key], partial)
    local out = {}
    for i = 1, #vals do
      out[i] = key .. "=" .. vals[i]
    end
    return out
  end

  -- Completing a key; suggest `key=` for each.
  local out = {}
  local keys = starts_with(KEYS, arglead)
  for i = 1, #keys do
    out[i] = keys[i] .. "="
  end
  return out
end

---Register all commands. Idempotent at the nvim level (re-creates cleanly).
---@param cfg DiffNvim.Config
---@return nil
function M.register(cfg)
  local names = cfg.commands

  if cfg.features.diff then
    api.nvim_create_user_command(names.diff, function(info)
      core.run(info.args or "")
    end, {
      nargs = "*",
      complete = complete,
      desc = "Diff sources  :Diff [target=…] [source=…] [view=…] [output=…]",
    })

    api.nvim_create_user_command(names.diff_clear, function()
      core.clear()
    end, {
      desc = "Close all :Diff windows and disable diffmode",
    })
  end

  if cfg.features.diff_origin then
    api.nvim_create_user_command(names.diff_orig, function()
      require("diff_nvim.features.origin").run()
    end, {
      desc = "Diff current buffer against its on-disk saved version",
    })
  end

  if cfg.features.diff_exit then
    api.nvim_create_user_command(names.diff_exit, function()
      require("diff_nvim.features.exit").exit()
    end, {
      desc = "Leave diff mode (diffoff!) from anywhere",
    })
  end
end

return M

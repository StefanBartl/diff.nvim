---@module 'diff.features.diffopt_profile'
--- Named `diffopt` profiles, and the selector/cycle logic that switches
--- between them. Moved from my.nvim (cross-feature report, finding F1) —
--- see `profiles.lua` for why this belongs here rather than there.
---
--- Applying a profile always REPLACES `vim.o.diffopt` wholesale (never
--- `diffopt+=`), so switching is deterministic and never leaves stray
--- options from a previous profile behind.

local PROFILES = require("diff.features.diffopt_profile.profiles")

local M = {}

---Profile names, sorted, so cycling and listing are stable across restarts
---(`vim.tbl_keys` order is not).
---@return DiffNvim.DiffProfile[]
function M.names()
  local names = vim.tbl_keys(PROFILES) --[[@as DiffNvim.DiffProfile[] ]]
  table.sort(names)
  return names
end

---The `diffopt` string a profile builds, or nil for an unknown name.
---@param name string
---@return string|nil
function M.get(name)
  local opts = PROFILES[name]
  if not opts then
    return nil
  end
  return table.concat(opts, ",")
end

---Apply a named profile to `vim.o.diffopt`. Errors on an unknown name, naming
---it — the same contract the moved-from my.nvim version had.
---@param name string
---@return nil
function M.set(name)
  local diffopt = M.get(name)
  if not diffopt then
    error(("Unknown diff profile: %s"):format(name))
  end
  vim.o.diffopt = diffopt
end

---Which profile `vim.o.diffopt` currently matches, or nil when it matches
---none (set by hand, or a profile was edited after being applied).
---
---Derived rather than remembered: a module-local "last set" variable would go
---stale the moment something else changed `diffopt`, and a cycle built on it
---would jump from a profile the user is no longer on.
---@return DiffNvim.DiffProfile|nil
function M.current()
  local now = vim.o.diffopt
  for _, name in ipairs(M.names()) do
    if M.get(name) == now then
      return name
    end
  end
  return nil
end

---Move `diffopt` one step along the sorted profile list and apply it. An
---unrecognised current `diffopt` starts the cycle at the first profile.
---@return DiffNvim.DiffProfile applied
function M.cycle()
  local names = M.names()
  if #names == 0 then
    error("no diff profiles defined")
  end

  local current = M.current()
  local idx = 0
  for i, name in ipairs(names) do
    if name == current then
      idx = i
      break
    end
  end

  local next_name = names[(idx % #names) + 1]
  M.set(next_name)
  return next_name
end

return M

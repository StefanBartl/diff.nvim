---@module 'diff_nvim.config.DEFAULTS'
---@brief Immutable default configuration for diff.nvim.
---@description
--- Single source of truth for every configurable value. `config/init.lua`
--- deep-merges user options over a copy of this table, so this table is never
--- mutated at runtime.

---@type DiffNvim.Config
local DEFAULTS = {
  features = {
    diff        = true,
    diff_origin = true,
    diff_exit   = true,
  },
  diff = {
    default_view      = "vsplit",
    default_output     = "buffer",
    default_source     = "current",
    -- Split direction used by :DiffOrig ("vsplit" for side-by-side, "split"
    -- for stacked). Kept separate from `default_view` because :DiffOrig is
    -- always a native diffmode split, never "inline".
    default_orig_view  = "vsplit",
    algorithm           = "histogram",
    ctxlen              = 3,
    -- Word/char-level highlighting of changed spans in view=inline/float
    -- (DiffText extmarks over paired -/+ line runs). Set false to disable.
    word_diff           = true,
  },
  exit = {
    key   = "<Esc><Esc>",
    scope = "buffer",
  },
  commands = {
    diff       = "Diff",
    diff_clear = "DiffClear",
    diff_orig  = "DiffOrig",
    diff_exit  = "DiffExit",
  },
  select_fn = nil,
}

return DEFAULTS

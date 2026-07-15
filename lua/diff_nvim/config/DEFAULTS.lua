---@module 'diff_nvim.config.DEFAULTS'
---@brief Immutable default configuration for diff.nvim.
---@description
--- Single source of truth for every configurable value. `config/init.lua`
--- deep-merges user options over a copy of this table, so this table is never
--- mutated at runtime.

---@type DiffNvim.Config
local DEFAULTS = {
  features = {
    diff           = true,
    diff_origin    = true,
    diff_exit      = true,
    diff_on_hold   = true, -- ambient CursorHold line-diff preview
    conflict_marks = true, -- highlight <<<<<<< / ======= / >>>>>>> markers
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
  on_hold = {
    modes                 = "n",             -- "n"|"v"|"i" (any combination) or array; nil = n+v
    delay                 = 3000,             -- extra debounce (ms) beyond 'updatetime'
    hl_prev               = "Comment",        -- highlight group for fallback EOL preview text
    virt_priority         = 1000,             -- extmark virt_text priority
    max_len               = 160,              -- truncate fallback preview to this many characters
    git_cmd               = "git",            -- git executable to use
    ignore_buftypes       = { "nofile", "prompt", "terminal" },
    only_tracked          = true,             -- skip files not tracked by git
    require_clean_buffer  = false,            -- skip if buffer has unsaved changes
    prefix                = "previous: ",     -- prefix before fallback EOL preview text
    right_align           = false,            -- place virt_text right-aligned instead of eol
    events_override       = nil,              -- fully override auto-mapped events, e.g. { "CursorHold", "CursorHoldI" }
    prefer_inline         = true,             -- prefer gitsigns.preview_hunk_inline() when available
    restore_view          = true,             -- save/restore winsaveview()+cursor to avoid scroll jumps
    throttle_ms           = 1200,             -- min time (ms) between triggers per window
  },
  conflict_marks = {
    hl_a = "DiffDelete", -- highlight group for "<<<<<<<" lines
    hl_b = "DiffChange",  -- highlight group for "=======" separator
    hl_c = "DiffAdd",     -- highlight group for ">>>>>>>" lines
  },
  select_fn = nil,
}

return DEFAULTS

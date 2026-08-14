---@module 'diff.config.DEFAULTS'
--- Immutable default configuration for diff.nvim.
---
--- Single source of truth for every configurable value. `config/init.lua`
--- deep-merges user options over a copy of this table, so this table is never
--- mutated at runtime.

---@type DiffNvim.Config
local DEFAULTS = {
  features = {
    diff = true,
    diff_origin = true,
    diff_exit = true,
  },
  diff = {
    default_view = "vsplit",
    default_output = "buffer",
    default_source = "current",
    -- Split direction used by :DiffOrig ("vsplit" for side-by-side, "split"
    -- for stacked). Kept separate from `default_view` because :DiffOrig is
    -- always a native diffmode split, never "inline".
    default_orig_view = "vsplit",
    algorithm = "histogram",
    ctxlen = 3,
    -- Word/char-level highlighting of changed spans in view=inline/float
    -- (DiffText extmarks over paired -/+ line runs). Set false to disable.
    word_diff = true,
    -- Timeout (ms) for http(s):// sources/targets — see docs/url-sources.md.
    url_timeout_ms = 10000,
    -- When both source and target are raster-image file paths (png/jpg/jpeg/
    -- gif/webp/bmp — not svg, which is text and diffs fine as-is), show them
    -- side by side via images.nvim instead of text-diffing raw bytes, which
    -- produces meaningless output at best. Set false to restore the old
    -- behavior (or install images.nvim to actually see something with it on).
    image_compare = true,
    -- output=stat can also push its hunks into the quickfix ("qf") or
    -- location ("loc") list, so hunks from several :Diff invocations can be
    -- navigated in one list instead of only ever seeing the latest
    -- notification. "off" (default) keeps output=stat notification-only.
    stat_list = "off",
    -- "add" (default) accumulates entries across invocations — the point of
    -- stat_list existing at all; "replace" resets the list to just the
    -- latest diff's hunks each time, for a single-diff "browse the hunks"
    -- use instead of a running log.
    stat_list_mode = "add",
    -- source=/target= both resolving to real directories compares the two
    -- trees file-by-file instead of a single unified diff — see
    -- core/directory.lua. Caps the file count so pointing this at a huge
    -- tree by mistake errors instead of hanging.
    directory_max_files = 2000,
  },
  exit = {
    key = "<Esc><Esc>",
    scope = "buffer",
    -- Also mirror the exit key onto buffers a *native* :diffthis puts into
    -- diffmode (scope="buffer" only), not just diff.nvim's own diffs. Off
    -- by default: it changes buffer-local keymaps outside diff.nvim's own
    -- workflow, which could surprise users invoking :diffthis directly.
    native_diffthis = false,
  },
  commands = {
    diff = "Diff",
    diff_clear = "DiffClear",
    diff_buffers = "DiffBuffers",
    diff_orig = "DiffOrig",
    diff_exit = "DiffExit",
  },
  select_fn = nil,
  -- Auto-detect pickers.nvim (StefanBartl/pickers.nvim) and use its fuzzy
  -- engine for the target/source picker when select_fn is unset. Set false
  -- to always use vim.ui.select instead, even if pickers.nvim is installed.
  use_pickers_nvim = true,
}

return DEFAULTS

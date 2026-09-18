---@module 'diff.features.gitsigns_peek'
--- Git hunk preview via gitsigns.nvim: maps `gh` to its inline/float hunk
--- preview when gitsigns is available.
---
--- Moved from my.nvim (cross-feature report, finding F2) — it was "a git
--- operation wearing a highlight-feature's clothes" there: a `gh` keymap
--- installed through my.nvim's hl_config feature-toggle system, next to
--- cursorline and mode-tinting, even though it has no highlight content of
--- its own and nothing to do with painting a window. diff.nvim already owns
--- the sibling gitsigns surface this fleet assigns it
--- (`Externe-Plugins-Nachbau-Analyse.md`'s `gitsigns → :ToggleInlineDiff`
--- entry), so the two belong under one roof.
---
--- Setup-time only, like `diff_origin`/`diff_exit`: `cfg.features.gitsigns_peek`
--- decides once, at `require("diff").setup()`, whether the keymap is
--- installed at all — there is no runtime toggle command, matching every
--- other entry in `features`.

local notify = require("diff.util.notify")

local M = {}

---Install the `gh` keymap. The `require("gitsigns")` happens on keypress, not
---here: gitsigns is typically lazy-loaded on a buffer event, and probing for
---it eagerly at setup time would be the load trigger and pull it into every
---startup regardless of whether the user ever presses `gh`.
---@return nil
function M.register()
  vim.keymap.set("n", "gh", function()
    local ok, gs = pcall(require, "gitsigns")
    if not ok then
      notify.info("Diff peek requires gitsigns.nvim")
      return
    end

    if type(gs.preview_hunk_inline) == "function" then
      gs.preview_hunk_inline()
    elseif type(gs.preview_hunk) == "function" then
      gs.preview_hunk()
    else
      notify.warn("gitsigns.nvim loaded but preview functions unavailable")
    end
  end, { desc = "[diff] Git hunk peek" })
end

return M

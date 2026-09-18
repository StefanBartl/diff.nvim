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
---
---Refuses rather than overwriting when `gh` is already mapped: this plugin's
---own binding philosophy is "diff.nvim imposes no mappings" everywhere else
---(`bindings/keymaps.lua`'s header comment) -- silently replacing a user's or
---another plugin's normal-mode `gh` with no warning on an ordinary, default-on
---`setup()` would be the one exception. `features.gitsigns_peek = false` skips
---this whole check for a host that would rather keep its own binding.
---@return nil
function M.register()
  local existing = vim.fn.maparg("gh", "n")
  if existing ~= "" then
    notify.warn(
      "'gh' is already mapped -- not installing the gitsigns hunk peek over it. "
        .. "Set features.gitsigns_peek = false to silence this, or free up 'gh' yourself."
    )
    return
  end

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

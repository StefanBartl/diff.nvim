# Roadmap — diff.nvim

Planned and potential features. Nothing here is a promise; it is a backlog of
ideas, not ordered by priority.

## Done

- **Image-file comparison** (`diff.image_compare`, `lua/diff/features/
  image_compare.lua`) — `:Diff target=a.png source=b.png` used to
  text-diff raw binary bytes via `vim.fn.readfile`, producing meaningless
  output. Both sides being raster-image paths (`.svg` excluded — it's
  text) now shows them side by side via images.nvim's `gallery` instead,
  with a clear warning if images.nvim isn't installed rather than a
  silent fallback to the meaningless text diff. From images.nvim's
  `docs/ROADMAP/CROSS-PLUGIN.md`. No relative scaling between the two
  images (unlike images.nvim's own `:Image compare`, which needs
  `lib.nvim.ui.kit.compare`'s directory-scan-and-pick flow to get both
  images known at once) — `:Diff` already has both exact paths from its
  own arguments, so `images.gallery({a, b}, 2)` is the right primitive,
  no new API needed in either dependency.

## Ideas

- UTF-8 codepoint-aware word diff. `apply_word_diff` in
  [`lua/diff/core/render.lua`](../lua/diff/core/render.lua) currently
  highlights changed spans at byte granularity (see the docstring on
  `word_diff_ranges`); a multi-byte codepoint can straddle a highlight
  boundary on non-ASCII lines. Low priority — cosmetic only.
- Directory/recursive diff (`target=` pointing at a directory), producing a
  per-file summary instead of a single unified diff. Would need its own
  `output=` handling since "buffer"/"inline" assume a single comparison.
- Optional integration with `quickfix`/`loclist` for `output=stat` across
  multiple diffs, so hunks from several `:Diff` invocations can be
  navigated in one list.
- `git:<rev>..<rev>` range specifier (diff two revisions of the file
  directly, instead of one revision against the working buffer).

Nothing is currently in progress.

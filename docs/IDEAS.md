# `diff.nvim` - IDEAS

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

---

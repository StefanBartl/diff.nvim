# Features

Everything `diff.nvim` does, in one file — a small, single-purpose plugin
(one core command plus three thin wrappers around it), so a theme split
would only add navigation for its own sake. See
[`docs/FEATURES_FORMAT.md`](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/FEATURES_FORMAT.md)
(in `documentation.nvim`) for the format this file follows.

## `:Diff` — flexible source/target comparison

Compares a **source** (left, default: the current buffer) against a
**target** (right) using `vim.diff` (libvim) — no shell commands, no
external diff binary. Both sides accept the same specifier grammar:
`clipboard`, `ask` (force the interactive picker), `git:{rev}` (the current
file at a git revision), `http(s)://{url}` (async fetch), a file path
(tab-completed), or an already-open buffer number. Omitting `target=`
shows an interactive picker. A visual-selection range restricts `source=
current` to just the selected lines; the target side is always taken in
full.

- **Module:** `lua/diff/core/resolve.lua` (`M.parse_args`,
  `M.resolve_lines`), `lua/diff/core/init.lua`
- **Usercmds:** `:[range]Diff [target=…] [source=…] [base=…] [view=…]
  [output=…]` ([BINDINGS.md](BINDINGS.md#user-commands))
- **Config:** `opts.features.diff` (default `true`), `opts.diff.*` for
  defaults (`default_view`, `default_output`, `default_source`,
  `algorithm`, `ctxlen`)

## Output delivery (`output=`)

Five ways to receive the computed diff: `buffer` (interactive split/tab,
the default, native diffmode), `prompt` (unified diff echoed to the
message area), `file` (unified diff written to a temp file), `clipboard`
(unified diff copied to `+`), or `stat` (just `+N -M, K hunks` as a
notification, no window opened at all).

`output=stat` can also push each hunk into the quickfix or location list
(`opts.diff.stat_list`, `"off"` by default) instead of only ever showing the
latest notification, so hunks from several `:Diff` invocations accumulate in
one navigable list (`opts.diff.stat_list_mode`, `"add"` by default —
`"replace"` resets the list each time). Entries carry a real
`filename`/`bufnr` when the diffed side resolved to one; otherwise they're
text-only.

- **Module:** `lua/diff/core/render.lua` (`M.compute_hunks`, `M.push_stat_list`)
- **Config:** `opts.diff.default_output` (default `"buffer"`),
  `opts.diff.stat_list` (default `"off"`), `opts.diff.stat_list_mode`
  (default `"add"`)

## View layout (`view=`, `output=buffer` only)

`vsplit` (side-by-side, default), `split` (stacked horizontal), `tab`
(side-by-side in a new tab) all use native diffmode. `inline` renders the
unified diff into a single scratch buffer (`ft=diff`); `float` is the same
in a floating window (`q`/`<Esc>` to close). `vsplit`/`split`/`tab` follow
Neovim's own `'splitright'`/`'splitbelow'` for left-right/top-bottom order.

- **Module:** `lua/diff/core/render.lua`
- **Config:** `opts.diff.default_view` (default `"vsplit"`)

## Word-level diff highlighting

In `view=inline`/`view=float`, changed spans within a paired removed/added
line get intra-line `DiffText` highlighting — the same highlight group
native diffmode uses — instead of only whole-line coloring. Only applies
where the removed and added line counts match within a hunk (an
unambiguous 1:1 pairing); mismatched counts fall back to whole-line only.
Computed at UTF-8 codepoint granularity, so a highlighted span always
starts and ends on a codepoint boundary — a multi-byte character on a
non-ASCII line is highlighted as one unit, never split across a
highlighted/unhighlighted boundary. Falls back to byte granularity only
when a line fails UTF-8 positioning (malformed byte sequences).

- **Module:** `lua/diff/core/render.lua` (`word_diff_ranges`)
- **Config:** `opts.diff.word_diff` (default `true`)

## `git:{rev}` sources

Resolves the **current file** (not an arbitrary path) at a git revision —
`git:HEAD`, `git:HEAD~1`, a SHA, or a branch name — via a synchronous
`git show <rev>:<relpath>`, no shell string involved. Requires Neovim
0.10+ (`vim.system`), `git` on `PATH`, and a file-backed buffer inside a
git repository.

`target=git:{rev1}..{rev2}` diffs the file directly between two revisions
instead of one revision against the working buffer: sugar for
`source=git:{rev1} target=git:{rev2}`, overriding any `source=` given
alongside it. Only recognized in `target=`.

- **Module:** `lua/diff/core/git.lua`, `lua/diff/core/resolve.lua`
  (`M.split_git_range`)
- **Config:** none — checked by `:checkhealth diff`

## Directory diff (`source=`/`target=` both directories)

When both sides resolve to real, existing directories, `:Diff` compares the
two trees file-by-file and produces a per-file summary (`M`/`A`/`D` +
`+added -removed` + path) instead of a single, meaningless unified diff over
two trees' concatenated bytes. Hidden path segments (`.git`, `.hg`, …) are
always excluded. `view=` is ignored; `output=` gets its own handling:
`buffer` (default, one scratch buffer with the summary), `prompt`, `file`,
`clipboard` (the same summary delivered differently), or `stat` (just the
rolled-up file-count + `+N -M` total — and, with `opts.diff.stat_list` set,
one real jump-able quickfix/location-list entry per changed file).

- **Module:** `lua/diff/core/directory.lua`
- **Config:** `opts.diff.directory_max_files` (default `2000`) — caps files
  walked per side

## `http(s)://` URL sources

Fetches a URL's content via `curl` through `vim.system` (direct argv exec,
never a shell string) and diffs it like any other source/target. Runs
asynchronously — the editor stays responsive while the fetch is in
flight — bounded by a libuv timer independent of `curl`'s own timeout.
Non-2xx responses (`curl --fail`) are reported as errors rather than
diffed as error-page content.

- **Module:** `lua/diff/core/url.lua`
- **Config:** `opts.diff.url_timeout_ms` (default `10000`) — checked by
  `:checkhealth diff` (requires Neovim 0.10+ and `curl` on `PATH`)

## Image comparison via images.nvim

When both `source=` and `target=` are readable raster-image paths
(`.png`/`.jpg`/`.jpeg`/`.gif`/`.webp`/`.bmp` — `.svg` is excluded, it's
text and diffs fine as text), `:Diff` shows them side by side via
[images.nvim](https://github.com/StefanBartl/images.nvim) instead of
text-diffing raw bytes. Every `view=`/`output=` value is ignored in this
case, since none of them mean anything for a pair of binary images.
Without images.nvim installed, a clear warning is shown instead of
silently falling through to a meaningless text diff. No relative scaling
between the two images, unlike images.nvim's own `:Image compare` (which
needs `lib.nvim.ui.kit.compare`'s directory-scan-and-pick flow to get both
images known at once) — `:Diff` already has both exact paths from its own
arguments, so `images.gallery({a, b}, 2)` is the right primitive, no new
API needed in either dependency.

- **Module:** `lua/diff/features/image_compare.lua` (`M.maybe_compare`),
  `lua/diff/core/init.lua` (call site)
- **Config:** `opts.diff.image_compare` (default `true`)

## Three-way diff (`base=`)

Adds a third side to `:Diff`, opening a native three-window diffmode
instead of two — the merge-conflict layout: **local** (the current buffer,
always live and editable, so `:diffget`/`:diffput` write straight into the
file you'll save), **base** (the common ancestor, read-only scratch), and
**target** (the incoming/remote version, read-only scratch). `base=`
accepts the same specifier grammar as `target=`/`source=`. Neovim's native
diffmode does the actual 3-window diffing — nothing custom computed.
Requires `output=buffer` (the default) and `view=vsplit`/`split`/`tab`;
`inline`/`float`/non-`buffer` output are rejected up front with an error,
since they're single-diff concepts with no three-way equivalent.

- **Tab:** true
- **Module:** `lua/diff/core/init.lua`, `lua/diff/core/render.lua`
- **Usercmds:** `:Diff target=… base=…` ([Commands](commands.md),
  [Three-way diff](three-way-diff.md))
- **Config:** none beyond the shared `opts.diff.*` view/output validation

### Classic merge-conflict resolution

```vim
:Diff target=git:MERGE_HEAD base=git:HEAD
```

Your working copy on the left, the common ancestor in the middle, the
incoming branch on the right — resolve with `:diffget`/`:diffput` between
the panes, exactly like native `:Gdiffsplit!` or a git mergetool.

### Mixing specifier types

`base=` and `target=` don't have to be the same kind of specifier — a
`git:` ancestor against an `http(s)://` reference implementation, or two
plain file paths, both work, since all three sides go through the same
resolution grammar as `target=`/`source=` on a two-way `:Diff`.

## `:DiffBuffers` — diff against another open buffer

A convenience wrapper over `:Diff target={number}`: the source is always
the current buffer, the target is chosen from a picker listing every
other listed, loaded buffer. Only `view=`/`output=` apply.

- **Module:** `lua/diff/init.lua` (`M.diff_buffers`)
- **Usercmds:** `:DiffBuffers [view=…] [output=…]`
  ([BINDINGS.md](BINDINGS.md#user-commands))
- **Config:** `opts.features.diff` (default `true`, shares the flag with
  `:Diff`/`:DiffClear`)

## `:DiffOrig` — diff against the on-disk saved version

"What changed since the last save" — diffs the current buffer against a
read-only snapshot taken from disk. Always opens a native diffmode split
(`vsplit`/`split`, never `inline`/`float` — a separate default from
`:Diff`'s own `default_view`, since `:DiffOrig` never supports inline).
The snapshot buffer is tracked and cleaned up by `:DiffClear`.

- **Module:** `lua/diff/init.lua` (`M.diff_origin`)
- **Usercmds:** `:DiffOrig` ([BINDINGS.md](BINDINGS.md#user-commands))
- **Config:** `opts.features.diff_origin` (default `true`),
  `opts.diff.default_orig_view` (default `"vsplit"`)

## `:DiffClear` — close every diff.nvim window

Closes every scratch buffer `diff.nvim` created and disables diffmode in
every window it touched, without disturbing windows/buffers it didn't
open.

- **Module:** `lua/diff/init.lua` (`M.clear`)
- **Usercmds:** `:DiffClear` ([BINDINGS.md](BINDINGS.md#user-commands))
- **Config:** `opts.features.diff` (default `true`)

## `:DiffExit` + buffer-local exit key

Leaves diff mode (`diffoff!`) from anywhere. The default exit keymap
(`<Esc><Esc>`) is bound **buffer-locally** by default (`exit.scope =
"buffer"`) — only on buffers `diff.nvim` itself put into diffmode — so a
plain `<Esc>` elsewhere in the editor isn't delayed waiting for a possible
second key, unlike the legacy global-mapping behavior (`exit.scope =
"global"`). `exit.scope = false` disables the keymap entirely; `:DiffExit`
always works regardless of scope.

- **Module:** `lua/diff/features/exit.lua`
- **Keymaps:** `<Esc><Esc>` (`exit.key`/`exit.scope`,
  [BINDINGS.md](BINDINGS.md#keymaps))
- **Usercmds:** `:DiffExit` ([BINDINGS.md](BINDINGS.md#user-commands))
- **Config:** `opts.features.diff_exit` (default `true`), `opts.exit.key`
  (default `<Esc><Esc>`; a list binds several, so `<C-c>` can be added
  alongside rather than replacing the default), `opts.exit.scope` (default
  `"buffer"`)

## Optional keymap shortcuts

Fixed-invocation shortcuts for the invocations long enough to be worth a key:
`:Diff target=git:HEAD` and the merge-conflict form
(`base=git:HEAD target=git:MERGE_HEAD`), plus the three standalone commands.

**Nothing is bound by default.** diff.nvim deliberately imposes no leader
mappings, and that has not changed — the shortcuts exist so you don't have to
write the `vim.keymap.set` yourself *if you want one*, not because the plugin
thinks you should.

The right-hand side is built from the configured command names, and a
shortcut whose command is switched off via `features` is refused with a
warning rather than bound to something that errors on first press.

- **Module:** `lua/diff/bindings/keymaps.lua` (`register_shortcuts`,
  `SHORTCUTS`)
- **Keymaps:** `keymaps.{diff,diff_head,diff_merge,diff_buffers,diff_orig,diff_clear}`
  ([BINDINGS.md](BINDINGS.md#optional-shortcuts))
- **Config:** `opts.keymaps` (default `{}`)
- **Tests:** `docs/TESTS/keymaps_spec.lua`

Added 2026-08-24, closing the flag/option audit's entries about missing
keymaps for the HEAD/merge-conflict invocations and for
`:DiffBuffers`/`:DiffOrig`/`:DiffClear`, and about there being no way to add
a second exit key.

## Native `:diffthis` exit-key mirroring

`exit.native_diffthis = true` (requires `scope = "buffer"`) mirrors the
buffer-local exit key onto *any* buffer entering or leaving diffmode,
including a plain native `:diffthis`/`:diffoff!` outside diff.nvim's own
workflow, via an `OptionSet` watcher on the window-local `'diff'` option.
Off by default — it changes buffer-local keymaps outside diff.nvim's own
workflow, which could surprise a config that already binds its own key on
native `:diffthis` buffers.

- **Module:** `lua/diff/bindings/autocmds.lua` (`OptionSet diff` /
  `diff_native_diffthis`), `lua/diff/features/native_diffthis.lua`
- **Autocmds:** `OptionSet diff` ([BINDINGS.md](BINDINGS.md#autocommands))
- **Config:** `opts.exit.native_diffthis` (default `false`)

## Picker resolution (pickers.nvim auto-detect)

The target/source/base picker (shown when a specifier is omitted or set to
`ask`) resolves in order: an explicit `select_fn` override, then
[pickers.nvim](https://github.com/StefanBartl/pickers.nvim) if installed
and `use_pickers_nvim` isn't `false` (its fuzzy engine — telescope.nvim,
fzf-lua, or snacks.nvim, whichever pickers.nvim resolved — used
automatically, no config needed), then `vim.ui.select` as the always-
available fallback. Detection is soft: nothing errors if pickers.nvim
isn't installed or has no engine available. pickers.nvim's engines have no
reliable cross-engine cancel signal, so cancelling that picker doesn't
show the usual "Diff cancelled" message the way cancelling `vim.ui.select`
does.

- **Module:** `lua/diff/core/pickers_bridge.lua`
- **Config:** `opts.select_fn` (default `nil`), `opts.use_pickers_nvim`
  (default `true`)

## Renameable commands

Every user command diff.nvim registers can be renamed via
`opts.commands.*` — the command names shown throughout the docs are
defaults, not fixed identifiers.

- **Module:** `lua/diff/bindings/usrcmds.lua`
- **Config:** `opts.commands.diff`, `opts.commands.diff_clear`,
  `opts.commands.diff_buffers`, `opts.commands.diff_orig`,
  `opts.commands.diff_exit`

## Statusline component

`require("diff").status()` returns a short indicator string while a
diff.nvim diff is active (default `diff:N`, `N` = active scratch buffer
count), or `""` when none is — drop straight into a native statusline
string or a lualine component.

- **Module:** `lua/diff/init.lua` (`M.status`)
- **Config:** `opts.prefix` (passed to `status()` directly, not part of
  `setup()`'s config; overrides the `diff:` prefix)

## `:checkhealth diff`

Reports Neovim version, `git`/`curl` availability (needed for `git:` and
`http(s)://` specifiers respectively), and `lib.nvim`/pickers.nvim/
images.nvim detection — the "is this set up right" check to run once per
machine, not per edit.

- **Module:** `lua/diff/health.lua`
- **Docs:** [testing.md](testing.md)

# Commands

## `:[range]Diff [target=…] [source=…] [base=…] [view=…] [output=…]`

Compares a **source** (left) with a **target** (right). Arguments use a
`key=value` grammar, in any order; a key outside `target=`/`source=`/`base=`/
`view=`/`output=` has no effect and is warned about (typically a typo, e.g.
`veiw=inline`), rather than being silently indistinguishable from not typing
it at all. Adding `base=` turns this into a **three-way diff** (see
[Three-way diff](three-way-diff.md)) — a native three-window diffmode for
merge-conflict workflows.

When invoked with a **range** (e.g. a visual selection, `:'<,'>Diff`) and
`source=current` (the default), only the selected lines are used as the
source instead of the whole buffer. The range applies to the source side
only — the target is always taken in full.

**`target=`** (the "other" material)

| Value | Meaning |
|---|---|
| `clipboard` | Content from the system clipboard (`+`) |
| `ask` | Force the interactive picker (same as omitting `target=`) |
| `git:{rev}` | The current file at a git revision (see below) |
| `http(s)://{url}` | Content fetched from a URL, async (see below) |
| `{path}` | A file (tab-completed) |
| `{number}` | An already-open buffer number |

When `target=` is omitted, an interactive picker is shown.

**`source=`** (default: `current`)

| Value | Meaning |
|---|---|
| `current` | The buffer active when `:Diff` was invoked (default) |
| `clipboard` | System clipboard |
| `ask` | Force the interactive picker (also offers "current buffer") |
| `git:{rev}` | The current file at a git revision (see below) |
| `http(s)://{url}` | Content fetched from a URL, async (see below) |
| `{path}` / `{number}` | A file or buffer |

**`git:{rev}`** — resolves the **current file** at a git revision, e.g.
`git:HEAD`, `git:HEAD~1`, `git:<sha>`, or `git:<branch>`. Requires Neovim
0.10+ (`vim.system`), a `git` executable on PATH, and a file-backed buffer
inside a git repository. Runs `git show <rev>:<relpath>` off the main loop
(async); no shell is spawned.

**`target=git:{rev1}..{rev2}`** — diffs the current file directly between
two revisions, instead of one revision against the working buffer: sugar for
`source=git:{rev1} target=git:{rev2}`, and it overrides any `source=` given
alongside it (there are two revisions to compare, not a revision and
whatever `source=` would otherwise resolve to). The split point is the
first `..`, so a revision name that itself contains a dot (`v1.2.3`) is
still parsed correctly. Only recognized in `target=` — a range in `source=`
has no second thing to pair it with.

**`http(s)://{url}`** — fetches the URL's content asynchronously via `curl`
(the editor stays responsive while it's in flight) and diffs against it.
Requires Neovim 0.10+ (`vim.system`) and a `curl` executable on PATH. See
[URL sources](url-sources.md) for the timeout setting, requirements, and
usage examples.

**Line endings** — a side that arrives as raw text (`clipboard`,
`http(s)://`, `git:{rev}`) is normalized to the same shape a buffer or a file
already has: a trailing CR is dropped from every line, and a trailing newline
terminates the last line rather than starting an empty one. Without that, a
clipboard filled by a Windows application, a URL serving a CRLF document, or a
repository with `core.autocrlf=true` would make two identical sides differ in
every single line — a believable-looking diff that is entirely an artifact.
Line-ending differences are therefore not something `:Diff` reports; Neovim
keeps that in `'fileformat'`, and a buffer side could never have shown it
either.

**Directory diff** — when both `source=` and `target=` resolve to real,
existing directories, `:Diff` compares the two trees file-by-file instead of
computing a single unified diff (which wouldn't mean anything over two
whole trees' concatenated bytes). Hidden path segments (`.git`, `.hg`, …)
are always excluded. `view=` is ignored — there is no native-diffmode
notion of "diff these two trees" — and `output=` gets its own, smaller
handling:

| `output=` | Directory-diff behavior |
|---|---|
| `buffer` (default) | One scratch buffer listing every changed file: `M`/`A`/`D` + `+added -removed` + path |
| `prompt` | The same summary, echoed to the message area |
| `file` | The same summary, written to a temp file |
| `clipboard` | The same summary, copied to the clipboard (`+`) |
| `stat` | Just the rolled-up total: file count + `+N -M` |

Capped at `opts.diff.directory_max_files` (default 2000) per side — errors
rather than silently walking an unexpectedly huge tree. See
[Configuration](configuration.md) for `directory_max_files` and how
directory-diff `output=stat` also feeds `stat_list` (below) with one
real, jump-able entry per changed file. A file that becomes unreadable
mid-walk, or whose diff can't be computed at all (e.g. an invalid
`diff.algorithm`), is reported as an error rather than being silently
treated as unchanged.

**Image files** — when both `source=` and `target=` are readable
raster-image paths (`.png`/`.jpg`/`.jpeg`/`.gif`/`.webp`/`.bmp`; `.svg` is
excluded, it's text and diffs fine as text), `:Diff` shows them side by
side via [images.nvim](https://github.com/StefanBartl/images.nvim) instead
of text-diffing raw bytes — every `view=`/`output=` value is ignored in
this case, since none of them mean anything for a pair of binary images.
Without images.nvim installed, a clear warning is shown instead of
silently falling through to a meaningless text diff. Set
`diff.image_compare = false` to disable this and force the old text-diff
behavior. No relative scaling between the two images (unlike images.nvim's
own `:Image compare`) — see [Configuration](configuration.md).

**`base=`** (optional — turns this into a three-way diff)

Accepts the same grammar as `target=` (`clipboard`, `ask`, `git:{rev}`,
`http(s)://{url}`, a file path, or a buffer number). When set, `:Diff` opens
a native **three-window** diffmode instead of two: the current buffer stays
live and editable in the origin window (local), `base=` gets a read-only
scratch buffer (the common ancestor), `target=` gets another (the
remote/incoming version). Requires `output=buffer` (the default),
`view=vsplit`/`split`/`tab`, and `source=current` (the default) — the other
`output=`/`view=` values are single-diff concepts with no three-way
equivalent, and a three-way layout has no window to put an explicit
`source=` in. All three are rejected with an error if combined with `base=`,
rather than accepted and ignored. See [Three-way diff](three-way-diff.md) for
the full picture and merge-conflict-resolution examples.

**`view=`** (only for `output=buffer`, default: `vsplit`)

| Value | Layout |
|---|---|
| `vsplit` | Vertical split + native diffmode (side-by-side) |
| `split` | Horizontal split + native diffmode |
| `tab` | Side-by-side native diffmode in a new tab |
| `inline` | Single scratch buffer holding the unified diff (`ft=diff`), with word-level `DiffText` highlighting on changed spans |
| `float` | Same as `inline`, in a floating window (press `q` or `<Esc>` to close) |

For `vsplit`/`split`/`tab`, the left-hand pane is the **origin window's own
live buffer** when the source is that buffer in full — `source=current` (the
default) with no range. That side stays editable on purpose, so
`:diffget`/`:diffput` write straight into the file you will save.

Any other `source=` (a buffer number, a file path, `clipboard`, `git:{rev}`,
a URL) and any range resolve to content that window is *not* showing, so that
side is materialized into its own read-only scratch buffer and gets a window
of its own. The origin window keeps the buffer you were editing and stays out
of the diff — nothing is evicted from it.

**`output=`** (default: `buffer`)

| Value | Delivery |
|---|---|
| `buffer` | Interactive diff in a split (see `view`) |
| `prompt` | Unified diff echoed to the message area |
| `file` | Unified diff written to a temp file |
| `clipboard` | Unified diff copied to the clipboard (`+`) |
| `stat` | Report `+N -M, K hunks` as a notification only (no window by default — see `stat_list` below) |

**Side labels** — the unified-diff header (`--- <source>` / `+++ <target>`)
and the scratch-buffer names (`[Diff:source] <label>`, `[Diff:target]
<label>`, `[Diff:base] <label>`) use the specifier as written, which reads well
for a file path, `clipboard`, `git:{rev}` or a URL. A **buffer number** is the
exception — `--- 7` says nothing — so it is labelled by that buffer's own
name, shortened relative to the cwd/`$HOME` (`--- lua/old.lua`); an unnamed
buffer falls back to `buf:{N}`. `source=current` is labelled `buf:{N}`, plus
`@{line1}-{line2}` when a range narrowed it. A label is always folded to a
single line — a buffer name may legally contain a newline, and a diff header
is exactly two lines.

`output=stat` can also push each hunk into the quickfix or location list via
`opts.diff.stat_list` (`"off"` by default, or `"qf"`/`"loc"`) so hunks from
several `:Diff` invocations accumulate in one navigable list instead of only
ever showing the latest notification (`opts.diff.stat_list_mode`, `"add"` by
default; `"replace"` resets the list to just the latest diff each time). See
[Configuration](configuration.md).

**Examples**

```vim
:Diff                                  " interactive target picker
:Diff target=clipboard                 " current buffer vs. clipboard
:Diff target=42                        " current buffer vs. buffer 42
:Diff target=src/old.lua               " current buffer vs. a file
:Diff target=clipboard output=prompt   " unified diff in the message area
:Diff target=clipboard view=inline     " unified diff in a single buffer
:Diff target=a.lua source=b.lua        " compare two files
:Diff target=clipboard output=clipboard " diff to the clipboard
:Diff target=src/old.lua output=stat   " just the +N -M, K hunks summary
:'<,'>Diff target=clipboard            " compare only the selection vs. clipboard
:Diff target=clipboard view=float      " unified diff in a floating window
:Diff target=a.lua view=tab            " side-by-side diff in a new tab
:Diff target=git:HEAD                   " current file vs. its last commit
:Diff target=git:HEAD~1 output=stat     " summary vs. two commits back
:Diff target=git:HEAD~5..HEAD           " the file directly between two revisions
:Diff target=https://raw.githubusercontent.com/user/repo/main/f.lua  " current buffer vs. a URL
:Diff target=git:MERGE_HEAD base=git:HEAD  " three-way merge-conflict view
:Diff target=new.png source=old.png    " image files -> side by side via images.nvim
:Diff source=./old_src target=./new_src output=stat  " directory diff: per-file summary
```

## `:DiffClear`

Closes every scratch buffer diff.nvim created and disables diffmode in every
window.

## `:DiffBuffers [view=…] [output=…]`

Diffs the current buffer against another open buffer, chosen from a picker of
all other listed, loaded buffers (the same picker as `:Diff` — see
[Configuration › Picker resolution](configuration.md#picker-resolution)). A
convenience wrapper over `:Diff target={number}`: the source is always the
current buffer, so only `view=` and `output=` apply.

## `:DiffOrig`

Diffs the current buffer against its last-saved version on disk — "what
changed since the last save". The snapshot buffer is tracked and cleaned up by
`:DiffClear`.

## `:DiffExit`

Leaves diff mode from anywhere (`diffoff!`).

## `:DiffProfile {name}`

Replaces `'diffopt'` wholesale with one of four named profiles — `minimal`,
`context`, `review`, `strict` — see
[Configuration › Diffopt profiles](configuration.md#diffopt-profiles) for
what each one sets and why a full replacement rather than `diffopt+=`.
Tab-completes the profile name.

## `gh` — gitsigns hunk peek

Not a command but worth listing here: with `features.gitsigns_peek` on
(default), `gh` in normal mode previews the git hunk under the cursor via
[gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) — see
[Configuration › Gitsigns hunk peek](configuration.md#gitsigns-hunk-peek).

## Tab completion

`:Diff` completes the `key=value` grammar context-sensitively:

```
:Diff <Tab>            → target=  source=  base=  view=  output=
:Diff view=<Tab>       → view=vsplit  view=split  view=tab  view=inline  view=float
:Diff output=<Tab>     → output=buffer  output=prompt  output=file  output=clipboard  output=stat
:Diff source=<Tab>     → source=current  source=clipboard  source=ask  source=git:HEAD
:Diff target=<Tab>     → target=clipboard  target=ask  target=git:HEAD  (+ file paths)
:Diff base=<Tab>       → base=clipboard  base=ask  base=git:HEAD  (+ file paths)
```

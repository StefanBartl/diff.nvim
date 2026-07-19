# Three-way diff

`base=` adds a third side to `:Diff`, opening a native three-window diffmode
instead of the usual two — the layout merge-conflict tools use: your local
(editable) version, the common ancestor, and the incoming/remote version, all
diffed against each other simultaneously.

```vim
:Diff target=<remote> base=<ancestor>
```

## How it works

- **Local** is always the current buffer, shown in the window `:Diff` was
  invoked from — and it stays **live and editable**. That's the whole point
  of a three-way diff for merge resolution: `:diffget`/`:diffput` write
  straight into the file you'll actually save, exactly like native
  `:Gdiffsplit!` or a git mergetool.
- **Base** (the common ancestor) and **Target** (the remote/incoming version)
  each get a read-only scratch buffer.
- All three windows get `'diff'` turned on. Neovim's diffmode natively
  diffs 3+ windows against each other — nothing custom is computed; this is
  the same engine and highlighting (`DiffAdd`/`DiffChange`/`DiffText`/
  `DiffDelete`) as a normal two-way `:diffthis`.
- `base=` accepts the exact same specifier grammar as `target=`/`source=`:
  a file path, buffer number, `clipboard`, `git:<rev>`, `http(s)://…`, or
  `ask` to pick interactively. See [Commands](commands.md),
  [URL sources](url-sources.md).

## Constraints

A three-way diff is inherently a "put things in windows" concept, not a
"compute one unified diff" concept — so:

- **`output=` must be `buffer`** (the default). `prompt`/`file`/`clipboard`/
  `stat` all represent a single two-input unified diff and have no
  three-way equivalent.
- **`view=` must be `vsplit` (default), `split`, or `tab`** — not `inline`/
  `float`, which are single-buffer unified-diff views.

Both are validated up front; an incompatible combination is rejected with an
explanatory error before anything opens.

`source=` is accepted but only `current` (the default) makes practical
sense — local is always the live buffer in the origin window.

## Examples

**Classic merge-conflict resolution**
```vim
:Diff target=git:MERGE_HEAD base=git:HEAD
```
Your working copy (with conflict markers or your in-progress edits) on the
left, the common ancestor in the middle, the incoming branch on the right.
Use `:diffget`/`:diffput` between the panes to resolve.

**Compare a rewrite against both its origin and a reference implementation**
```vim
:Diff target=https://raw.githubusercontent.com/user/repo/main/util.lua base=git:HEAD~5
```
See what changed in your last 5 commits (`base`) *and* how far you've
diverged from someone else's implementation (`target`) — both at once.

**Resolve a conflicted file against two file-based versions**
```vim
:Diff target=/tmp/theirs.lua base=/tmp/original.lua view=split
```
Stacked horizontal layout instead of side-by-side.

**Interactive picker for the ancestor**
```vim
:Diff target=git:HEAD base=ask
```
Forces the picker for `base=` (useful when you don't remember the exact
revision/path off-hand); `target=` here is still explicit.

## Layout

```
view=vsplit (default)        view=split                    view=tab
┌───────┬───────┬───────┐    ┌───────────────────────┐     (same window
│ local │ base  │target │    │        local           │      layout,
│(live, │(read- │(read- │    ├───────────────────────┤      opened in a
│editable)│only)│ only) │    │        base            │      fresh tab —
│       │       │       │    ├───────────────────────┤      current layout
└───────┴───────┴───────┘    │        target          │      untouched)
                              └───────────────────────┘
```

Left-to-right / top-to-bottom order follows Neovim's own `'splitright'`/
`'splitbelow'` settings, same as every other split-based view in diff.nvim.

# Workflow — getting real use out of diff.nvim day to day

Every feature here is documented on its own elsewhere (`docs/commands.md`,
`docs/three-way-diff.md`, `docs/url-sources.md`, `docs/configuration.md`).
This is the different question: which combination of `target=`/`source=`/
`base=`/`view=`/`output=` actually gets reached for, and when.

## The default reflex: bare `:Diff`

Most sessions start with just `:Diff` — no arguments. It opens the
interactive picker for `target=` and diffs against the current buffer
(`source=current`, the default). This is the fastest path when you know
*what* you want to compare against but don't want to type its full
specifier — a file path, an open buffer, `clipboard`, or `git:HEAD` are
all one picker selection away. Reach for the explicit `target=…` form
only once the picker becomes slower than typing (a `git:` revision you
already know, or a URL).

## `output=stat` before `output=buffer` — check the size before opening a window

`:Diff target=… output=stat` reports `+N -M, K hunks` as a plain
notification, no window. This is worth running *before* a full
side-by-side, not just as a lighter alternative to it: a one-line change
doesn't need a split opened and closed again, and a 2000-line rewrite is
worth knowing about before committing to a `vsplit` that's mostly noise.
`:Diff target=git:HEAD~1 output=stat` as a pre-commit gut check on "how
big is this diff really" is the same idea `:DocMap check` in
documentation.nvim applies to findings — a fast, disposable signal before
the expensive interactive step.

## `git:{rev}` vs. actually checking out — the trap this exists to prevent

`:Diff target=git:HEAD~3` resolves the **current file only**, synchronously,
via `git show` — no `git checkout`, no `git stash`, no changed working
tree. The trap: it is tempting to reach for `git stash` + manual `:e` +
`git stash pop` to compare against an old revision, all to see one file's
drift. `target=git:<rev>` (or `base=git:<rev>` in a three-way) replaces
that whole dance for the common case — anything that only needs to *look*
at an old revision of *this* file, not check it out.

The corollary gotcha: `git:{rev}` always resolves the file at its
**current relative path**. A file that was renamed or moved since `{rev}`
won't resolve — there's no path-following, unlike `git log --follow`.

## Three-way diff: `base=` turns merge resolution into a real workflow, not just viewing

The single highest-value combination for anyone doing manual conflict
resolution outside a dedicated mergetool:

```vim
:Diff target=git:MERGE_HEAD base=git:HEAD
```

Local (editable, your working copy) on the left, the ancestor in the
middle, the incoming branch on the right — `:diffget`/`:diffput` between
panes writes straight into the file you'll save. This only works with
`output=buffer` (the default) and `view=vsplit`/`split`/`tab` — reaching
for `view=inline` or `output=stat` here is rejected up front with an
error, since neither means anything once there are three sides instead of
one unified diff. If you find yourself wanting a `stat`-style summary of a
three-way, that's a sign to fall back to two separate two-way `:Diff`
calls (`target= base=HEAD` and `target= base=MERGE_HEAD`) instead.

`base=` isn't limited to git revisions — mixing specifier types works:
`base=git:HEAD~5` against `target=https://…` compares your own recent
history *and* a reference implementation elsewhere, in one three-window
view, without two separate trips.

## `view=inline`/`float` vs. `view=vsplit`/`split`/`tab` — reading vs. resolving

`vsplit`/`split`/`tab` open real native diffmode — the right choice when
you intend to *act* on the diff (`:diffget`/`:diffput`, editing one side).
`inline`/`float` render a single scratch buffer holding the unified diff
text (`ft=diff`, with word-level `DiffText` highlighting on changed spans
when `diff.word_diff` is on) — better for *reading* a diff you don't plan
to interact with, especially `output=clipboard`/`output=file`'s natural
companion when you just want to glance at what's about to be copied or
written before committing to it. `view=float` additionally never disturbs
the current window layout — reach for it specifically when checking
something mid-edit and closing with `q`/`<Esc>` should leave everything
exactly as it was.

## `:DiffOrig` as the pre-write sanity check

`:DiffOrig` — "what changed since the last save" — is cheap enough to run
before every `:w` on a file you're not fully sure about, the same
reflex as `git diff` before `git add`. Unlike `:Diff`, it always opens a
native diffmode split (`diff.default_orig_view`, never `inline`/`float`)
and its snapshot buffer is tracked and cleaned up by `:DiffClear` — no
manual `:bdelete` needed once you're done looking.

## `exit.native_diffthis` — turn it on once you've hit the gap

By default, `diff.nvim`'s buffer-local exit key (`<Esc><Esc>`) only
attaches to buffers *diff.nvim itself* put into diffmode. A plain
`:diffthis` on two arbitrary buffers — outside diff.nvim's own commands
entirely, e.g. poking at diffmode manually while debugging — won't have
that key. `exit.native_diffthis = true` closes that gap by mirroring the
key onto any buffer that enters or leaves diffmode natively. It's off by
default specifically because it changes buffer-local keymaps outside
diff.nvim's own workflow; turn it on once you've actually been bitten by
the gap (typed `<Esc><Esc>` on a plain `:diffthis` pair out of habit and
had it do nothing), not preemptively.

The related, already-fixed trap: the *old* global `<Esc><Esc>` mapping
(`exit.scope = "global"`, legacy) delayed every plain `<Esc>` everywhere
in the editor, waiting to see if a second `<Esc>` was coming. `scope =
"buffer"` (the current default) only exists on buffers actually in a
diff.nvim diff, so this delay is gone unless you deliberately opt back
into the legacy global scope.

## Image pairs bypass `view=`/`output=` entirely — don't fight it

`:Diff target=new.png source=old.png` doesn't go through the text-diff
pipeline at all when both sides are readable raster images (`diff.
image_compare`, on by default) — it hands off to images.nvim's side-by-
side gallery instead, and every `view=`/`output=` flag you pass is
silently ignored, since none of them mean anything for two binary images.
The gotcha worth knowing: if images.nvim isn't installed, you get a clear
warning, not a silent fallback into a meaningless byte-level text diff of
two PNGs — don't mistake the warning for a bug and go looking for a text
diff that was deliberately not produced. Set `diff.image_compare = false`
only if you specifically want the old (mostly useless) raw-byte text-diff
behavior back.

## URL sources: async means the diff arrives later, not instantly

`:Diff target=https://…` returns control to the editor immediately — the
`curl` fetch runs in the background, bounded by `diff.url_timeout_ms`
(default 10s). The practical implication: don't chain a `:Diff target=
https://…` immediately followed by another command that assumes the diff
window already exists (a macro, a script) — the window/notification
appears once the fetch resolves, not on the line after the command. For a
same-session sanity check before trusting a downloaded file (a vendored
dependency, an install script), `output=stat` against the URL is the
fast version of "did this actually change" without opening a window at
all:

```vim
:Diff target=https://example.com/install.sh source=/tmp/install.sh output=stat
```

## Picker cancellation looks different depending on the engine

Cancelling the default `vim.ui.select` picker (`<Esc>`) shows a "Diff
cancelled" notification. Cancelling a pickers.nvim-backed picker (when
`use_pickers_nvim` is on and pickers.nvim is installed) may not — its
underlying engines (telescope.nvim/fzf-lua/snacks.nvim) have no reliable
cross-engine cancel signal diff.nvim can hook into. Silence after `<Esc>`
in the picker is expected in that setup, not evidence the command hung.

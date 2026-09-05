# Configuration

Full defaults:

```lua
require("diff").setup({
  features = {
    diff        = true,   -- register :Diff / :DiffClear
    diff_origin = true,   -- register :DiffOrig
    diff_exit   = true,   -- register :DiffExit + exit keymap
  },
  diff = {
    default_view      = "vsplit",    -- "vsplit"|"split"|"tab"|"inline"|"float"
    default_output    = "buffer",    -- "buffer"|"prompt"|"file"|"clipboard"|"stat"
    default_source    = "current",   -- "current"|"clipboard"|"ask"|"git:<rev>"|"http(s)://…"|path|bufnr
    default_orig_view = "vsplit",    -- "vsplit"|"split" — split direction for :DiffOrig
    algorithm         = "histogram", -- vim.diff algorithm
    ctxlen            = 3,           -- context lines per hunk
    word_diff         = true,        -- word/char-level DiffText highlighting in view=inline/float
    url_timeout_ms    = 10000,       -- fetch timeout for http(s):// sources/targets
    url_max_bytes     = 10485760,    -- byte cap for http(s):// sources/targets (curl --max-filesize)
    image_compare     = true,        -- show two raster-image paths side by side via images.nvim
    stat_list         = "off",       -- "off"|"qf"|"loc" — also push output=stat's hunks to a list
    stat_list_mode    = "add",       -- "add"|"replace" — accumulate across :Diff calls, or reset each time
    directory_max_files = 2000,      -- cap on files walked per side of a directory diff
  },
  exit = {
    key             = "<Esc><Esc>", -- exit mapping; a list binds several, e.g. { "<Esc><Esc>", "<C-c>" }
    scope           = "buffer",     -- "buffer"|"global"|false
    native_diffthis = false,        -- also mirror the key onto native :diffthis buffers
  },
  keymaps = {                       -- optional shortcuts, none bound by default
    -- diff         = "<leader>dd", -- :Diff (pick source and target)
    -- diff_head    = "<leader>dh", -- :Diff target=git:HEAD
    -- diff_merge   = "<leader>dm", -- :Diff base=git:HEAD target=git:MERGE_HEAD
    -- diff_buffers = "<leader>db", -- :DiffBuffers
    -- diff_orig    = "<leader>do", -- :DiffOrig
    -- diff_clear   = "<leader>dc", -- :DiffClear
  },
  commands = {
    diff         = "Diff",
    diff_clear   = "DiffClear",
    diff_buffers = "DiffBuffers",
    diff_orig    = "DiffOrig",
    diff_exit    = "DiffExit",
  },
  select_fn        = nil,          -- optional vim.ui.select replacement (DI)
  use_pickers_nvim = true,         -- auto-detect pickers.nvim as the picker engine
})
```

`diff.default_orig_view` is split off from `default_view` because `:DiffOrig`
always opens a native diffmode split — it never supports `"inline"`.

`diff.word_diff` highlights the exact changed byte span within each paired
removed/added line in `view=inline`/`view=float`, using the same `DiffText`
group Neovim's native diffmode uses for intra-line changes. Only applies to
runs where the removed and added line counts match (an unambiguous 1:1
pairing); set to `false` to disable.

`diff.url_timeout_ms` bounds how long an `http(s)://` source/target is given
to fetch before it's cancelled and reported as an error. `diff.url_max_bytes`
(default 10 MiB) bounds how large the fetched response may be, enforced by
`curl --max-filesize` so an unexpectedly huge response is aborted rather than
read entirely into memory. See [URL sources](url-sources.md) for the full
picture (requirements, how the async fetch works, and usage examples).

`diff.image_compare` (default `true`): when both `source` and `target` are
readable raster-image file paths (`.png`/`.jpg`/`.jpeg`/`.gif`/`.webp`/
`.bmp` — not `.svg`, which is text and diffs fine as text), `:Diff` shows
them side by side via [images.nvim](https://github.com/StefanBartl/images.nvim)
(`images.gallery`) instead of text-diffing raw bytes, which produces
meaningless output. Without images.nvim installed, a clear warning is shown
instead of silently falling through to that meaningless text diff. Set to
`false` to restore the old behavior unconditionally.

`diff.stat_list` (default `"off"`): `output=stat` can push each hunk into
the quickfix (`"qf"`) or location (`"loc"`) list instead of only ever
reporting the latest diff as a notification. `diff.stat_list_mode`
(default `"add"`) accumulates entries across separate `:Diff` invocations,
so hunks from several diffs end up navigable in one list; `"replace"` resets
the list to just the latest diff each time. Entries carry a real
`filename`/`bufnr` when the diffed side resolved to one (a file path or an
open buffer) and are text-only otherwise (`clipboard`, `git:<rev>`, a URL —
still listed, just not jump-able). A directory diff's own `output=stat`
(see [Commands](commands.md)) feeds the same list with one entry per changed
file, each carrying that file's real path.

`diff.directory_max_files` (default `2000`): when `source=`/`target=` both
resolve to real directories, `:Diff` walks both trees recursively to build
the per-file summary (see [Commands](commands.md)) — this caps how many
files it will walk per side before erroring instead of silently continuing
on an unexpectedly huge tree. Hidden path segments (`.git`, `.hg`, …) are
always excluded from the walk and don't count against the cap.

## Picker resolution

The target/source picker (shown when `target=`/`source=` is omitted or set to
`ask`) resolves in this order:

1. `select_fn`, if set — an explicit override always wins.
2. [pickers.nvim](https://github.com/StefanBartl/pickers.nvim), if installed
   and `use_pickers_nvim` isn't `false` — its fuzzy engine (telescope.nvim,
   fzf-lua, or snacks.nvim, whichever pickers.nvim already resolved) is used
   automatically. No configuration needed on diff.nvim's side.
3. `vim.ui.select` — the built-in fallback, always available.

Detection is soft: if pickers.nvim isn't installed, or has no picker engine
available, diff.nvim silently falls back to `vim.ui.select` — nothing errors.
Note that pickers.nvim's engines have no reliable cross-engine cancel signal,
so cancelling that picker (e.g. `<Esc>`) does not show the usual
"Diff cancelled" message the way cancelling `vim.ui.select` does.

## Exit scope

The original global `<Esc><Esc>` mapping noticeably delayed a plain `<Esc>`
because Neovim had to wait for a possible second key everywhere. diff.nvim
fixes this:

- `scope = "buffer"` (default) — the exit key is bound **buffer-locally**,
  only on buffers `diff.nvim` itself puts into diffmode. No global delay.
- `scope = "global"` — legacy behaviour (global normal-mode mapping).
- `scope = false` — no keymap at all; `:DiffExit` only.

`:DiffExit` always works, regardless of scope. All keymaps carry a `desc`, so
[which-key.nvim](https://github.com/folke/which-key.nvim) (if installed) shows
them out of the box — no extra wiring needed.

### Native `:diffthis`

By default the buffer-local exit key is only attached to buffers `diff.nvim`
itself puts into diffmode — a plain `:diffthis` on some other buffer (outside
diff.nvim's workflow) won't have it. Set `exit.native_diffthis = true`
(requires `scope = "buffer"`) to mirror the key onto *any* buffer that enters
or leaves diffmode, native `:diffthis`/`:diffoff!` included, via an `OptionSet`
watcher on the window-local `'diff'` option.

This is **off by default**: it changes buffer-local keymaps outside
diff.nvim's own workflow, which could surprise a config that already binds
its own key on native `:diffthis` buffers (e.g. a merge-conflict tool), or
that uses `:diffthis` for something unrelated to diff.nvim entirely.

# Configuration

Full defaults:

```lua
require("diff_nvim").setup({
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
  },
  exit = {
    key             = "<Esc><Esc>", -- exit mapping
    scope           = "buffer",     -- "buffer"|"global"|false
    native_diffthis = false,        -- also mirror the key onto native :diffthis buffers
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
to fetch before it's cancelled and reported as an error. See
[URL sources](url-sources.md) for the full picture (requirements, how the
async fetch works, and usage examples).

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

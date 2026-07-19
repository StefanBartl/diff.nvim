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
    default_source    = "current",   -- "current"|"clipboard"|"ask"|"git:<rev>"|path|bufnr
    default_orig_view = "vsplit",    -- "vsplit"|"split" — split direction for :DiffOrig
    algorithm         = "histogram", -- vim.diff algorithm
    ctxlen            = 3,           -- context lines per hunk
  },
  exit = {
    key   = "<Esc><Esc>",         -- exit mapping
    scope = "buffer",             -- "buffer"|"global"|false
  },
  commands = {
    diff       = "Diff",
    diff_clear = "DiffClear",
    diff_orig  = "DiffOrig",
    diff_exit  = "DiffExit",
  },
  select_fn = nil,                -- optional vim.ui.select replacement (DI)
})
```

`diff.default_orig_view` is split off from `default_view` because `:DiffOrig`
always opens a native diffmode split — it never supports `"inline"`.

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

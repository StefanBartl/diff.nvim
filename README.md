```
██████╗ ██╗███████╗███████╗
██╔══██╗██║██╔════╝██╔════╝
██║  ██║██║█████╗  █████╗
██║  ██║██║██╔══╝  ██╔══╝
██████╔╝██║██║     ██║
╚═════╝ ╚═╝╚═╝     ╚═╝
                  .nvim
```

![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-brightgreen?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-blue?logo=lua)
![Status](https://img.shields.io/badge/status-alpha-orange)

> **Pairs well with [pickers.nvim](https://github.com/StefanBartl/pickers.nvim)** —
> if it's installed, diff.nvim auto-detects it and uses its fuzzy picker
> (telescope.nvim/fzf-lua/snacks.nvim, whichever pickers.nvim resolved) for
> the target/source picker instead of the flat `vim.ui.select` — no config
> needed. Set `select_fn` to use a different picker, or
> `use_pickers_nvim = false` to always use `vim.ui.select`.

Flexible diffing for Neovim — a single `:Diff` command that compares arbitrary
sources (the current buffer, a file, a buffer number, the clipboard) against
each other and delivers the result however you like (side-by-side, inline,
message prompt, file, or clipboard).

Cross-platform (Windows + Unix). All diffing goes through `vim.diff` (libvim)
— no shell commands. Notifications go through
[`lib.nvim`](https://github.com/StefanBartl/lib.nvim), the only dependency.

---

## Quickstart

```lua
-- lazy.nvim
{
  "StefanBartl/diff.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "Diff", "DiffClear", "DiffBuffers", "DiffOrig", "DiffExit" },
  opts = {},
}
```

| Command | Description |
|---|---|
| `:Diff [target=… source=… base=… view=… output=…]` | Compare two sources (or three, with `base=`) |
| `:DiffClear` | Close every diff window and leave diffmode |
| `:DiffBuffers [view=… output=…]` | Diff the current buffer against another open buffer (picker) |
| `:DiffOrig` | Diff the current buffer against its on-disk saved version |
| `:DiffExit` | Leave diff mode from anywhere (`diffoff!`) |

Omitting `target=` opens an interactive picker (`vim.ui.select`).

```vim
:Diff                                  " interactive target picker
:Diff target=clipboard                 " current buffer vs. clipboard
:Diff target=src/old.lua               " current buffer vs. a file
:Diff target=git:HEAD                  " current file vs. its last commit
:Diff target=clipboard output=stat     " just the +N -M, K hunks summary
:'<,'>Diff target=clipboard            " compare only the visual selection
:Diff target=https://example.com/f.lua " current buffer vs. a URL (async)
:Diff target=git:MERGE_HEAD base=git:HEAD " three-way merge-conflict view
```

---

## Documentation

- [Installation](docs/installation.md) — requirements and setup for lazy.nvim, packer.nvim, and vim-plug.
- [Configuration](docs/configuration.md) — full defaults, every option explained, and exit-key scope behaviour.
- [Commands](docs/commands.md) — full `:Diff` argument grammar, examples, and tab completion.
- [URL sources](docs/url-sources.md) — diffing against `http(s)://` URLs, async fetch, timeout, and examples.
- [Three-way diff](docs/three-way-diff.md) — `base=` for merge-conflict workflows, layout, and examples.
- [Lua API](docs/api.md) — the `require("diff_nvim")` module surface.
- [Architecture](docs/architecture.md) — module layout and load order.
- [Testing & health check](docs/testing.md) — `:checkhealth diff_nvim` and the headless spec suite.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command, and autocommand.
- [Roadmap](docs/ROADMAP.md) — planned features.

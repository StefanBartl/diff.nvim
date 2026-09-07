> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# diff.nvim

```
██████╗ ██╗███████╗███████╗
██╔══██╗██║██╔════╝██╔════╝
██║  ██║██║█████╗  █████╗
██║  ██║██║██╔══╝  ██╔══╝
██████╔╝██║██║     ██║
╚═════╝ ╚═╝╚═╝     ╚═╝
                  .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)

Flexible diffing for Neovim: one `:Diff` command that compares arbitrary sources
against each other and delivers the result however you like.

A source is the current buffer, a file, a buffer number, the clipboard, a git
revision, a URL, or a whole directory tree. An output is a side-by-side or inline
view, a message prompt, a file, or the clipboard. Any of the first against any of
the second.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Features](docs/FEATURES.md) — everything diff.nvim does, one section per capability.
- [Installation](docs/installation.md) — requirements and setup for every plugin manager.
- [Configuration](docs/configuration.md) — full defaults, every option explained, and exit-key scope behaviour.
- [Commands](docs/commands.md) — the full `:Diff` argument grammar, examples, and tab completion.
- [URL sources](docs/url-sources.md) — diffing against `http(s)://` URLs: async fetch, timeout, examples.
- [Three-way diff](docs/three-way-diff.md) — `base=` for merge-conflict workflows, layout, examples.
- [Lua API](docs/api.md) — the `require("diff")` module surface.
- [Architecture](docs/architecture.md) — module layout and load order.
- [Testing and health check](docs/testing.md) — `:checkhealth diff` and the headless spec suite.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command and autocommand.
- [Workflow](docs/WORKFLOW.md) — which shape of `:Diff` answers which everyday question.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a source.

`:help diff.nvim` is the same reference inside the editor.

---

## What it does

Neovim's own `:diffthis` compares two windows. Everything else you actually want
to compare — what is on the clipboard, what is in the last commit, what a URL
serves, what is in the directory next door — first has to be turned into a
window, by hand, every time.

diff.nvim removes that step. `target=`, `source=` and `base=` each accept any of:

| Source | Written as |
| --- | --- |
| The current buffer | the default `source=` |
| A file | `target=src/old.lua` |
| A buffer number | `target=42` |
| The system clipboard | `target=clipboard` |
| A git revision | `target=git:HEAD`, `target=git:MERGE_HEAD` |
| A URL | `target=https://example.com/f.lua` — fetched asynchronously |
| A directory tree | `source=./old_src target=./new_src` — a per-file summary |

All diffing goes through `vim.diff` (libvim). There are no shell commands, which
is what makes it behave identically on Windows and Unix — the one exception is
`curl` for URL sources, and it is optional.

`base=` turns the two-way comparison into a three-way merge-conflict view. A
Visual range restricts the comparison to the selection. `output=stat` reduces the
whole thing to a `+N -M, K hunks` line when that is all you wanted.

---

## Around it

> **[pickers.nvim](https://github.com/StefanBartl/pickers.nvim)** — when it is
> installed, diff.nvim detects it and uses its fuzzy picker
> (telescope.nvim/fzf-lua/snacks.nvim, whichever pickers.nvim resolved) for the
> target and source pickers instead of the flat `vim.ui.select`. No configuration
> needed; set `select_fn` for a different picker, or `use_pickers_nvim = false`
> to always use `vim.ui.select`.
>
> **[images.nvim](https://github.com/StefanBartl/images.nvim)** — makes
> `:Diff target=new.png source=old.png` show the two images side by side instead
> of comparing their bytes.
>
> Both are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — notifications and the command layer |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `curl` | URL sources (`target=https://…`). Without it, every other source still works |
| `git` | `git:` revisions |
| [pickers.nvim](https://github.com/StefanBartl/pickers.nvim) | A fuzzy target/source picker instead of `vim.ui.select` |
| [images.nvim](https://github.com/StefanBartl/images.nvim) | Side-by-side rendering when both sides are image files |

`:Lib deps show diff.nvim` reports what of this is missing;
`:Lib deps install diff.nvim` offers to install it, asking first — see
[docs/install.json](docs/install.json) and
[lib.nvim.deps](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup shows this once, the first time `setup()` runs after installing; turn it
off with `vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) or
`vim.g.lib_nvim_deps_disabled_plugins = { "diff.nvim" }` (just this one).

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/diff.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "Diff", "DiffClear", "DiffBuffers", "DiffOrig", "DiffExit" },
  opts = {},
}
```

`cmd`-lazy is safe here: nothing happens until you ask for a diff, and there is
no tracker or autocmd that would miss anything in the meantime. Other plugin
managers are in [docs/installation.md](docs/installation.md).

---

## Quickstart

Run `:Diff` with no arguments and pick what to compare against — that is the
whole plugin in one command:

```vim
:Diff
```

Then, once you know what you want, say it directly:

```vim
:Diff target=clipboard                     " current buffer vs. the clipboard
:Diff target=src/old.lua                   " current buffer vs. a file
:Diff target=git:HEAD                      " current file vs. its last commit
:Diff target=clipboard output=stat         " just the +N -M, K hunks summary
:'<,'>Diff target=clipboard                " compare only the Visual selection
:Diff target=https://example.com/f.lua     " vs. a URL, fetched asynchronously
:Diff target=git:MERGE_HEAD base=git:HEAD  " three-way merge-conflict view
:Diff source=./old_src target=./new_src output=stat  " directory diff
```

Verify your setup any time with:

```vim
:checkhealth diff
```

---

## What you get with the defaults

| Command | Does |
| --- | --- |
| `:Diff [target=… source=… base=… view=… output=…]` | Compare two sources, or three with `base=` |
| `:DiffBuffers [view=… output=…]` | The current buffer against another open one, via a picker |
| `:DiffOrig` | The current buffer against its saved version on disk |
| `:DiffClear` | Close every diff window and leave diff mode |
| `:DiffExit` | Leave diff mode from anywhere (`diffoff!`) |

Omitting `target=` opens the interactive picker. The full argument grammar, with
completion, is [docs/commands.md](docs/commands.md).

---

## Health check

```vim
:checkhealth diff
```

Reports whether `lib.nvim` resolved, which optional external tools (`curl`,
`git`) are reachable, and which picker backend the target picker will use. See
[docs/testing.md](docs/testing.md).

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the project
layout; [docs/architecture.md](docs/architecture.md) shows where a new source or
output kind plugs in.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/diff.nvim/issues) to report bugs,
suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/diff.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).

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

Flexible diffing for Neovim: one `:Diff` command compares arbitrary sources —
buffers, files, git revisions, URLs, whole directories — against each other and
delivers the result however you like: split, inline, prompt, file, clipboard, or
a one-line stat summary.

---

## Documentation

Start at [docs/README.md](docs/README.md) — what's where, and which question
each page answers.

**Getting it running**

- [Requirements](docs/installation.md#requirements) — Neovim version, required plugins and CLI tools.
- [Installation](docs/installation.md) — plugin managers and load-trigger variants.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.
- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Testing and health check](docs/testing.md) — what `:checkhealth diff` reports, and how to run the spec suite.

**Using it**

- [Commands](docs/commands.md) — the full `:Diff` argument grammar, examples, and tab completion.
- [Workflow](docs/WORKFLOW.md) — which shape of `:Diff` answers which everyday question.
- [Three-way diff](docs/three-way-diff.md) — `base=` for merge-conflict workflows, layout, examples.
- [URL sources](docs/url-sources.md) — diffing against `http(s)://` URLs: async fetch, timeout, examples.
- [Lua API](docs/api.md) — the `require("diff")` module surface.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command and autocommand.

**The rest**

- [Features](docs/FEATURES.md) — everything diff.nvim does, one section per capability.
- [Around it](docs/around-it.md) — pickers.nvim and images.nvim, and what changes when they're installed.
- [Architecture](docs/architecture.md) — module layout and load order.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a source.
- [Feedback](https://github.com/StefanBartl/diff.nvim/issues) — bugs, features, questions; broader discussion in [Discussions](https://github.com/StefanBartl/diff.nvim/discussions).

`:help diff.nvim` is the same reference inside the editor.

---

## License

MIT — see [LICENSE](LICENSE).

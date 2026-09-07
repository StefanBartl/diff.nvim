# Contributing to diff.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/diff.nvim/issues); pull requests
very welcome.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it to
the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/diff.nvim")
require("diff").setup({})
```

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation.
- **All diffing goes through `vim.diff` (libvim).** No shelling out to `diff`,
  `git diff` or anything else to produce hunks. That is the single reason this
  plugin behaves identically on Windows and Unix, and it is not negotiable for a
  convenience.
- **Sources and outputs are orthogonal.** A source resolves to lines; an output
  consumes hunks. Neither knows about the other, and any new source works with
  every existing output for free. A change that couples them is the wrong shape.
- External tools are optional and detected, never assumed. `curl` for URLs and
  `git` for revisions are declared in [`install.json`](install.json); a missing
  one degrades that source, not the plugin.
- Notifications go through `lib.nvim`, not `vim.notify` directly.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/diff/core/` | Resolution of a source to lines, and `vim.diff` invocation |
| `lua/diff/features/` | The outputs: side-by-side, inline, prompt, file, clipboard, stat, directory, three-way |
| `lua/diff/bindings/` | The `:Diff` argument grammar, completion, and the companion commands |
| `lua/diff/config/` | Defaults, `setup()` validation, exit-key scope |
| `lua/diff/util/` | Shared helpers |
| `lua/diff/health.lua` | `:checkhealth diff` |
| `docs/` | Everything the README links to |
| `TESTS/` | The headless spec suite |

## Adding a source

1. Implement the resolver under `lua/diff/core/`: it takes the argument string
   and returns lines plus a display name, or an error. Asynchronous resolvers
   (URLs) return through a callback; keep the synchronous path synchronous.
2. Teach the `target=` / `source=` / `base=` grammar in `lua/diff/bindings/` to
   recognise it, and add it to the completion.
3. If it needs an external tool, declare it in [`install.json`](install.json) and
   report on it in `health.lua`.
4. Add a spec under `TESTS/`, including the case where the source cannot be
   resolved.
5. Document it in [`commands.md`](commands.md) and [`FEATURES.md`](FEATURES.md).

You should not have to touch anything under `features/` — if you do, the source
and the output have become coupled and the design has drifted.

## Tests

`TESTS/` runs headless; [`testing.md`](testing.md) has the invocation.
[GitHub Actions](../.github/workflows/ci.yml) runs it on every push and PR to
`main`.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.

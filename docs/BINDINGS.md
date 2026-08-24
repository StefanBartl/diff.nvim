# diff.nvim — Binding Cheatsheet

Machine-readable overview of every keymap, user command, and autocommand defined by `diff.nvim`. This file is documentation only and mirrors the source of truth in `lua/diff/bindings/usrcmds.lua`, `lua/diff/bindings/keymaps.lua`, and `lua/diff/bindings/autocmds.lua`. Any change there must be reflected here.

## Table of content

  - [Keymaps](#keymaps)
  - [User Commands](#user-commands)
  - [Autocommands](#autocommands)
  - [which-key](#which-key)

---

## Keymaps

| mode | lhs | desc | default scope | configurable via |
| --- | --- | --- | --- | --- |
| n | `<Esc><Esc>` | Exit diff mode | buffer | `exit.key` / `exit.scope` |
| n | `q` / `<Esc>` | Close diff float | buffer (float windows only, `view=float`) | not configurable |

`exit.key` takes a **list** as well as a single string, so a second key can
coexist with the default instead of replacing it — useful when `<Esc><Esc>`
collides with another plugin:

```lua
exit = { key = { "<Esc><Esc>", "<C-c>" } },
```

### Optional shortcuts

**None are bound by default** — diff.nvim imposes no mappings. Set any of
these to an lhs and it registers a normal-mode keymap for that fixed
invocation:

| `keymaps.<name>` | Runs |
| --- | --- |
| `diff` | `:Diff` (pick source and target) |
| `diff_head` | `:Diff target=git:HEAD` |
| `diff_merge` | `:Diff base=git:HEAD target=git:MERGE_HEAD` |
| `diff_buffers` | `:DiffBuffers` |
| `diff_orig` | `:DiffOrig` |
| `diff_clear` | `:DiffClear` |

```lua
require("diff").setup({
  keymaps = {
    diff_head  = "<leader>dh",
    diff_merge = "<leader>dm",
    diff_orig  = "<leader>do",
  },
})
```

The right-hand side follows your configured command names, so renaming
`commands.diff` renames what the shortcut runs. A shortcut whose command is
switched off via `features` is refused with a warning rather than bound to
something that would error on the first press. These are *fixed*
invocations — for anything else, map `:Diff …` yourself.

---

## User Commands

| default name | args | desc | feature flag |
| --- | --- | --- | --- |
| `:Diff` | `:[range]Diff [target=…] [source=…] [base=…] [view=…] [output=…]` | Compare a source (left) with a target (right); a range restricts the `current` source to the selection; `base=` opens a three-window three-way diff; two raster-image paths show side by side via images.nvim instead (`diff.image_compare`) | `features.diff` |
| `:DiffClear` | — | Close every scratch buffer and disable diffmode | `features.diff` |
| `:DiffBuffers` | `[view=…] [output=…]` | Diff the current buffer against another open buffer (picker) | `features.diff` |
| `:DiffOrig` | — | Diff current buffer against its on-disk saved version | `features.diff_origin` |
| `:DiffExit` | — | Leave diff mode (`diffoff!`) from anywhere | `features.diff_exit` |

Note: the command name column shows the default; every command is renameable via `config.commands`.

---

## Autocommands

| event | group | desc |
| --- | --- | --- |
| `VimLeavePre` | `diff_cleanup` | Wipe tracked scratch buffers on exit without touching diffmode |
| `OptionSet diff` | `diff_native_diffthis` | Opt-in (`exit.native_diffthis = true`, `exit.scope = "buffer"`): mirror the buffer-local exit key onto any buffer entering/leaving diffmode, including native `:diffthis`/`:diffoff!` |

---

## which-key

diff.nvim binds only the exit key unless you opt into the shortcuts above,
and defines no leader-prefixed group, so there is nothing to label with a
which-key group. Every keymap it registers — buffer and global exit keys, and
each shortcut — carries a `desc`, which
[which-key.nvim](https://github.com/folke/which-key.nvim) picks up
automatically — no extra wiring required.

---


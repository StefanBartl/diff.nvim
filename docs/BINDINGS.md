# diff.nvim — Binding Cheatsheet

Machine-readable overview of every keymap, user command, and autocommand defined by `diff.nvim`. This file is documentation only and mirrors the source of truth in `lua/diff_nvim/bindings/usrcmds.lua`, `lua/diff_nvim/bindings/keymaps.lua`, and `lua/diff_nvim/bindings/autocmds.lua`. Any change there must be reflected here.

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

---

## User Commands

| default name | args | desc | feature flag |
| --- | --- | --- | --- |
| `:Diff` | `:[range]Diff [target=…] [source=…] [view=…] [output=…]` | Compare a source (left) with a target (right); a range restricts the `current` source to the selection | `features.diff` |
| `:DiffClear` | — | Close every scratch buffer and disable diffmode | `features.diff` |
| `:DiffOrig` | — | Diff current buffer against its on-disk saved version | `features.diff_origin` |
| `:DiffExit` | — | Leave diff mode (`diffoff!`) from anywhere | `features.diff_exit` |

Note: the command name column shows the default; every command is renameable via `config.commands`.

---

## Autocommands

| event | group | desc |
| --- | --- | --- |
| `VimLeavePre` | `diff_nvim_cleanup` | Wipe tracked scratch buffers on exit without touching diffmode |
| `OptionSet diff` | `diff_nvim_native_diffthis` | Opt-in (`exit.native_diffthis = true`, `exit.scope = "buffer"`): mirror the buffer-local exit key onto any buffer entering/leaving diffmode, including native `:diffthis`/`:diffoff!` |

---

## which-key

diff.nvim ships a single keymap (the exit key above) and no leader-prefixed
group, so there is nothing to label with a which-key group. Both the buffer
and global exit keymaps carry a `desc`, which
[which-key.nvim](https://github.com/folke/which-key.nvim) picks up
automatically — no extra wiring required.

---


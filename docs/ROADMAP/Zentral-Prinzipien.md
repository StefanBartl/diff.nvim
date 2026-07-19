# Zentrale Prinzipien — Audit

Mental-check audit of [diff.nvim](../../lua/diff_nvim) against
[Zentrale-Prinzipien.md](../../../Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md).

## 6. Treesitter notwendig oder nicht?

Not used, not needed — diff.nvim never inspects syntax; `vim.diff` operates
on raw line arrays. N/A.

## 7. Cache vorhanden und explizit?

No caching exists. Each `:Diff` invocation resolves fresh content and calls
`vim.diff` once; results aren't reused across invocations because there's
nothing to gain by caching a diff between two mutable, user-chosen sources
that could have changed since the last comparison. N/A (deliberately).

## 8. Allokationen im Hot-Path vermeiden

No hot path exists — everything runs once per explicit user action, and
`vim.diff` (native libvim code) does the actual comparison. N/A.

## 9. Debugbarkeit eingeplant?

- It's always clear when diff.nvim is "active": diffmode is a visible window
  option, and every user-facing message is prefixed `[diff] `
  ([util/notify.lua](../../lua/diff_nvim/util/notify.lua)).
- `:checkhealth diff_nvim` reports whether the plugin is loaded and which
  runtime dependencies (`vim.diff`, `vim.ui.select`, clipboard, git) are
  present.
- No dedicated `debug = true` switch exists, but there's also no
  hidden/deferred logic to trace — every call path is a direct, synchronous
  function call from a command handler. Not adding a debug flag here is a
  judgment call, not a gap.

## 10. Laufzeit wichtiger als Startup?

diff.nvim never hooks `CursorMoved`/`TextChanged`/`BufEnter` — no code runs
on high-frequency events, so this question doesn't apply. N/A.

## Referenzen

- [Zentrale-Prinzipien.md](../../../Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md)
- [Arch&Coding.md](./Arch&Coding.md) (this repo)
- [Checklist.md](./Checklist.md) (this repo)

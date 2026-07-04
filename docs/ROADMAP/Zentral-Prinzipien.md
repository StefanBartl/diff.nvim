# Zentrale Prinzipien — Audit

Mental-check audit of [diff.nvim](../../lua/diff_nvim) against
[Zentrale-Prinzipien.md](../../../Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md).

## 1. Events bündeln, Logik entkoppeln

diff.nvim owns exactly one autocmd (`VimLeavePre` in
[bindings/autocmds.lua](../../lua/diff_nvim/bindings/autocmds.lua)), scoped to
its own augroup (`diff_nvim_cleanup`). No other module reacts to the same
event, and no logic is bound redundantly to multiple events. ✅

## 2. Eigene Logik lazy laden

[plugin/diff_nvim.lua](../../plugin/diff_nvim.lua) only checks the load
guard — it does nothing else, so lazy.nvim's `cmd = {...}` loading actually
defers all `require()`s until `:Diff`/`:DiffOrig`/etc. is invoked. Nothing is
`require`d at startup that isn't strictly the guard check. ✅

## 3. Kontext statt Mehrfach-API-Zugriffe

`DiffNvim.Context` ([@types.lua](../../lua/diff_nvim/@types.lua)) snapshots
`source_bufnr`/`origin_win` once, at the instant `:Diff` is invoked —
explicitly "captured eagerly so async pickers cannot let these values drift"
(see [core/init.lua](../../lua/diff_nvim/core/init.lua) docstring). No
function re-queries `nvim_get_current_buf()`/`nvim_get_current_win()` after
that point. ✅

## 4. Autocommand-Gruppen sauber nutzen

Single augroup, `clear = true` on creation (idempotent re-registration), one
clearly-named autocmd inside it with a `desc`. A reload would cleanly replace
it without leaking a duplicate. ✅

## 5. Event oder Command?

Every diff.nvim behavior is either an explicit user command or an explicit
keymap — nothing fires automatically on buffer/cursor events except the
unavoidable `VimLeavePre` cleanup (which is inherently exit-triggered, not a
frequent editing event). ✅

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
  runtime dependencies (`vim.diff`, `vim.ui.select`, clipboard) are present.
- No dedicated `debug = true` switch exists, but there's also no
  hidden/deferred logic to trace — every call path is a direct, synchronous
  function call from a command handler. Not adding a debug flag here is a
  judgment call, not a gap.

## 10. Laufzeit wichtiger als Startup?

diff.nvim never hooks `CursorMoved`/`TextChanged`/`BufEnter` — no code runs
on high-frequency events, so this question doesn't apply. N/A.

## Kurzform (mental) — quick pass

| Frage | Antwort |
|---|---|
| Wann läuft es? | Nur bei explizitem `:Diff*`-Aufruf oder dem Exit-Keymap. |
| Muss es jetzt laufen? | Ja — es ist immer eine direkte Nutzeraktion. |
| Lädt es mehr als nötig? | Nein — lazy via `cmd = {...}`, kein Autoload. |
| Läuft es öfter als nötig? | Nein — kein Event-Handler außer `VimLeavePre`. |
| Wird Arbeit wiederholt? | Nein — ein `vim.diff`-Call pro Invocation, kein Redraw-Loop. |
| Ist der Datenfluss klar? | Ja — `resolve → execute → render`, mit `Context` als einzigem geteilten Zustand. |

## Referenzen

- [Zentrale-Prinzipien.md](../../../Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md)
- [Arch&Coding.md](./Arch&Coding.md) (this repo)
- [Checklist.md](./Checklist.md) (this repo)

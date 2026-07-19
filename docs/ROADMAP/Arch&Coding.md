# Architecture & Coding Guidelines — Audit

Audit of [diff.nvim](../../lua/diff_nvim) against
[Arch&Coding-Regeln.md](../../../Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md).
Only sections relevant to a small, synchronous, UI-triggered plugin are
scored; performance sections aimed at hot loops / large data structures
(strings, tables, GC tuning, CPU-cycle costs, weak-table memoization) don't
apply here — diff.nvim never runs in a loop hot enough to matter, and the
actual diff computation is delegated to `vim.diff` (libvim), not
hand-rolled Lua.

## 1. Sicherheitsprinzipien & Fehlerbehandlung

| Regel | Status | Notes |
|---|---|---|
| Kein `notify()` in Low-Level-Code | ⚠️ Partial | `core/resolve.lua` is silent (correct). `core/render.lua` notifies deliberately — its own header documents this ("Renderers may notify the user because this is the UI-facing layer"). `core/init.lua`'s `run()`/`execute()`/`clear()` also notify directly rather than bubbling `(ok, err)` up to `bindings/usrcmds.lua`. Accepted as-is: splitting `core/init.lua` into a silent core + a notifying command layer would add a return-value-threading layer for a single-command plugin with no other caller of `core.run()`/`core.execute()` — not worth the indirection at this size. |
| Standardisiertes Error-Wrapping | N/A | No `safe_call` wrapper; `pcall` call-sites are few enough that a wrapper would be pure ceremony. |
| Strukturierte Fehlertypen | N/A | Errors are plain strings (`nil, "reason"`), consumed only by `notify.error()`. No caller branches on error *type*, so structured error objects would add nothing. |
| `@error` / `@raises` Tags | ➖ Not used | No function in diff.nvim raises past a `pcall` boundary uncaught, so there's nothing to tag. |

## 2. Modularisierung & Strukturprinzipien

| Regel | Status | Notes |
|---|---|---|
| Tools via Registry | N/A | diff.nvim has 4 commands, not a tool/registry of many similar things. |

## 3. Buffer- & Window-Management

| Regel | Status | Notes |
|---|---|---|
| Zentraler `ui_state` | ➖ N/A at this scale | Only two pieces of transient state exist (`DiffNvim.Context`, the scratch-buffer registry) — a dedicated `ui_state` module would just re-wrap `core/scratch.lua`. |

## 4–11 (Metatables, Docs, Testability, Perf, Caching, Weak Tables, Special Cases)

| Section | Status | Notes |
|---|---|---|
| 4. Methoden/Metatables | N/A | No stateful object needs a metatable-backed method set; module tables (`M.foo()`) are sufficient. |
| 8. Performance & Speicher | N/A | No hot loop, no large in-memory structures; `vim.diff` does the heavy lifting natively. |
| 9. Cache hitting | N/A | Diffs are computed once per invocation on user demand — nothing to gain by caching a diff between two mutable, user-chosen sources that could have changed since the last comparison. |
| 10. Schwache Tabellen & Memoisierung | N/A | No long-lived cache exists to leak. |
| 11. Spezialfälle | N/A | No FIFO/history/favorites structures in this plugin. |

## Annotations Regeln (audit)

- Central `@types.lua` file: diff.nvim uses **one** root [`@types.lua`](../../lua/diff_nvim/@types.lua) rather than a per-subdirectory `/types` folder per the guideline's stricter form. Deliberate simplification — the plugin has ~10 files and ~15 type declarations total; splitting that further would fragment more than it clarifies. Bigger sibling plugins (e.g. `markdown.nvim`) do use per-directory `@types/` folders because they have an order of magnitude more types.
- `@see` cross-links: ➖ not used — the module graph is small and flat enough (7 modules deep at most) that `require(...)` call sites already make the relationship obvious.

## Referenzen

- [Arch&Coding-Regeln.md](../../../Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md)
- [Zentral-Prinzipien.md](./Zentral-Prinzipien.md) (this repo)
- [Checklist.md](./Checklist.md) (this repo)

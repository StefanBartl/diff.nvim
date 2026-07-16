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
| `pcall()` bevorzugt | ✅ | Used at every real risk point: `vim.diff` ([render.lua:24](../../lua/diff_nvim/core/render.lua)), `nvim_buf_delete` ([scratch.lua](../../lua/diff_nvim/core/scratch.lua)), `nvim_buf_set_name`, `writefile`. |
| Type Guards & Literal Checks | ✅ | Centralized in [util/validate.lua](../../lua/diff_nvim/util/validate.lua) (`buf_valid`, `win_valid`, `is_one_of`), used before every API access. |
| Explizite Rückgaben | ✅ | `resolve.lua` and `resolve_lines`/`resolve_side` return `(value, err)`, never notify. |
| Kein `notify()` in Low-Level-Code | ⚠️ Partial | `core/resolve.lua` is silent (correct). `core/render.lua` notifies deliberately — its own header documents this ("Renderers may notify the user because this is the UI-facing layer"). `core/init.lua`'s `run()`/`execute()`/`clear()` also notify directly rather than bubbling `(ok, err)` up to `bindings/usrcmds.lua`. Accepted as-is: splitting `core/init.lua` into a silent core + a notifying command layer would add a return-value-threading layer for a single-command plugin with no other caller of `core.run()`/`core.execute()` — not worth the indirection at this size. |
| Standardisiertes Error-Wrapping | N/A | No `safe_call` wrapper; `pcall` call-sites are few enough (5) that a wrapper would be pure ceremony. |
| Strukturierte Fehlertypen | N/A | Errors are plain strings (`nil, "reason"`), consumed only by `notify.error()`. No caller branches on error *type*, so structured error objects would add nothing. |
| `@error` / `@raises` Tags | ➖ Not used | No function in diff.nvim raises past a `pcall` boundary uncaught, so there's nothing to tag. |

## 2. Modularisierung & Strukturprinzipien

| Regel | Status | Notes |
|---|---|---|
| Modul = eine Verantwortung | ✅ | `core/resolve.lua` (specifier → lines), `core/render.lua` (output), `core/scratch.lua` (buffer lifecycle), `bindings/*` (wiring only). |
| Reine Funktionen bevorzugen | ✅ | `resolve.lua`, `validate.lua` are pure. `render.compute_unified` is pure (raises via pcall internally, returns value/err). |
| Lokale statt globale Funktionen | ✅ | Helpers like `resolve_side`, `pick_target`, `starts_with`, `complete`, `with_header` are all `local function`, never exported. |
| Entwurfsmuster | ✅ (implicit) | `select_fn` is dependency injection for the target picker; `scratch.lua` is a small registry pattern for buffer lifecycle. No heavier pattern (Factory/Observer) is needed at this scope. |
| Tools via Registry | N/A | diff.nvim has 4 commands, not a tool/registry of many similar things. |
| Keine globalen States | ✅ | All state is module-local upvalues (`_active` in config, `_cfg`/`_bufs` in scratch/exit, `_setup_done` in init) — no `_G.*`. |
| Pure Functions | ✅ | See above. |

## 3. Buffer- & Window-Management

| Regel | Status | Notes |
|---|---|---|
| Zuerst `local win/buf = ...`, dann prüfen | ✅ | Consistent across `core/init.lua`, `render.lua`, `scratch.lua`, `origin.lua`. |
| Immer `~= nil` & `nvim_*_is_valid()` | ✅ | `validate.buf_valid`/`win_valid` gate every use. |
| Keine API-Calls ohne Prüfung | ✅ | Confirmed by grep — no un-guarded `nvim_win_*`/`nvim_buf_*` call sites outside the validated paths. |
| Einheitliche UI-Methoden | ✅ | `render.side_by_side`, `render.inline` — consistent split/diffmode setup. |
| Zentraler `ui_state` | ➖ N/A at this scale | Only two pieces of transient state exist (`DiffNvim.Context`, the scratch-buffer registry) — a dedicated `ui_state` module would just re-wrap `core/scratch.lua`. |
| `cleanup_all()` | ✅ | [core/scratch.lua](../../lua/diff_nvim/core/scratch.lua) — wired to both `:DiffClear` and `VimLeavePre`. |

## 4–11 (Metatables, Docs, Testability, Perf, Caching, Weak Tables, Special Cases)

| Section | Status | Notes |
|---|---|---|
| 4. Methoden/Metatables | N/A | No stateful object needs a metatable-backed method set; module tables (`M.foo()`) are sufficient. |
| 5. Dokumentation & Annotationen | ✅ | Every file opens with `@module`/`@brief`/`@description`; functions carry `@param`/`@return`. See [Annotations Regeln](#annotations-regeln-audit) below. |
| 6. Testbarkeit & Lesbarkeit | ✅ | `resolve.lua`/`validate.lua` are pure and directly unit-tested in [docs/TESTS/](../TESTS/); `select_fn` is DI. |
| 7. Fehlerbehandlung (Sicherheit) | ✅ | Covered under §1. |
| 8. Performance & Speicher | N/A | No hot loop, no large in-memory structures; `vim.diff` does the heavy lifting natively. |
| 9. Cache hitting | N/A | Diffs are computed once per invocation on user demand — nothing to cache. |
| 10. Schwache Tabellen & Memoisierung | N/A | No long-lived cache exists to leak. |
| 11. Spezialfälle | N/A | No FIFO/history/favorites structures in this plugin. |

## Annotations Regeln (audit)

- Central `@types.lua` file: diff.nvim uses **one** root [`@types.lua`](../../lua/diff_nvim/@types.lua) rather than a per-subdirectory `/types` folder per the guideline's stricter form. Deliberate simplification — the plugin has ~10 files and ~15 type declarations total; splitting that further would fragment more than it clarifies. Bigger sibling plugins (e.g. `markdown.nvim`) do use per-directory `@types/` folders because they have an order of magnitude more types.
- `return {}` as the last line: ✅ (`@types.lua:90`).
- `@module`/`@class`/`@brief`/`@description` header on every file: ✅.
- `@param`/`@return` on every public function: ✅.
- `@see` cross-links: ➖ not used — the module graph is small and flat enough (7 modules deep at most) that `require(...)` call sites already make the relationship obvious.

## Importreihung

Checked against `core/init.lua`'s import block (the most-imported module):

```lua
local api = vim.api                              -- 1. system/core
local notify   = require("diff_nvim.util.notify") -- 2. debug/notify
local validate = require("diff_nvim.util.validate")-- 3. utils
local config   = require("diff_nvim.config")       -- 3. config
local resolve  = require("diff_nvim.core.resolve")  -- logic
local render   = require("diff_nvim.core.render")
local scratch  = require("diff_nvim.core.scratch")
```

Matches the prescribed order (System → Debug/Notify → Utils/Config → Logic).
No UI/Keymap imports appear here since `core/init.lua` has none of its own —
keymaps live in `bindings/keymaps.lua`, which is imported last, from
`bindings/init.lua`.

## MISC / NVIM-Config spezifisch

- **Cross-platform**: ✅ — no shell calls; `vim.diff`, `vim.fn.tempname()`,
  `vim.fn.readfile()`/`writefile()` are all platform-agnostic. Documented in
  the README.
- **`lib.nvim`**: now a dependency, used for notifications only. The former
  "Eigenständiges Plugin ohne `lib.nvim`-Abhängigkeit" goal was reversed
  deliberately: `util/notify.lua` was a hand-rolled copy of what
  `lib.nvim.notify` already provides (prefixing + level dispatch), and
  maintaining a private duplicate of a shared helper outweighed the value of
  staying dependency-free. It now delegates to
  `require("lib.nvim.notify").create("[diff]")` while keeping its own
  `info`/`warn`/`error` surface, so no call site changed. Everything else
  stays self-contained: diffing still goes through `vim.diff`, with no shell
  and no `lib.map`/`lib.hover_select`.

## Referenzen

- [Arch&Coding-Regeln.md](../../../Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md)
- [Zentral-Prinzipien.md](./Zentral-Prinzipien.md) (this repo)
- [Checklist.md](./Checklist.md) (this repo)

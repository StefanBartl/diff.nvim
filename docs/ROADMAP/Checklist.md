# Checklist — Audit

Audit of [diff.nvim](../../lua/diff_nvim) against
[Checklist.md](../../../Notes/MyNotes/Checklists/Lua/Checklist.md). Only the
sections relevant to a small, synchronous Neovim plugin are checked below.
The algorithm/data-structure sections (sorting, hash tables, B-trees,
tries, bloom filters, bit tricks, etc.) are **out of scope** — diff.nvim
holds no custom data structures and does no sorting/searching of its own;
all comparison work is delegated to `vim.diff` (libvim).

## Schnell-Check (10 Punkte, vor jedem Merge)

| Status | Prüfschritt | Priorität | Verdict |
|---|---|---|---|
| `[x]` | Fehlerbehandlung vorhanden | 🔴 KRITISCH | `pcall` at every real risk point; `resolve.lua` returns `(value, err)`. |
| `[x]` | Type Guards | 🔴 KRITISCH | `util/validate.lua` gates every buffer/window use. |
| `[x]` | Buffer/Window validieren | 🔴 KRITISCH | `nvim_*_is_valid()` before every access — no exceptions found. |
| `[x]` | Keine globalen States | 🔴 KRITISCH | Everything is a module-local upvalue; no `_G.*`. |
| `[x]` | Single Responsibility | 🔴 KRITISCH | `resolve`/`render`/`scratch`/`bindings/*` each own one concern. |
| `[x]` | UI-Cleanup | 🟡 EMPFOHLEN | `scratch.cleanup_all()` wired to both `:DiffClear` and `VimLeavePre`. |
| `[x]` | Performance-Hotspots | 🟡 EMPFOHLEN | N/A-by-design — no string concat loops, no large data structures; diffing is native. |
| `[x]` | Annotationen vollständig | 🟡 EMPFOHLEN | `@module`/`@brief`/`@param`/`@return` throughout; see [Arch&Coding.md](./Arch&Coding.md). |
| `[x]` | Testbarkeit | 🟡 EMPFOHLEN | Pure `resolve`/`validate` covered by [docs/TESTS/](../TESTS/); DI via `select_fn`. |
| `[x]` | Import-Reihenfolge | 🟢 NICE-TO-HAVE | System → Debug/Notify → Utils/Config → Logic; verified in `core/init.lua`. |

### Bonuspunkt: Custom `lib`-Modul nutzen

`[ ]` **Not adopted, deliberately.** diff.nvim's README states "standalone
plugin, no `lib.nvim` dependency" as an explicit design goal — the plugin is
~500 lines total and self-contained. Pulling in `lib.notify`/`lib.map`/
`lib.hover_select` here would add a runtime dependency purely to satisfy the
convention, not to solve an actual problem the plugin has. Recorded as an
accepted deviation, not a TODO.

## PR-Review-Checkliste (Detail)

### 1. Sicherheit und Fehlerbehandlung

All four items ✅ — see the Schnell-Check row above and the `pcall`/
`validate` audit in [Arch&Coding.md §1](./Arch&Coding.md#1-sicherheitsprinzipien--fehlerbehandlung).

### 2. Modularität und Struktur

| Status | Prüfschritt | Verdict |
|---|---|---|
| `[x]` | Single Responsibility | ✅ |
| `[x]` | Keine Globals | ✅ |
| `[x]` | Reine Funktionen | ✅ (`resolve.lua`, `validate.lua`) |
| `[x]` | Interne Helfer lokal | ✅ |
| `[ ]` | Tools/Registry | N/A — 4 commands, not a tool collection. |
| `[x]` | Config | ✅ `config/DEFAULTS.lua` + `config/init.lua`. |

### 3. Buffer-/Window-Management (Neovim)

All five items ✅ — handles are bound then validated everywhere; deferred
callbacks (`vim.ui.select`/`vim.ui.input` continuations in `pick_target`)
re-validate the origin window (`ctx.origin_win`) before use in `execute()`.

### 4. UI-State-Management

`[x]` No dedicated `ui_state` module, but the only transient state
(`DiffNvim.Context`, the scratch-buffer registry in `core/scratch.lua`) is
already centralized and accessed through functions (`scratch.create`,
`scratch.track`, `scratch.cleanup_all`), not raw field access. Snapshot/
restore isn't needed since there's no undo-able state to restore.

### 5. Dokumentation und Annotationen

`[x]` all rows — see [Arch&Coding.md](./Arch&Coding.md#annotations-regeln-audit).

### 6. Testbarkeit und Lesbarkeit

`[x]` DI via `select_fn`; pure functions in `resolve`/`validate`; a
headless spec suite now exists in [docs/TESTS/](../TESTS/) as the
"separate test entry".

### 7. Tooling

| Status | Prüfschritt | Verdict |
|---|---|---|
| `[x]` | Lua LS Settings | `.luarc.json` added at repo root (`diagnostics.globals = ["vim"]`, `workspace.library`). |
| `[ ]` | Formatter/Linter (stylua/luacheck) im CI | Not set up. Left as a roadmap item — see [docs/ROADMAP.md](../ROADMAP.md); no CI workflow exists yet for this repo. |

## Coding-Checkliste (beim Implementieren)

Only the directly-applicable subsections:

### A. Strings und Tabellen

N/A — diff.nvim builds at most a handful of header/label strings per
invocation (`string.format`, one `..` concat for the unified-diff header);
never in a loop, never at a size where `table.concat` buffering would matter.

### C. Neovim-API sicher verwenden

`[x]` all three rows — see the Buffer/Window audit above.

### D. State- und Datenmodelle

`[x]` Getter/Setter used for config (`config.get()`/`config.setup()`).
Metatables and FIFO/ringbuffer structures: N/A, nothing in diff.nvim needs
either.

### F. Lazy-Loading und On-Demand-Konfiguration

`[x]` `config/init.lua` builds the full merged config eagerly on `setup()`
rather than lazily per-field — appropriate here since the config is tiny
(5 top-level keys) and read constantly (`config.get()` on every `:Diff`
call); a lazy-metatable resolver would add indirection without saving
meaningful work.

## Anti-Pattern-Check

| Status | Muster | Verdict |
|---|---|---|
| `[x]` | Globaler State | None found. |
| `[x]` | API ohne Guards | None found. |
| `[x]` | String-Concat im Loop | None present. |
| `[x]` | Closures im Loop | None present. |
| `[x]` | Viele kleine temporäre Tabellen | Not a concern at this scale/frequency. |

## Import- und Dateistruktur-Check

| Status | Punkt | Verdict |
|---|---|---|
| `[x]` | Import-Reihenfolge | ✅ (see [Arch&Coding.md](./Arch&Coding.md#importreihung)). |
| `[x]` | Datei-Header | ✅ every file. |
| `[ ]` | Typ-Ablage (projektweiter `@types`-Ordner) | Uses a single root `@types.lua` rather than per-directory `/types` folders — see the rationale in [Arch&Coding.md](./Arch&Coding.md#annotations-regeln-audit). Accepted deviation, not a gap. |

## Reviewer-Notizen

| Bereich | Beobachtung | Empfehlung |
|---|---|---|
| Sicherheit | `pcall`/type-guards consistently applied | None |
| Modularität | Clean split after the `bindings/` refactor (usrcmds/keymaps/autocmds) | None |
| Neovim-API | Handles validated before every use, including deferred picker callbacks | None |
| Performance | Not a concern at this scale; `vim.diff` does the real work | None |
| Doku/Annotation | Full `@module`/`@param`/`@return` coverage | None |
| Tests | Headless spec suite added ([docs/TESTS/](../TESTS/)) | Consider adding a GitHub Actions workflow to run it in CI (tracked as a separate task, not part of this checklist) |
| checkhealth | Implemented (`:checkhealth diff_nvim`) | None |

## Referenzen

- [Checklist.md](../../../Notes/MyNotes/Checklists/Lua/Checklist.md)
- [Arch&Coding.md](./Arch&Coding.md) (this repo)
- [Zentral-Prinzipien.md](./Zentral-Prinzipien.md) (this repo)

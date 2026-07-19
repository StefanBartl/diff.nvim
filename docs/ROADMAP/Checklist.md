# Checklist — Audit

Audit of [diff.nvim](../../lua/diff_nvim) against
[Checklist.md](../../../Notes/MyNotes/Checklists/Lua/Checklist.md). Only the
sections relevant to a small, synchronous Neovim plugin are checked below.
The algorithm/data-structure sections (sorting, hash tables, B-trees,
tries, bloom filters, bit tricks, etc.) are **out of scope** — diff.nvim
holds no custom data structures and does no sorting/searching of its own;
all comparison work is delegated to `vim.diff` (libvim).

## PR-Review-Checkliste (Detail)

### Modularität und Struktur

| Status | Prüfschritt | Verdict |
|---|---|---|
| `[ ]` | Tools/Registry | N/A — 4 commands, not a tool collection. |

### Tooling

| Status | Prüfschritt | Verdict |
|---|---|---|
| `[~]` | Formatter/Linter (stylua/luacheck) im CI | Partial. A GitHub Actions workflow ([.github/workflows/ci.yml](../../.github/workflows/ci.yml)) now runs the headless spec suite on push/PR. `stylua`/`luacheck` gates are intentionally not wired yet (no formatter config committed); tracked as the remaining half of this item. |

## Coding-Checkliste (beim Implementieren)

### Strings und Tabellen

N/A — diff.nvim builds at most a handful of header/label strings per
invocation (`string.format`, one `..` concat for the unified-diff header);
never in a loop, never at a size where `table.concat` buffering would matter.

## Import- und Dateistruktur-Check

| Status | Punkt | Verdict |
|---|---|---|
| `[ ]` | Typ-Ablage (projektweiter `@types`-Ordner) | Uses a single root `@types.lua` rather than per-directory `/types` folders — see the rationale in [Arch&Coding.md](./Arch&Coding.md#annotations-regeln-audit). Accepted deviation, not a gap. |

## Reviewer-Notizen

| Bereich | Beobachtung | Empfehlung |
|---|---|---|
| Tests | Headless spec suite ([docs/TESTS/](../TESTS/)), now run in CI ([.github/workflows/ci.yml](../../.github/workflows/ci.yml)) | Add `stylua`/`luacheck` gates once a formatter config is committed |

## Referenzen

- [Checklist.md](../../../Notes/MyNotes/Checklists/Lua/Checklist.md)
- [Arch&Coding.md](./Arch&Coding.md) (this repo)
- [Zentral-Prinzipien.md](./Zentral-Prinzipien.md) (this repo)

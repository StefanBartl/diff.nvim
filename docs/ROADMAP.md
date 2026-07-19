# diff.nvim — Roadmap

## Geplante Features

### Quellen / Ziele

- **URL als Quelle** — `target=https://…` lädt den Inhalt asynchron via
  `vim.system`/curl und difft dagegen. Erfordert Async-Handling + Timeout.

### Drei-Wege & Merge

- **Drei-Wege-Diff** — `:Diff target=… base=…` für Merge-Konflikt-Workflows
  (`diffmode` mit drei Fenstern). Größere Layout-Änderung → separater Renderer.

---

## Implementierungsplan

**Drei-Wege-Diff** und **URL als Quelle** sind die größten verbleibenden
architektonischen Änderungen (dritter Layout-Renderer bzw. Async-HTTP-Handling)
und brauchen jeweils eigene Design-Entscheidungen. Reihenfolge offen — beide
sind voneinander unabhängig.

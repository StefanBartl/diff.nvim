# diff.nvim — Roadmap

## Geplante Features

### Quellen / Ziele

- **URL als Quelle** — `target=https://…` lädt den Inhalt asynchron via
  `vim.system`/curl und difft dagegen. Erfordert Async-Handling + Timeout.

### Drei-Wege & Merge

- **Drei-Wege-Diff** — `:Diff target=… base=…` für Merge-Konflikt-Workflows
  (`diffmode` mit drei Fenstern). Größere Layout-Änderung → separater Renderer.

### Robustheit

- **Konfigurierbarer Exit-Key auch für `scope="buffer"`** — derzeit greift der
  konfigurierte Key bei `buffer`-Scope nur auf Plugin-Diffs. Optionaler
  `OptionSet`-Autocmd, der die buffer-lokale Map auch bei nativem `:diffthis`
  setzt/entfernt (Window-lokales `diff` → Buffer-lokale Map sauber abbilden).

- **Diff gegen ungespeicherte Versionen anderer Buffer** — bereits via
  Buffernummer möglich; ggf. ein `:DiffBuffers`-Convenience-Command mit Picker.

---

## Implementierungsplan

Priorisierte Reihenfolge für die "Geplante Features"-Liste oben, nach
Aufwand/Abhängigkeit sortiert:

1. **Konfigurierbarer Exit-Key auch bei `scope="buffer"` für natives
   `:diffthis`** — optionaler `OptionSet`-Autocmd, unabhängig vom Rest.
2. **`:DiffBuffers`-Convenience-Command** — Buffer-Picker-Wrapper um die
   bestehende Buffernummer-Auflösung.
3. **Drei-Wege-Diff** und **URL als Quelle** — größte architektonische
   Änderungen (dritter Layout-Renderer bzw. Async-HTTP-Handling); bewusst
   zuletzt, da beide eigene Design-Entscheidungen brauchen.

---


# diff.nvim — Roadmap

## Geplante Features

### Anzeige / UX

- **Wort-Level-Highlighting im Inline-View** — innerhalb geänderter Zeilen die
  konkreten Wort-/Zeichen-Unterschiede hervorheben (`vim.diff` mit
  `result_type = "indices"` + Extmarks). Nur im `view=inline`-Pfad.

### Quellen / Ziele

- **Telescope-/Picker-Integration** — Buffernummer-Ziel über einen Buffer-Picker
  auswählen statt manueller Eingabe; optionale Dependency, lazy geladen.

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

1. **Wort-Level-Highlighting im Inline-View** — reine `render.lua`-Erweiterung
   mit UI-Detailarbeit (Extmarks, Highlight-Gruppen, Intra-Zeilen-Diff über
   `vim.diff` mit `result_type = "indices"`). Isoliert, gut testbar.
2. **Telescope-/Picker-Integration** — baut auf dem `select_fn`-DI-Hook auf
   (siehe [Configuration](configuration.md), Nutzung in `core/init.lua`s
   `pick_specifier()`); optionale, lazy geladene Dependency.
3. **Konfigurierbarer Exit-Key auch bei `scope="buffer"` für natives
   `:diffthis`** — optionaler `OptionSet`-Autocmd, unabhängig vom Rest.
4. **`:DiffBuffers`-Convenience-Command** — Buffer-Picker-Wrapper um die
   bestehende Buffernummer-Auflösung.
5. **Drei-Wege-Diff** und **URL als Quelle** — größte architektonische
   Änderungen (dritter Layout-Renderer bzw. Async-HTTP-Handling); bewusst
   zuletzt, da beide eigene Design-Entscheidungen brauchen.

---

## Nicht geplant

- **Eigene Diff-Engine** — `vim.diff` (libvim/xdiff) ist schnell und korrekt;
  keine Notwendigkeit für eine Lua-Reimplementierung.

- **Patch-Anwendung** (`:Diff` → `patch -p1`) — gehört in ein separates
  `patch.nvim`-Plugin; Diffing und Patching sind verschiedene Domänen.

- **Zeilenweises Inline-Merging im selben Buffer** — Konfliktlösung deckt
  bereits `diffget`/`diffput` aus Neovim-Core ab.

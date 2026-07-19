# diff.nvim — Roadmap

## Implemented (v0.1)

- `:Diff [target= source= view= output=]` — flexible source/target diffing
- Sources/targets: `current`, `clipboard`, file path, buffer number
- Views: `vsplit`, `split`, `tab`, `inline` (single unified `ft=diff` buffer), `float`
- Outputs: `buffer`, `prompt`, `file`, `clipboard`, `stat` (`+N -M, K hunks` summary)
- `:DiffClear` — tear down all scratch buffers + diffmode
- `:DiffOrig` — diff buffer vs. on-disk saved version (core-integrated)
- `:DiffExit` — leave diffmode from anywhere
- `target=ask` / `source=ask` — force the interactive picker even with a default
- `:[range]Diff` — visual-range selection as the source (e.g. `:'<,'>Diff`)
- `view=tab` — side-by-side native diffmode in a new tab
- `view=float` — unified diff in a floating window
- `target=git:<rev>` / `source=git:<rev>` — current file at a git revision
  (`git:HEAD`, `git:HEAD~1`, `git:<sha>`, `git:<branch>`), via `core/git.lua`
- `require("diff_nvim").status()` — statusline component (active-diff indicator)
- Buffer-local exit keymap (fixes the global `<Esc><Esc>` delay)
- Interactive target picker via `vim.ui.select`
- Context-aware `key=value` tab completion
- Config system with `config/DEFAULTS.lua`, idempotent `setup()`/`enable()`
- `:checkhealth diff_nvim`
- All diffing via `vim.diff` — no shell, cross-platform
- Notifications via `lib.nvim.notify` (lib.nvim is the only dependency)

---

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

Die kleinen, gut abgegrenzten Punkte (Diff-Statistik, `target=ask`/`source=ask`,
Visual-Range, `view=tab`/`view=float`, Git-Quellen, Statuszeilen-Komponente)
sind umgesetzt — siehe **Implemented** oben. Die verbleibende Reihenfolge, nach
Aufwand/Abhängigkeit sortiert:

1. **Wort-Level-Highlighting im Inline-View** — reine `render.lua`-Erweiterung
   mit UI-Detailarbeit (Extmarks, Highlight-Gruppen, Intra-Zeilen-Diff über
   `vim.diff` mit `result_type = "indices"`). Isoliert, gut testbar.
2. **Telescope-/Picker-Integration** — baut auf dem `select_fn`-DI-Hook auf
   (siehe [Configuration](configuration.md), Nutzung in `core/init.lua`s
   `pick_specifier()`); optionale, lazy geladene Dependency. Profitiert von den
   inzwischen stabilisierten Target-Typen (Git, Range).
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

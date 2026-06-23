# diff.nvim — Roadmap

## Implemented (v0.1)

- `:Diff [target= source= view= output=]` — flexible source/target diffing
- Sources/targets: `current`, `clipboard`, file path, buffer number
- Views: `vsplit`, `split`, `inline` (single unified `ft=diff` buffer)
- Outputs: `buffer`, `prompt`, `file`, `clipboard`
- `:DiffClear` — tear down all scratch buffers + diffmode
- `:DiffOrig` — diff buffer vs. on-disk saved version (core-integrated)
- `:DiffExit` — leave diffmode from anywhere
- Buffer-local exit keymap (fixes the global `<Esc><Esc>` delay)
- Interactive target picker via `vim.ui.select`
- Context-aware `key=value` tab completion
- Config system with `config/DEFAULTS.lua`, idempotent `setup()`/`enable()`
- `:checkhealth diff_nvim`
- All diffing via `vim.diff` — no shell, cross-platform
- No lib.nvim dependency

---

## Geplante Features

### High Priority

- **Git als Quelle/Ziel** — `:Diff target=git:HEAD` / `git:HEAD~1` / `git:<sha>`
  Vergleich gegen eine Git-Revision der aktuellen Datei. Cross-platform via
  `vim.system({ "git", "show", rev .. ":" .. relpath })`. Erfordert Repo-Root-
  Erkennung (Aufwärtssuche nach `.git`); deshalb als eigenes `core/git.lua`.

- **Visual-Range als Quelle** — `:'<,'>Diff target=clipboard` vergleicht nur die
  selektierten Zeilen statt des ganzen Buffers. Benötigt `range = true` am
  User-Command und Übergabe von `line1`/`line2` an die Resolver-Schicht.

- **Diff-Statistik** — kurze Zusammenfassung (`+N -M, K hunks`) als `notify.info`
  nach jedem Diff bzw. als eigener `output=stat`. Aus dem Unified-Diff ableitbar
  durch Zählen von `^+`/`^-`-Zeilen (ohne Header).

### Anzeige / UX

- **Wort-Level-Highlighting im Inline-View** — innerhalb geänderter Zeilen die
  konkreten Wort-/Zeichen-Unterschiede hervorheben (`vim.diff` mit
  `result_type = "indices"` + Extmarks). Nur im `view=inline`-Pfad.

- **`view=tab`** — Side-by-Side-Diff in einem neuen Tab statt Split; nützlich für
  große Dateien. Kleiner Zusatz in `render.side_by_side`.

- **`view=float`** — Inline-Unified-Diff in einem Floating-Window statt Split.

- **Persistenter Diff-Status in der Statuszeile** — kleine Komponente, die
  anzeigt, dass aktuell ein `diff.nvim`-Diff aktiv ist (Anzahl Scratch-Buffer).

### Quellen / Ziele

- **`target=ask` / `source=ask`** — erzwingt den interaktiven Picker auch wenn
  ein Default existiert; vereinheitlicht den Workflow.

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

## Nicht geplant

- **Eigene Diff-Engine** — `vim.diff` (libvim/xdiff) ist schnell und korrekt;
  keine Notwendigkeit für eine Lua-Reimplementierung.

- **Patch-Anwendung** (`:Diff` → `patch -p1`) — gehört in ein separates
  `patch.nvim`-Plugin; Diffing und Patching sind verschiedene Domänen.

- **Zeilenweises Inline-Merging im selben Buffer** — Konfliktlösung deckt
  bereits `diffget`/`diffput` aus Neovim-Core ab.

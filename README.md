# diff.nvim

Flexibles Diffing für Neovim — ein `:Diff`-Befehl, der beliebige Quellen
(aktueller Buffer, Datei, Buffernummer, Zwischenablage) gegeneinander
vergleicht und das Ergebnis auf verschiedene Arten ausgibt (Side-by-Side,
Inline, Prompt, Datei oder Zwischenablage).

Eigenständiges Plugin ohne `lib.nvim`-Abhängigkeit, plattformübergreifend
(Windows + Unix), das gesamte Diffing läuft über `vim.diff` (libvim) — keine
Shell-Aufrufe.

---

## Funktionsüberblick

| Befehl | Beschreibung |
|---|---|
| `:Diff [target=… source=… view=… output=…]` | Zwei Quellen vergleichen |
| `:DiffClear` | Alle Diff-Fenster schließen und diffmode beenden |
| `:DiffOrig` | Aktuellen Buffer gegen die gespeicherte Version auf der Platte diffen |
| `:DiffExit` | Diff-Modus von überall aus verlassen (`diffoff!`) |

Wird `target=` weggelassen, öffnet sich ein interaktiver Auswahldialog
(`vim.ui.select`).

---

## Voraussetzungen

- Neovim 0.9+
- Keine externen Plugins erforderlich

---

## Installation

```lua
-- lazy.nvim (lokaler Checkout)
{
  dir   = vim.env.REPOS_DIR .. "/diff.nvim",
  cmd   = { "Diff", "DiffClear", "DiffOrig", "DiffExit" },
  opts  = {},
}
```

Oder per `config`:

```lua
{
  dir = vim.env.REPOS_DIR .. "/diff.nvim",
  config = function()
    require("diff_nvim").setup({})
  end,
}
```

---

## Konfiguration

Vollständige Defaults:

```lua
require("diff_nvim").setup({
  features = {
    diff        = true,   -- :Diff / :DiffClear registrieren
    diff_origin = true,   -- :DiffOrig registrieren
    diff_exit   = true,   -- :DiffExit + Exit-Keymap registrieren
  },
  diff = {
    default_view   = "vsplit",    -- "vsplit"|"split"|"inline"
    default_output = "buffer",    -- "buffer"|"prompt"|"file"|"clipboard"
    default_source = "current",   -- "current"|"clipboard"|Pfad|Buffernummer
    algorithm      = "histogram", -- vim.diff-Algorithmus
    ctxlen         = 3,           -- Kontextzeilen pro Hunk
  },
  exit = {
    key   = "<Esc><Esc>",         -- Tastenkombination zum Verlassen
    scope = "buffer",             -- "buffer"|"global"|false
  },
  commands = {
    diff       = "Diff",
    diff_clear = "DiffClear",
    diff_orig  = "DiffOrig",
    diff_exit  = "DiffExit",
  },
  select_fn = nil,                -- optionaler Ersatz für vim.ui.select (DI)
})
```

### Exit-Scope

Das ursprüngliche globale `<Esc><Esc>`-Mapping verzögerte das normale `<Esc>`
spürbar, weil Neovim überall auf einen möglichen zweiten Tastendruck warten
musste. `diff.nvim` behebt das:

- `scope = "buffer"` (Standard) — die Exit-Taste wird **buffer-lokal** nur auf
  jenen Buffern gesetzt, die `diff.nvim` selbst in den Diff-Modus versetzt.
  Kein globaler Verzögerungseffekt.
- `scope = "global"` — altes Verhalten (globales Normal-Mode-Mapping).
- `scope = false` — keine Tastenkombination; nur `:DiffExit`.

`:DiffExit` funktioniert in jedem Fall, unabhängig vom Scope.

---

## Befehlsreferenz

### `:Diff [target=…] [source=…] [view=…] [output=…]`

Vergleicht eine **Quelle** (links) mit einem **Ziel** (rechts).

**`target=`** (das „andere" Material)

| Wert | Bedeutung |
|---|---|
| `clipboard` | Inhalt aus der Zwischenablage (`+`) |
| `<Pfad>` | Datei (mit Tab-Completion) |
| `<Nummer>` | Bereits geöffnete Buffernummer |

Fehlt `target=`, erscheint ein interaktiver Auswahldialog.

**`source=`** (Standard: `current`)

| Wert | Bedeutung |
|---|---|
| `current` | Der bei `:Diff` aktive Buffer (Standard) |
| `clipboard` | Zwischenablage |
| `<Pfad>` / `<Nummer>` | Datei bzw. Buffer |

**`view=`** (nur bei `output=buffer`, Standard: `vsplit`)

| Wert | Layout |
|---|---|
| `vsplit` | Vertikaler Split + nativer diffmode (Side-by-Side) |
| `split` | Horizontaler Split + nativer diffmode |
| `inline` | Einzelner Scratch-Buffer mit Unified-Diff (`ft=diff`) |

**`output=`** (Standard: `buffer`)

| Wert | Ausgabe |
|---|---|
| `buffer` | Interaktiver Diff im Split (siehe `view`) |
| `prompt` | Unified-Diff in den Nachrichtenbereich |
| `file` | Unified-Diff in temporäre Datei schreiben |
| `clipboard` | Unified-Diff in die Zwischenablage kopieren |

**Beispiele**

```vim
:Diff                                  " interaktiver Zieldialog
:Diff target=clipboard                 " aktueller Buffer vs. Zwischenablage
:Diff target=42                        " aktueller Buffer vs. Buffer 42
:Diff target=src/old.lua               " aktueller Buffer vs. Datei
:Diff target=clipboard output=prompt   " Unified-Diff im Prompt
:Diff target=clipboard view=inline     " Unified-Diff in einem Buffer
:Diff target=a.lua source=b.lua        " zwei Dateien vergleichen
:Diff target=clipboard output=clipboard " Diff in die Zwischenablage
```

### `:DiffClear`

Schließt alle von `diff.nvim` erzeugten Scratch-Buffer und schaltet den
Diff-Modus in allen Fenstern ab.

### `:DiffOrig`

Vergleicht den aktuellen Buffer mit seiner zuletzt gespeicherten Version auf
der Festplatte — „was habe ich seit dem letzten Speichern geändert?". Der
Snapshot-Buffer wird mitverwaltet und von `:DiffClear` mit aufgeräumt.

### `:DiffExit`

Verlässt den Diff-Modus von überall aus (`diffoff!`).

---

## Tab-Completion

`:Diff` vervollständigt kontextsensitiv die `key=value`-Grammatik:

```
:Diff <Tab>            → target=  source=  view=  output=
:Diff view=<Tab>       → view=vsplit  view=split  view=inline
:Diff output=<Tab>     → output=buffer  output=prompt  output=file  output=clipboard
:Diff source=<Tab>     → source=current  source=clipboard
:Diff target=<Tab>     → target=clipboard  (+ Dateipfade)
```

---

## Lua-API

```lua
local diff = require("diff_nvim")

diff.setup(opts)        -- konfigurieren + aktivieren (idempotent)
diff.enable(opts)       -- Alias für setup() (Kompatibilität zu custom.diff)
diff.run("target=…")    -- entspricht :Diff …
diff.clear()            -- entspricht :DiffClear
diff.diff_origin()      -- entspricht :DiffOrig
diff.exit()             -- entspricht :DiffExit
```

---

## Architektur

```
plugin/diff_nvim.lua         Load-Guard
lua/diff_nvim/
  init.lua                   Öffentliche API, setup()/enable()
  @types.lua                 LuaLS-Typdefinitionen
  config/
    DEFAULTS.lua             Unveränderliche Default-Konfiguration
    init.lua                 Merge + Zugriff auf aktive Config
  util/
    notify.lua               "[diff] "-präfigierter vim.notify-Wrapper
    validate.lua             Reine Validierungs-Helfer (is_one_of, *_valid)
  core/
    init.lua                 Orchestrierung: run(), execute(), Zielpicker
    resolve.lua              Spezifizierer → Zeilen, Argument-Parsing
    scratch.lua              Scratch-Buffer-Lebenszyklus + cleanup_all()
    render.lua               Output-Renderer (buffer/prompt/file/clipboard)
  features/
    origin.lua               :DiffOrig
    exit.lua                 :DiffExit + Exit-Keymap
  commands.lua               Befehlsregistrierung + Tab-Completion
  health.lua                 :checkhealth diff_nvim
```

Ladereihenfolge: util → config → core → features → commands → init

---

## Health-Check

```
:checkhealth diff_nvim
```

---

## Lizenz

MIT

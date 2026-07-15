```
██████╗ ██╗███████╗███████╗
██╔══██╗██║██╔════╝██╔════╝
██║  ██║██║█████╗  █████╗
██║  ██║██║██╔══╝  ██╔══╝
██████╔╝██║██║     ██║
╚═════╝ ╚═╝╚═╝     ╚═╝
                  .nvim
```

![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-brightgreen?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-blue?logo=lua)
![Status](https://img.shields.io/badge/status-alpha-orange)

> **Pairs well with [pickers.nvim](https://github.com/StefanBartl/pickers.nvim)** —
> diff.nvim's `select_fn` option lets you swap the built-in `vim.ui.select`
> target picker for pickers.nvim's fuzzy picker, so choosing a buffer or file
> to diff against gets fuzzy search instead of a flat list.

Flexible diffing for Neovim — a single `:Diff` command that compares arbitrary
sources (the current buffer, a file, a buffer number, the clipboard) against
each other and delivers the result however you like (side-by-side, inline,
message prompt, file, or clipboard).

Standalone plugin (no `lib.nvim` dependency), cross-platform (Windows + Unix).
All diffing goes through `vim.diff` (libvim) — no shell commands.

---

## Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
  - [Exit scope](#exit-scope)
- [Commands](#commands)
- [Autocommands](#autocommands)
- [Tab completion](#tab-completion)
- [Lua API](#lua-api)
- [Architecture](#architecture)
- [Health check](#health-check)
- [Tests](#tests)
- [Roadmap](#roadmap)

---

## Overview

| Command | Description |
|---|---|
| `:Diff [target=… source=… view=… output=…]` | Compare two sources |
| `:DiffClear` | Close every diff window and leave diffmode |
| `:DiffOrig` | Diff the current buffer against its on-disk saved version |
| `:DiffExit` | Leave diff mode from anywhere (`diffoff!`) |

Omitting `target=` opens an interactive picker (`vim.ui.select`).

---

## Requirements

- Neovim 0.9+
- No external plugins required

---

## Installation

<details open>
<summary><b>lazy.nvim</b></summary>

```lua
{
  "StefanBartl/diff.nvim",
  event = "VeryLazy", -- on_hold/conflict_marks are ambient autocmds, not command-triggered
  cmd = { "Diff", "DiffClear", "DiffOrig", "DiffExit" },
  opts = {},
}
```

Or via `config`:

```lua
{
  "StefanBartl/diff.nvim",
  event = "VeryLazy",
  cmd = { "Diff", "DiffClear", "DiffOrig", "DiffExit" },
  config = function()
    require("diff_nvim").setup({})
  end,
}
```
</details>

<details>
<summary><b>packer.nvim</b></summary>

```lua
use {
  "StefanBartl/diff.nvim",
  event = "VeryLazy",
  cmd = { "Diff", "DiffClear", "DiffOrig", "DiffExit" },
  config = function()
    require("diff_nvim").setup({})
  end,
}
```
</details>

<details>
<summary><b>vim-plug</b></summary>

```vim
Plug 'StefanBartl/diff.nvim'
```

Then, in an `init.lua` sourced later:

```lua
require("diff_nvim").setup({})
```
</details>

---

## Configuration

Full defaults:

```lua
require("diff_nvim").setup({
  features = {
    diff           = true,   -- register :Diff / :DiffClear
    diff_origin    = true,   -- register :DiffOrig
    diff_exit      = true,   -- register :DiffExit + exit keymap
    diff_on_hold   = true,   -- ambient CursorHold line-diff preview
    conflict_marks = true,   -- highlight <<<<<<< / ======= / >>>>>>> markers
  },
  diff = {
    default_view      = "vsplit",    -- "vsplit"|"split"|"inline"
    default_output    = "buffer",    -- "buffer"|"prompt"|"file"|"clipboard"
    default_source    = "current",   -- "current"|"clipboard"|path|bufnr
    default_orig_view = "vsplit",    -- "vsplit"|"split" — split direction for :DiffOrig
    algorithm         = "histogram", -- vim.diff algorithm
    ctxlen            = 3,           -- context lines per hunk
  },
  exit = {
    key   = "<Esc><Esc>",         -- exit mapping
    scope = "buffer",             -- "buffer"|"global"|false
  },
  commands = {
    diff       = "Diff",
    diff_clear = "DiffClear",
    diff_orig  = "DiffOrig",
    diff_exit  = "DiffExit",
  },
  on_hold = {
    modes                 = "n",             -- "n"|"v"|"i" (any combination) or array; nil = n+v
    delay                 = 3000,             -- extra debounce (ms) beyond 'updatetime'
    throttle_ms           = 1200,             -- min time (ms) between triggers per window
    git_cmd               = "git",
    ignore_buftypes       = { "nofile", "prompt", "terminal" },
    only_tracked          = true,             -- skip files not tracked by git
    require_clean_buffer  = false,            -- skip if buffer has unsaved changes
    prefix                = "previous: ",     -- prefix before fallback EOL preview text
    right_align           = false,            -- place virt_text right-aligned instead of eol
    max_len               = 160,              -- truncate fallback preview to this many characters
    hl_prev               = "Comment",
    virt_priority         = 1000,
    prefer_inline         = true,             -- prefer gitsigns.preview_hunk_inline() when available
    restore_view          = true,             -- save/restore winsaveview()+cursor to avoid scroll jumps
    events_override       = nil,              -- fully override auto-mapped events
  },
  conflict_marks = {
    hl_a = "DiffDelete",  -- highlight group for "<<<<<<<" lines
    hl_b = "DiffChange",  -- highlight group for "=======" separator
    hl_c = "DiffAdd",     -- highlight group for ">>>>>>>" lines
  },
  select_fn = nil,                -- optional vim.ui.select replacement (DI)
})
```

`diff.default_orig_view` is split off from `default_view` because `:DiffOrig`
always opens a native diffmode split — it never supports `"inline"`.

`on_hold` and `conflict_marks` are ambient autocmd-driven features, toggled
solely via `features.diff_on_hold` / `features.conflict_marks` (set to `false`
to disable either entirely) — see [Autocommands](#autocommands).

### Exit scope

The original global `<Esc><Esc>` mapping noticeably delayed a plain `<Esc>`
because Neovim had to wait for a possible second key everywhere. diff.nvim
fixes this:

- `scope = "buffer"` (default) — the exit key is bound **buffer-locally**,
  only on buffers `diff.nvim` itself puts into diffmode. No global delay.
- `scope = "global"` — legacy behaviour (global normal-mode mapping).
- `scope = false` — no keymap at all; `:DiffExit` only.

`:DiffExit` always works, regardless of scope. All keymaps carry a `desc`, so
[which-key.nvim](https://github.com/folke/which-key.nvim) (if installed) shows
them out of the box — no extra wiring needed.

---

## Commands

### `:Diff [target=…] [source=…] [view=…] [output=…]`

Compares a **source** (left) with a **target** (right). Arguments use a
`key=value` grammar, in any order; unknown keys are ignored.

**`target=`** (the "other" material)

| Value | Meaning |
|---|---|
| `clipboard` | Content from the system clipboard (`+`) |
| `{path}` | A file (tab-completed) |
| `{number}` | An already-open buffer number |

When `target=` is omitted, an interactive picker is shown.

**`source=`** (default: `current`)

| Value | Meaning |
|---|---|
| `current` | The buffer active when `:Diff` was invoked (default) |
| `clipboard` | System clipboard |
| `{path}` / `{number}` | A file or buffer |

**`view=`** (only for `output=buffer`, default: `vsplit`)

| Value | Layout |
|---|---|
| `vsplit` | Vertical split + native diffmode (side-by-side) |
| `split` | Horizontal split + native diffmode |
| `inline` | Single scratch buffer holding the unified diff (`ft=diff`) |

**`output=`** (default: `buffer`)

| Value | Delivery |
|---|---|
| `buffer` | Interactive diff in a split (see `view`) |
| `prompt` | Unified diff echoed to the message area |
| `file` | Unified diff written to a temp file |
| `clipboard` | Unified diff copied to the clipboard (`+`) |

**Examples**

```vim
:Diff                                  " interactive target picker
:Diff target=clipboard                 " current buffer vs. clipboard
:Diff target=42                        " current buffer vs. buffer 42
:Diff target=src/old.lua               " current buffer vs. a file
:Diff target=clipboard output=prompt   " unified diff in the message area
:Diff target=clipboard view=inline     " unified diff in a single buffer
:Diff target=a.lua source=b.lua        " compare two files
:Diff target=clipboard output=clipboard " diff to the clipboard
```

### `:DiffClear`

Closes every scratch buffer diff.nvim created and disables diffmode in every
window.

### `:DiffOrig`

Diffs the current buffer against its last-saved version on disk — "what
changed since the last save". The snapshot buffer is tracked and cleaned up by
`:DiffClear`.

### `:DiffExit`

Leaves diff mode from anywhere (`diffoff!`).

---

## Autocommands

Both are ambient — no command to run, they just work in the background once
enabled (default: both `true`).

### `diff_on_hold`

On `CursorHold`/`CursorHoldI`, previews what changed on the current line:
prefers gitsigns' inline hunk preview when available, otherwise falls back to
showing the previous committed content of the line as virtual text (via
`git blame`/`git show`, argv-only — no shell). Per-window throttled, mode-aware
(`on_hold.modes`), and cleared on the next cursor move. Sets
`vim.o.updatetime = 100` when enabled, matching the responsiveness the fallback
preview needs.

Disable: `features.diff_on_hold = false`.

### `conflict_marks`

On `BufWinEnter`/`BufWinLeave`, highlights unresolved Git conflict markers
(`<<<<<<<`, `=======`, `>>>>>>>`) using `matchadd`/`matchdelete`, scoped
per-window.

Disable: `features.conflict_marks = false`.

---

## Tab completion

`:Diff` completes the `key=value` grammar context-sensitively:

```
:Diff <Tab>            → target=  source=  view=  output=
:Diff view=<Tab>       → view=vsplit  view=split  view=inline
:Diff output=<Tab>     → output=buffer  output=prompt  output=file  output=clipboard
:Diff source=<Tab>     → source=current  source=clipboard
:Diff target=<Tab>     → target=clipboard  (+ file paths)
```

---

## Lua API

```lua
local diff = require("diff_nvim")

diff.setup(opts)        -- configure + activate (idempotent)
diff.enable(opts)       -- alias for setup() (compat with custom.diff)
diff.run("target=…")    -- equivalent to :Diff …
diff.clear()            -- equivalent to :DiffClear
diff.diff_origin()      -- equivalent to :DiffOrig
diff.exit()             -- equivalent to :DiffExit
```

---

## Architecture

```
plugin/diff_nvim.lua         Load guard
lua/diff_nvim/
  init.lua                   Public API, setup()/enable()
  @types.lua                 LuaLS type definitions
  config/
    DEFAULTS.lua             Immutable default configuration
    init.lua                 Merge + access to active config
  util/
    notify.lua               "[diff] " prefixed vim.notify wrapper
    validate.lua              Pure validation helpers (is_one_of, *_valid)
  core/
    init.lua                 Orchestration: run(), execute(), target picker
    resolve.lua               Specifier → lines, argument parsing
    scratch.lua                Scratch-buffer lifecycle + cleanup_all()
    render.lua                 Output renderers (buffer/prompt/file/clipboard)
  features/
    origin.lua                :DiffOrig logic
    exit.lua                    :DiffExit logic + exit-behaviour config
    on_hold.lua                   Ambient CursorHold line-diff preview
    conflict_marks.lua              Conflict-marker highlighting
  bindings/
    usrcmds.lua                 :Diff/:DiffClear/:DiffOrig/:DiffExit registration + completion
    keymaps.lua                  Exit-keymap wiring (global + buffer-local)
    autocmds.lua                   VimLeavePre cleanup + on_hold/conflict_marks setup
    init.lua                       Orchestrates the three above
  health.lua                  :checkhealth diff_nvim
```

Load order: util → config → core → features → bindings → init

Every keymap, user command, and autocmd is also cataloged in
[docs/BINDINGS.md](docs/BINDINGS.md).

---

## Health check

```
:checkhealth diff_nvim
```

---

## Tests

Headless spec suite covering config merge, argument parsing, and validation
helpers — see [docs/TESTS/README.md](docs/TESTS/README.md).

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
```

---

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) — planned: git revisions as a
target/source, visual-range diffing, diff statistics, word-level inline
highlighting, and more.

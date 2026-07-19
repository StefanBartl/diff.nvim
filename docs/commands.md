# Commands

## `:[range]Diff [target=…] [source=…] [view=…] [output=…]`

Compares a **source** (left) with a **target** (right). Arguments use a
`key=value` grammar, in any order; unknown keys are ignored.

When invoked with a **range** (e.g. a visual selection, `:'<,'>Diff`) and
`source=current` (the default), only the selected lines are used as the
source instead of the whole buffer. The range applies to the source side
only — the target is always taken in full.

**`target=`** (the "other" material)

| Value | Meaning |
|---|---|
| `clipboard` | Content from the system clipboard (`+`) |
| `ask` | Force the interactive picker (same as omitting `target=`) |
| `{path}` | A file (tab-completed) |
| `{number}` | An already-open buffer number |

When `target=` is omitted, an interactive picker is shown.

**`source=`** (default: `current`)

| Value | Meaning |
|---|---|
| `current` | The buffer active when `:Diff` was invoked (default) |
| `clipboard` | System clipboard |
| `ask` | Force the interactive picker (also offers "current buffer") |
| `{path}` / `{number}` | A file or buffer |

**`view=`** (only for `output=buffer`, default: `vsplit`)

| Value | Layout |
|---|---|
| `vsplit` | Vertical split + native diffmode (side-by-side) |
| `split` | Horizontal split + native diffmode |
| `tab` | Side-by-side native diffmode in a new tab |
| `inline` | Single scratch buffer holding the unified diff (`ft=diff`) |
| `float` | Unified diff in a floating window (press `q` or `<Esc>` to close) |

**`output=`** (default: `buffer`)

| Value | Delivery |
|---|---|
| `buffer` | Interactive diff in a split (see `view`) |
| `prompt` | Unified diff echoed to the message area |
| `file` | Unified diff written to a temp file |
| `clipboard` | Unified diff copied to the clipboard (`+`) |
| `stat` | Report `+N -M, K hunks` as a notification only (no window) |

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
:Diff target=src/old.lua output=stat   " just the +N -M, K hunks summary
:'<,'>Diff target=clipboard            " compare only the selection vs. clipboard
:Diff target=clipboard view=float      " unified diff in a floating window
:Diff target=a.lua view=tab            " side-by-side diff in a new tab
```

## `:DiffClear`

Closes every scratch buffer diff.nvim created and disables diffmode in every
window.

## `:DiffOrig`

Diffs the current buffer against its last-saved version on disk — "what
changed since the last save". The snapshot buffer is tracked and cleaned up by
`:DiffClear`.

## `:DiffExit`

Leaves diff mode from anywhere (`diffoff!`).

## Tab completion

`:Diff` completes the `key=value` grammar context-sensitively:

```
:Diff <Tab>            → target=  source=  view=  output=
:Diff view=<Tab>       → view=vsplit  view=split  view=tab  view=inline  view=float
:Diff output=<Tab>     → output=buffer  output=prompt  output=file  output=clipboard  output=stat
:Diff source=<Tab>     → source=current  source=clipboard  source=ask
:Diff target=<Tab>     → target=clipboard  target=ask  (+ file paths)
```

# Commands

## `:Diff [target=…] [source=…] [view=…] [output=…]`

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
:Diff view=<Tab>       → view=vsplit  view=split  view=inline
:Diff output=<Tab>     → output=buffer  output=prompt  output=file  output=clipboard
:Diff source=<Tab>     → source=current  source=clipboard
:Diff target=<Tab>     → target=clipboard  (+ file paths)
```

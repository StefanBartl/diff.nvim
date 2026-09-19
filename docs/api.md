# Lua API

```lua
local diff = require("diff")

diff.setup(opts)              -- configure + activate (idempotent)
diff.enable(opts)             -- alias for setup() (compat with custom.diff)
diff.run("target=…", opts)    -- equivalent to :Diff …
diff.clear()                  -- equivalent to :DiffClear
diff.diff_buffers(args, opts) -- equivalent to :DiffBuffers (buffer picker)
diff.diff_origin()            -- equivalent to :DiffOrig
diff.diff_history(args, opts) -- equivalent to :DiffHistory (file-history picker)
diff.exit()                   -- equivalent to :DiffExit
diff.status()                 -- statusline string: "diff:N" while active, "" otherwise
```

`diff.run`, `diff.diff_buffers` and `diff.diff_history` take the same
`key=value` argument string as their commands (see [Commands](commands.md)),
plus an optional table of caller-side options — currently just `on_done`.
`diff.diff_history`'s `args` additionally accepts a leading path, exactly
like `:DiffHistory [path] [view=…] [output=…]`.

## Knowing when a diff has finished: `on_done`

```lua
require("diff").run("source=7 target=8 view=vsplit", {
  on_done = function(result, err)
    if not result then
      -- Nothing was produced: an unresolvable side, a rejected option
      -- combination, or a cancelled picker. `err` says which.
      return
    end
    -- Take the diff back down again. Closing the windows is enough: the
    -- scratch buffers are `bufhidden = "wipe"` and go with them.
    for _, win in ipairs(result.windows) do
      pcall(vim.api.nvim_win_close, win, true)
    end
  end,
})
```

`on_done` is called **exactly once**, on every path. That includes the
asynchronous ones — `http(s)://` fetches, `git:<rev>`, and the interactive
picker — which is why this is a callback rather than a return value from
`run()`: a return value could only ever be filled in for the synchronous
specifiers and would be silently empty for the rest, which is exactly the kind
of "works until it doesn't" surface an integrating plugin cannot build on.

Errors are still notified the way they always were; `on_done` is in addition
to that, not instead of it.

### The result

| Field | |
|---|---|
| `output` | The `output=` that produced this run |
| `view` | The layout that was applied; `nil` when none was — the text outputs, and image/directory comparisons, which ignore `view=` |
| `buffers` | Scratch buffers diff.nvim created |
| `windows` | Windows diff.nvim opened |
| `path` | The file written, for `output=file` (`nil` otherwise) |

**`windows` lists only windows diff.nvim opened.** The window `:Diff` was
invoked from is never included, even when it is part of the diff — with
`source=current` and a side-by-side view, that window keeps the user's live,
editable buffer as the left-hand side. It belongs to the caller, and closing
everything in `windows` must not close the window they were working in.

Both lists can be empty on success: `output=prompt`/`clipboard`/`stat` create
nothing, and two sides that turn out to be identical produce a result with
nothing in it rather than an error. Check `#result.windows`, not `result`, to
decide whether anything is on screen.

"Nothing to show" and "it could not be produced" are kept apart, because they
need opposite handling. A diff that could not be computed, a file that could
not be written, a layout that could not be opened — each of those is `nil`
plus a reason, exactly like an unresolvable side, and never an empty result.

> **A window in `windows` may be showing a buffer that is not yours to
> touch.** `view=tab` opens its own tab and puts the left-hand side in it, so
> with `source=current` one of the two windows shows the user's own live
> buffer. Closing that window is correct and is what `windows` is for;
> deleting the buffer behind it is not, and with unsaved changes it destroys
> the user's work. Close windows, never `nvim_buf_delete` whatever
> `nvim_win_get_buf` hands back.
>
> `buffers` is safe by construction — it only ever lists scratch buffers
> diff.nvim created, never the user's. It is there so a caller can read them
> (their content, name or filetype); it does not have to delete them, because
> they are `bufhidden = "wipe"` and go away with their windows. `:DiffClear`
> also takes down everything diff.nvim is tracking.

### What each mode reports

| Invocation | `buffers` | `windows` |
|---|---|---|
| `output=prompt` / `clipboard` / `stat` | — | — |
| `output=file` | — | — (`path` is set) |
| `view=inline` / `float` | the unified-diff buffer | its window |
| `view=vsplit` / `split`, `source=current` | the target side | the one window opened |
| `view=vsplit` / `split`, explicit `source=` | both sides | both windows |
| `view=tab` | the target side, plus the source side when materialized | both windows in the new tab |
| `base=…` (three-way) | base + target | the two windows opened |
| directory diff, `output=buffer` | the summary buffer | its window |
| two image files | — | — (images.nvim owns what it opened) |

An `on_done` that raises is caught: it is third-party code reached from
diff.nvim's own async callbacks, and an error there must not surface as an
unhandled error inside a URL fetch.

## Statusline component

`diff.status()` returns a short indicator string while a diff.nvim diff is
active (default `diff:N`, where `N` is the number of active scratch buffers),
or `""` when none is. `opts.prefix` overrides the `diff:` prefix.

```lua
-- native statusline
vim.o.statusline = "%f %{v:lua.require'diff'.status()}"

-- lualine
require("lualine").setup({
  sections = { lualine_x = { function() return require("diff").status() end } },
})
```

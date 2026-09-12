# Quickstart

Run `:Diff` with no arguments and pick what to compare against — that is the
whole plugin in one command:

```vim
:Diff
```

Then, once you know what you want, say it directly:

```vim
:Diff target=clipboard                     " current buffer vs. the clipboard
:Diff target=src/old.lua                   " current buffer vs. a file
:Diff target=git:HEAD                      " current file vs. its last commit
:Diff target=clipboard output=stat         " just the +N -M, K hunks summary
:'<,'>Diff target=clipboard                " compare only the Visual selection
:Diff target=https://example.com/f.lua     " vs. a URL, fetched asynchronously
:Diff target=git:MERGE_HEAD base=git:HEAD  " three-way merge-conflict view
:Diff source=./old_src target=./new_src output=stat  " directory diff
```

Verify your setup any time with:

```vim
:checkhealth diff
```

The full argument grammar is [Commands](commands.md); which combination fits
which everyday situation is [Workflow](WORKFLOW.md).

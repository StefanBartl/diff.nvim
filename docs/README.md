# diff.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be there first, and a spec per plugin manager |
| [configuration.md](configuration.md) | Every option, with the full defaults printed out |
| [testing.md](testing.md) | What `:checkhealth` asks, and how to run the suite |

## Using it

| Page | Answers |
| --- | --- |
| [commands.md](commands.md) | `:[range]Diff` argument by argument — `target=`, `source=`, `base=`, `view=`, `output=` — and what each combination opens |
| [three-way-diff.md](three-way-diff.md) | What `base=` adds: a third side, in a native three-window diff, and when that is the one you want |
| [url-sources.md](url-sources.md) | Diffing against an `http(s)` URL — what is fetched, and what the content type decides |
| [BINDINGS.md](BINDINGS.md) | Every keymap, user command and autocommand this plugin registers |
| [api.md](api.md) | Every Lua function a config or another plugin can call |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each argument does, but which shape of `:Diff` answers which everyday question |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [FEATURES.md](FEATURES.md) | Everything this plugin does, in one file — deliberately one file, because it is a small single-purpose plugin |
| [architecture.md](architecture.md) | Which module does what |

## Here, but not prose

**`install.json`** declares the external tools this plugin can use,
machine-readably, for `:Lib deps show diff.nvim`.

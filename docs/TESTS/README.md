# Tests

Headless spec suite for diff.nvim. Covers the pure / buffer-level logic that
is trivially testable without a UI.

## Run

From the repo root:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
```

The runner prints one line per spec and exits non-zero on the first failure
(`DIFF_NVIM_TESTS_OK` on success).

## Layout

| File               | Covers                                                          |
| ------------------ | ---------------------------------------------------------------- |
| `harness.lua`      | Shared `eq`/`ok` assertions and a `scratch(ft)` buffer helper.    |
| `config_spec.lua`  | Config defaults + deep-merge of user options.                    |
| `resolve_spec.lua` | `parse_args` grammar + `resolve_lines` for clipboard/buffer/file. |
| `validate_spec.lua`| `is_one_of` / `buf_valid` / `win_valid`.                          |
| `run.lua`          | Runner: loads every spec, reports results, sets the exit code.   |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.scratch`) and add its filename to the `specs` list in `run.lua`.

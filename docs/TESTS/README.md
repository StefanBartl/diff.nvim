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
| `render_spec.lua`  | `compute_stats` / `format_stats` (the `output=stat` summary).     |
| `git_spec.lua`     | `is_git_spec` + live `git:HEAD` resolution against this repo.     |
| `status_spec.lua`  | `scratch.active_count` + `diff.status` statusline string.    |
| `pickers_bridge_spec.lua` | `pickers_bridge.resolve()` nil-fallback (absent / no engine).|
| `native_diffthis_spec.lua` | `native_diffthis.sync()` attach/detach logic + `register()` gating. |
| `url_spec.lua`     | `is_url_spec` + `fetch()` guard clauses; best-effort live round-trip (skipped, not failed, without network). |
| `three_way_spec.lua` | `render.three_way()` layout (vsplit/tab/invalid window) + `core.run()`'s `base=` validation and end-to-end wiring. |
| `run.lua`          | Runner: loads every spec, reports results, sets the exit code.   |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.scratch`) and add its filename to the `specs` list in `run.lua`.

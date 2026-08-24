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
| `harness.lua`      | Shared `eq`/`ok` assertions, a `scratch(ft)` buffer helper, and `tmpdir()`/`write_file()`. |
| `config_spec.lua`  | Config defaults + deep-merge of user options.                    |
| `resolve_spec.lua` | `parse_args` grammar, `resolve_lines` for clipboard/buffer/file, `split_git_range`. |
| `validate_spec.lua`| `is_one_of` / `buf_valid` / `win_valid`.                          |
| `render_spec.lua`  | `compute_stats`/`format_stats` (`output=stat`), UTF-8 codepoint-aware word-diff highlighting, `compute_hunks`/`push_stat_list` (qf/loc). |
| `git_spec.lua`     | `is_git_spec` + live `git:HEAD` resolution against this repo, plus an end-to-end `target=git:<rev1>..<rev2>` check. |
| `status_spec.lua`  | `scratch.active_count` + `diff.status` statusline string.    |
| `pickers_bridge_spec.lua` | `pickers_bridge.resolve()` nil-fallback (absent / no engine).|
| `pick_specifier_spec.lua` | `pick_specifier`'s default fallback renders via `kit.confirm` (≤4 choices), and a configured `select_fn` still takes precedence. |
| `native_diffthis_spec.lua` | `native_diffthis.sync()` attach/detach logic + `register()` gating. |
| `keymaps_spec.lua` | `bindings.keymaps`: `exit.key` as a list (both keys bound, both removed again by `detach_buffer` — which used to delete `cfg.key` directly and so removed nothing once it could be a list), a plain string still working, empty/non-string keys binding nothing, and `scope` gating. Then `register_shortcuts`: an empty table binding nothing, each of the six shortcuts producing the right `<Cmd>…<CR>` rhs, the rhs following a renamed command rather than hardcoding `Diff`, a shortcut being refused when its `features` gate is off, and unknown/false/empty entries binding nothing. |
| `url_spec.lua`     | `is_url_spec` + `fetch()` guard clauses; best-effort live round-trip (skipped, not failed, without network). |
| `three_way_spec.lua` | `render.three_way()` layout (vsplit/tab/invalid window) + `core.run()`'s `base=` validation and end-to-end wiring. |
| `image_compare_spec.lua` | `image_compare.maybe_compare()` extension detection + images.nvim-absent warning path. |
| `directory_spec.lua` | `core.directory`: `is_directory_spec`, per-file M/A/D summary across `output=` values, hidden-segment exclusion, `directory_max_files`, `stat_list` integration. |
| `run.lua`          | Runner: loads every spec, reports results, sets the exit code.   |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.scratch` / `H.tmpdir` / `H.write_file`) and add its filename to the
`specs` list in `run.lua`.

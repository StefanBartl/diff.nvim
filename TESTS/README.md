# Tests

Headless spec suite for diff.nvim. Covers the pure / buffer-level logic that
is trivially testable without a UI.

## Run

From the repo root:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile TESTS/run.lua" -c "qa!"
```

The runner prints one line per spec and exits non-zero on the first failure
(`DIFF_NVIM_TESTS_OK` on success).

`TESTS/run.lua` puts lib.nvim (a runtime dependency) on the runtimepath: a
sibling checkout wins over the plugin-manager copy, and `$LIB_NVIM_PATH`
overrides both — that is what CI sets. It also installs an in-memory fake
clipboard provider, so `"+"` behaves like a real register on a bare runner
with no xclip/xsel/wl-clipboard/pbcopy.

## Layout

| File               | Covers                                                          |
| ------------------ | ---------------------------------------------------------------- |
| `harness.lua`      | Shared `eq`/`ok` assertions, a `scratch(ft)` buffer helper, `tmpdir()`/`write_file()`, and `canonical()` for comparing paths across platforms. |
| `config_spec.lua`  | Config defaults + deep-merge of user options.                    |
| `resolve_spec.lua` | `parse_args` grammar, `resolve_lines` for clipboard/buffer/file, `split_git_range`, `split_lines`. |
| `validate_spec.lua`| `is_one_of` / `buf_valid` / `win_valid`.                          |
| `render_spec.lua`  | `compute_stats`/`format_stats` (`output=stat`), UTF-8 codepoint-aware word-diff highlighting, `compute_hunks`/`push_stat_list` (qf/loc). |
| `render_edge_spec.lua` | The other half of every renderer: the `diff failed` arm and the "No differences found" arm of `stat`/`prompt`/`file`/`clipboard`/`inline`, the exact two-line header each text output writes, `M.file` surviving an unwritable destination (its own message, not a raw `E482`), `push_stat_list` with nothing to push, `list="off"`/`list="loc"`, `format_stats` pluralisation, the count-omitted `@@ -N +N @@` spelling, and the two cases that must produce no word-diff extmarks (an unbalanced `-`/`+` run, `word_diff = false`). |
| `git_spec.lua`     | `is_git_spec` + live `git:HEAD` resolution against this repo, plus an end-to-end `target=git:<rev1>..<rev2>` check. |
| `git_argv_spec.lua`| `core.git` with `vim.system` replaced: the **argv** `git show` would have been given (`git -C <root> show <rev>:<path>`, five elements, `text = true`), forward slashes only in both path-bearing elements, a path with spaces staying one unquoted element, a full refspec surviving the `git:` strip, a `.git` *file* (worktree/submodule) counting as a repo root, and — on Windows — a backslash-spelled buffer name reaching byte-identical argv. Then every branch around the spawn: non-zero exit with and without stderr, empty stdout, CRLF stdout, a throwing spawn, and all six guard clauses (each asserted to report *before* anything is spawned). |
| `status_spec.lua`  | `scratch.active_count` + `diff.status` statusline string.    |
| `scratch_spec.lua` | The scratch registry directly: `create`'s buffer options and duplicate-name tolerance, `discard` (including twice, and on an untracked handle), `cleanup_all` on a *displayed* buffer (the E937 shape) and its wipe count, stray-diffmode teardown, `wipe_on_exit` leaving diffmode alone, and `track`'s accept/refuse rules — plus the duplicate-tracking bug pinned below. |
| `pickers_bridge_spec.lua` | `pickers_bridge.resolve()` nil-fallback (absent / no engine).|
| `pick_specifier_spec.lua` | `pick_specifier`'s default fallback renders via `kit.confirm` (≤4 choices), and a configured `select_fn` still takes precedence. |
| `prompt_file_spec.lua` | `prompt_file` via `ui.kit.input`: a submitted path, a cancel, and an empty submit. |
| `run_buffers_spec.lua` | `:DiffBuffers` end to end: the "no other listed buffers" refusal, unlisted/unloaded buffers never becoming candidates, the candidate labels (path vs `[No Name]`, never the buffer you are diffing *from*), the chosen label mapping back to its buffer number, a cancel, an invalid `view=`/`output=` refused before the picker is built, and the `kit.select` fallback including its `on_cancel` → `nil` translation. Then `prompt_buffer` (valid number, non-numeric answer, cancel) and the pickers.nvim adapter itself against a fake `pickers.engines`: item→index mapping, an unknown item, an explicit nil, the default prompt, and a throwing `pick_item` falling back to `vim.ui.select`. |
| `native_diffthis_spec.lua` | `native_diffthis.sync()` attach/detach logic + `register()` gating. |
| `keymaps_spec.lua` | `bindings.keymaps`: `exit.key` as a list (both keys bound, both removed again by `detach_buffer` — which used to delete `cfg.key` directly and so removed nothing once it could be a list), a plain string still working, empty/non-string keys binding nothing, and `scope` gating. Then `register_shortcuts`: an empty table binding nothing, each of the six shortcuts producing the right `<Cmd>…<CR>` rhs, the rhs following a renamed command rather than hardcoding `Diff`, a shortcut being refused when its `features` gate is off, and unknown/false/empty entries binding nothing. |
| `bindings_spec.lua`| The wiring layer, driven through the real `:` command line: all five commands registered by default, each `features.*` gate dropping only its own commands, configurable command names, `:Diff` forwarding a *typed* range but never the cursor line, `:DiffBuffers`/`:DiffClear`/`:DiffOrig`/`:DiffExit` reaching their targets, `usrcmds.register` being re-runnable, `autocmds.register` installing exactly one `VimLeavePre` autocmd and staying at one across re-registrations (with the event fired for real), and `bindings.register`'s full orchestration including the `features.diff_exit = false` path. |
| `url_spec.lua`     | `is_url_spec` + `fetch()` guard clauses; best-effort live round-trip (skipped, not failed, without network). |
| `url_stub_spec.lua`| `core.url` with `vim.system` replaced: curl's **argv** (`--silent`/`--show-error`/`--fail`/`--location`, `--max-filesize` carrying the configured `max_bytes`, the URL last and unquoted), the 10 MiB default for a junk `opts`, CRLF normalisation, the distinct messages for exit 63 / an exit with stderr / an exit without, the libuv timeout killing the process and naming its own budget, curl's late callback after a timeout being swallowed rather than delivered as a second result, and a throwing spawn. No network. |
| `three_way_spec.lua` | `render.three_way()` layout (vsplit/tab/invalid window) + `core.run()`'s `base=` validation and end-to-end wiring. |
| `side_by_side_spec.lua` | `view=vsplit`/`split`/`tab` honouring `source=`/a range on the left-hand side (and still using the live origin buffer for plain `source=current`), diffmode staying window-local, a failed render discarding its scratch buffers, `base=` rejecting an explicit `source=`, and side labels: a buffer number resolving to the buffer's name (`buf:N` when unnamed) and a label with newlines never growing the two-line diff header. |
| `on_done_spec.lua` | The `on_done` completion contract: fires exactly once on every path (including failures, rejected combinations and identical sides), `result.windows` never containing the caller's own window, the reported handles being enough to take the diff back down, and a throwing `on_done` not propagating. |
| `image_compare_spec.lua` | `image_compare.maybe_compare()` extension detection, the images.nvim-absent warning path, and — against a double in `package.loaded` — the handoff contract itself: `images.gallery({expanded_a, expanded_b}, 2)`, a case-insensitive extension match, and an `images` without `gallery()` falling back to the warning instead of erroring. |
| `origin_spec.lua`  | `:DiffOrig`: both refusals (an unnamed buffer, a file not on disk yet) tracking nothing, the happy path (one new window, both in diffmode, cursor left in the working buffer, the snapshot holding the *saved* lines, read-only, labelled and tracked), `default_orig_view = "split"` splitting horizontally and an unrecognised value falling back to vsplit, the buffer-local exit key landing on the snapshot, and two invocations being torn down by a single `:DiffClear`. |
| `directory_spec.lua` | `core.directory`: `is_directory_spec`, per-file M/A/D summary across `output=` values, hidden-segment exclusion, `directory_max_files`, `stat_list` integration. |
| `directory_edge_spec.lua` | Hidden segments excluded at *every* depth (not just the top), quickfix entries actually resolving to readable files — with a `D` entry pointing into the source tree, the only side that still has the file, `stat_list_mode = "add"` accumulating, an empty result being a result and not an error, `output=prompt` opening nothing, the end-to-end route through `core.run`, and the unreadable-file bug pinned below. |
| `public_api_spec.lua` | `lua/diff/init.lua` and the last of `core.init`: `core.valid_lists`, the `view=`/`output=` rejection messages, `core.clear` (including twice), `features.exit.exit()` in all three states, `attach_buffer()` before `setup()`, `view=float` (a real floating window, ft=diff, reversible from the reported handles), what `output=stat` puts in the quickfix list for a file / a buffer number / a clipboard target, the five delegating wrappers, `status()`'s prefix edge cases, and `setup()`/`enable()`'s once-only latch. |
| `health_spec.lua`  | `:checkhealth diff` against a recording `vim.health`, with each probe faked one at a time: a full machine, an unset `vim.g.loaded_diff`, no diff primitive, no `vim.ui.select`, no clipboard, Neovim < 0.9, git/curl off PATH, no `vim.system` at all (both checks must blame `vim.system`, not the binaries), and pickers.nvim present vs absent — plus the lib.nvim-missing bug pinned below. |
| `run.lua`          | Runner: bootstraps lib.nvim and the fake clipboard, loads every spec, reports results, sets the exit code. |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.scratch` / `H.tmpdir` / `H.write_file`) and add its filename to the
`specs` list in `run.lua`.

Comparing two paths needs `H.canonical` on **both** sides, never
`vim.fs.normalize` alone. Normalizing rewrites separators but not symlinks,
and the runners disagree about which spelling reaches a buffer name: macOS
resolves `/var/folders/…` (what `tempname()` returns) to `/private/var/…`,
Windows leaves junctions and `RUNNER~1` short names as it found them.
`H.canonical` puts every spelling of one file onto the same one.

Specs share one Neovim process and run in the listed order, so a spec that
changes global state (config, commands, keymaps, `package.loaded`, the current
window layout) restores it before returning. `public_api_spec.lua` runs late on
purpose: `diff.setup()` latches a module-local guard that cannot be undone.

## No subprocesses, no network — with one deliberate exception

Every process this plugin can spawn is cut at a seam that is replaced *before*
the module under test is required, because these modules bind their
dependencies at load time and a late field patch would be too late:

| Real process | Seam | Spec |
| --- | --- | --- |
| `git show` | `vim.system`, plus `vim.fn.executable` | `git_argv_spec.lua` |
| `curl` | `vim.system`, plus `vim.fn.executable` | `url_stub_spec.lua` |
| a fuzzy-picker backend | `package.loaded["pickers.engines"]` | `run_buffers_spec.lua` |
| `ui.kit`'s input/select/confirm | `package.loaded["ui.kit"]`, `package.loaded["ui.kit.confirm"]` | `prompt_file_spec.lua`, `pick_specifier_spec.lua`, `run_buffers_spec.lua` |
| images.nvim's gallery | `package.loaded["images"]` | `image_compare_spec.lua` |
| an unreadable file | `vim.fn.readfile` | `directory_edge_spec.lua` |

The exception is `git_spec.lua` and `url_spec.lua`, which were here first:
`git_spec` runs a **real `git show`** against this repository's own history
(skipped when git is unavailable), and `url_spec` attempts one **real HTTPS
round-trip** to raw.githubusercontent.com, skipped rather than failed when
there is no network. They are kept because an end-to-end check against the real
tool is worth having; `git_argv_spec`/`url_stub_spec` exist so that everything
those two can only assert when the environment cooperates is also asserted when
it does not.

## Coverage

Every file under `lua/` has assertion-backed coverage except the ones listed
under "Deliberately not covered" below.

- **Core** — `core/init.lua` (dispatch, the three-way path, labelling,
  `stat_list_target`, `run_buffers`, both interactive prompts, `clear`,
  `valid_lists`, view/output validation), `core/resolve.lua`,
  `core/render.lua`, `core/scratch.lua`, `core/directory.lua`,
  `core/git.lua`, `core/url.lua`, `core/pickers_bridge.lua`.
- **Features** — `features/exit.lua`, `features/origin.lua`,
  `features/native_diffthis.lua`, `features/image_compare.lua`.
- **Wiring** — `bindings/init.lua`, `bindings/usrcmds.lua`,
  `bindings/keymaps.lua`, `bindings/autocmds.lua`.
- **Rest** — `init.lua`, `config/init.lua`, `util/validate.lua`,
  `util/diffmode.lua`, `health.lua`.

### Deliberately not covered

- `lua/diff/@types.lua` — `---@class`/`---@alias` annotations only, no runtime
  code to exercise.
- `lua/diff/config/DEFAULTS.lua` — a declarative table with no branches. Every
  value in it is asserted indirectly, through `config_spec.lua` and through
  each feature's own default-path test.
- `lua/diff/util/notify.lua` — one line, re-exporting `lib.nvim.notify`'s
  prefixed surface. Every spec that captures notifications drives it.
- `lua/diff/plugin/` (`plugin/diff.lua`) — a load guard, and not sourced at all
  under `-u NONE`.
- The actual pixels: `render.open_float`'s geometry arithmetic against a real
  terminal size, and images.nvim's gallery rendering. The *decisions* around
  both are covered (`view=float` really opens a `relative = "editor"` window;
  the gallery gets both expanded paths and two columns).
- The real `git show`/`curl` invocations beyond the two end-to-end checks
  described above — every branch around them is covered against a double.
- `core/git.lua`'s "file is outside the git repo root" guard. It is defensive:
  the root is derived from the file's own path by walking upward, so the two
  cannot disagree in any way reachable from Lua. Every other guard in that
  function *is* covered.

### Bugs found in this round

Three defects came out of writing it. The third is **fixed**, its assertion in
`health_spec.lua` turned into a regression guard; the other two are pinned with
`BUG:`-marked assertions rather than fixed, so the suite fails the day that
behaviour changes.

1. **`core/directory.lua` — an unreadable file escapes as a raw `E484`**
   (`directory_edge_spec.lua`). `list_files` walks the tree, then `diff_trees`
   reads every entry with a bare `fn.readfile`. Anything that makes a listed
   file unreadable between those two steps — a build directory being rewritten,
   a branch switch mid-walk, a lock or permission problem, another process
   removing a file — throws straight out of `directory.run`, past its own
   `notify.error(...)` / `return nil, err` contract, and out of
   `core.execute`. The user gets Vim's `E484: Can't open file …` instead of
   "could not diff directories", and because the throw unwinds the whole call,
   the caller's `on_done` never fires at all. The `pcall(fn.writefile, …)`
   twelve lines below it in the same module guards against exactly this class,
   and so does the `pcall` around `render.side_by_side`'s `split_into`, added
   for precisely this reason ("an error would escape `core.execute` and take
   every cleanup path with it"). The directory dispatch is the one route into
   `core.execute` that still has it.

2. **`core/scratch.lua` — `track()` does not deduplicate**
   (`scratch_spec.lua`). Adopting a buffer that is already tracked parks a
   second entry for the same handle. `active_count()` counts entries, not
   distinct buffers, and that count is what `diff.status()` prints — so one
   diff can report `diff:3`. `cleanup_all()`/`wipe_on_exit()` are unaffected
   (they re-check validity per entry). Nothing in `lua/` calls `track()`
   today, which is why it has stayed invisible; it is a documented public
   entry point "for buffers it did not itself create", so an integrating
   plugin reaches it first.

3. **`health.lua` — the lib.nvim-missing branch could not survive lib.nvim
   being missing** (`health_spec.lua`) — **fixed.** `check()` diagnoses an
   absent lib.nvim correctly and reports it as an error with an install hint,
   and used to end unconditionally with
   `require("lib.nvim.bindings.usercmd.composer").checkhealth("Diff")`. When
   lib.nvim really was absent that require threw, so `:checkhealth diff`
   aborted partway through and the user never saw the diagnosis.
   `lib.nvim.deps.health`, two lines earlier, was already `pcall`'d for
   precisely this reason; the last line is now too.

### Verified, not assumed

Two Windows path questions that broke sibling plugins in this family were
checked empirically here and turned out **correct**, so they are pinned rather
than left to chance:

- `core/git.lua` normalises with `vim.fs.normalize`, which on Windows folds
  backslashes to `/` *and* upper-cases the drive letter — so the repo root and
  the buffer's absolute path agree, and git receives forward slashes in both
  `-C <root>` and `<rev>:<path>`. `git_argv_spec.lua` asserts both, and on
  Windows additionally asserts that a backslash-spelled buffer name yields
  byte-identical argv.
- `core/directory.lua`'s `has_hidden_segment` tests for `^%.` or `/%.`, which
  only works because `vim.fs.dir` yields forward-slash relative names on every
  platform, Windows included. `directory_edge_spec.lua` pins it at depth: a
  wrong answer here is a summary full of `.git` internals, not an error.

---@meta
---@module 'diff.@types'
--- Type definitions for diff.nvim.
---
--- Central type catalog so the source files stay free of long annotation blocks.
--- All `@types` modules return an empty table.

-- #####################################################################
-- core / command surface
-- #####################################################################

---@alias DiffNvim.Target
--- The right-hand side of the comparison (the "other" content). See docs/url-sources.md for `http(s)://` requirements and examples.
---| '"clipboard"'  # Pull content from the system clipboard register (+)
---| '"ask"'        # Force the interactive picker even if a default exists
---| string         # File path, buffer number, `git:<rev>`, or `http(s)://…` (fetched async via curl)
---| integer        # An already-open buffer number

---@alias DiffNvim.Source
--- The left-hand side of the comparison. See docs/url-sources.md for `http(s)://` requirements and examples.
---| '"current"'    # The buffer active when :Diff was invoked (default)
---| '"clipboard"'  # System clipboard register (+)
---| '"ask"'        # Force the interactive picker even if a default exists
---| string         # File path, `git:<rev>`, or `http(s)://…` (fetched async via curl)
---| integer        # Buffer number

---@alias DiffNvim.View
--- How a `output="buffer"` diff is laid out on screen.
---| '"vsplit"'     # Side-by-side vertical split + native diffmode (default)
---| '"split"'      # Horizontal split + native diffmode
---| '"tab"'        # Side-by-side native diffmode in a new tab
---| '"inline"'     # Single scratch buffer holding the unified diff (ft=diff)
---| '"float"'      # Unified diff (ft=diff) in a floating window

---@alias DiffNvim.Output
--- Where the diff result is delivered.
---| '"buffer"'     # Interactive diff inside a split (see View)
---| '"prompt"'     # Unified-diff text echoed to the message area
---| '"file"'       # Write unified diff to a temp file on disk
---| '"clipboard"'  # Copy unified diff to the system clipboard register (+)
---| '"stat"'       # Report `+N -M, K hunks` as a notification only

---@class DiffNvim.ResolvedOpts
--- Fully-resolved options handed to the core executor.
---@field target DiffNvim.Target
---@field source DiffNvim.Source
---@field base   DiffNvim.Target|nil  Third side for a three-way diff — @see docs/three-way-diff.md
---@field view   DiffNvim.View
---@field output DiffNvim.Output

---@class DiffNvim.Result
--- What a completed diff produced, handed to `DiffNvim.RunOpts.on_done`.
---
--- `buffers`/`windows` list only what diff.nvim itself created, which is what
--- an integrating plugin needs in order to take the diff down again. The
--- origin window is deliberately never in `windows` even when it is part of
--- the diff (`source=current` with a side-by-side view keeps the user's live
--- buffer as the left-hand side): it belongs to the user, and a caller
--- closing everything in `windows` must not close the window they were
--- working in. Both lists are empty when there was nothing to show — a
--- `output=stat` run, or two sides that turned out to be identical. A run
--- that could not produce its output at all is not this: that reports nil
--- plus a reason through `on_done`, never an empty result.
---@field output  DiffNvim.Output   The delivery that produced this run
---@field view    DiffNvim.View|nil The layout applied, nil when none was
---@field buffers integer[]         Scratch buffers diff.nvim created
---@field windows integer[]         Windows diff.nvim opened
---@field path    string|nil        The file written, when `output == "file"`

---@alias DiffNvim.RunOpts.OnDone fun(result: DiffNvim.Result|nil, err: string|nil): nil

---@class DiffNvim.RunOpts
--- Caller-side options for the programmatic entry points, separate from the
--- `key=value` argument string so the command grammar stays untouched.
---@field on_done? DiffNvim.RunOpts.OnDone
--- Called exactly once when the diff has finished, on every path including
--- the asynchronous ones (`http(s)://` fetches, `git:<rev>`, the interactive
--- picker). `result` is nil and `err` carries the reason when nothing was
--- produced — an unresolvable side, a rejected option combination, or a
--- cancelled picker. Errors are notified as before; `on_done` is in addition
--- to that, not instead of it.

---@class DiffNvim.Range
--- A 1-based, inclusive line span from a :Diff invoked with a visual range.
---@field line1 integer  First selected line (1-based)
---@field line2 integer  Last selected line (1-based, inclusive)

---@class DiffNvim.Context
--- Snapshot of the editing context captured the instant :Diff was invoked.
--- Captured eagerly so async pickers cannot let these values drift.
---@field source_bufnr integer         Buffer that was active at invocation
---@field origin_win   integer         Window that was active at invocation
---@field range        DiffNvim.Range|nil  Selected span when :Diff got a range
---@field anchor       string|nil  Overrides `source_bufnr`'s name as the path `git:<rev>` resolution anchors its repo-root lookup on -- for a caller (core/history.lua) that already resolved the right file/root independently of whichever buffer happened to be current, and would otherwise get `source_bufnr`'s (possibly unrelated, possibly unnamed) buffer instead

---@class DiffNvim.HistoryEntry
--- One commit from `core/history.lua`'s `git log --follow` walk of a file.
---@field sha          string  Full commit hash
---@field short        string  Abbreviated commit hash
---@field date         string  Author date, `--date=short` (YYYY-MM-DD)
---@field author       string  Author name
---@field subject      string  First line of the commit message
---@field path         string  The file's path (relative to the repo root) at this commit -- may differ from the current path across a rename `--follow` crossed
---@field parent_path  string  The file's path at the parent commit -- same as `path` outside a rename

-- #####################################################################
-- config
-- #####################################################################

---@alias DiffNvim.DiffProfile
--- A named `diffopt` bundle — @see features/diffopt_profile/profiles.lua.
---| '"minimal"'
---| '"context"'
---| '"review"'
---| '"strict"'

---@class DiffNvim.Config.Features
---@field diff             boolean  Register the :Diff / :DiffClear commands
---@field diff_origin      boolean  Register the :DiffOrig command
---@field diff_exit        boolean  Register the :DiffExit command + exit keymap
---@field diff_history     boolean  Register the :DiffHistory command
---@field diffopt_profile  boolean  Register the :DiffProfile command (cross-feature report finding F1)
---@field gitsigns_peek    boolean  Bind `gh` to gitsigns.nvim's hunk preview (cross-feature report finding F2)

---@class DiffNvim.Config.Diff
---@field default_view      DiffNvim.View    Default layout when none is given
---@field default_output    DiffNvim.Output  Default delivery when none is given
---@field default_source    DiffNvim.Source  Default source when none is given
---@field default_orig_view "vsplit"|"split" Split direction used by :DiffOrig
---@field algorithm         "myers"|"minimal"|"patience"|"histogram"  vim.diff algorithm
---@field ctxlen            integer  Context lines around each hunk in unified output
---@field word_diff         boolean  Word/char-level DiffText highlighting in view=inline/float
---@field url_timeout_ms    integer  Timeout for http(s):// sources/targets in ms — @see docs/url-sources.md
---@field url_max_bytes     integer  Byte cap for http(s):// sources/targets, enforced via curl --max-filesize — @see docs/url-sources.md
---@field image_compare     boolean  Show two raster-image file paths side by side via images.nvim instead of text-diffing their bytes (default true; svg excluded — it's text)
---@field stat_list         "off"|"qf"|"loc"  Also push output=stat's hunks to the quickfix/location list (default "off")
---@field stat_list_mode    "add"|"replace"   "add" accumulates across :Diff invocations (default), "replace" resets the list each time
---@field directory_max_files integer  Cap on files walked per side of a directory diff (default 2000) — see core/directory.lua
---@field history_max_entries integer  Cap on commits `:DiffHistory` walks (`git log --max-count`, default 200) — see core/history.lua
---@field diffopt_profile   DiffNvim.DiffProfile|nil  Apply this profile to 'diffopt' once, at setup() — nil (default) leaves 'diffopt' untouched, diff.nvim's behaviour before this field existed

---@alias DiffNvim.Config.ExitScope
---| '"buffer"'  # Buffer-local mapping on plugin-created diff buffers (default)
---| '"global"'  # Global normal-mode mapping (legacy behaviour)
---| false       # No keymap; :DiffExit command only

---Optional shortcuts for common invocations. All unset by default —
---diff.nvim imposes no mappings. Each value is the lhs to bind.
---@class DiffNvim.Config.Keymaps
---@field diff?         string  `:Diff` (pick source and target)
---@field diff_head?    string  `:Diff target=git:HEAD`
---@field diff_merge?   string  `:Diff base=git:HEAD target=git:MERGE_HEAD`
---@field diff_buffers? string  `:DiffBuffers`
---@field diff_orig?    string  `:DiffOrig` (needs `features.diff_origin`)
---@field diff_history? string  `:DiffHistory` (needs `features.diff_history`)
---@field diff_clear?   string  `:DiffClear`

---@class DiffNvim.Config.Exit
---@field key   string|string[]          Left-hand side(s) of the exit mapping
---@field scope DiffNvim.Config.ExitScope How aggressively the mapping is set
---@field native_diffthis boolean  Also mirror the key onto buffers a native :diffthis puts into diffmode (scope="buffer" only). Off by default — see config/DEFAULTS.lua for the rationale.

---@class DiffNvim.Config.Commands
---@field diff           string  Name of the main diff command
---@field diff_clear     string  Name of the clear command
---@field diff_buffers   string  Name of the buffer-picker diff command
---@field diff_orig      string  Name of the origin command
---@field diff_history   string  Name of the file-history command
---@field diff_exit      string  Name of the exit command
---@field diff_profile   string  Name of the diffopt-profile command

---@class DiffNvim.Config
---@field features  DiffNvim.Config.Features
---@field diff      DiffNvim.Config.Diff
---@field exit      DiffNvim.Config.Exit
---@field keymaps   DiffNvim.Config.Keymaps  Optional shortcuts for common invocations (default: none)
---@field commands  DiffNvim.Config.Commands
---@field select_fn (fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil)|nil  Optional vim.ui.select replacement (dependency injection)
---@field use_pickers_nvim boolean  Auto-detect pickers.nvim as the picker engine when select_fn is unset (default true)

-- #####################################################################
-- setup() input
-- #####################################################################

--- What `setup()` accepts: the same shape as `DiffNvim.Config`, every field
--- optional, nested tables included. `config.setup` merges it over
--- `config/DEFAULTS.lua` and everything downstream reads the resolved
--- `DiffNvim.Config`, which stays strict -- so a partial call is legal
--- without every read of `cfg.diff.ctxlen` turning into a nil check.
---@class DiffNvim.Opts
---@field features?         DiffNvim.Opts.Features
---@field diff?             DiffNvim.Opts.Diff
---@field exit?             DiffNvim.Opts.Exit
---@field keymaps?          DiffNvim.Config.Keymaps  Optional shortcuts for common invocations (default: none)
---@field commands?         DiffNvim.Opts.Commands
---@field select_fn?        (fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil)|nil  Optional vim.ui.select replacement (dependency injection)
---@field use_pickers_nvim? boolean  Auto-detect pickers.nvim as the picker engine when select_fn is unset (default true)

---@class DiffNvim.Opts.Features
---@field diff?             boolean  Register the :Diff / :DiffClear commands
---@field diff_origin?      boolean  Register the :DiffOrig command
---@field diff_exit?        boolean  Register the :DiffExit command + exit keymap
---@field diff_history?     boolean  Register the :DiffHistory command
---@field diffopt_profile?  boolean  Register the :DiffProfile command
---@field gitsigns_peek?    boolean  Bind `gh` to gitsigns.nvim's hunk preview

---@class DiffNvim.Opts.Diff
---@field default_view?        DiffNvim.View    Default layout when none is given
---@field default_output?      DiffNvim.Output  Default delivery when none is given
---@field default_source?      DiffNvim.Source  Default source when none is given
---@field default_orig_view?   "vsplit"|"split" Split direction used by :DiffOrig
---@field algorithm?           "myers"|"minimal"|"patience"|"histogram"  vim.diff algorithm
---@field ctxlen?              integer  Context lines around each hunk in unified output
---@field word_diff?           boolean  Word/char-level DiffText highlighting in view=inline/float
---@field url_timeout_ms?      integer  Timeout for http(s):// sources/targets in ms — @see docs/url-sources.md
---@field url_max_bytes?       integer  Byte cap for http(s):// sources/targets, enforced via curl --max-filesize — @see docs/url-sources.md
---@field image_compare?       boolean  Show two raster-image file paths side by side via images.nvim instead of text-diffing their bytes (default true; svg excluded — it's text)
---@field stat_list?           "off"|"qf"|"loc"  Also push output=stat's hunks to the quickfix/location list (default "off")
---@field stat_list_mode?      "add"|"replace"   "add" accumulates across :Diff invocations (default), "replace" resets the list each time
---@field directory_max_files? integer  Cap on files walked per side of a directory diff (default 2000) — see core/directory.lua
---@field history_max_entries? integer  Cap on commits `:DiffHistory` walks (`git log --max-count`, default 200)
---@field diffopt_profile?     DiffNvim.DiffProfile|nil  Apply this profile to 'diffopt' once, at setup()

---@class DiffNvim.Opts.Exit
---@field key?             string|string[]          Left-hand side(s) of the exit mapping
---@field scope?           DiffNvim.Config.ExitScope How aggressively the mapping is set
---@field native_diffthis? boolean  Also mirror the key onto buffers a native :diffthis puts into diffmode (scope="buffer" only). Off by default — see config/DEFAULTS.lua for the rationale.

---@class DiffNvim.Opts.Commands
---@field diff?           string  Name of the main diff command
---@field diff_clear?     string  Name of the clear command
---@field diff_buffers?   string  Name of the buffer-picker diff command
---@field diff_orig?      string  Name of the origin command
---@field diff_history?   string  Name of the file-history command
---@field diff_exit?      string  Name of the exit command
---@field diff_profile?   string  Name of the diffopt-profile command
return {}

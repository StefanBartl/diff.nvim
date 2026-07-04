---@meta
---@module 'diff_nvim.@types'
---@brief Type definitions for diff.nvim.
---@description
--- Central type catalog so the source files stay free of long annotation blocks.
--- All `@types` modules return an empty table.

-- #####################################################################
-- core / command surface
-- #####################################################################

---@alias DiffNvim.Target
--- The right-hand side of the comparison (the "other" content).
---| '"clipboard"'  # Pull content from the system clipboard register (+)
---| string         # Absolute or relative file path (tab-completion supported)
---| integer        # An already-open buffer number

---@alias DiffNvim.Source
--- The left-hand side of the comparison.
---| '"current"'    # The buffer active when :Diff was invoked (default)
---| '"clipboard"'  # System clipboard register (+)
---| string         # File path
---| integer        # Buffer number

---@alias DiffNvim.View
--- How a `output="buffer"` diff is laid out on screen.
---| '"vsplit"'     # Side-by-side vertical split + native diffmode (default)
---| '"split"'      # Horizontal split + native diffmode
---| '"inline"'     # Single scratch buffer holding the unified diff (ft=diff)

---@alias DiffNvim.Output
--- Where the diff result is delivered.
---| '"buffer"'     # Interactive diff inside a split (see View)
---| '"prompt"'     # Unified-diff text echoed to the message area
---| '"file"'       # Write unified diff to a temp file on disk
---| '"clipboard"'  # Copy unified diff to the system clipboard register (+)

---@class DiffNvim.ResolvedOpts
--- Fully-resolved options handed to the core executor.
---@field target DiffNvim.Target
---@field source DiffNvim.Source
---@field view   DiffNvim.View
---@field output DiffNvim.Output

---@class DiffNvim.Context
--- Snapshot of the editing context captured the instant :Diff was invoked.
--- Captured eagerly so async pickers cannot let these values drift.
---@field source_bufnr integer  Buffer that was active at invocation
---@field origin_win   integer  Window that was active at invocation

-- #####################################################################
-- config
-- #####################################################################

---@class DiffNvim.Config.Features
---@field diff        boolean  Register the :Diff / :DiffClear commands
---@field diff_origin boolean  Register the :DiffOrig command
---@field diff_exit   boolean  Register the :DiffExit command + exit keymap

---@class DiffNvim.Config.Diff
---@field default_view      DiffNvim.View    Default layout when none is given
---@field default_output    DiffNvim.Output  Default delivery when none is given
---@field default_source    DiffNvim.Source  Default source when none is given
---@field default_orig_view "vsplit"|"split" Split direction used by :DiffOrig
---@field algorithm         "myers"|"minimal"|"patience"|"histogram"  vim.diff algorithm
---@field ctxlen            integer  Context lines around each hunk in unified output

---@alias DiffNvim.Config.ExitScope
---| '"buffer"'  # Buffer-local mapping on plugin-created diff buffers (default)
---| '"global"'  # Global normal-mode mapping (legacy behaviour)
---| false       # No keymap; :DiffExit command only

---@class DiffNvim.Config.Exit
---@field key   string                   Left-hand side of the exit mapping
---@field scope DiffNvim.Config.ExitScope How aggressively the mapping is set

---@class DiffNvim.Config.Commands
---@field diff       string  Name of the main diff command
---@field diff_clear string  Name of the clear command
---@field diff_orig  string  Name of the origin command
---@field diff_exit  string  Name of the exit command

---@class DiffNvim.Config
---@field features  DiffNvim.Config.Features
---@field diff      DiffNvim.Config.Diff
---@field exit      DiffNvim.Config.Exit
---@field commands  DiffNvim.Config.Commands
---@field select_fn (fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil)|nil  Optional vim.ui.select replacement (dependency injection)

return {}

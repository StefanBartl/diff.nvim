# Architecture

```
plugin/diff.lua         Load guard
lua/diff/
  init.lua                   Public API, setup()/enable()
  @types.lua                 LuaLS type definitions
  config/
    DEFAULTS.lua             Immutable default configuration
    init.lua                 Merge + access to active config
  util/
    notify.lua               "[diff] " prefixed vim.notify wrapper
    validate.lua              Pure validation helpers (is_one_of, *_valid)
  core/
    init.lua                 Orchestration: run(), run_buffers(), execute(), picker
    resolve.lua               Specifier → lines, argument parsing
    git.lua                    git:<rev> resolution via vim.system git-show
    url.lua                    http(s):// async fetch via curl + timeout timer
    pickers_bridge.lua         Optional select_fn adapter for pickers.nvim
    scratch.lua                Scratch-buffer lifecycle + cleanup_all() + active_count()
    render.lua                 Output renderers (buffer/prompt/file/clipboard/stat) + tab/float/three-way layouts
  features/
    origin.lua                :DiffOrig logic
    exit.lua                    :DiffExit logic + exit-behaviour config
    native_diffthis.lua           Opt-in exit-key mirroring onto native :diffthis buffers
  bindings/
    usrcmds.lua                 :Diff/:DiffClear/:DiffOrig/:DiffExit registration + completion
    keymaps.lua                  Exit-keymap wiring (global + buffer-local)
    autocmds.lua                  VimLeavePre cleanup
    init.lua                       Orchestrates the three above
  health.lua                  :checkhealth diff
```

Load order: util → config → core → features → bindings → init

Every keymap, user command, and autocmd is also cataloged in
[BINDINGS.md](BINDINGS.md).

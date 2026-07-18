# Architecture

```
plugin/diff_nvim.lua         Load guard
lua/diff_nvim/
  init.lua                   Public API, setup()/enable()
  @types.lua                 LuaLS type definitions
  config/
    DEFAULTS.lua             Immutable default configuration
    init.lua                 Merge + access to active config
  util/
    notify.lua               "[diff] " prefixed vim.notify wrapper
    validate.lua              Pure validation helpers (is_one_of, *_valid)
  core/
    init.lua                 Orchestration: run(), execute(), target picker
    resolve.lua               Specifier → lines, argument parsing
    scratch.lua                Scratch-buffer lifecycle + cleanup_all()
    render.lua                 Output renderers (buffer/prompt/file/clipboard)
  features/
    origin.lua                :DiffOrig logic
    exit.lua                    :DiffExit logic + exit-behaviour config
  bindings/
    usrcmds.lua                 :Diff/:DiffClear/:DiffOrig/:DiffExit registration + completion
    keymaps.lua                  Exit-keymap wiring (global + buffer-local)
    autocmds.lua                  VimLeavePre cleanup
    init.lua                       Orchestrates the three above
  health.lua                  :checkhealth diff_nvim
```

Load order: util → config → core → features → bindings → init

Every keymap, user command, and autocmd is also cataloged in
[BINDINGS.md](BINDINGS.md).

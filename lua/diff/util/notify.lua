---@module 'diff.util.notify'
--- Prefixed wrapper around lib.nvim.notify so every message is traceable.
---
--- Only the UI layer should call this — keep low-level/core modules silent and
--- let them return `(value, err)` instead.
---
--- Delegates to `lib.nvim.notify`, which supplies the prefixing and level
--- dispatch. The module keeps its own `info`/`warn`/`error` surface so callers
--- are unaffected.

return require("lib.nvim.notify").create("[diff]")

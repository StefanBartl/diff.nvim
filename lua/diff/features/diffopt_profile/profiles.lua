---@module 'diff.features.diffopt_profile.profiles'
--- Named `diffopt` profiles: each is a full replacement value, not a delta.
--- `M.set` in `init.lua` joins one of these into `vim.o.diffopt` wholesale, so
--- switching profiles never mixes old and new options the way repeated
--- `diffopt+=`/`diffopt-=` calls would.
---
--- Moved here from my.nvim (cross-feature report, finding F1): `diffopt` is a
--- *global* option that only takes effect once a window enters diffmode, and
--- diff.nvim is the plugin that puts windows into diffmode (`view=vsplit`,
--- `"split"`, `"tab"` all call `diffmode.set()`). my.nvim painted the window's
--- content; it had no stake in which diff algorithm ran inside it.

---@type table<DiffNvim.DiffProfile, string[]>
local PROFILES = {
  -- Minimal, fast diff with least context.
  minimal = {
    "internal",
    "filler",
    "closeoff",
    "vertical",
    "linematch:60",
    "algorithm:histogram",
    "indent-heuristic",
    "iwhite",
  },

  -- Reduced context for quick reviews.
  context = {
    "internal",
    "filler",
    "closeoff",
    "vertical",
    "context:3",
    "linematch:60",
    "algorithm:patience",
    "indent-heuristic",
    "iwhite",
  },

  -- Standard review profile with moderate context.
  review = {
    "internal",
    "filler",
    "closeoff",
    "vertical",
    "context:8",
    "linematch:80",
    "algorithm:histogram",
    "indent-heuristic",
    "iwhite",
  },

  -- Strict profile showing all changes in detail.
  strict = {
    "internal",
    "filler",
    "closeoff",
    "vertical",
    "linematch:80",
    "algorithm:myers",
    "indent-heuristic",
  },
}

return PROFILES

# Lua API

```lua
local diff = require("diff_nvim")

diff.setup(opts)        -- configure + activate (idempotent)
diff.enable(opts)       -- alias for setup() (compat with custom.diff)
diff.run("target=…")    -- equivalent to :Diff …
diff.clear()            -- equivalent to :DiffClear
diff.diff_origin()      -- equivalent to :DiffOrig
diff.exit()             -- equivalent to :DiffExit
diff.status()           -- statusline string: "diff:N" while active, "" otherwise
```

## Statusline component

`diff.status()` returns a short indicator string while a diff.nvim diff is
active (default `diff:N`, where `N` is the number of active scratch buffers),
or `""` when none is. `opts.prefix` overrides the `diff:` prefix.

```lua
-- native statusline
vim.o.statusline = "%f %{v:lua.require'diff_nvim'.status()}"

-- lualine
require("lualine").setup({
  sections = { lualine_x = { function() return require("diff_nvim").status() end } },
})
```

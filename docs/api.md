# Lua API

```lua
local diff = require("diff_nvim")

diff.setup(opts)        -- configure + activate (idempotent)
diff.enable(opts)       -- alias for setup() (compat with custom.diff)
diff.run("target=…")    -- equivalent to :Diff …
diff.clear()            -- equivalent to :DiffClear
diff.diff_origin()      -- equivalent to :DiffOrig
diff.exit()             -- equivalent to :DiffExit
```

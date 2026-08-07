# Installation

## Requirements

- Neovim 0.9+ (0.10+ for `git:<rev>` and `http(s)://` sources/targets, which use `vim.system`)
- [lib.nvim](https://github.com/StefanBartl/lib.nvim) — the `:Diff`/`:DiffClear`/`:DiffBuffers`/`:DiffOrig`/`:DiffExit` command layer (`lib.nvim.usercmd.composer`), plus notifications
- Optional: a `git` executable on `PATH` for `git:<rev>` sources/targets
- Optional: a `curl` executable on `PATH` for `http(s)://` sources/targets — see [URL sources](url-sources.md)
- Optional: [images.nvim](https://github.com/StefanBartl/images.nvim) — when both `source`/`target` are raster-image files, `:Diff` shows them side by side through it instead of text-diffing raw bytes (`diff.image_compare`, default on; see [Configuration](configuration.md))

## Package managers

<details open>
<summary><b>lazy.nvim</b></summary>

```lua
{
  "StefanBartl/diff.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "Diff", "DiffClear", "DiffBuffers", "DiffOrig", "DiffExit" },
  opts = {},
}
```

Or via `config`:

```lua
{
  "StefanBartl/diff.nvim",
  cmd = { "Diff", "DiffClear", "DiffBuffers", "DiffOrig", "DiffExit" },
  config = function()
    require("diff").setup({})
  end,
}
```
</details>

<details>
<summary><b>packer.nvim</b></summary>

```lua
use {
  "StefanBartl/diff.nvim",
  requires = { "StefanBartl/lib.nvim" },
  cmd = { "Diff", "DiffClear", "DiffBuffers", "DiffOrig", "DiffExit" },
  config = function()
    require("diff").setup({})
  end,
}
```
</details>

<details>
<summary><b>vim-plug</b></summary>

```vim
Plug 'StefanBartl/diff.nvim'
```

Then, in an `init.lua` sourced later:

```lua
require("diff").setup({})
```
</details>

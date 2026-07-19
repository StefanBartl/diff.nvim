# Installation

## Requirements

- Neovim 0.9+ (0.10+ for `git:<rev>` and `http(s)://` sources/targets, which use `vim.system`)
- [lib.nvim](https://github.com/StefanBartl/lib.nvim) (used for notifications)
- Optional: a `git` executable on `PATH` for `git:<rev>` sources/targets
- Optional: a `curl` executable on `PATH` for `http(s)://` sources/targets — see [URL sources](url-sources.md)

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
    require("diff_nvim").setup({})
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
    require("diff_nvim").setup({})
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
require("diff_nvim").setup({})
```
</details>

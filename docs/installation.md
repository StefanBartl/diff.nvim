# Installation

## Requirements

- Neovim 0.9+
- No external plugins required

## Package managers

<details open>
<summary><b>lazy.nvim</b></summary>

```lua
{
  "StefanBartl/diff.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "Diff", "DiffClear", "DiffOrig", "DiffExit" },
  opts = {},
}
```

Or via `config`:

```lua
{
  "StefanBartl/diff.nvim",
  cmd = { "Diff", "DiffClear", "DiffOrig", "DiffExit" },
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
  cmd = { "Diff", "DiffClear", "DiffOrig", "DiffExit" },
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

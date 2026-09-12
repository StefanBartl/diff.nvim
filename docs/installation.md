# Installation

## Requirements

- Neovim 0.9+ (0.10+ for `git:<rev>` and `http(s)://` sources/targets, which use `vim.system`)
- [lib.nvim](https://github.com/StefanBartl/lib.nvim) — the `:Diff`/`:DiffClear`/`:DiffBuffers`/`:DiffOrig`/`:DiffExit` command layer (`lib.nvim.bindings.usercmd.composer`), plus notifications
- Optional: a `git` executable on `PATH` for `git:<rev>` sources/targets
- Optional: a `curl` executable on `PATH` for `http(s)://` sources/targets — see [URL sources](url-sources.md)
- Optional: [pickers.nvim](https://github.com/StefanBartl/pickers.nvim) — a fuzzy target/source picker instead of the plain `vim.ui.select` (see [Around it](around-it.md))
- Optional: [images.nvim](https://github.com/StefanBartl/images.nvim) — when both `source`/`target` are raster-image files, `:Diff` shows them side by side through it instead of text-diffing raw bytes (`diff.image_compare`, default on; see [Configuration](configuration.md))

`:Lib deps show diff.nvim` reports what of the above is missing;
`:Lib deps install diff.nvim` offers to install it, asking first — see
[install.json](install.json) and
[lib.nvim.deps](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup shows this once, the first time `setup()` runs after installing; turn
it off with `vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) or
`vim.g.lib_nvim_deps_disabled_plugins = { "diff.nvim" }` (just this one).

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

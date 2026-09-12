# Around it

diff.nvim detects a couple of sibling plugins at runtime and uses them when
present. Both are soft: without them, everything else works unchanged.

[**pickers.nvim**](https://github.com/StefanBartl/pickers.nvim) — when it is
installed, diff.nvim detects it and uses its fuzzy picker
(telescope.nvim/fzf-lua/snacks.nvim, whichever pickers.nvim resolved) for the
target and source pickers instead of the flat `vim.ui.select`. No
configuration needed; set `select_fn` for a different picker, or
`use_pickers_nvim = false` to always use `vim.ui.select`. See
[Configuration › Picker resolution](configuration.md#picker-resolution).

[**images.nvim**](https://github.com/StefanBartl/images.nvim) — makes
`:Diff target=new.png source=old.png` show the two images side by side
instead of comparing their bytes. See
[Configuration](configuration.md) for `diff.image_compare`.

[**lib.nvim**](https://github.com/StefanBartl/lib.nvim) is the one real,
non-optional dependency — see [Requirements](installation.md#requirements).

# Testing & health check

## Health check

```
:checkhealth diff
```

## Tests

Headless spec suite covering the whole plugin: config merge, argument parsing,
validation helpers, every renderer and its failure arms, the scratch-buffer
registry, git and URL resolution (including the exact argv each would spawn),
directory diffs, `:DiffOrig`, the command/keymap/autocmd wiring, the public
API, and `:checkhealth` itself — see [TESTS/README.md](../TESTS/README.md) for
the per-file register, the deliberate omissions, and the bugs it pins.

```sh
bash scripts/test.sh
```

The suite is run by [testing.nvim](https://github.com/StefanBartl/testing.nvim).
Nothing in it needs a fuzzy-picker backend, images.nvim, or pickers.nvim
installed; only testing.nvim and lib.nvim are required, and `$TESTING_NVIM_DIR` /
`$LIB_NVIM_DIR` point at them when they are not sibling checkouts. Two specs talk to the outside world on purpose —
`git_spec.lua` runs a real `git show` against this repository, and
`url_spec.lua` attempts one HTTPS round-trip — and both skip rather than fail
when git or the network is unavailable.

This same command runs in CI on every push and pull request via
[.github/workflows/ci.yml](../.github/workflows/ci.yml), alongside
`stylua --check .` and `luacheck lua plugin TESTS`.

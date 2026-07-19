# Testing & health check

## Health check

```
:checkhealth diff_nvim
```

## Tests

Headless spec suite covering config merge, argument parsing, validation
helpers, diff statistics, git resolution, and the statusline component — see
[TESTS/README.md](TESTS/README.md).

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
```

This same command runs in CI on every push and pull request via
[.github/workflows/ci.yml](../.github/workflows/ci.yml).

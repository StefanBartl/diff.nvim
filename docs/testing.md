# Testing & health check

## Health check

```
:checkhealth diff_nvim
```

## Tests

Headless spec suite covering config merge, argument parsing, and validation
helpers — see [TESTS/README.md](TESTS/README.md).

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
```

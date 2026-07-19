# URL sources

`target=` and `source=` accept an `http://` or `https://` URL. The content at
that URL is fetched and diffed exactly like any other source/target — the
one specifier type that talks to the network, hence its own page.

```vim
:Diff target=https://raw.githubusercontent.com/user/repo/main/init.lua
```

## How it works

- Fetched via `curl` through `vim.system` — a direct argv exec (`{"curl", ...}`),
  never a shell string, so URLs are never subject to shell quoting/injection.
- **Asynchronous**: the fetch runs in the background: the editor stays
  responsive while it's in flight, and the diff renders once it completes.
  Compare with `git:<rev>` sources, which resolve synchronously (a local
  `git show` is fast enough not to need this).
- **Timeout-bounded**: `diff.url_timeout_ms` (default `10000`) enforces an
  upper bound via a libuv timer, independent of `curl`'s own timeout — a
  stalled TLS handshake or hung connection is killed rather than left
  hanging indefinitely.
- Non-2xx HTTP responses are treated as failures (`curl --fail`) and reported
  as errors, not silently diffed as empty/error-page content.

## Requirements

- Neovim 0.10+ (`vim.system`)
- A `curl` executable on `PATH`

Both are checked by `:checkhealth diff_nvim`.

## Configuration

```lua
require("diff_nvim").setup({
  diff = {
    url_timeout_ms = 10000, -- fetch timeout in ms
  },
})
```

## Examples

**Local config vs. the canonical version in your dotfiles repo**
```vim
:Diff target=https://raw.githubusercontent.com/you/dotfiles/main/init.lua
```
See what's changed locally without pulling or checking out the repo.

**Vendored code vs. upstream**
```vim
:Diff target=https://raw.githubusercontent.com/foo/bar/main/lua/util.lua output=stat
```
You copied a file from another project into your own (vendoring) and want a
quick `+N -M, K hunks` summary of how far it's drifted from the original.

**A gist someone sent you**
```vim
:Diff target=https://gist.githubusercontent.com/user/id/raw/snippet.lua view=inline
```
Diff directly against the raw gist URL instead of downloading it first.

**Local notes vs. an upstream changelog**
```vim
:Diff target=https://raw.githubusercontent.com/plugin/repo/main/CHANGELOG.md source=~/notes/plugin-changelog.md
```
See what's new since you last synced your notes.

**Verify a downloaded script before running it**
```vim
:Diff target=https://example.com/install.sh source=/tmp/install.sh
```
Confirm a downloaded install script exactly matches what's currently
published online before executing it — no unexpected tampering or cache
drift.

**API schema drift**
```vim
:Diff target=https://api.example.com/openapi.json source=./schema/openapi.json output=stat
```
Check whether a publicly hosted API schema has diverged from the version
checked into your repo.

## Security note

diff.nvim fetches and displays whatever content is at the URL you give it —
there's no sandboxing beyond what `curl` itself provides (TLS verification,
`--location` following redirects). Only diff URLs you trust; the same caution
that applies to `curl | sh` applies here, minus the "sh" — this only ever
*displays* the content, never executes it.

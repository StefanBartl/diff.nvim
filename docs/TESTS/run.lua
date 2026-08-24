-- docs/TESTS/run.lua — headless test runner for diff.nvim.
--
-- Run from the repo root:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero on the first failing spec.

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

-- resolve_spec.lua exercises the "+" register (target=clipboard). Relying on
-- whatever clipboard provider (or lack of one) the host happens to have is
-- exactly the kind of environment-dependent flakiness a test suite should not
-- have: a bare headless runner (no xclip/xsel/wl-clipboard/pbcopy, e.g. CI's
-- ubuntu image) has no provider at all, so getreg/setreg("+") silently no-op
-- instead of behaving like a register, which reads as "clipboard is always
-- empty" and fails the spec. An in-memory fake provider (the pattern from
-- `:h g:clipboard`) makes "+" behave like a real register deterministically,
-- everywhere, regardless of what's installed on the host.
do
  local fake_reg = { "" }
  vim.g.clipboard = {
    name = "FakeClipboardForTests",
    copy = {
      ["+"] = function(lines)
        fake_reg = lines
      end,
      ["*"] = function(lines)
        fake_reg = lines
      end,
    },
    paste = {
      ["+"] = function()
        return fake_reg
      end,
      ["*"] = function()
        return fake_reg
      end,
    },
  }
end

-- diff.nvim depends on lib.nvim at runtime (util/notify.lua,
-- util/validate.lua), so the suite needs it on the runtimepath.
--
-- A sibling checkout wins over the plugin-manager copy on purpose: the
-- bootstrap clone under stdpath("data")/lazy is frequently older than the
-- working checkout, and testing against a stale lib.nvim gives misleading
-- failures. `$LIB_NVIM_PATH` overrides both (useful in CI).
local function add_lib_nvim()
  -- Built by appending, not as a literal: an unset $LIB_NVIM_PATH would put a
  -- nil at index 1 and `ipairs` would stop before checking anything.
  local candidates = {}
  if vim.env.LIB_NVIM_PATH then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_PATH
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/../lib.nvim"
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"

  for _, path in ipairs(candidates) do
    -- Normalize first: the sibling candidate contains a ".." segment and the
    -- stdpath one mixes separators on Windows; the runtimepath module searcher
    -- does not resolve either, so an unnormalized entry silently finds nothing.
    local norm = vim.fs.normalize(path)
    if vim.fn.isdirectory(norm .. "/lua/lib") == 1 then
      vim.opt.rtp:append(norm)
      -- rtp alone is not enough here: the runtimepath searcher does not pick
      -- up entries appended after startup. lib.nvim's own README prescribes
      -- registering it on package.path as well (the C require searcher is the
      -- fallback that always applies).
      package.path = table.concat({
        norm .. "/lua/?.lua",
        norm .. "/lua/?/init.lua",
        package.path,
      }, ";")
      return norm
    end
  end
  return nil
end

local lib_path = add_lib_nvim()
if not lib_path then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of diff.nvim).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

local specs = {
  "config_spec.lua",
  "resolve_spec.lua",
  "validate_spec.lua",
  "render_spec.lua",
  "git_spec.lua",
  "status_spec.lua",
  "pickers_bridge_spec.lua",
  "pick_specifier_spec.lua",
  "prompt_file_spec.lua",
  "native_diffthis_spec.lua",
  "keymaps_spec.lua",
  "url_spec.lua",
  "three_way_spec.lua",
  "image_compare_spec.lua",
  "directory_spec.lua",
}

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    print(("ok    %s"):format(name))
  else
    failed = failed + 1
    print(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  print(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

print("\nDIFF_NVIM_TESTS_OK")

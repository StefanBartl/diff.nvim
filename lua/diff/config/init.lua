---@module 'diff.config'
--- Runtime configuration store for diff.nvim.
---
--- Merges user options over the immutable DEFAULTS and exposes the active
--- config via `get()`. Keeps no global state — the active table is module-local.

local levenshtein = require("lib.lua.strings.distance").levenshtein

local DEFAULTS = require("diff.config.DEFAULTS")

local M = {}

---@type DiffNvim.Config|nil
local _active = nil

---@internal
---@param v any
---@return boolean
local function is_boolean(v)
  return type(v) == "boolean"
end

---@internal
---@param v any
---@return boolean
local function is_nonneg_int(v)
  return type(v) == "number" and v >= 0 and v == math.floor(v)
end

---@internal
---@param v any
---@return boolean
local function is_pos_int(v)
  return type(v) == "number" and v > 0 and v == math.floor(v)
end

---A validated leaf: `value` merges only when `ok(value)` holds, else the
---issue names `expect` and the key is dropped so the default underneath
---applies (ERR-22).
---@alias DiffNvim.Config.Check { ok: fun(v: any): boolean, expect: string }

---Schema for `setup()`'s top-level and one-level-nested keys.
---  - `true`                        accept any value at that leaf, unchecked
---  - `DiffNvim.Config.Check`       accept only a value `ok()` approves
---  - `table<string, ...>`          nested table, validated recursively
---`keymaps` and `commands` are dynamic name->value maps checked by their own
---consumers (`bindings/keymaps.lua`'s "Unknown keymaps.*" warning; commands
---are free-form user command names), so both accept any sub-key here.
---@alias DiffNvim.Config.Schema true|DiffNvim.Config.Check|table<string, DiffNvim.Config.Schema>
---@type table<string, DiffNvim.Config.Schema>
local KNOWN = {
  features = {
    diff = { ok = is_boolean, expect = "a boolean" },
    diff_origin = { ok = is_boolean, expect = "a boolean" },
    diff_exit = { ok = is_boolean, expect = "a boolean" },
    diffopt_profile = { ok = is_boolean, expect = "a boolean" },
    gitsigns_peek = { ok = is_boolean, expect = "a boolean" },
  },
  diff = {
    -- Kept in sync by hand with VALID_VIEWS/VALID_OUTPUTS in core/init.lua
    -- (and usrcmds.lua's own VALUE_LISTS) -- core/init.lua requires
    -- diff.config already, so requiring core back here to share the list
    -- would be circular.
    default_view = {
      ok = function(v)
        return v == "vsplit" or v == "split" or v == "inline" or v == "tab" or v == "float"
      end,
      expect = "one of vsplit, split, inline, tab, float",
    },
    default_output = {
      ok = function(v)
        return v == "buffer" or v == "prompt" or v == "file" or v == "clipboard" or v == "stat"
      end,
      expect = "one of buffer, prompt, file, clipboard, stat",
    },
    -- default_source is deliberately unchecked: it accepts "current",
    -- "clipboard", "ask", "git:<rev>", "http(s)://…", a path, or a bufnr --
    -- not a closed enum (see core/init.lua's run(), which only validates a
    -- typed source= the same way, never this default).
    default_source = true,
    default_orig_view = {
      ok = function(v)
        return v == "vsplit" or v == "split"
      end,
      expect = 'one of "vsplit", "split"',
    },
    -- Applied through a guarded pcall at setup() (bindings/init.lua) and
    -- checked against the live profile registry there, with its own name in
    -- the error -- re-validating the name here would just duplicate that.
    diffopt_profile = true,
    algorithm = {
      ok = function(v)
        return v == "myers" or v == "minimal" or v == "patience" or v == "histogram"
      end,
      expect = "one of myers, minimal, patience, histogram",
    },
    ctxlen = { ok = is_nonneg_int, expect = "a non-negative integer" },
    word_diff = { ok = is_boolean, expect = "a boolean" },
    url_timeout_ms = { ok = is_pos_int, expect = "a positive integer" },
    url_max_bytes = { ok = is_pos_int, expect = "a positive integer" },
    image_compare = { ok = is_boolean, expect = "a boolean" },
    stat_list = {
      ok = function(v)
        return v == "off" or v == "qf" or v == "loc"
      end,
      expect = 'one of "off", "qf", "loc"',
    },
    stat_list_mode = {
      ok = function(v)
        return v == "add" or v == "replace"
      end,
      expect = 'one of "add", "replace"',
    },
    directory_max_files = { ok = is_pos_int, expect = "a positive integer" },
  },
  keymaps = true,
  exit = {
    key = true,
    scope = {
      ok = function(v)
        return v == "buffer" or v == "global" or v == false
      end,
      expect = '"buffer", "global", or false',
    },
    native_diffthis = { ok = is_boolean, expect = "a boolean" },
  },
  commands = true,
  select_fn = true,
  use_pickers_nvim = { ok = is_boolean, expect = "a boolean" },
}

---@internal
---`key` with the nearest sibling in `known` as a hint, when there is a
---plausible one (edit distance <= 3) — catches the everyday typo
---(`diff_orgin` for `diff_origin`) without claiming a match for a key that
---is not actually related.
---@param key any
---@param known table<string, any>
---@param prefix string dotted path so far, e.g. "diff."
---@return string
local function describe_unknown(key, known, prefix)
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local d = levenshtein(name, candidate)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = candidate, d
    end
  end
  if best then
    return ("unknown option '%s%s' (did you mean '%s%s'?)"):format(prefix, name, prefix, best)
  end
  return ("unknown option '%s%s'"):format(prefix, name)
end

---Validate `opts` against `KNOWN` before the merge.
---
---ERR-50: an unrecognized key — almost always a typo in a nested option —
---would otherwise vanish silently into the default, with the plugin behaving
---as if it had never been set at all. ERR-22: a recognized key whose value
---fails its check (e.g. a typo'd `diff.algorithm`) is dropped the same way,
---so the default underneath takes over instead of the bad value reaching
---every consumer unchecked. Recurses into a nested table; a value given
---where a nested table is expected is dropped too, so a wrong shape falls
---back to the default rather than reaching `vim.tbl_deep_extend` as-is.
---
---Does not mutate `opts` — a rejected entry is left out of the returned copy
---rather than stripped from the caller's own table.
---@internal
---@param opts table
---@param schema table<string, DiffNvim.Config.Schema>
---@param prefix string
---@return table clean
---@return string[] found_issues
local function sanitize(opts, schema, prefix)
  local clean, found_issues = {}, {}
  for key, value in pairs(opts) do
    local expected = schema[key]
    if expected == nil then
      found_issues[#found_issues + 1] = describe_unknown(key, schema, prefix)
    elseif expected == true then
      clean[key] = value
    elseif type(expected) == "table" and expected.ok ~= nil then
      if expected.ok(value) then
        clean[key] = value
      else
        found_issues[#found_issues + 1] = ("option '%s%s' must be %s, got %s -- using the default"):format(
          prefix,
          tostring(key),
          expected.expect,
          vim.inspect(value)
        )
      end
    elseif type(value) ~= "table" then
      found_issues[#found_issues + 1] = ("option '%s%s' must be a table, got %s -- using the default"):format(
        prefix,
        tostring(key),
        type(value)
      )
    else
      local sub_clean, sub_issues = sanitize(value, expected, prefix .. tostring(key) .. ".")
      clean[key] = sub_clean
      vim.list_extend(found_issues, sub_issues)
    end
  end
  return clean, found_issues
end

---@type string[]
local _issues = {}

---Whatever the last `setup()` call rejected (unknown option, wrong type,
---invalid value) — one message per issue, empty when everything validated.
---For `:checkhealth diff`.
---@return string[]
function M.issues()
  return vim.deepcopy(_issues)
end

---Merge user options over the defaults and store the result.
---`opts` is validated first (ERR-50, ERR-22): an unknown key or an
---invalid-for-its-kind value is dropped so the built-in default is what
---actually takes effect, and every issue is kept for `:checkhealth` (see
---`M.issues()`).
---@param user_opts? DiffNvim.Opts
---@return DiffNvim.Config
function M.setup(user_opts)
  if type(user_opts) ~= "table" then
    -- Partial/absent user opts are valid here; DEFAULTS (merged below) is
    -- what actually guarantees a complete DiffNvim.Config.
    user_opts = {} --[[@as table]]
  end

  local clean, found_issues = sanitize(user_opts, KNOWN, "")
  table.sort(found_issues)
  _issues = found_issues

  _active = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), clean)
  return _active
end

---Return the active configuration, falling back to defaults if `setup` was
---never called.
---@return DiffNvim.Config
function M.get()
  if _active == nil then
    _active = vim.deepcopy(DEFAULTS)
  end
  return _active
end

return M

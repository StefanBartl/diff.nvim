-- TESTS/config_spec.lua — config merge (DEFAULTS + user options).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff.config")

  -- defaults
  config.setup({})
  local d = config.get()
  eq(d.diff.default_view, "vsplit", "default default_view")
  eq(d.diff.default_output, "buffer", "default default_output")
  eq(d.diff.default_source, "current", "default default_source")
  eq(d.diff.default_orig_view, "vsplit", "default default_orig_view")
  eq(d.diff.algorithm, "histogram", "default algorithm")
  eq(d.diff.ctxlen, 3, "default ctxlen")
  eq(d.diff.word_diff, true, "default word_diff")
  eq(d.diff.url_timeout_ms, 10000, "default url_timeout_ms")
  eq(d.exit.key, "<Esc><Esc>", "default exit key")
  eq(d.exit.scope, "buffer", "default exit scope")
  eq(d.exit.native_diffthis, false, "default exit native_diffthis")
  eq(d.commands.diff_buffers, "DiffBuffers", "default diff_buffers command name")
  eq(d.use_pickers_nvim, true, "default use_pickers_nvim")
  ok(d.features.diff, "diff feature on by default")
  ok(d.features.diff_origin, "diff_origin feature on by default")
  ok(d.features.diff_exit, "diff_exit feature on by default")

  -- shallow override
  config.setup({ exit = { scope = "global" } })
  local o = config.get()
  eq(o.exit.scope, "global", "override exit.scope")
  -- untouched sibling keys keep their default
  eq(o.exit.key, "<Esc><Esc>", "untouched sibling key keeps default")

  -- nested deep-merge keeps sibling keys
  config.setup({ diff = { default_orig_view = "split" } })
  local n = config.get()
  eq(n.diff.default_orig_view, "split", "nested override applied")
  eq(n.diff.default_view, "vsplit", "nested sibling kept from defaults")

  -- unknown key dropped before the merge, reported via issues() (ERR-50) ----
  -- A typo in a nested option (`diff_orgin` for `diff_origin`) must not
  -- vanish silently into the default with nothing anywhere able to tell.
  config.setup({ features = { diff_orgin = false } })
  local u = config.get()
  eq(u.features.diff_origin, true, "the real option keeps its default -- the typo never touched it")
  local unknown_issues = config.issues()
  ok(#unknown_issues > 0, "the typo is recorded as an issue")
  ok(
    table.concat(unknown_issues, "\n"):find("diff_orgin", 1, true) ~= nil,
    "and names the offending key"
  )

  -- invalid value degrades to its own default, reported via issues() (ERR-22)
  -- A typo'd algorithm must not reach every vim.diff call unchecked.
  config.setup({ diff = { algorithm = "not-a-real-algorithm", ctxlen = -1 } })
  local bad = config.get()
  eq(
    bad.diff.algorithm,
    "histogram",
    "an invalid algorithm degrades to the default, not aborting setup"
  )
  eq(bad.diff.ctxlen, 3, "a negative ctxlen degrades to the default too")
  local value_issues = config.issues()
  eq(#value_issues, 2, "both bad values are recorded as issues")

  -- default_view/default_output/default_orig_view are closed enums too --
  -- an invalid one must degrade instead of making every :Diff without an
  -- explicit view=/output= fail via resolve_view_output() (ERR-22).
  config.setup({
    diff = {
      default_view = "not-a-view",
      default_output = "not-an-output",
      default_orig_view = "nope",
    },
  })
  local bad_enums = config.get()
  eq(bad_enums.diff.default_view, "vsplit", "an invalid default_view degrades to the default")
  eq(bad_enums.diff.default_output, "buffer", "an invalid default_output degrades to the default")
  eq(
    bad_enums.diff.default_orig_view,
    "vsplit",
    "an invalid default_orig_view degrades to the default"
  )
  eq(#config.issues(), 3, "all three bad enum values are recorded as issues")

  -- setup() never aborts over a validation issue (ERR-22) -- the rest of the
  -- config still merges normally alongside the degraded fields.
  config.setup({ diff = { algorithm = "bogus", ctxlen = 5 } })
  eq(config.get().diff.ctxlen, 5, "a sibling value in the same setup() call still applies")

  -- issues() reflects only the LAST setup() call, not an accumulation
  config.setup({})
  eq(#config.issues(), 0, "a clean setup() call clears the previous issues")

  -- reset for subsequent specs
  config.setup({})
end

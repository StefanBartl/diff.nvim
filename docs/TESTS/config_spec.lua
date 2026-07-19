-- docs/TESTS/config_spec.lua — config merge (DEFAULTS + user options).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("diff_nvim.config")

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

  -- reset for subsequent specs
  config.setup({})
end

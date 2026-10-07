-- TESTS/usrcmds_help_spec.lua -- every key=value pair of :Diff, :DiffBuffers and :DiffHistory has a
-- line in lib.nvim's option float.
--
-- The text comes from `KV_HELP` in bindings/usrcmds.lua. A new `key=` without an entry shows up as
-- a bare row in the cheatsheet (and `kv()` would fail outright), so this fails until it is
-- described.

return function(H)
  local ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  H.ok(ok, "the composer loads")

  -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
  -- feature of the dependency, not a defect of this plugin.
  if type(composer.help.undocumented) ~= "function" then
    return
  end

  local cfg = require("diff.config").setup({})
  require("diff.bindings.usrcmds").register(cfg)

  for _, name in ipairs({ cfg.commands.diff, cfg.commands.diff_buffers, cfg.commands.diff_history }) do
    H.ok(composer.registry()[name] ~= nil, ":" .. name .. " is registered through the composer")

    local missing = {}
    for _, m in ipairs(composer.help.undocumented(name)) do
      missing[#missing + 1] = m.name
    end
    H.eq(
      #missing,
      0,
      ":" .. name .. " options without a help text: " .. table.concat(missing, ", ")
    )
  end
end

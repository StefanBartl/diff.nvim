-- TESTS/usrcmds_help_spec.lua -- every key=value pair of :Diff, :DiffBuffers and :DiffHistory, and
-- every positional argument of :DiffProfile (and :DiffHistory's built-in FILE), has a line in
-- lib.nvim's option float.
--
-- The key=value text comes from `KV_HELP` in bindings/usrcmds.lua. A new `key=` without an entry
-- shows up as a bare row in the cheatsheet (and `kv()` would fail outright), so this fails until it
-- is described. The `:DiffProfile {profile}` text is the `desc` / `enum_desc` of its ArgSpec.

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

  for _, name in ipairs({
    cfg.commands.diff,
    cfg.commands.diff_buffers,
    cfg.commands.diff_history,
    cfg.commands.diff_profile,
  }) do
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

    -- The positional arguments too.
    local missing_args = {}
    for _, m in ipairs(composer.help.undocumented(name, { args = true })) do
      missing_args[#missing_args + 1] = m.kind .. ":" .. m.name
    end
    H.eq(
      #missing_args,
      0,
      ":" .. name .. " entries without a help text: " .. table.concat(missing_args, ", ")
    )
  end

  -- The :DiffProfile texts follow the house style (one line, no trailing period, <= 80 characters)
  -- and describe every profile there is: a profile added later must not show up as a bare row.
  local profile = composer.registry()[cfg.commands.diff_profile]:spec().routes[1].args[1]
  local texts = { profile.desc }
  for value, text in pairs(profile.enum_desc or {}) do
    H.ok(vim.tbl_contains(profile.enum, value), "enum_desc key " .. value .. " is a profile")
    texts[#texts + 1] = text
  end
  for _, text in ipairs(texts) do
    H.ok(
      not text:find("\n", 1, true) and text:sub(-1) ~= "." and #text <= 80,
      "text is one line, without a trailing period, <= 80 characters: " .. text
    )
  end
  for _, value in ipairs(profile.enum) do
    H.ok(profile.enum_desc[value] ~= nil, "profile " .. value .. " has a text")
  end
end

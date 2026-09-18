-- TESTS/diffopt_profile_spec.lua — the diffopt profiles and the selector
-- that turns one into 'diffopt' (moved from my.nvim, cross-feature report
-- finding F1).

return function(H)
  local eq, ok = H.eq, H.ok
  local diffopt_profile = require("diff.features.diffopt_profile")
  local profiles = require("diff.features.diffopt_profile.profiles")

  local saved = vim.o.diffopt

  -- names() / profiles table ------------------------------------------------
  local names = diffopt_profile.names()
  local expected = { "context", "minimal", "review", "strict" }
  eq(#names, #expected, "four documented profiles")
  for i, name in ipairs(expected) do
    eq(names[i], name, "names() is sorted, stable across restarts")
  end

  for name, list in pairs(profiles) do
    ok(#list > 0, ("profile '%s' is empty"):format(name))
    for _, entry in ipairs(list) do
      eq(type(entry), "string")
      -- A comma inside an entry would silently split into two options.
      ok(not entry:find(","), ("'%s' contains a comma"):format(entry))
    end
    -- Everything else in these lists (linematch, algorithm,
    -- indent-heuristic) is only honoured by the internal engine, so a
    -- profile without it is quietly a different profile than it reads as.
    eq(list[1], "internal", ("profile '%s' does not start internal"):format(name))
  end

  -- get() --------------------------------------------------------------------
  eq(diffopt_profile.get("review"), table.concat(profiles.review, ","))
  eq(diffopt_profile.get("no_such_profile"), nil, "unknown name returns nil, not an error")

  -- set() ----------------------------------------------------------------------
  diffopt_profile.set("strict")
  eq(vim.o.diffopt, table.concat(profiles.strict, ","))

  -- replaces rather than appends when switching profiles
  diffopt_profile.set("minimal")
  diffopt_profile.set("review")
  eq(vim.o.diffopt, table.concat(profiles.review, ","))

  local set_ok, err = pcall(diffopt_profile.set, "no_such_profile")
  ok(not set_ok, "set() throws on an unknown profile")
  ok(tostring(err):find("no_such_profile", 1, true) ~= nil, "the error names it")

  -- current() ------------------------------------------------------------------
  diffopt_profile.set("context")
  eq(diffopt_profile.current(), "context")

  vim.o.diffopt = "internal,filler"
  eq(diffopt_profile.current(), nil, "a hand-set 'diffopt' matches no profile")

  -- cycle() --------------------------------------------------------------------
  diffopt_profile.set("minimal")
  local applied = diffopt_profile.cycle()
  eq(applied, "review", "cycle() moves to the next name after 'minimal' in sorted order")
  eq(vim.o.diffopt, table.concat(profiles.review, ","))

  applied = diffopt_profile.cycle()
  eq(applied, "strict")

  vim.o.diffopt = "internal,filler"
  applied = diffopt_profile.cycle()
  eq(applied, "context", "an unrecognised 'diffopt' starts the cycle at the first profile")

  vim.o.diffopt = saved
end

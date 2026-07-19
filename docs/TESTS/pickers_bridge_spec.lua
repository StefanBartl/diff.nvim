-- docs/TESTS/pickers_bridge_spec.lua — core.pickers_bridge: optional
-- pickers.nvim adapter for select_fn.

return function(H)
  local eq, ok = H.eq, H.ok
  local bridge = require("diff_nvim.core.pickers_bridge")

  -- pickers.nvim is not on rtp/package.path yet in this process: resolve()
  -- must return nil, never error.
  local without = bridge.resolve()
  eq(without, nil, "resolve() is nil when pickers.nvim is not installed")

  -- Best-effort: add a sibling pickers.nvim checkout to rtp (same pattern as
  -- run.lua's lib.nvim detection). If it's not present, the nil-fallback
  -- check above already covers the module's core contract.
  local candidate = vim.fs.normalize(vim.fn.getcwd() .. "/../pickers.nvim")
  if vim.fn.isdirectory(candidate .. "/lua/pickers") ~= 1 then
    return
  end
  vim.opt.rtp:append(candidate)
  package.path = table.concat({
    candidate .. "/lua/?.lua",
    candidate .. "/lua/?/init.lua",
    package.path,
  }, ";")

  -- pickers.nvim is now resolvable, but this headless test environment has
  -- no telescope.nvim/fzf-lua/snacks.nvim installed, so no engine is
  -- available either — resolve() must still degrade to nil, never error.
  -- pickers.engines.load() notifies (by design) when it finds nothing; that
  -- notification is expected noise here, not a test failure — silence it.
  local saved_notify = vim.notify
  vim.notify = function() end
  local call_ok, result = pcall(bridge.resolve)
  vim.notify = saved_notify
  ok(call_ok, "resolve() does not throw when pickers.nvim has no usable engine")
  ok(result == nil or type(result) == "function", "resolve() returns nil or a function, never anything else")
end

-- docs/TESTS/native_diffthis_spec.lua — features.native_diffthis: sync() logic
-- and register()'s gating. sync() is tested directly (attach/detach against a
-- real window's 'diff' state) rather than via the OptionSet event itself,
-- since OptionSet does not reliably fire in this headless test environment
-- (verified: no option, via any API, triggers it here) — the underlying
-- attach/detach logic is what actually matters and is what this covers.

return function(H)
  local eq, ok = H.eq, H.ok
  local native = require("diff_nvim.features.native_diffthis")

  local cfg = { key = "<C-x><C-x>", scope = "buffer", native_diffthis = true }

  local function has_exit_map(buf)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs == cfg.key or m.lhs == "<C-X><C-X>" then
        return true
      end
    end
    return false
  end

  -- sync(): diff=true attaches the buffer-local exit key ------------------
  local buf = H.scratch()
  local win = vim.api.nvim_get_current_win()
  ok(not has_exit_map(buf), "no exit map before diffmode is on")

  vim.wo[win].diff = true
  native.sync(cfg, win)
  ok(has_exit_map(buf), "sync() attaches the exit key once 'diff' is on")

  -- sync(): diff=false detaches it again -----------------------------------
  vim.wo[win].diff = false
  native.sync(cfg, win)
  ok(not has_exit_map(buf), "sync() detaches the exit key once 'diff' is off")

  -- register(): no-op unless scope=="buffer" and native_diffthis==true ----
  local function autocmd_count()
    return #vim.api.nvim_get_autocmds({ group = "diff_nvim_native_diffthis" })
  end

  local ok1, err1 = pcall(native.register, { key = "<C-x><C-x>", scope = "global", native_diffthis = true })
  ok(ok1, "register() does not throw for scope=global: " .. tostring(err1))

  local ok2, err2 = pcall(native.register, { key = "<C-x><C-x>", scope = "buffer", native_diffthis = false })
  ok(ok2, "register() does not throw for native_diffthis=false: " .. tostring(err2))

  local ok3, count_err = pcall(autocmd_count)
  ok((not ok3) or count_err == 0, "no autocmd registered when scope~=buffer or native_diffthis~=true")

  -- register(): does create the OptionSet autocmd when both conditions hold
  native.register(cfg)
  eq(autocmd_count(), 1, "register() creates exactly one autocmd when opted in")
end

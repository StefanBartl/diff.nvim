-- docs/TESTS/resolve_spec.lua — core.resolve: parse_args + resolve_lines.

return function(H)
  local eq, ok = H.eq, H.ok
  local resolve = require("diff.core.resolve")

  -- parse_args -----------------------------------------------------------
  local kv = resolve.parse_args("target=clipboard view=inline output=prompt")
  eq(kv.target, "clipboard", "parse target")
  eq(kv.view, "inline", "parse view")
  eq(kv.output, "prompt", "parse output")

  eq(next(resolve.parse_args("")), nil, "empty args parse to empty table")
  eq(next(resolve.parse_args(nil)), nil, "non-string args parse to empty table")

  -- resolve_lines: clipboard ----------------------------------------------
  local saved = vim.fn.getreg("+")
  vim.fn.setreg("+", "a\nb\nc")
  local lines, err = resolve.resolve_lines("clipboard", "target")
  ok(err == nil, "clipboard resolve has no error")
  eq(#lines, 3, "clipboard splits into 3 lines")
  eq(lines[2], "b", "clipboard line content")

  vim.fn.setreg("+", "")
  local empty_lines, empty_err = resolve.resolve_lines("clipboard", "target")
  eq(empty_lines, nil, "empty clipboard resolves to nil")
  ok(empty_err ~= nil, "empty clipboard reports an error")
  vim.fn.setreg("+", saved)

  -- resolve_lines: buffer number -------------------------------------------
  local buf = H.scratch()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x", "y" })
  local buf_lines = resolve.resolve_lines(tostring(buf), "source")
  eq(#buf_lines, 2, "buffer resolve line count")
  eq(buf_lines[1], "x", "buffer resolve line content")

  local bad_lines, bad_err = resolve.resolve_lines("999999", "source")
  eq(bad_lines, nil, "invalid buffer resolves to nil")
  ok(bad_err ~= nil, "invalid buffer reports an error")

  -- resolve_lines: unreadable file ------------------------------------------
  local file_lines, file_err = resolve.resolve_lines("/does/not/exist.lua", "target")
  eq(file_lines, nil, "unreadable file resolves to nil")
  ok(file_err ~= nil, "unreadable file reports an error")
end

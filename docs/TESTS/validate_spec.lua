-- docs/TESTS/validate_spec.lua — util.validate: pure helpers.

return function(H)
  local eq, ok = H.eq, H.ok
  local validate = require("diff_nvim.util.validate")

  -- is_one_of --------------------------------------------------------------
  ok(validate.is_one_of("b", { "a", "b", "c" }), "is_one_of finds a member")
  eq(validate.is_one_of("z", { "a", "b", "c" }), false, "is_one_of rejects a non-member")
  eq(validate.is_one_of("a", {}), false, "is_one_of rejects against empty list")

  -- buf_valid ----------------------------------------------------------------
  local buf = H.scratch()
  ok(validate.buf_valid(buf), "buf_valid accepts a real buffer")
  eq(validate.buf_valid(999999), false, "buf_valid rejects a non-existent buffer")
  eq(validate.buf_valid("not-a-number"), false, "buf_valid rejects a non-number")

  -- win_valid ----------------------------------------------------------------
  local win = vim.api.nvim_get_current_win()
  ok(validate.win_valid(win), "win_valid accepts the current window")
  eq(validate.win_valid(999999), false, "win_valid rejects a non-existent window")
  eq(validate.win_valid("not-a-number"), false, "win_valid rejects a non-number")
end

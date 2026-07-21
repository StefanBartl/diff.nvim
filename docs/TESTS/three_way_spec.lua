-- docs/TESTS/three_way_spec.lua — render.three_way() layout + core.run()'s
-- base= validation and end-to-end wiring. See docs/three-way-diff.md.

return function(H)
  local eq, ok = H.eq, H.ok
  local render = require("diff.core.render")

  local function count_diff_wins()
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.wo[w].diff then
        n = n + 1
      end
    end
    return n
  end

  -- render.three_way(): vsplit layout -----------------------------------
  vim.cmd("silent! tabonly | silent! only")
  local origin_buf = H.scratch()
  local origin_win = vim.api.nvim_get_current_win()
  local scratch = require("diff.core.scratch")
  local b_buf = scratch.create({ "base" }, "[Diff:base] test")
  local t_buf = scratch.create({ "target" }, "[Diff:target] test")

  render.three_way(origin_win, b_buf, t_buf, "vsplit")
  eq(#vim.api.nvim_list_wins(), 3, "vsplit: three windows open")
  eq(count_diff_wins(), 3, "vsplit: all three windows are in diffmode")
  ok(vim.api.nvim_win_get_buf(origin_win) == origin_buf,
    "vsplit: origin window still shows the live origin buffer")
  ok(vim.bo[origin_buf].modifiable, "vsplit: origin buffer stays modifiable (editable)")
  eq(vim.api.nvim_get_current_win(), origin_win, "vsplit: focus returns to the origin window")

  -- render.three_way(): tab layout -----------------------------------------
  vim.cmd("silent! tabonly | silent! only")
  local origin_buf2 = H.scratch()
  local origin_win2 = vim.api.nvim_get_current_win()
  local b_buf2 = scratch.create({ "base" }, "[Diff:base] test2")
  local t_buf2 = scratch.create({ "target" }, "[Diff:target] test2")
  local tabs_before = #vim.api.nvim_list_tabpages()

  render.three_way(origin_win2, b_buf2, t_buf2, "tab")
  eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "tab: opens exactly one new tab")
  local tab_diffwins = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.wo[w].diff then
      tab_diffwins = tab_diffwins + 1
    end
  end
  eq(tab_diffwins, 3, "tab: three diffmode windows in the new tab")

  -- render.three_way(): invalid origin window --------------------------
  vim.cmd("silent! tabonly | silent! only")
  local msgs = {}
  local saved_notify = vim.notify
  vim.notify = function(m) msgs[#msgs + 1] = m end
  local b_buf3 = scratch.create({ "base" }, "[Diff:base] test3")
  local t_buf3 = scratch.create({ "target" }, "[Diff:target] test3")
  render.three_way(999999, b_buf3, t_buf3, "vsplit")
  vim.notify = saved_notify
  ok(#msgs > 0 and msgs[#msgs]:find("no longer valid", 1, true) ~= nil,
    "three_way() reports an error for an invalid origin window")

  -- core.run(): base= validation -------------------------------------------
  vim.cmd("silent! tabonly | silent! only")
  local core = require("diff.core")
  local base_file = vim.fn.tempname()
  vim.fn.writefile({ "base line" }, base_file)
  local target_file = vim.fn.tempname()
  vim.fn.writefile({ "target line" }, target_file)

  local function run_capturing(args)
    local out = {}
    local sn = vim.notify
    vim.notify = function(m) out[#out + 1] = m end
    core.run(args)
    vim.notify = sn
    return out
  end

  local err1 = run_capturing(string.format("target=%s base=%s output=stat", target_file, base_file))
  ok(#err1 > 0 and err1[#err1]:find("output=buffer", 1, true) ~= nil,
    "base= + output=stat is rejected")

  local err2 = run_capturing(string.format("target=%s base=%s view=inline", target_file, base_file))
  ok(#err2 > 0 and err2[#err2]:find("does not support view", 1, true) ~= nil,
    "base= + view=inline is rejected")

  local err3 = run_capturing(string.format("target=%s base=%s view=float", target_file, base_file))
  ok(#err3 > 0 and err3[#err3]:find("does not support view", 1, true) ~= nil,
    "base= + view=float is rejected")

  -- core.run(): end-to-end three-way diff -----------------------------------
  vim.cmd("silent! tabonly | silent! only")
  local live_buf = H.scratch()
  vim.api.nvim_buf_set_lines(live_buf, 0, -1, false, { "local line" })
  vim.notify = function() end
  core.run(string.format("target=%s base=%s", target_file, base_file))
  vim.notify = saved_notify

  eq(#vim.api.nvim_list_wins(), 3, "end-to-end: three windows open")
  eq(count_diff_wins(), 3, "end-to-end: all three windows are in diffmode")
  local shows_live = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == live_buf then
      shows_live = true
    end
  end
  ok(shows_live, "end-to-end: the live current buffer is one of the three windows")

  vim.cmd("silent! tabonly | silent! only")
end

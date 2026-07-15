---@module 'diff_nvim.features.conflict_marks'
---@brief Highlight Git conflict markers (<<<<<<< / ======= / >>>>>>>) per-window.
---@description
--- Ported from the host config's former `autocmds.git.conflict_marks`.
--- diff.nvim already renders diff/hunk state elsewhere (vsplit/split/inline);
--- conflict-marker highlighting is the same domain, just a different trigger
--- (BufWinEnter/BufWinLeave instead of a :Diff invocation).

local api, fn = vim.api, vim.fn

local M = {}

---@param name string
---@return integer
local function augroup(name)
  return api.nvim_create_augroup("diff_nvim_conflict_marks_" .. name, { clear = true })
end

---Register the BufWinEnter/BufWinLeave conflict-marker highlight autocmds.
---@param cfg DiffNvim.Config.ConflictMarks
---@return nil
function M.setup(cfg)
  cfg = cfg or {}

  api.nvim_create_autocmd("BufWinEnter", {
    group = augroup("on"),
    callback = function()
      local id_a = fn.matchadd(cfg.hl_a or "DiffDelete", [[^<<<<<<< .\+$]])
      local id_b = fn.matchadd(cfg.hl_b or "DiffChange", [[^=======\s*$]])
      local id_c = fn.matchadd(cfg.hl_c or "DiffAdd", [[^>>>>>>> .\+$]])
      vim.w._diff_nvim_conflict_match_ids = { id_a, id_b, id_c }
    end,
    desc = "[diff] Highlight conflict markers",
  })

  api.nvim_create_autocmd("BufWinLeave", {
    group = augroup("off"),
    callback = function()
      local ids = vim.w._diff_nvim_conflict_match_ids
      if type(ids) == "table" then
        for _, id in ipairs(ids) do
          pcall(fn.matchdelete, id)
        end
      end
      vim.w._diff_nvim_conflict_match_ids = nil
    end,
    desc = "[diff] Clear conflict marker highlights",
  })
end

return M

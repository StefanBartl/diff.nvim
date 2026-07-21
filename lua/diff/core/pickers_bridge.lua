---@module 'diff.core.pickers_bridge'
---@brief Optional select_fn bridge to pickers.nvim (StefanBartl/pickers.nvim).
---@description
--- pickers.nvim already resolves which fuzzy-picker engine (telescope.nvim,
--- fzf-lua, snacks.nvim) is installed on the system and normalizes it behind
--- `pickers.engines`. When pickers.nvim is present and has a usable engine,
--- this module adapts its list picker into a vim.ui.select-compatible
--- function so diff.nvim's target/source pickers get fuzzy search for free
--- — no configuration required.
---
--- Fully optional and soft-failing: pickers.nvim absence, a missing engine,
--- or an internal API mismatch all just resolve to nil so the caller falls
--- back to vim.ui.select. Nothing here is require()d eagerly — resolution
--- only happens when a picker is actually about to be shown.
---
--- Note: pickers.nvim's engine picker has no reliable cross-engine "cancel"
--- signal (Esc simply closes without invoking a callback on any of the three
--- backends), so on cancel `on_choice` is never called here either — unlike
--- vim.ui.select, which always calls back with `(nil, nil)`. Callers that
--- rely on a cancel notification firing should account for this.

local M = {}

---Resolve a vim.ui.select-compatible function backed by pickers.nvim, or nil
---when pickers.nvim isn't installed or has no usable picker engine.
---@return (fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil)|nil
function M.resolve()
  local ok, engines = pcall(require, "pickers.engines")
  if not ok or type(engines) ~= "table" or type(engines.load) ~= "function" then
    return nil
  end

  local load_ok, engine = pcall(engines.load)
  if not load_ok or type(engine) ~= "table" or type(engine.pick_item) ~= "function" then
    return nil
  end

  return function(items, opts, on_choice)
    local prompt = (type(opts) == "table" and type(opts.prompt) == "string") and opts.prompt or "Select:"
    local call_ok = pcall(engine.pick_item, {
      items = items,
      prompt = prompt,
      on_select = function(item)
        if item == nil then
          on_choice(nil, nil)
          return
        end
        for i, v in ipairs(items) do
          if v == item then
            on_choice(item, i)
            return
          end
        end
        on_choice(item, nil)
      end,
    })
    if not call_ok then
      vim.ui.select(items, opts, on_choice)
    end
  end
end

return M

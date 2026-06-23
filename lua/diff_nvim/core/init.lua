---@module 'diff_nvim.core'
---@brief Orchestration for the :Diff workflow.
---@description
--- Ties the resolution, render, and scratch layers together. `run()` parses raw
--- command args, validates them, optionally shows an interactive target picker,
--- and finally dispatches to the right renderer via `execute()`.

local api = vim.api

local notify   = require("diff_nvim.util.notify")
local validate = require("diff_nvim.util.validate")
local config   = require("diff_nvim.config")
local resolve  = require("diff_nvim.core.resolve")
local render   = require("diff_nvim.core.render")
local scratch  = require("diff_nvim.core.scratch")

local M = {}

---@type string[]
local VALID_VIEWS = { "vsplit", "split", "inline" }

---@type string[]
local VALID_OUTPUTS = { "buffer", "prompt", "file", "clipboard" }

---@type string[]  Labels for the interactive target picker
local TARGET_CHOICES = { "clipboard", "file path …", "buffer number …" }

---Resolve a side to its lines, treating "current" as the snapshotted buffer.
---@param spec DiffNvim.Source|DiffNvim.Target
---@param label string
---@param source_bufnr integer
---@return string[]|nil lines, string|nil err
local function resolve_side(spec, label, source_bufnr)
  if spec == "current" then
    if not validate.buf_valid(source_bufnr) then
      return nil, label .. " buffer is no longer valid"
    end
    return api.nvim_buf_get_lines(source_bufnr, 0, -1, false), nil
  end
  return resolve.resolve_lines(spec, label)
end

---Run the diff with fully-resolved options.
---@param opts DiffNvim.ResolvedOpts
---@param ctx DiffNvim.Context
---@return nil
function M.execute(opts, ctx)
  local cfg = config.get().diff

  local src_lines, src_err = resolve_side(opts.source, "source", ctx.source_bufnr)
  if not src_lines then
    notify.error(src_err or "could not resolve source")
    return
  end

  local tgt_lines, tgt_err = resolve_side(opts.target, "target", ctx.source_bufnr)
  if not tgt_lines then
    notify.error(tgt_err or "could not resolve target")
    return
  end

  local src_label = (opts.source == "current") and ("buf:" .. ctx.source_bufnr) or tostring(opts.source)
  local tgt_label = tostring(opts.target)

  if opts.output == "prompt" then
    render.prompt(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
    return
  end
  if opts.output == "file" then
    render.file(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
    return
  end
  if opts.output == "clipboard" then
    render.clipboard(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
    return
  end

  -- output == "buffer"
  local exit = require("diff_nvim.features.exit")

  if opts.view == "inline" then
    local buf = render.inline(ctx.origin_win, src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
    if buf then
      exit.attach_buffer(buf)
    end
    return
  end

  local buf = scratch.create(tgt_lines, string.format("[Diff] %s", tgt_label))
  render.side_by_side(ctx.origin_win, buf, opts.view)
  exit.attach_buffer(buf)
end

---Show the interactive target picker; calls `callback` with the chosen
---specifier string, or nil on cancel.
---@param callback fun(target: string|nil): nil
---@return nil
local function pick_target(callback)
  local select_fn = config.get().select_fn
  if type(select_fn) ~= "function" then
    select_fn = vim.ui.select
  end

  select_fn(TARGET_CHOICES, { prompt = "Diff target:" }, function(choice, idx)
    if not choice then
      callback(nil)
      return
    end
    if idx == 1 then
      callback("clipboard")
    elseif idx == 2 then
      vim.ui.input({ prompt = "File path: ", completion = "file" }, function(path)
        callback((type(path) == "string" and path ~= "") and path or nil)
      end)
    elseif idx == 3 then
      vim.ui.input({ prompt = "Buffer number: " }, function(raw)
        local n = tonumber(raw)
        if n then
          callback(tostring(n))
        else
          notify.warn("Invalid buffer number")
          callback(nil)
        end
      end)
    end
  end)
end

---Parse raw command arguments and launch the diff workflow.
---When `target` is absent an interactive picker is shown first.
---@param raw_args string  Raw <args> delivered by nvim_create_user_command
---@return nil
function M.run(raw_args)
  ---@type DiffNvim.Context
  local ctx = {
    source_bufnr = api.nvim_get_current_buf(),
    origin_win   = api.nvim_get_current_win(),
  }

  local cfg = config.get().diff
  local kv  = resolve.parse_args(type(raw_args) == "string" and raw_args or "")

  local view = kv.view or cfg.default_view
  if not validate.is_one_of(view, VALID_VIEWS) then
    notify.error(string.format("Unknown view=%q  (valid: %s)", view, table.concat(VALID_VIEWS, ", ")))
    return
  end

  local output = kv.output or cfg.default_output
  if not validate.is_one_of(output, VALID_OUTPUTS) then
    notify.error(string.format("Unknown output=%q  (valid: %s)", output, table.concat(VALID_OUTPUTS, ", ")))
    return
  end

  ---@type DiffNvim.ResolvedOpts
  local opts = {
    target = "",
    source = kv.source or cfg.default_source,
    view   = view --[[@as DiffNvim.View]],
    output = output --[[@as DiffNvim.Output]],
  }

  if not kv.target or kv.target == "" then
    pick_target(function(chosen)
      if not chosen then
        notify.info("Diff cancelled")
        return
      end
      opts.target = chosen
      M.execute(opts, ctx)
    end)
    return
  end

  opts.target = kv.target
  M.execute(opts, ctx)
end

---Close all diff.nvim scratch buffers and disable diffmode.
---@return nil
function M.clear()
  scratch.cleanup_all()
  notify.info("Diff cleared")
end

---Expose validity lists for completion/health without re-declaring them.
---@return string[] views, string[] outputs
function M.valid_lists()
  return VALID_VIEWS, VALID_OUTPUTS
end

return M

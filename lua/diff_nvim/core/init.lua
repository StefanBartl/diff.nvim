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
local VALID_VIEWS = { "vsplit", "split", "inline", "tab", "float" }

---@type string[]
local VALID_OUTPUTS = { "buffer", "prompt", "file", "clipboard", "stat" }

-- Picker choice labels (see pick_specifier).
local CHOICE_CURRENT   = "current buffer"
local CHOICE_CLIPBOARD = "clipboard"
local CHOICE_FILE      = "file path …"
local CHOICE_BUFFER    = "buffer number …"

---Resolve a side to its lines, treating "current" as the snapshotted buffer.
---When `range` is given (only meaningful for "current"), just the selected
---line span is returned instead of the whole buffer.
---@param spec DiffNvim.Source|DiffNvim.Target
---@param label string
---@param source_bufnr integer
---@param range DiffNvim.Range|nil
---@return string[]|nil lines, string|nil err
local function resolve_side(spec, label, source_bufnr, range)
  if spec == "current" then
    if not validate.buf_valid(source_bufnr) then
      return nil, label .. " buffer is no longer valid"
    end
    local first = range and (range.line1 - 1) or 0
    local last  = range and range.line2 or -1
    return api.nvim_buf_get_lines(source_bufnr, first, last, false), nil
  end
  -- `git:<rev>` resolves the current file at a git revision; it needs the name
  -- of the buffer :Diff was invoked from, which resolve.resolve_lines lacks.
  local git = require("diff_nvim.core.git")
  if git.is_git_spec(spec) then
    local bufname = validate.buf_valid(source_bufnr) and api.nvim_buf_get_name(source_bufnr) or ""
    return git.resolve(spec, bufname, label)
  end
  return resolve.resolve_lines(spec, label)
end

---Run the diff with fully-resolved options.
---@param opts DiffNvim.ResolvedOpts
---@param ctx DiffNvim.Context
---@return nil
function M.execute(opts, ctx)
  local cfg = config.get().diff

  -- The visual range applies to the source side only (the selection lives in
  -- the buffer that was current when :Diff was invoked).
  local src_lines, src_err = resolve_side(opts.source, "source", ctx.source_bufnr, ctx.range)
  if not src_lines then
    notify.error(src_err or "could not resolve source")
    return
  end

  local tgt_lines, tgt_err = resolve_side(opts.target, "target", ctx.source_bufnr, nil)
  if not tgt_lines then
    notify.error(tgt_err or "could not resolve target")
    return
  end

  local src_label
  if opts.source == "current" then
    src_label = "buf:" .. ctx.source_bufnr
    if ctx.range then
      src_label = src_label .. string.format("@%d-%d", ctx.range.line1, ctx.range.line2)
    end
  else
    src_label = tostring(opts.source)
  end
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
  if opts.output == "stat" then
    render.stat(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
    return
  end

  -- output == "buffer"
  local exit = require("diff_nvim.features.exit")

  if opts.view == "inline" or opts.view == "float" then
    local buf = render.inline(ctx.origin_win, src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen, {
      layout    = (opts.view == "float") and "float" or "split",
      word_diff = cfg.word_diff,
    })
    if buf then
      exit.attach_buffer(buf)
    end
    return
  end

  -- view == "vsplit" | "split" | "tab"
  local buf = scratch.create(tgt_lines, string.format("[Diff] %s", tgt_label))
  render.side_by_side(ctx.origin_win, buf, opts.view)
  exit.attach_buffer(buf)
end

---Prompt for a file path and hand it back (nil on empty/cancel).
---@param callback fun(spec: string|nil): nil
local function prompt_file(callback)
  vim.ui.input({ prompt = "File path: ", completion = "file" }, function(path)
    callback((type(path) == "string" and path ~= "") and path or nil)
  end)
end

---Prompt for a buffer number and hand it back (nil on invalid/cancel).
---@param callback fun(spec: string|nil): nil
local function prompt_buffer(callback)
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

---Show the interactive picker for a side; calls `callback` with the chosen
---specifier string, or nil on cancel. The source picker additionally offers
---"current buffer"; the target picker does not.
---@param kind "target"|"source"
---@param callback fun(spec: string|nil): nil
---@return nil
local function pick_specifier(kind, callback)
  local cfg = config.get()
  local select_fn = cfg.select_fn
  -- Explicit select_fn always wins. Otherwise, unless opted out, prefer
  -- pickers.nvim's fuzzy engine (if installed) over the flat vim.ui.select.
  if type(select_fn) ~= "function" and cfg.use_pickers_nvim ~= false then
    select_fn = require("diff_nvim.core.pickers_bridge").resolve()
  end
  if type(select_fn) ~= "function" then
    select_fn = vim.ui.select
  end

  local choices, handlers
  if kind == "source" then
    choices  = { CHOICE_CURRENT, CHOICE_CLIPBOARD, CHOICE_FILE, CHOICE_BUFFER }
    handlers = {
      function(cb) cb("current") end,
      function(cb) cb("clipboard") end,
      prompt_file,
      prompt_buffer,
    }
  else
    choices  = { CHOICE_CLIPBOARD, CHOICE_FILE, CHOICE_BUFFER }
    handlers = {
      function(cb) cb("clipboard") end,
      prompt_file,
      prompt_buffer,
    }
  end

  select_fn(choices, { prompt = "Diff " .. kind .. ":" }, function(choice, idx)
    if not choice or not idx or not handlers[idx] then
      callback(nil)
      return
    end
    handlers[idx](callback)
  end)
end

---Parse raw command arguments and launch the diff workflow.
---When `target` is absent an interactive picker is shown first.
---@param raw_args string  Raw <args> delivered by nvim_create_user_command
---@param range? DiffNvim.Range  Selected line span (only when :Diff got a range)
---@return nil
function M.run(raw_args, range)
  ---@type DiffNvim.Range|nil
  local sel = nil
  if type(range) == "table"
    and type(range.line1) == "number" and type(range.line2) == "number"
    and range.line2 >= range.line1 then
    sel = { line1 = range.line1, line2 = range.line2 }
  end

  ---@type DiffNvim.Context
  local ctx = {
    source_bufnr = api.nvim_get_current_buf(),
    origin_win   = api.nvim_get_current_win(),
    range        = sel,
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

  -- A missing target, or an explicit "ask", forces the interactive picker.
  local need_target = (not kv.target) or kv.target == "" or kv.target == "ask"
  local need_source = kv.source == "ask"

  local function pick_target_then_run()
    if not need_target then
      opts.target = kv.target
      M.execute(opts, ctx)
      return
    end
    pick_specifier("target", function(chosen)
      if not chosen then
        notify.info("Diff cancelled")
        return
      end
      opts.target = chosen
      M.execute(opts, ctx)
    end)
  end

  if need_source then
    pick_specifier("source", function(chosen)
      if not chosen then
        notify.info("Diff cancelled")
        return
      end
      opts.source = chosen
      pick_target_then_run()
    end)
    return
  end

  pick_target_then_run()
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

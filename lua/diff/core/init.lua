---@module 'diff.core'
---@brief Orchestration for the :Diff workflow.
---@description
--- Ties the resolution, render, and scratch layers together. `run()` parses raw
--- command args, validates them, optionally shows an interactive target picker,
--- and finally dispatches to the right renderer via `execute()`.

local api = vim.api

local notify   = require("diff.util.notify")
local validate = require("diff.util.validate")
local config   = require("diff.config")
local resolve  = require("diff.core.resolve")
local render   = require("diff.core.render")
local scratch  = require("diff.core.scratch")
local url      = require("diff.core.url")

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
---line span is returned instead of the whole buffer. Synchronous — url:// (@see
---`resolve_side_async`) specifiers never reach this function.
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
  local git = require("diff.core.git")
  if git.is_git_spec(spec) then
    local bufname = validate.buf_valid(source_bufnr) and api.nvim_buf_get_name(source_bufnr) or ""
    return git.resolve(spec, bufname, label)
  end
  return resolve.resolve_lines(spec, label)
end

---Resolve a side to its lines and hand `(lines, err)` to `callback`. Async
---only for `http(s)://` specifiers (@see docs/url-sources.md); every other
---specifier resolves synchronously and calls back immediately, so callers
---never need to know which path was taken.
---@param spec DiffNvim.Source|DiffNvim.Target
---@param label string
---@param source_bufnr integer
---@param range DiffNvim.Range|nil
---@param callback fun(lines: string[]|nil, err: string|nil): nil
---@return nil
local function resolve_side_async(spec, label, source_bufnr, range, callback)
  if url.is_url_spec(spec) then
    url.fetch(spec, label, { timeout_ms = config.get().diff.url_timeout_ms }, callback)
    return
  end
  callback(resolve_side(spec, label, source_bufnr, range))
end

---Run a three-way diff: the origin window keeps its live buffer (left/local
---— still editable, matching side_by_side's convention for output=buffer),
---`base` (middle/ancestor) and `target` (right/remote) each get a read-only
---scratch buffer. opts.source is deliberately not resolved here — exactly
---like the two-way output=buffer path, the origin window's live content is
---what's shown, so fetching/reading it separately would be wasted work (a
---discarded network round-trip for a url:// source, in the worst case).
---@see docs/three-way-diff.md
---@param opts DiffNvim.ResolvedOpts
---@param ctx DiffNvim.Context
---@return nil
local function execute_three_way(opts, ctx)
  resolve_side_async(opts.base, "base", ctx.source_bufnr, nil, function(base_lines, base_err)
    if not base_lines then
      notify.error(base_err or "could not resolve base")
      return
    end

    resolve_side_async(opts.target, "target", ctx.source_bufnr, nil, function(tgt_lines, tgt_err)
      if not tgt_lines then
        notify.error(tgt_err or "could not resolve target")
        return
      end

      local base_label = tostring(opts.base)
      local tgt_label  = tostring(opts.target)
      local base_buf = scratch.create(base_lines, string.format("[Diff:base] %s", base_label))
      local tgt_buf  = scratch.create(tgt_lines, string.format("[Diff:target] %s", tgt_label))

      render.three_way(ctx.origin_win, base_buf, tgt_buf, opts.view)

      local exit = require("diff.features.exit")
      exit.attach_buffer(base_buf)
      exit.attach_buffer(tgt_buf)
    end)
  end)
end

---Run the diff with fully-resolved options.
---@param opts DiffNvim.ResolvedOpts
---@param ctx DiffNvim.Context
---@return nil
function M.execute(opts, ctx)
  if opts.base then
    execute_three_way(opts, ctx)
    return
  end

  local cfg = config.get().diff

  -- The visual range applies to the source side only (the selection lives in
  -- the buffer that was current when :Diff was invoked). Nested rather than
  -- parallel because a URL fetch is the one path that's genuinely async; every
  -- other specifier's callback fires synchronously within the same tick.
  resolve_side_async(opts.source, "source", ctx.source_bufnr, ctx.range, function(src_lines, src_err)
    if not src_lines then
      notify.error(src_err or "could not resolve source")
      return
    end

    resolve_side_async(opts.target, "target", ctx.source_bufnr, nil, function(tgt_lines, tgt_err)
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
      local exit = require("diff.features.exit")

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
    end)
  end)
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

---Resolve the effective picker function: an explicit select_fn always wins,
---otherwise pickers.nvim (if installed and not opted out), else vim.ui.select.
---@return fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil
local function resolve_select_fn()
  local cfg = config.get()
  local select_fn = cfg.select_fn
  if type(select_fn) ~= "function" and cfg.use_pickers_nvim ~= false then
    select_fn = require("diff.core.pickers_bridge").resolve()
  end
  if type(select_fn) ~= "function" then
    select_fn = vim.ui.select
  end
  return select_fn
end

---Show the interactive picker for a side; calls `callback` with the chosen
---specifier string, or nil on cancel. The source picker additionally offers
---"current buffer"; target and base do not (base is virtually never the
---current buffer in a three-way diff).
---@param kind "target"|"source"|"base"
---@param callback fun(spec: string|nil): nil
---@return nil
local function pick_specifier(kind, callback)
  local select_fn = resolve_select_fn()

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

---Resolve+validate view/output from parsed args, notifying on an invalid
---value. Shared by run() and run_buffers().
---@param kv table<string, string>
---@param cfg DiffNvim.Config.Diff
---@return string|nil view, string|nil output  Both nil when validation failed
local function resolve_view_output(kv, cfg)
  local view = kv.view or cfg.default_view
  if not validate.is_one_of(view, VALID_VIEWS) then
    notify.error(string.format("Unknown view=%q  (valid: %s)", view, table.concat(VALID_VIEWS, ", ")))
    return nil, nil
  end
  local output = kv.output or cfg.default_output
  if not validate.is_one_of(output, VALID_OUTPUTS) then
    notify.error(string.format("Unknown output=%q  (valid: %s)", output, table.concat(VALID_OUTPUTS, ", ")))
    return nil, nil
  end
  return view, output
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

  local view, output = resolve_view_output(kv, cfg)
  if not view then
    return
  end

  -- base= (three-way diff) only makes sense as native multi-window diffmode:
  -- prompt/file/clipboard/stat and inline/float are all fundamentally
  -- two-input concepts (a single unified diff), not representable as three.
  local has_base = type(kv.base) == "string" and kv.base ~= ""
  if has_base then
    if output ~= "buffer" then
      notify.error(string.format("base= (three-way diff) only supports output=buffer, got output=%q", output))
      return
    end
    if view == "inline" or view == "float" then
      notify.error(string.format(
        "base= (three-way diff) does not support view=%q (use vsplit, split, or tab)", view))
      return
    end
  end

  ---@type DiffNvim.ResolvedOpts
  local opts = {
    target = "",
    source = kv.source or cfg.default_source,
    base   = has_base and kv.base or nil,
    view   = view --[[@as DiffNvim.View]],
    output = output --[[@as DiffNvim.Output]],
  }

  -- A missing target, or an explicit "ask", forces the interactive picker.
  local need_target = (not kv.target) or kv.target == "" or kv.target == "ask"
  local need_source = kv.source == "ask"
  local need_base   = has_base and kv.base == "ask"

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

  local function pick_base_then_target_then_run()
    if not need_base then
      pick_target_then_run()
      return
    end
    pick_specifier("base", function(chosen)
      if not chosen then
        notify.info("Diff cancelled")
        return
      end
      opts.base = chosen
      pick_target_then_run()
    end)
  end

  if need_source then
    pick_specifier("source", function(chosen)
      if not chosen then
        notify.info("Diff cancelled")
        return
      end
      opts.source = chosen
      pick_base_then_target_then_run()
    end)
    return
  end

  pick_base_then_target_then_run()
end

---Diff the current buffer against another open buffer chosen from a picker.
---Convenience wrapper over `target=<bufnr>`; only `view=`/`output=` args apply
---(the source is always the current buffer).
---@param raw_args string  Raw <args> (view=/output= only)
---@return nil
function M.run_buffers(raw_args)
  ---@type DiffNvim.Context
  local ctx = {
    source_bufnr = api.nvim_get_current_buf(),
    origin_win   = api.nvim_get_current_win(),
  }

  local cfg = config.get().diff
  local kv  = resolve.parse_args(type(raw_args) == "string" and raw_args or "")

  local view, output = resolve_view_output(kv, cfg)
  if not view then
    return
  end

  -- Collect every other listed, loaded buffer as a diff candidate.
  local items = {}
  local by_label = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if b ~= ctx.source_bufnr
      and api.nvim_buf_is_loaded(b)
      and vim.bo[b].buflisted
      and validate.buf_valid(b) then
      local name = api.nvim_buf_get_name(b)
      local disp = (name ~= "") and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
      local label = string.format("buf %d  %s", b, disp)
      items[#items + 1] = label
      by_label[label] = b
    end
  end

  if #items == 0 then
    notify.warn("No other listed buffers to diff against")
    return
  end

  resolve_select_fn()(items, { prompt = "Diff against buffer:" }, function(choice)
    local bufnr = choice and by_label[choice]
    if not bufnr then
      notify.info("Diff cancelled")
      return
    end
    ---@type DiffNvim.ResolvedOpts
    M.execute({
      target = tostring(bufnr),
      source = "current",
      view   = view --[[@as DiffNvim.View]],
      output = output --[[@as DiffNvim.Output]],
    }, ctx)
  end)
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

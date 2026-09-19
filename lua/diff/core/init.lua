---@module 'diff.core'
--- Orchestration for the :Diff workflow.
---
--- Ties the resolution, render, and scratch layers together. `run()` parses raw
--- command args, validates them, optionally shows an interactive target picker,
--- and finally dispatches to the right renderer via `execute()`.

local api = vim.api
local expand_path = require("lib.nvim.cross.fs.expand_path")

local notify = require("diff.util.notify")
local validate = require("diff.util.validate")
local config = require("diff.config")
local resolve = require("diff.core.resolve")
local render = require("diff.core.render")
local scratch = require("diff.core.scratch")
local url = require("diff.core.url")

local M = {}

---@type string[]
local VALID_VIEWS = { "vsplit", "split", "inline", "tab", "float" }

---@type string[]
local VALID_OUTPUTS = { "buffer", "prompt", "file", "clipboard", "stat" }

---@type string[]  Recognized `key=value` args for :Diff / M.run
local KNOWN_RUN_KEYS = { "target", "source", "base", "view", "output" }

---@type string[]  Recognized `key=value` args for :DiffBuffers / M.run_buffers
local KNOWN_RUN_BUFFERS_KEYS = { "view", "output" }

---@internal
---Warn about any arg key `parse_args` did not recognize (ERR-10) -- a
---misspelled key must not read the same as no key at all.
---@param unknown string[]
---@param known string[]
---@return nil
local function warn_unknown_keys(unknown, known)
  if #unknown == 0 then
    return
  end
  notify.warn(
    string.format(
      "Unknown arg key(s): %s -- ignoring (accepted: %s)",
      table.concat(unknown, ", "),
      table.concat(known, ", ")
    )
  )
end

-- Picker choice labels (see pick_specifier).
local CHOICE_CURRENT = "current buffer"
local CHOICE_CLIPBOARD = "clipboard"
local CHOICE_FILE = "file path …"
local CHOICE_BUFFER = "buffer number …"

---Resolve a side to its lines, treating "current" as the snapshotted buffer.
---When `range` is given (only meaningful for "current"), just the selected
---line span is returned instead of the whole buffer. Synchronous — url:// and
---git:<rev> (@see `resolve_side_async`) specifiers never reach this function.
---@internal
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
    local last = range and range.line2 or -1
    return api.nvim_buf_get_lines(source_bufnr, first, last, false), nil
  end
  -- `git:<rev>` is deliberately absent here: it resolves through a subprocess
  -- and therefore lives in resolve_side_async below, next to the url path.
  return resolve.resolve_lines(spec, label)
end

---Resolve a side to its lines and hand `(lines, err)` to `callback`. Async for
---`http(s)://` specifiers (@see docs/url-sources.md) and for `git:<rev>`, which
---shells out to `git show`; every other specifier resolves synchronously and
---calls back immediately, so callers never need to know which path was taken.
---@param spec DiffNvim.Source|DiffNvim.Target
---@param label string
---@param ctx DiffNvim.Context
---@param range DiffNvim.Range|nil
---@internal
---@param callback fun(lines: string[]|nil, err: string|nil): nil
---@return nil
local function resolve_side_async(spec, label, ctx, range, callback)
  if url.is_url_spec(spec) then
    url.fetch(spec --[[@as string]], label, {
      timeout_ms = config.get().diff.url_timeout_ms,
      max_bytes = config.get().diff.url_max_bytes,
    }, callback)
    return
  end

  -- `git:<rev>` resolves the current file at a git revision; it needs the name
  -- of the buffer :Diff was invoked from, which resolve.resolve_lines lacks.
  -- `git show` is a subprocess, so this belongs on the async path -- a
  -- three-way diff resolves two sides and would otherwise block twice.
  local git = require("diff.core.git")
  if git.is_git_spec(spec) then
    -- ctx.anchor overrides the buffer-derived name: a `git:<rev>:<path>`
    -- explicit-path spec's repo-root lookup has nothing to do with whatever
    -- buffer happened to be current when :Diff (or a caller like
    -- core/history.lua) was invoked, and using it anyway breaks for an
    -- unnamed current buffer or one that lives in a different repository
    -- than the explicit path names -- see core/history.lua's own doc
    -- comment on why it sets ctx.anchor.
    local bufname = ctx.anchor
      or (validate.buf_valid(ctx.source_bufnr) and api.nvim_buf_get_name(ctx.source_bufnr) or "")
    git.resolve(spec --[[@as string]], bufname, label, callback)
    return
  end

  callback(resolve_side(spec, label, ctx.source_bufnr, range))
end

---A label always has to stay on one line: `with_header` writes exactly two
---header lines ("--- a" / "+++ b") and `render.apply_word_diff` counts on the
---diff body starting at line 3. A buffer name may legitimately contain
---newlines (nvim accepts them, and a filename can carry one on Linux/macOS),
---which would otherwise push extra lines -- including a forged `@@` hunk
---header -- into a diff that `output=file`/`clipboard` hands to `git apply`.
---Control characters are folded to a space for the same reason.
---@internal
---@param label string
---@return string
local function one_line(label)
  return (label:gsub("%c", " "))
end

---Human-readable label for a resolved side, used in the unified-diff header
---("--- <label>" / "+++ <label>") and in scratch-buffer names.
---
---A numeric specifier is the one kind that labels itself badly: `--- 7` says
---nothing about what buffer 7 holds, and it is the shape an integrating
---plugin naturally produces (it hands `:Diff` a scratch buffer it just
---created). Resolve it to that buffer's own name, shortened relative to the
---cwd/$HOME so it reads like a typed-in path specifier does, and fall back to
---`buf:N` for an unnamed buffer -- the same shape `source=current` already
---uses. Every other specifier (a file path, "clipboard", `git:<rev>`, a URL)
---is already its own best label and is passed through unchanged.
---@internal
---@param spec DiffNvim.Source|DiffNvim.Target
---@return string
local function side_label(spec)
  local bufnr = resolve.as_bufnr(spec)
  if bufnr == nil then
    return one_line(tostring(spec))
  end
  local name = validate.buf_valid(bufnr) and api.nvim_buf_get_name(bufnr) or ""
  if name == "" then
    return string.format("buf:%d", bufnr)
  end
  local short = vim.fn.fnamemodify(name, ":~:.")
  return one_line((type(short) == "string" and short ~= "") and short or name)
end

---Wrap a caller's `on_done` into a `(result, err)` pair of reporters that
---are safe to call unconditionally and exactly once.
---
---Every terminal branch of a diff ends in one of these two, including the
---ones that only notify, so a caller gets told the run is over on paths that
---produce nothing to show (`output=stat`, or two identical sides) just as
---much as on the ones that open windows. `on_done` runs inside pcall: it is
---third-party code reached from our async callbacks, and an error thrown
---there must not surface as an unhandled error inside a URL fetch.
---The third return value is that same guard as a plain `on_done`, for
---passing on to code that will wrap it again. `M.run` hands it to
---`M.execute` rather than the caller's own function: each would otherwise
---build its own guard, and the flag only spans one of them, so a picker that
---invokes its callback twice produced a `fail` from one instance and a `done`
---from the other -- two calls, against a documented "exactly once".
---@internal
---@param on_done DiffNvim.RunOpts.OnDone|nil
---@return fun(result: DiffNvim.Result): nil done
---@return fun(err: string): nil fail
---@return DiffNvim.RunOpts.OnDone|nil guarded
local function reporters(on_done)
  if type(on_done) ~= "function" then
    return function() end, function() end, nil
  end

  local fired = false
  local function call(result, err)
    if fired then
      return
    end
    fired = true
    -- Not propagated: this is third-party code reached from our own async
    -- callbacks, and an error here must not surface inside a URL fetch. Not
    -- swallowed either -- an integration whose callback dies would otherwise
    -- get no signal at all, from anywhere.
    local ok, caller_err = pcall(on_done, result, err)
    if not ok then
      notify.error("on_done failed: " .. tostring(caller_err))
    end
  end
  return function(result)
    call(result, nil)
  end, function(err)
    call(nil, err)
  end, function(result, err)
    call(result, err)
  end
end

---Run a three-way diff: the origin window keeps its live buffer (left/local
---— still editable, which is the point of the layout), `base`
---(middle/ancestor) and `target` (right/remote) each get a read-only scratch
---buffer. opts.source is deliberately not resolved here: local is always the
---live buffer, so fetching/reading a source separately would be wasted work
---(a discarded network round-trip for a url:// source, in the worst case).
---Unlike the two-way path, which materializes a non-`current` source into its
---own window, a three-way diff has no window to put one in — `M.run` rejects
---an explicit `source=` alongside `base=` up front rather than accepting one
---and quietly ignoring it.
---@see docs/three-way-diff.md
---@internal
---@param opts DiffNvim.ResolvedOpts
---@param ctx DiffNvim.Context
---@param on_done DiffNvim.RunOpts.OnDone|nil
---@return nil
local function execute_three_way(opts, ctx, on_done)
  local done, fail = reporters(on_done)

  resolve_side_async(opts.base, "base", ctx, nil, function(base_lines, base_err)
    if not base_lines then
      base_err = base_err or "could not resolve base"
      notify.error(base_err)
      fail(base_err)
      return
    end

    resolve_side_async(opts.target, "target", ctx, nil, function(tgt_lines, tgt_err)
      if not tgt_lines then
        tgt_err = tgt_err or "could not resolve target"
        notify.error(tgt_err)
        fail(tgt_err)
        return
      end

      local base_label = side_label(opts.base)
      local tgt_label = side_label(opts.target)
      local base_buf = scratch.create(base_lines, string.format("[Diff:base] %s", base_label))
      local tgt_buf = scratch.create(tgt_lines, string.format("[Diff:target] %s", tgt_label))

      local windows = render.three_way(
        ctx.origin_win,
        base_buf,
        tgt_buf,
        opts.view --[[@as "vsplit"|"split"|"tab"]]
      )
      if not windows then
        -- Never displayed, so nothing will ever wipe these two.
        scratch.discard(base_buf)
        scratch.discard(tgt_buf)
        fail("could not open the three-way diff")
        return
      end

      local exit = require("diff.features.exit")
      exit.attach_buffer(base_buf)
      exit.attach_buffer(tgt_buf)

      done({
        output = opts.output,
        view = opts.view,
        buffers = { base_buf, tgt_buf },
        windows = windows,
      })
    end)
  end)
end

---@internal
---Resolve a raw target/source spec to a real quickfix/location-list
---location, for `render.push_stat_list`'s optional navigation — mirrors
---`resolve.resolve_lines`'s own buffer-number-vs-file-path dispatch, since
---those are the only two specifier kinds with an on-disk/in-buffer identity
---of their own. "current"/"clipboard"/`git:<rev>`/`http(s)://` specifiers
---have none, so they resolve to `nil` (the entry is still listed, just not
---jump-able — see `push_stat_list`'s own doc comment).
---@param spec DiffNvim.Source|DiffNvim.Target
---@return { filename: string }|{ bufnr: integer }|nil
local function stat_list_target(spec)
  if type(spec) ~= "string" then
    return nil
  end
  local bufnr = resolve.as_bufnr(spec)
  if bufnr ~= nil then
    return { bufnr = bufnr }
  end
  if
    spec == "current"
    or spec == "clipboard"
    or url.is_url_spec(spec)
    or require("diff.core.git").is_git_spec(spec)
  then
    return nil
  end
  -- expand_path, not vim.fn.expand (SEC-34): `spec` is the raw `:Diff <spec>`
  -- argument -- vim.fn.expand() would run a backtick span through &shell.
  local path = expand_path(spec)
  if vim.fn.filereadable(path) == 1 then
    return { filename = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")) }
  end
  return nil
end

---Run the diff with fully-resolved options.
---@param opts DiffNvim.ResolvedOpts
---@param ctx DiffNvim.Context
---@param on_done? DiffNvim.RunOpts.OnDone  Called once when the diff finishes
---@return nil
function M.execute(opts, ctx, on_done)
  if opts.base then
    execute_three_way(opts, ctx, on_done)
    return
  end

  local done, fail = reporters(on_done)

  -- source= and target= both resolving to real, existing directories: this
  -- is a directory/recursive diff (a per-file summary), not a single
  -- unified diff — dispatched to core.directory entirely, before the
  -- image-compare check and the normal resolve_side_async pipeline below
  -- (which would just fail with "file not readable" on a directory path).
  local directory = require("diff.core.directory")
  if directory.is_directory_spec(opts.source) and directory.is_directory_spec(opts.target) then
    local dir_result, dir_err = directory.run(
      opts.source --[[@as string]],
      opts.target --[[@as string]],
      tostring(opts.source),
      tostring(opts.target),
      opts.output,
      config.get().diff
    )
    if dir_result then
      done(dir_result)
    else
      fail(dir_err or "could not diff directories")
    end
    return
  end

  -- Both sides look like raster-image files: show them side by side via
  -- images.nvim instead of text-diffing raw bytes (see
  -- diff.features.image_compare's moduledoc for why). "current" (a live
  -- buffer) never matches this, so it never fires for the common
  -- current-vs-target case.
  if require("diff.features.image_compare").maybe_compare(opts.source, opts.target) then
    -- images.nvim owns whatever it opened; none of it is ours to report. No
    -- `view` either: this comparison ignores view= entirely, so naming one
    -- would describe a layout that was never applied (same for a directory
    -- diff -- @see DiffNvim.Result).
    done({ output = opts.output, buffers = {}, windows = {} })
    return
  end

  local cfg = config.get().diff

  -- Whether the left-hand side of this diff is the origin window's own live
  -- buffer rather than content we have to produce. That is the case for the
  -- native-diffmode views when the source really is that buffer in full --
  -- `source=current` (the default) with no range -- and it is worth keeping:
  -- the left side stays editable, so :diffget/:diffput write into the file
  -- being saved (the same property three-way diffs rely on, see
  -- docs/three-way-diff.md).
  --
  -- Every other source (a buffer number, a file path, clipboard, git:<rev>, a
  -- URL) and every range resolve to lines that are *not* what that window is
  -- showing, and get a read-only scratch buffer of their own further down.
  --
  -- Decided here, before anything is resolved, because it answers two
  -- questions at once: which buffer goes on the left, and whether the source
  -- has to be read at all. When the live buffer is the left-hand side its
  -- content is never used, and resolving it would copy the whole buffer into
  -- a Lua table only to drop it -- the same waste `execute_three_way` avoids.
  local uses_origin_buffer = opts.output == "buffer"
    and (opts.view == "vsplit" or opts.view == "split" or opts.view == "tab")
    and opts.source == "current"
    and ctx.range == nil

  ---@internal
  ---Hand the source side's lines to `callback`, or skip straight to it with an
  ---empty list when they are not going to be read (see `uses_origin_buffer`).
  ---@param callback fun(lines: string[]|nil, err: string|nil): nil
  ---@return nil
  local function resolve_source(callback)
    if not uses_origin_buffer then
      -- The visual range applies to the source side only (the selection lives
      -- in the buffer that was current when :Diff was invoked).
      resolve_side_async(opts.source, "source", ctx, ctx.range, callback)
      return
    end
    if not validate.buf_valid(ctx.source_bufnr) then
      callback(nil, "source buffer is no longer valid")
      return
    end
    callback({}, nil)
  end

  -- Nested rather than parallel because a URL fetch is the one path that's
  -- genuinely async; every other specifier's callback fires synchronously
  -- within the same tick.
  resolve_source(function(src_lines, src_err)
    if not src_lines then
      src_err = src_err or "could not resolve source"
      notify.error(src_err)
      fail(src_err)
      return
    end

    resolve_side_async(opts.target, "target", ctx, nil, function(tgt_lines, tgt_err)
      if not tgt_lines then
        tgt_err = tgt_err or "could not resolve target"
        notify.error(tgt_err)
        fail(tgt_err)
        return
      end

      local src_label
      if opts.source == "current" then
        src_label = "buf:" .. ctx.source_bufnr
        if ctx.range then
          src_label = src_label .. string.format("@%d-%d", ctx.range.line1, ctx.range.line2)
        end
      else
        src_label = side_label(opts.source)
      end
      local tgt_label = side_label(opts.target)

      -- The text outputs create nothing the caller could take down again, so
      -- they all report the same empty result -- what matters to a caller is
      -- that the run is over, which is just as true here as it is for a
      -- window-opening view. output=file adds the path it wrote.
      ---Report a text output: nothing was created that a caller could take
      ---down again, so the result is empty either way -- but "nothing to
      ---show" and "it could not be produced" are opposite outcomes and each
      ---renderer says which it was (@see render.prompt).
      ---@param render_err string|nil
      ---@param path string|nil
      ---@return nil
      local function finish_text_output(render_err, path)
        if render_err then
          fail(render_err)
          return
        end
        done({ output = opts.output, buffers = {}, windows = {}, path = path })
      end

      if opts.output == "prompt" then
        finish_text_output(
          render.prompt(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
        )
        return
      end
      if opts.output == "file" then
        local path, file_err =
          render.file(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
        finish_text_output(file_err, path)
        return
      end
      if opts.output == "clipboard" then
        finish_text_output(
          render.clipboard(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen)
        )
        return
      end
      if opts.output == "stat" then
        finish_text_output(
          render.stat(src_lines, tgt_lines, src_label, tgt_label, cfg.algorithm, cfg.ctxlen, {
            list = cfg.stat_list,
            mode = cfg.stat_list_mode,
            target = stat_list_target(opts.target),
          })
        )
        return
      end

      -- output == "buffer"
      local exit = require("diff.features.exit")

      if opts.view == "inline" or opts.view == "float" then
        local buf, win = render.inline(
          ctx.origin_win,
          src_lines,
          tgt_lines,
          src_label,
          tgt_label,
          cfg.algorithm,
          cfg.ctxlen,
          {
            layout = (opts.view == "float") and "float" or "split",
            word_diff = cfg.word_diff,
          }
        )
        if buf then
          exit.attach_buffer(buf)
        end
        -- No buffer means render.inline found nothing to show (identical
        -- sides) or could not compute the diff; the first is a result with
        -- nothing in it, not a failure, and it already said so itself.
        done({
          output = opts.output,
          view = opts.view,
          buffers = buf and { buf } or {},
          windows = win and { win } or {},
        })
        return
      end

      -- view == "vsplit" | "split" | "tab"
      --
      -- `uses_origin_buffer` (computed before the source was resolved, see
      -- above) decides whether the left-hand side is the origin window's
      -- own live buffer or a scratch buffer of its own.
      local src_buf = nil
      if not uses_origin_buffer then
        src_buf = scratch.create(src_lines, string.format("[Diff:source] %s", src_label))
      end

      local buf = scratch.create(tgt_lines, string.format("[Diff:target] %s", tgt_label))

      local windows = render.side_by_side(ctx.origin_win, buf, opts.view, src_buf)
      if not windows then
        -- Nothing was displayed, so nothing will ever wipe these two.
        if src_buf then
          scratch.discard(src_buf)
        end
        scratch.discard(buf)
        fail("could not open the diff")
        return
      end

      if src_buf then
        exit.attach_buffer(src_buf)
      end
      exit.attach_buffer(buf)

      done({
        output = opts.output,
        view = opts.view,
        buffers = src_buf and { src_buf, buf } or { buf },
        windows = windows,
      })
    end)
  end)
end

---@internal
---Prompt for a file path and hand it back (nil on empty/cancel).
---@param callback fun(spec: string|nil): nil
local function prompt_file(callback)
  require("ui.kit").input({
    title = "File path: ",
    completion = "file",
    on_submit = function(path)
      callback(path ~= "" and path or nil)
    end,
    on_cancel = function()
      callback(nil)
    end,
  })
end

---@internal
---Prompt for a buffer number and hand it back (nil on invalid/cancel).
---@param callback fun(spec: string|nil): nil
local function prompt_buffer(callback)
  require("ui.kit").input({
    title = "Buffer number: ",
    on_submit = function(raw)
      local n = tonumber(raw)
      if n then
        callback(tostring(n))
      else
        notify.warn("Invalid buffer number")
        callback(nil)
      end
    end,
    on_cancel = function()
      callback(nil)
    end,
  })
end

---Resolve an explicit select_fn or pickers.nvim backend, if configured/
---available. Returns nil when neither applies — callers supply their own
---last-resort fallback (kit.confirm's button row for pick_specifier's
---always-≤4 choices, kit.select for run_buffers' dynamic-length list).
---@internal
---@return (fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil)|nil
local function resolve_configured_select_fn()
  local cfg = config.get()
  local select_fn = cfg.select_fn
  if type(select_fn) ~= "function" and cfg.use_pickers_nvim ~= false then
    select_fn = require("diff.core.pickers_bridge").resolve()
  end
  if type(select_fn) == "function" then
    return select_fn
  end
  return nil
end

---vim.ui.select-shaped adapter over kit.select's respect_override: still
---defers to a real vim.ui.select override (telescope-ui-select,
---dressing.nvim, ...), but uses kit's own themed chooser instead of the
---plain builtin vim.ui.select when nothing has overridden it. Used for
---run_buffers' dynamic-length buffer list, which isn't a good fit for
---kit_confirm_select's button row (see pick_specifier below).
---@internal
---@param items string[]
---@param opts table  # { prompt?, format_item? }
---@param on_choice fun(choice: string|nil, idx: integer|nil): nil
local function kit_select_select(items, opts, on_choice)
  require("ui.kit").select({
    items = items,
    title = opts and opts.prompt,
    format_item = opts and opts.format_item,
    respect_override = true,
    on_select = on_choice,
    -- kit.select reports cancellation through on_cancel rather than by
    -- calling on_select with nil; translate back, since this adapter is
    -- interchangeable with the vim.ui.select-shaped cfg.select_fn and
    -- pickers.nvim bridge (and run_buffers relies on the nil call for its
    -- "Diff cancelled" notice). Same translation kit_confirm_select does.
    on_cancel = function()
      on_choice(nil, nil)
    end,
  })
end

---Resolve the effective picker function: an explicit select_fn always wins,
---otherwise pickers.nvim (if installed and not opted out), else kit.select
---(itself deferring to a real vim.ui.select override, if any).
---@internal
---@return fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil
local function resolve_select_fn()
  return resolve_configured_select_fn() or kit_select_select
end

---vim.ui.select-shaped adapter over kit.confirm's button row — the default
---fallback for pick_specifier, whose choice lists are always ≤4 long (a
---natural fit for buttons, unlike run_buffers' dynamic-length buffer list,
---which uses kit_select_select above).
---@internal
---@param items string[]
---@param opts table  # { prompt? }
---@param on_choice fun(choice: string|nil, idx: integer|nil): nil
local function kit_confirm_select(items, opts, on_choice)
  require("ui.kit.confirm").open({
    question = (opts and opts.prompt) or "Select",
    choices = items,
    on_answer = function(choice)
      if choice == nil then
        on_choice(nil, nil)
        return
      end
      for i, item in ipairs(items) do
        if item == choice then
          on_choice(choice, i)
          return
        end
      end
      on_choice(nil, nil)
    end,
  })
end

---Show the interactive picker for a side; calls `callback` with the chosen
---specifier string, or nil on cancel. The source picker additionally offers
---"current buffer"; target and base do not (base is virtually never the
---current buffer in a three-way diff).
---@internal
---@param kind "target"|"source"|"base"
---@param callback fun(spec: string|nil): nil
---@return nil
local function pick_specifier(kind, callback)
  local select_fn = resolve_configured_select_fn() or kit_confirm_select

  local choices, handlers
  if kind == "source" then
    choices = { CHOICE_CURRENT, CHOICE_CLIPBOARD, CHOICE_FILE, CHOICE_BUFFER }
    handlers = {
      function(cb)
        cb("current")
      end,
      function(cb)
        cb("clipboard")
      end,
      prompt_file,
      prompt_buffer,
    }
  else
    choices = { CHOICE_CLIPBOARD, CHOICE_FILE, CHOICE_BUFFER }
    handlers = {
      function(cb)
        cb("clipboard")
      end,
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
---@internal
---@param kv table<string, string>
---@param cfg DiffNvim.Config.Diff
---@return string|nil view, string|nil output  Both nil when validation failed
local function resolve_view_output(kv, cfg)
  local view = kv.view or cfg.default_view
  if not validate.is_one_of(view, VALID_VIEWS) then
    notify.error(
      string.format("Unknown view=%q  (valid: %s)", view, table.concat(VALID_VIEWS, ", "))
    )
    return nil, nil
  end
  local output = kv.output or cfg.default_output
  if not validate.is_one_of(output, VALID_OUTPUTS) then
    notify.error(
      string.format("Unknown output=%q  (valid: %s)", output, table.concat(VALID_OUTPUTS, ", "))
    )
    return nil, nil
  end
  return view, output
end

---Parse raw command arguments and launch the diff workflow.
---When `target` is absent an interactive picker is shown first.
---@param raw_args string  Raw <args> delivered by nvim_create_user_command
---@param range? DiffNvim.Range  Selected line span (only when :Diff got a range)
---@param run_opts? DiffNvim.RunOpts  Caller-side options (`on_done`)
---@return nil
function M.run(raw_args, range, run_opts)
  local _, fail, guarded_on_done = reporters(type(run_opts) == "table" and run_opts.on_done or nil)

  ---@type DiffNvim.Range|nil
  local sel = nil
  if
    type(range) == "table"
    and type(range.line1) == "number"
    and type(range.line2) == "number"
    and range.line2 >= range.line1
  then
    sel = { line1 = range.line1, line2 = range.line2 }
  end

  ---@type DiffNvim.Context
  local ctx = {
    source_bufnr = api.nvim_get_current_buf(),
    origin_win = api.nvim_get_current_win(),
    range = sel,
  }

  local cfg = config.get().diff
  local kv, unknown_kv =
    resolve.parse_args(type(raw_args) == "string" and raw_args or "", KNOWN_RUN_KEYS)
  warn_unknown_keys(unknown_kv, KNOWN_RUN_KEYS)

  -- target=git:<rev1>..<rev2> is sugar for diffing the file directly between
  -- two revisions, bypassing the working buffer entirely: expands to
  -- source=git:<rev1> target=git:<rev2>, overriding any source= given
  -- alongside it — the whole point is "two revisions", not "one revision
  -- against whatever source= would otherwise resolve to" (see
  -- docs/commands.md's git:<rev> section). Only target= is recognized: a
  -- range in source= wouldn't have a second thing to pair it with.
  do
    local rev_a, rev_b = resolve.split_git_range(kv.target)
    if rev_a then
      kv.source = "git:" .. rev_a
      kv.target = "git:" .. rev_b
    end
  end

  local view, output = resolve_view_output(kv, cfg)
  if not view then
    fail("invalid view= or output=")
    return
  end

  -- base= (three-way diff) only makes sense as native multi-window diffmode:
  -- prompt/file/clipboard/stat and inline/float are all fundamentally
  -- two-input concepts (a single unified diff), not representable as three.
  local has_base = type(kv.base) == "string" and kv.base ~= ""
  if has_base then
    if output ~= "buffer" then
      local msg =
        string.format("base= (three-way diff) only supports output=buffer, got output=%q", output)
      notify.error(msg)
      fail(msg)
      return
    end
    if view == "inline" or view == "float" then
      local msg = string.format(
        "base= (three-way diff) does not support view=%q (use vsplit, split, or tab)",
        view
      )
      notify.error(msg)
      fail(msg)
      return
    end
    -- The local side of a three-way diff is always the origin window's live
    -- buffer -- there is no third window to put a materialized source in, the
    -- way the two-way side-by-side views have. Only an *explicitly given*
    -- source= is rejected: a configured `default_source` must not make every
    -- three-way diff fail, and "ask" would just pick something we then could
    -- not honour either.
    if type(kv.source) == "string" and kv.source ~= "" and kv.source ~= "current" then
      local msg = string.format(
        "base= (three-way diff) only supports source=current, got source=%q",
        kv.source
      )
      notify.error(msg)
      fail(msg)
      return
    end
  end

  ---@type DiffNvim.ResolvedOpts
  local opts = {
    target = "",
    source = kv.source or cfg.default_source,
    base = has_base and kv.base or nil,
    view = view --[[@as DiffNvim.View]],
    output = output --[[@as DiffNvim.Output]],
  }

  -- A missing target, or an explicit "ask", forces the interactive picker.
  local need_target = (not kv.target) or kv.target == "" or kv.target == "ask"
  local need_source = kv.source == "ask"
  local need_base = has_base and kv.base == "ask"

  -- A cancelled picker is not an error, but it is still "nothing was
  -- produced", and a caller waiting on on_done has to hear about it or it
  -- waits forever.
  local function cancelled()
    notify.info("Diff cancelled")
    fail("Diff cancelled")
  end

  local function pick_target_then_run()
    if not need_target then
      opts.target = kv.target
      M.execute(opts, ctx, guarded_on_done)
      return
    end
    pick_specifier("target", function(chosen)
      if not chosen then
        cancelled()
        return
      end
      opts.target = chosen
      M.execute(opts, ctx, guarded_on_done)
    end)
  end

  local function pick_base_then_target_then_run()
    if not need_base then
      pick_target_then_run()
      return
    end
    pick_specifier("base", function(chosen)
      if not chosen then
        cancelled()
        return
      end
      opts.base = chosen
      pick_target_then_run()
    end)
  end

  if need_source then
    pick_specifier("source", function(chosen)
      if not chosen then
        cancelled()
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
---@param run_opts? DiffNvim.RunOpts  Caller-side options (`on_done`)
---@return nil
function M.run_buffers(raw_args, run_opts)
  local _, fail, guarded_on_done = reporters(type(run_opts) == "table" and run_opts.on_done or nil)

  ---@type DiffNvim.Context
  local ctx = {
    source_bufnr = api.nvim_get_current_buf(),
    origin_win = api.nvim_get_current_win(),
  }

  local cfg = config.get().diff
  local kv, unknown_kv =
    resolve.parse_args(type(raw_args) == "string" and raw_args or "", KNOWN_RUN_BUFFERS_KEYS)
  warn_unknown_keys(unknown_kv, KNOWN_RUN_BUFFERS_KEYS)

  local view, output = resolve_view_output(kv, cfg)
  if not view then
    fail("invalid view= or output=")
    return
  end

  -- Collect every other listed, loaded buffer as a diff candidate.
  local items = {}
  local by_label = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if
      b ~= ctx.source_bufnr
      and api.nvim_buf_is_loaded(b)
      and vim.bo[b].buflisted
      and validate.buf_valid(b)
    then
      local name = api.nvim_buf_get_name(b)
      local disp = (name ~= "") and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
      local label = string.format("buf %d  %s", b, disp)
      items[#items + 1] = label
      by_label[label] = b
    end
  end

  if #items == 0 then
    local msg = "No other listed buffers to diff against"
    notify.warn(msg)
    fail(msg)
    return
  end

  resolve_select_fn()(items, { prompt = "Diff against buffer:" }, function(choice)
    local bufnr = choice and by_label[choice]
    if not bufnr then
      notify.info("Diff cancelled")
      fail("Diff cancelled")
      return
    end
    M.execute({
      target = tostring(bufnr),
      source = "current",
      view = view --[[@as DiffNvim.View]],
      output = output --[[@as DiffNvim.Output]],
    }, ctx, guarded_on_done)
  end)
end

---Close all diff.nvim scratch buffers and disable diffmode.
---@return nil
function M.clear()
  scratch.cleanup_all()
  notify.info("Diff cleared")
end

---The effective picker function (explicit select_fn > pickers.nvim >
---kit.select), exposed for `core/history.lua`'s dynamic-length revision list
----- the same reasoning `run_buffers` above already needed this for.
---@return fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)): nil
function M.select_fn()
  return resolve_select_fn()
end

---Expose validity lists for completion/health without re-declaring them.
--- CDX: zero callers anywhere — health.lua and bindings/usrcmds.lua's
--- VALUE_LISTS both re-declare these lists instead. Wire one to this, or drop it.
---@return string[] views, string[] outputs
function M.valid_lists()
  return VALID_VIEWS, VALID_OUTPUTS
end

return M

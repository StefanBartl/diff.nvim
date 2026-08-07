---@module 'diff.features.image_compare'
---@brief Show two image file paths side by side via images.nvim instead of
---       text-diffing their raw bytes.
---@description
--- `diff.core.resolve` reads every non-"clipboard"/non-bufnr/non-git/non-url
--- spec as a plain text file via `vim.fn.readfile()` — fine for source code,
--- meaningless (silently garbled, not even an error) for a binary raster
--- image. This module intercepts the case where BOTH sides are readable
--- raster-image file paths and shows them side by side instead, via
--- images.nvim's gallery — a soft dependency, same pcall-guarded pattern
--- the rest of the *.nvim family uses.
---
--- svg is deliberately excluded: it is XML text and diffs perfectly well as
--- text (seeing which path data changed is often exactly the point) — only
--- the raster formats where "diff the bytes" is meaningless are covered.
---
--- No relative scaling between the two images, unlike images.nvim's own
--- `:Image compare`: that needs `lib.nvim.ui.kit.compare`'s SEARCH-first
--- flow to pick two items out of a directory scan, which doesn't fit here —
--- this module already has both exact paths from `:Diff`'s own arguments.
--- `images.gallery({a, b}, 2)` is the right primitive for that (same one
--- `:Image gallery` itself uses): no picker UI, no new API needed in either
--- dependency. `imports.graph.include_external`-style config
--- (`diff.image_compare`) turns this off entirely if ever wanted.

local M = {}

local IMAGE_EXTS = { png = 1, jpg = 1, jpeg = 1, gif = 1, webp = 1, bmp = 1 }

---@internal
---@param path string
---@return boolean
local function has_image_ext(path)
  local ext = path:match("%.([%w]+)$")
  return ext ~= nil and IMAGE_EXTS[ext:lower()] == 1
end

---Whether `spec` is a plain, existing, raster-image file path — not
---"clipboard"/"current", not a bufnr, not a `git:`/`http(s)://` spec.
---@param spec DiffNvim.Source|DiffNvim.Target
---@return boolean ok
---@return string|nil path  the expanded path, when `ok`
function M.is_image_file_spec(spec)
  if type(spec) ~= "string" or spec == "" then
    return false, nil
  end
  if spec == "clipboard" or spec == "current" then
    return false, nil
  end
  if tonumber(spec) ~= nil then
    return false, nil
  end
  if require("diff.core.git").is_git_spec(spec) then
    return false, nil
  end
  if require("diff.core.url").is_url_spec(spec) then
    return false, nil
  end

  local path = vim.fn.expand(spec)
  if not has_image_ext(path) then
    return false, nil
  end
  if vim.fn.filereadable(path) ~= 1 then
    return false, nil
  end
  return true, path
end

---If both `source`/`target` are image file paths (and `diff.image_compare`
---is enabled), show them via images.nvim and return true — the caller
---should treat the diff as fully handled. Returns false for every other
---case, so the caller falls through to the normal text-diff pipeline
---completely unchanged.
---@param source DiffNvim.Source
---@param target DiffNvim.Target
---@return boolean handled
function M.maybe_compare(source, target)
  local cfg = (require("diff.config").get().diff or {})
  if cfg.image_compare == false then
    return false
  end

  local is_a, path_a = M.is_image_file_spec(source)
  local is_b, path_b = M.is_image_file_spec(target)
  if not (is_a and is_b) then
    return false
  end

  local notify = require("diff.util.notify")
  local ok_images, images = pcall(require, "images")
  if not (ok_images and images.gallery) then
    notify.warn(
      "Both sides look like image files, but images.nvim is not installed "
        .. "-- install it to compare them visually "
        .. "(https://github.com/StefanBartl/images.nvim), or set "
        .. "diff.image_compare = false to force a (meaningless) text diff."
    )
    return true
  end

  images.gallery({ path_a, path_b }, 2)
  return true
end

return M

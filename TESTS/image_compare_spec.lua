-- TESTS/image_compare_spec.lua — features.image_compare: spec
-- classification + the maybe_compare gate.

return function(H)
  local eq, ok = H.eq, H.ok
  local image_compare = require("diff.features.image_compare")

  -- is_image_file_spec: rejects everything that isn't a plain, existing,
  -- raster-image file path ------------------------------------------------
  ok(not image_compare.is_image_file_spec("current"), "current is never an image spec")
  ok(not image_compare.is_image_file_spec("clipboard"), "clipboard is never an image spec")
  ok(not image_compare.is_image_file_spec("42"), "a bufnr-looking string is never an image spec")
  ok(not image_compare.is_image_file_spec("git:HEAD"), "a git: spec is never an image spec")
  ok(
    not image_compare.is_image_file_spec("https://example.com/x.png"),
    "a URL is never an image spec (fetched, not a local path)"
  )
  ok(
    not image_compare.is_image_file_spec("/does/not/exist.png"),
    "an unreadable path is never an image spec"
  )

  -- A readable non-image file (this spec file itself) is not an image spec.
  local this_file = debug.getinfo(1, "S").source:sub(2)
  ok(not image_compare.is_image_file_spec(this_file), "a readable .lua file is not an image spec")

  -- svg is deliberately excluded (it's text, diffs fine as text) ----------
  local svg = vim.fn.tempname() .. ".svg"
  vim.fn.writefile({ "<svg></svg>" }, svg)
  ok(not image_compare.is_image_file_spec(svg), "svg is excluded -- it's text, not a raster format")
  vim.fn.delete(svg)

  -- A readable raster-image path IS an image spec, and expands correctly.
  local png = vim.fn.tempname() .. ".png"
  vim.fn.writefile({ "not a real png, extension is all that matters here" }, png)
  local is_img, expanded = image_compare.is_image_file_spec(png)
  ok(is_img, "a readable .png path is an image spec")
  eq(expanded, vim.fn.expand(png), "is_image_file_spec returns the expanded path")

  -- maybe_compare: only fires when BOTH sides qualify ----------------------
  ok(
    not image_compare.maybe_compare("current", png),
    "maybe_compare does nothing when only one side is an image"
  )
  ok(
    not image_compare.maybe_compare(png, this_file),
    "maybe_compare does nothing when the other side is a non-image file"
  )

  -- With images.nvim absent, maybe_compare still claims the pair (a clear
  -- warning is the intended behavior, not silently falling through to a
  -- meaningless text diff of binary bytes) -- verified without requiring
  -- images.nvim as a test dependency by checking the return value only.
  local handled = image_compare.maybe_compare(png, png)
  ok(
    handled,
    "maybe_compare claims the diff when both sides are image files, regardless of images.nvim availability"
  )

  -- With images.nvim present, the pair is handed to its gallery -----------
  -- The contract diff.nvim depends on is `images.gallery({a, b}, 2)` -- the
  -- same primitive `:Image gallery` itself uses -- with both *expanded* paths
  -- and a column count of 2. Driven against a double in `package.loaded`, so
  -- no images.nvim checkout is needed and nothing is actually drawn.
  do
    local saved_images = package.loaded["images"]
    local captured
    package.loaded["images"] = {
      gallery = function(paths, columns)
        captured = { paths = paths, columns = columns }
      end,
    }

    local png_b = vim.fn.tempname() .. ".JPEG"
    vim.fn.writefile({ "also not a real image" }, png_b)

    local handled_pair = image_compare.maybe_compare(png, png_b)
    ok(handled_pair, "maybe_compare claims the pair when images.nvim is installed")
    ok(captured ~= nil, "and hands it to images.gallery")
    eq(#captured.paths, 2, "with exactly two paths")
    eq(captured.paths[1], vim.fn.expand(png), "the source path, expanded")
    eq(captured.paths[2], vim.fn.expand(png_b), "the target path, expanded")
    eq(captured.columns, 2, "and two columns, so the pair sits side by side")

    -- The extension check is case-insensitive -- .JPEG matched above.
    ok(image_compare.is_image_file_spec(png_b), "an uppercase extension is still an image spec")

    -- An images.nvim without a gallery function (an API mismatch, or an older
    -- release) falls back to the warning rather than erroring.
    package.loaded["images"] = {}
    local no_gallery_ok, no_gallery = pcall(image_compare.maybe_compare, png, png_b)
    ok(no_gallery_ok, "an images.nvim without gallery() does not throw")
    ok(no_gallery, "and the pair is still claimed, with the install hint")

    vim.fn.delete(png_b)
    package.loaded["images"] = saved_images
  end

  -- diff.image_compare = false disables the whole feature -----------------
  local config = require("diff.config")
  config.setup({ diff = { image_compare = false } })
  ok(
    not image_compare.maybe_compare(png, png),
    "diff.image_compare = false restores the old (text-diff) behavior"
  )
  config.setup({}) -- reset for any spec that runs after this one

  vim.fn.delete(png)
end

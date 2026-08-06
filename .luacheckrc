-- LuaJIT (Neovim's runtime) exposes 5.2 additions such as table.pack/unpack.
std = "luajit"
globals = { "vim" }

-- Formatting (line width) is stylua's job (column_width = 100); regex
-- patterns and doc-comment annotations legitimately exceed that and are
-- not reflowed by stylua. Long lines are a style nit, not a bug.
max_line_length = false

exclude_files = {
  -- Pure `---@meta` LuaCATS annotation scaffolding.
  "lua/diff/@types.lua",
}

---@module 'diff.health'
--- :checkhealth diff provider.

local M = {}

---@return nil
function M.check()
  vim.health.start("diff")

  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.warn("Neovim 0.9+ recommended", { "Upgrade Neovim to 0.9+" })
  end

  if pcall(require, "lib.nvim.bindings.usercmd.composer") then
    vim.health.ok("lib.nvim detected (:Diff command layer available)")
  else
    vim.health.error(
      "lib.nvim not found — :Diff/:DiffClear/:DiffBuffers/:DiffOrig/:DiffExit will fail to register",
      { 'Install "StefanBartl/lib.nvim" as a dependency' }
    )
  end

  ---@diagnostic disable-next-line: deprecated
  local diff_fn = (vim.text and vim.text.diff) or vim.diff
  if type(diff_fn) == "function" then
    vim.health.ok(
      vim.text and vim.text.diff and "vim.text.diff is available"
        or "vim.diff is available (pre-0.11 name)"
    )
  else
    vim.health.error(
      "no diff primitive — prompt/file/clipboard/inline output will fail",
      { "Upgrade Neovim" }
    )
  end

  if type(vim.ui) == "table" and type(vim.ui.select) == "function" then
    vim.health.ok("vim.ui.select is available (interactive target picker)")
  else
    vim.health.warn("vim.ui.select unavailable — :Diff without target= will not work")
  end

  if vim.fn.has("clipboard") == 1 then
    vim.health.ok("clipboard provider present (target=clipboard / output=clipboard)")
  else
    vim.health.warn(
      "no clipboard provider — clipboard source/output unavailable",
      { "Install a clipboard provider (xclip, xsel, wl-clipboard, or a GUI Neovim)" }
    )
  end

  if type(vim.system) == "function" and vim.fn.executable("git") == 1 then
    vim.health.ok("git + vim.system available (target=git:<rev> / source=git:<rev>)")
  elseif type(vim.system) ~= "function" then
    vim.health.warn(
      "vim.system missing (Neovim 0.10+) — git:<rev> source/target unavailable",
      { "Upgrade Neovim to 0.10+" }
    )
  else
    vim.health.warn(
      "git executable not on PATH — git:<rev> source/target unavailable",
      { "install git" }
    )
  end

  if type(vim.system) == "function" and vim.fn.executable("curl") == 1 then
    vim.health.ok("curl + vim.system available (target=http(s):// / source=http(s)://)")
  elseif type(vim.system) ~= "function" then
    vim.health.warn(
      "vim.system missing (Neovim 0.10+) — http(s):// source/target unavailable",
      { "Upgrade Neovim to 0.10+" }
    )
  else
    vim.health.warn(
      "curl executable not on PATH — http(s):// source/target unavailable",
      { "install curl" }
    )
  end

  if type(require("diff.core.pickers_bridge").resolve()) == "function" then
    vim.health.ok("pickers.nvim detected — used for the target/source picker")
  else
    vim.health.ok(
      "pickers.nvim not detected — using ui.kit for the target/source picker"
        .. " (a vim.ui.select override is still honored)"
    )
  end

  if vim.g.loaded_diff then
    vim.health.ok("plugin loaded (vim.g.loaded_diff = " .. tostring(vim.g.loaded_diff) .. ")")
  else
    vim.health.info("plugin guard not set (call require('diff').setup())")
  end

  vim.health.start("diff: setup() options")
  -- Unknown top-level/nested option or invalid value from the last setup()
  -- call (ERR-50, ERR-22) -- dropped before the merge, reported here.
  local cfg_issues = require("diff.config").issues()
  if #cfg_issues == 0 then
    vim.health.ok("No unknown or invalid setup() options")
  else
    for _, issue in ipairs(cfg_issues) do
      vim.health.warn(issue)
    end
  end

  vim.health.start("diff: diffopt profiles")
  local diffopt_profile = require("diff.features.diffopt_profile")
  local names = diffopt_profile.names()
  if #names == 0 then
    vim.health.error("no diff profiles defined")
  else
    vim.health.ok(("%d profile(s): %s"):format(#names, table.concat(names, ", ")))
    local current = diffopt_profile.current()
    if current then
      vim.health.ok(("'diffopt' matches profile '%s'"):format(current))
    else
      vim.health.info("'diffopt' matches no profile -- set by hand, or a profile was edited")
    end
  end

  vim.health.start("diff: gitsigns peek (gh)")
  local cfg = require("diff.config").get()
  if not cfg.features.gitsigns_peek then
    vim.health.info("features.gitsigns_peek = false -- this section has nothing to report")
  elseif pcall(require, "gitsigns") then
    vim.health.ok("gitsigns.nvim is available -- 'gh' previews the hunk under the cursor")
  else
    vim.health.info("gitsigns.nvim is not installed -- 'gh' notifies instead of previewing")
  end

  -- The declared external tools (docs/install.json), reported out of the
  -- spec rather than listed a second time by hand. Silent when lib.nvim.deps
  -- is absent (an older lib.nvim) or this plugin ships no spec.
  local ok_deps, deps_health = pcall(require, "lib.nvim.deps.health")
  if ok_deps then
    vim.health.start("diff.nvim: declared tools (lib.nvim.deps)")
    deps_health.report_for("diff.nvim")
  end

  -- Guarded like the deps report above it: without lib.nvim this require
  -- throws, and `:checkhealth diff` would abort right here -- on exactly the
  -- machine whose report says lib.nvim is missing, so the user would never get
  -- to read the diagnosis they came for.
  local ok_composer, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  if ok_composer then
    composer.checkhealth("Diff")
  end
end

return M

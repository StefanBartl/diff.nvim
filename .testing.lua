-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "diff",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next). "file" because health_spec.lua fails after
  -- public_api_spec.lua in a shared process: lib.nvim's deps/health.lua caches vim.health.
  isolated = "file",

  -- Guards (docs/GUARDS.md of testing.nvim): every net is an error; the suite passes them with the
  -- allowlist below, so nothing is left at warn.
  guards = {
    fs = "error",
    state = "error", -- setup() state cannot leak: isolated = "file" gives each spec file its own editor
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
  },
  -- What the specs do on purpose (each entry is legitimate behavior, not a leak).
  guard_allow = {
    fs = {
      -- on_done_spec points tempname() at an unwritable drive to make writefile fail for real
      -- (a deliberate negative probe of output = "file").
      "Z:/definitely/not/writable",
    },
    spawn = {
      -- git_spec runs the real git against this repository (git show <rev>:<path>).
      "git",
      -- url_spec fetches a README over the network with curl on purpose (the real transport path).
      "curl",
    },
  },
}

-- make test のランナー。tests/test_*.lua をファイルごとに nvim で並べて流す。
-- make test FILE=... は今までどおり 1 ファイルを 1 つの nvim で流す（Makefile 側）。
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end

local jobs = math.max(1, #vim.uv.cpu_info() - 2)
do
  local i = 1
  while i <= #arg do
    if arg[i] == "--jobs" then
      jobs = math.max(1, tonumber(arg[i + 1]) or jobs)
      i = i + 1
    end
    i = i + 1
  end
end

local files = vim.fn.globpath(root .. "/tests", "test_*.lua", false, true)
table.sort(files)

local function strip_ansi(s)
  return (s:gsub("\27%[[%d;]*m", ""))
end

local total_cases, total_notes = 0, 0
local failed = {}

---@param batch string[]
local function run_batch(batch)
  local procs = {}
  for i, file in ipairs(batch) do
    local suffix = ("%d-%d"):format(vim.uv.os_getpid(), i)
    local cache = root .. "/.tests/cache/run-" .. suffix
    local state = root .. "/.tests/state/run-" .. suffix
    vim.fn.mkdir(cache, "p")
    vim.fn.mkdir(state, "p")
    procs[#procs + 1] = {
      file = file,
      cache = cache,
      state = state,
      proc = vim.system({
        "nvim",
        "--headless",
        "--noplugin",
        "-u",
        root .. "/tests/minimal_init.lua",
        "-c",
        ("lua MiniTest.run_file(%q)"):format(file),
      }, {
        text = true,
        timeout = 60000,
        env = {
          MINI_PATH = mini,
          SKKELETON_TEST_CACHE = cache,
          SKKELETON_TEST_STATE = state,
        },
      }),
    }
  end

  for _, p in ipairs(procs) do
    local r = p.proc:wait()
    local out = strip_ansi((r.stdout or "") .. (r.stderr or ""))
    vim.fn.delete(p.cache, "rf")
    vim.fn.delete(p.state, "rf")
    local cases = tonumber(out:match("Total number of cases:%s*(%d+)") or 0)
    local fails = tonumber(out:match("Fails %((%d+)%)") or (r.code == 0 and 0 or 1))
    total_cases = total_cases + cases
    total_notes = total_notes + tonumber(out:match("Notes %((%d+)%)") or 0)
    if r.code ~= 0 or fails > 0 then
      failed[#failed + 1] = { file = p.file, code = r.code, out = out }
    else
      io.stdout:write(("ok %s (%d cases)\n"):format(vim.fs.basename(p.file), cases))
    end
  end
end

for i = 1, #files, jobs do
  run_batch(vim.list_slice(files, i, math.min(i + jobs - 1, #files)))
end

if #failed > 0 then
  for _, f in ipairs(failed) do
    io.stderr:write(("\nFAIL %s (exit %d)\n%s\n"):format(f.file, f.code, f.out))
  end
  os.exit(1)
end

print(("%d files, %d cases, %d notes"):format(#files, total_cases, total_notes))

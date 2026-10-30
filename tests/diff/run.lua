-- 差分テスト: denops 版（upstream）と Lua 版に同じキー列を流して、1 キーごとの状態を比べる。
-- 使い方: make difftest（deno が無いときは skip）
--   nvim --headless -u NONE -i NONE -l tests/diff/run.lua [--random N] [--seed S] [--jobs J] [--filter 文字列]
-- 内部では自分を --worker で J 個起動して、シナリオを分けて流す
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")

local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end
vim.opt.rtp:append(mini)
package.path = here .. "/?.lua;" .. package.path
MiniTest = require("mini.test")
MiniTest.setup()

local driver = require("driver")
local scenarios = require("scenarios")
local known = require("known")

-- 引数
local opts = { fixed = true, verbose = false, random = 300, seed = 20261030, jobs = 6, filter = nil, worker = nil }
do
  local a = arg
  local i = 1
  while i <= #a do
    local k = a[i]
    if k == "--random" then
      opts.random = tonumber(a[i + 1])
      i = i + 1
    elseif k == "--seed" then
      opts.seed = tonumber(a[i + 1])
      i = i + 1
    elseif k == "--jobs" then
      opts.jobs = tonumber(a[i + 1])
      i = i + 1
    elseif k == "--no-fixed" then
      opts.fixed = false
    elseif k == "--verbose" then
      opts.verbose = true
    elseif k == "--filter" then
      opts.filter = a[i + 1]
      i = i + 1
    elseif k == "--worker" then
      opts.worker = { index = tonumber(a[i + 1]), count = tonumber(a[i + 2]) }
      i = i + 2
    end
    i = i + 1
  end
end

local function all_scenarios()
  local list = opts.fixed and scenarios.fixed() or {}
  vim.list_extend(list, scenarios.random(opts.random, opts.seed))
  if opts.filter then
    list = vim.tbl_filter(function(s)
      return s.keys:find(opts.filter, 1, true) ~= nil
    end, list)
  end
  return list
end

-- 子の nvim の stderr などを出さないよう、worker は結果を 1 行の JSON にして stdout に書く
local function worker()
  local list = all_scenarios()
  local lua_child = MiniTest.new_child_neovim()
  local denops_child = MiniTest.new_child_neovim()
  for i, sc in ipairs(list) do
    if (i - 1) % opts.worker.count == opts.worker.index - 1 then
      local a = driver.run("lua", lua_child, scenarios.dict, sc.keys, sc.config, sc.random)
      local b = driver.run("denops", denops_child, scenarios.dict, sc.keys, sc.config, sc.random)
      io.stdout:write(vim.json.encode({ i = i, a = a, b = b }), "\n")
      io.stdout:flush()
    end
  end
  vim.cmd("qall!")
end

-- 比較に使わない項目を落とす
local function normalize(step)
  local s = vim.deepcopy(step)
  s.hc = nil
  s.key = nil
  s.unsettled = nil
  -- 辞書登録の入力中は、元のバッファの見た目（pre-edit の出し方、popup）を比べない。cmdline の中身で比べる
  if s.vim and s.vim:sub(1, 1) == "c" then
    s.lines, s.cursor, s.popup = nil, nil, nil
  end
  return s
end

local function show(step)
  if not step then
    return "(none)"
  end
  local s = normalize(step)
  local parts = {
    ("lines=%s cursor=%s"):format(
      vim.inspect(s.lines, { newline = "", indent = "" }),
      vim.inspect(s.cursor, { newline = "", indent = "" })
    ),
    ("mode=%q vim=%q enabled=%s"):format(s.mode or "", s.vim or "", tostring(s.enabled)),
  }
  if s.popup then
    parts[#parts + 1] = "popup=" .. vim.inspect(s.popup, { newline = "", indent = "" })
  end
  if s.cmdline then
    parts[#parts + 1] = ("cmdline=%q"):format(s.cmdline)
  end
  return table.concat(parts, "  ")
end

-- 最初に違った段階を探す。{ index, a, b } か nil
local function first_diff(a, b)
  if a.error or b.error then
    return { error = true }
  end
  local n = math.max(#a.steps, #b.steps)
  for i = 1, n do
    local sa, sb = a.steps[i], b.steps[i]
    if not sa or not sb or not vim.deep_equal(normalize(sa), normalize(sb)) then
      return { index = i, a = sa, b = sb }
    end
  end
end

local function main()
  local why = driver.unavailable()
  if why then
    print("difftest: skipped (" .. why .. ")")
    vim.cmd("qall!")
    return
  end
  local list = all_scenarios()
  local jobs = {}
  local results = {}
  local script = here .. "/run.lua"
  for j = 1, opts.jobs do
    local cmd = {
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-l",
      script,
      "--random",
      tostring(opts.random),
      "--seed",
      tostring(opts.seed),
      "--worker",
      tostring(j),
      tostring(opts.jobs),
    }
    if not opts.fixed then
      cmd[#cmd + 1] = "--no-fixed"
    end
    if opts.filter then
      vim.list_extend(cmd, { "--filter", opts.filter })
    end
    jobs[j] = vim.system(cmd, { text = true, env = { MINI_PATH = mini } })
  end
  for _, job in ipairs(jobs) do
    local res = job:wait()
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      local ok, item = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
      if ok then
        results[item.i] = item
      end
    end
    if res.code ~= 0 then
      io.stderr:write("worker failed: ", res.stderr or "", "\n")
    end
  end

  local failed, excused, errors, ok_count = {}, {}, {}, 0
  for i, sc in ipairs(list) do
    local r = results[i]
    if not r then
      errors[#errors + 1] = { sc = sc, message = "no result" }
    else
      local d = first_diff(r.a, r.b)
      if opts.verbose and r.a.steps then
        print(("%s  =>  %s"):format(sc.name, show(r.a.steps[#r.a.steps])))
      end
      if not d then
        ok_count = ok_count + 1
      elseif d.error then
        errors[#errors + 1] = {
          sc = sc,
          message = ("lua: %s / denops: %s"):format(
            r.a.error and r.a.error:sub(1, 300) or "ok",
            r.b.error and r.b.error:sub(1, 300) or "ok"
          ),
        }
      else
        local excuse
        for _, k in ipairs(known) do
          if k.applies(sc, d.index, d.a, d.b, r) then
            excuse = k.id
            break
          end
        end
        if excuse then
          excused[#excused + 1] = { sc = sc, id = excuse }
        else
          failed[#failed + 1] = { sc = sc, d = d, r = r }
        end
      end
    end
  end

  for _, f in ipairs(failed) do
    print(("DIFF  %s"):format(f.sc.name))
    print(("  keys:   %s"):format(f.sc.keys))
    if next(f.sc.config) then
      print(("  config: %s"):format(vim.inspect(f.sc.config, { newline = "", indent = "" })))
    end
    local pre = {}
    for i = 2, f.d.index do
      local s = f.r.a.steps[i] or f.r.b.steps[i]
      pre[#pre + 1] = s and s.key or "?"
    end
    print(("  at key #%d: %s"):format(f.d.index - 1, table.concat(pre, " ")))
    print("  lua:    " .. show(f.d.a))
    print("  denops: " .. show(f.d.b))
  end
  for _, e in ipairs(errors) do
    print(("ERROR %s [%s]: %s"):format(e.sc.name, e.sc.keys, e.message:gsub("\nstack traceback:.*", ""):sub(1, 400)))
  end
  local fixed_n, random_n = 0, 0
  for _, sc in ipairs(list) do
    if sc.random then
      random_n = random_n + 1
    else
      fixed_n = fixed_n + 1
    end
  end
  print(
    ("difftest: %d scenarios (%d fixed, %d random), %d same, %d known differences, %d differences, %d errors"):format(
      #list,
      fixed_n,
      random_n,
      ok_count,
      #excused,
      #failed,
      #errors
    )
  )
  vim.cmd(((#failed + #errors) == 0) and "qall!" or "cquit 1")
end

if opts.worker then
  worker()
else
  main()
end

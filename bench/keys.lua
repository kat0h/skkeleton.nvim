-- キー 1 回の処理時間。子の nvim に典型的なキー列を打って、handle の 1 回ごとの時間を測る
-- （handle の入口から render.finish の終わりまで。vim.uv.hrtime()）。
-- 使い方: nvim --headless -u NONE -i NONE -l bench/keys.lua [--rounds N] [--out 結果の md]
--   make bench-keys
-- 辞書は SKK-JISYO.L（/usr/share/skk に無ければ skip）と、tests の小さな辞書の両方
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h")

local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end
vim.opt.rtp:append(mini)
package.path = root .. "/tests/?.lua;" .. package.path
MiniTest = require("mini.test")
MiniTest.setup()
local helpers = require("helpers")

local rounds = 60
local out
do
  local i = 1
  while i <= #arg do
    if arg[i] == "--rounds" then
      rounds = tonumber(arg[i + 1])
      i = i + 1
    elseif arg[i] == "--out" then
      out = arg[i + 1]
      i = i + 1
    end
    i = i + 1
  end
end

-- 1 周で打つキー列。辞書に必ずある語だけにする（辞書登録に入らないように）
local sequences = {
  big = {
    "kyouhatenkigaiidesune",
    "Kanji<Space><C-j>",
    "Tenki<Space><Space><C-j>",
    "Nihongo<Space><C-j>",
    "TabeRu<C-j>",
    "IKu<C-j>",
    "KaeRu<Space><C-j>",
    "Kyou<Space><C-j>hasigoto<Space>",
    "<C-j>",
    "Hana<Space><Space><C-j>desu",
  },
  small = {
    "kyouhatenkigaiidesune",
    "Kan<Space><C-j>",
    "Kanji<Space><C-j>",
    "Kan<Space><Space><Space><C-j>",
    "Nihon<Space><C-j>",
    "KaeRu<Space><C-j>",
    "WaruKu<C-j>",
    "Toukyou<Space><C-j>hakanzi",
    "Kan<Space>a",
  },
}

-- キーの分類
local function classify(key)
  if key == "<Space>" then
    return "Space"
  elseif key == "<C-j>" then
    return "C-j"
  elseif key:match("^%u$") then
    return "Shift+letter"
  elseif key:match("^%l$") then
    return "lowercase"
  end
  return "other"
end

local function percentile(a, r)
  return a[math.max(1, math.ceil(#a * r))]
end

local function stats(xs)
  table.sort(xs)
  local sum = 0
  for _, x in ipairs(xs) do
    sum = sum + x
  end
  return { n = #xs, mean = sum / #xs, p50 = percentile(xs, 0.5), p99 = percentile(xs, 0.99), max = xs[#xs] }
end

local function ms(ns)
  return ("%.3f"):format(ns / 1e6)
end

-- "Kan<Space>" -> { "K", "a", "n", "<Space>" }
local function helpers_tokens(keys)
  local ret = {}
  local i = 1
  while i <= #keys do
    local s, e = keys:find("^<[%w%-_]+>", i)
    if s then
      ret[#ret + 1] = keys:sub(s, e)
      i = e + 1
    else
      ret[#ret + 1] = keys:sub(i, i)
      i = i + 1
    end
  end
  return ret
end

local child = MiniTest.new_child_neovim()

-- 1 つの辞書で測る。{ 種類 = stats, ... } を返す
local function measure(dict_path, encoding, seqs)
  child.restart({ "-u", "NONE", "-i", "NONE", "--cmd", "set rtp+=" .. root })
  child.cmd("runtime plugin/skkeleton.lua")
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  child.lua("require('skkeleton').setup(...)", {
    {
      globalDictionaries = { { dict_path, encoding } },
      userDictionary = dir .. "/user",
      databasePath = dir .. "/db",
      indicator = false,
    },
  })
  child.lua([[
    _G.samples = {}
    _G.n = 0
    local main = require("skkeleton.main")
    local render = require("skkeleton.render")
    local handle, finish = main.handle, render.finish
    local t0
    main.handle = function(...)
      t0 = vim.uv.hrtime()
      return handle(...)
    end
    render.finish = function(...)
      local r = finish(...)
      if t0 then
        _G.samples[#_G.samples + 1] = vim.uv.hrtime() - t0
        _G.n = #_G.samples
        t0 = nil
      end
      return r
    end
  ]])
  child.type_keys("i")

  local classes = {}
  local function press(key)
    local before = child.lua_get("_G.n")
    child.api.nvim_input(key)
    local t = vim.uv.hrtime()
    while child.lua_get("_G.n") == before do
      if (vim.uv.hrtime() - t) / 1e9 > 5 then
        error("no response to " .. key .. " (a dictionary registration may have started)")
      end
      vim.uv.sleep(1)
    end
    classes[#classes + 1] = classify(key)
  end

  press("<Plug>(skkeleton-enable)")
  classes[#classes] = "enable"
  -- 1 周目は辞書を開く分が入るので、別に数える
  local function round()
    for _, seq in ipairs(seqs) do
      for _, key in ipairs(helpers_tokens(seq)) do
        press(key)
      end
    end
    -- バッファが伸びすぎないように空にする
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    child.api.nvim_win_set_cursor(0, { 1, 0 })
  end
  round()
  local warm = #classes
  for _ = 1, rounds do
    round()
  end
  local samples = child.lua_get("_G.samples")
  assert(#samples == #classes, ("%d samples for %d keys"):format(#samples, #classes))
  local by = { all = {} }
  local first = samples[1]
  local first_round = {}
  for i = 1, warm do
    first_round[#first_round + 1] = samples[i]
  end
  for i = warm + 1, #samples do
    local c = classes[i]
    by[c] = by[c] or {}
    table.insert(by[c], samples[i])
    table.insert(by.all, samples[i])
  end
  child.stop()
  vim.fn.delete(dir, "rf")
  return by, first, math.max(unpack(first_round))
end

local function cpu_name()
  for line in io.lines("/proc/cpuinfo") do
    local name = line:match("^model name%s*:%s*(.+)$")
    if name then
      return name
    end
  end
  return "unknown"
end

local lines = {}
local function emit(s)
  lines[#lines + 1] = s
end

local big = "/usr/share/skk/SKK-JISYO.L"
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local small_path = tmp .. "/small"
do
  local f = assert(io.open(small_path, "w"))
  f:write(helpers.dict_text)
  f:close()
end

local v = vim.version()
emit("# キー 1 回の処理時間")
emit("")
emit(
  "handle の入口から `render.finish` の終わりまでを `vim.uv.hrtime()` で測った。子の nvim に `nvim_input` で 1 キーずつ打ち、"
)
emit("`render.finish` が呼ばれるのを待ってから次のキーを打つ。時間の単位は ms。")
emit("")
emit("## 環境")
emit("")
emit("- 日付: " .. os.date("%Y-%m-%d"))
emit("- CPU: " .. cpu_name())
emit(("- Neovim: %d.%d.%d"):format(v.major, v.minor, v.patch))
emit(
  "- 1 周のキー列を 1 周ならして、そのあと "
    .. rounds
    .. " 周を測った（1 周目は辞書を開く分が入るので別に出す）"
)
emit("")

local function section(title, dict_path, encoding, seqs)
  local by, first, first_max = measure(dict_path, encoding, seqs)
  emit("## " .. title)
  emit("")
  emit(
    ("1 周目の最初のキー（辞書を開く。DB の生成を含む）: %s ms、1 周目の最大: %s ms"):format(
      ms(first),
      ms(first_max)
    )
  )
  emit("")
  emit("| キー | 回数 | 平均 | p50 | p99 | max |")
  emit("|---|---:|---:|---:|---:|---:|")
  for _, c in ipairs({ "all", "lowercase", "Shift+letter", "Space", "C-j", "other" }) do
    if by[c] then
      local s = stats(by[c])
      emit(
        ("| %s | %d | %s | %s | %s | %s |"):format(
          c == "all" and "全部" or c,
          s.n,
          ms(s.mean),
          ms(s.p50),
          ms(s.p99),
          ms(s.max)
        )
      )
    end
  end
  emit("")
  print(("done: %s"):format(title))
end

local ok, err = pcall(function()
  if vim.uv.fs_stat(big) then
    section("SKK-JISYO.L（17.6 万行）", big, "euc-jp", sequences.big)
  else
    emit("## SKK-JISYO.L")
    emit("")
    emit(big .. " が無いので skip した。")
    emit("")
  end
  section("小さな辞書（tests/helpers.lua の dict_text）", small_path, "utf-8", sequences.small)
end)
pcall(child.stop)
vim.fn.delete(tmp, "rf")
if not ok then
  io.stderr:write(tostring(err), "\n")
  vim.cmd("cquit 1")
end

local text = table.concat(lines, "\n") .. "\n"
io.stdout:write(text)
if out then
  local f = assert(io.open(out, "w"))
  f:write(text)
  f:close()
end
vim.cmd("qall!")

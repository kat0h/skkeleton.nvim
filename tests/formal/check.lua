-- 形式検証の PoC: 実装をそのまま遷移関係にした、有界のモデル検査（状態空間の幅優先探索）。
--
-- キーの集合（alphabet）を決め、初期状態から 1 キーずつ流して、落ち着いた状態を観測する。
-- 観測を抽象化（abstract）して同じものは 1 度しか広げないので、キー列を全部試すより少ない手数で、
-- 「モード × skkeleton の状態 × pre-edit の有無 × カーソルの位置 × popup」の組み合わせを一通りなめる。
-- 各遷移で spec.lua の不変条件と action の性質を確かめ、破れたら最短のキー列を反例として出す。
--
-- 使い方: make verify ARGS="--depth 4 --jobs 8 --mutate no-stale-check"
--   nvim --headless -u NONE -i NONE -l tests/formal/check.lua [--depth D] [--jobs J] [--mutate 名前]
--     [--random N --length L --seed S]   幅優先のかわりに、ランダムなキー列を N 本流して縮める
--     [--list-mutations]
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")

local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end
vim.opt.rtp:append(mini)
package.path = root .. "/tests/?.lua;" .. package.path
MiniTest = require("mini.test")
MiniTest.setup()

local spec = require("formal.spec")

-- 流すキー。insert モードの入力・変換、skkeleton が処理しない編集キー、モードとウィンドウの行き来
local ALPHABET = {
  "<C-j>", -- toggle（利用者の設定と同じく i と c に割り当てる）
  "k",
  "a",
  "n",
  "K",
  "<Space>",
  "x",
  "q",
  "<CR>",
  "<BS>",
  "<C-g>",
  "<C-u>",
  "<C-w>",
  "<Left>",
  "<Right>",
  "<Esc>",
  "i",
  "A",
  ":",
  "<Cmd>wincmd w<CR>",
  -- マクロ遷移: 深いところ（▽かん、候補一覧）へ 1 手で行く
  "Kan",
  "<Space><Space><Space><Space>",
}

-- 直したバグを子の中に戻す（検査がそれを見つけられるかを確かめるため）
local MUTATIONS = {
  ["no-stale-check"] = {
    issue = "#8 変換中の <C-u> で pre-edit が残る",
    code = [[require("skkeleton.main").init()
      vim.api.nvim_clear_autocmds({ group = "skkeleton-internal", event = { "TextChangedI", "TextChangedP", "CursorMovedI" } })]],
  },
  ["indicator-ignores-preedit"] = {
    issue = "#6 インジケータが pre-edit に置いていかれる",
    code = [[require("skkeleton.render").preedit_width = function() return 0 end]],
  },
  ["no-winleave-reset"] = {
    issue = "ウィンドウを移ると pre-edit と状態が前のウィンドウに残る",
    code = [[require("skkeleton.main").init()
      vim.api.nvim_clear_autocmds({ group = "skkeleton-internal", event = { "WinLeave", "BufLeave" } })]],
  },
  ["no-normal-reset"] = {
    issue = "normal に戻っても無効にならない",
    code = [[require("skkeleton.main").init()
      vim.api.nvim_clear_autocmds({ group = "skkeleton-internal", event = "ModeChanged" })]],
  },
  ["popup-leaks"] = {
    issue = "229f6be popup のバッファが漏れる",
    code = [[local p = require("skkeleton.popup")
      local open = vim.api.nvim_open_win
      vim.api.nvim_open_win = function(buf, enter, cfg)
        local w = open(buf, enter, cfg)
        vim.bo[buf].bufhidden = "hide"
        return w
      end]],
  },
  ["restore-loses-user-map"] = {
    issue = "229f6be 無効にすると利用者のバッファローカルのマッピングが消える",
    code = [[local map = require("skkeleton.map")
      local restore = map.restore
      map.restore = function() restore(); pcall(vim.keymap.del, "i", "<C-g>", { buffer = 0 }) end]],
  },
  ["textwidth-not-restored"] = {
    issue = "'textwidth' を戻し忘れる",
    code = [[require("skkeleton.map").restore_options = function() end]],
  },
}

-- 引数
local opts = { depth = 3, jobs = 8, mutate = nil, random = nil, length = 12, seed = 1, worker = nil, max_states = 400 }
do
  local i = 1
  while i <= #arg do
    local k = arg[i]
    local v = arg[i + 1]
    if k == "--depth" then
      opts.depth, i = tonumber(v), i + 1
    elseif k == "--jobs" then
      opts.jobs, i = tonumber(v), i + 1
    elseif k == "--mutate" then
      opts.mutate, i = v, i + 1
    elseif k == "--random" then
      opts.random, i = tonumber(v), i + 1
    elseif k == "--length" then
      opts.length, i = tonumber(v), i + 1
    elseif k == "--seed" then
      opts.seed, i = tonumber(v), i + 1
    elseif k == "--keys" then
      opts.keys, i = vim.split(v, ",", { plain = true }), i + 1
    elseif k == "--max-states" then
      opts.max_states, i = tonumber(v), i + 1
    elseif k == "--worker" then
      opts.worker = { input = v, output = arg[i + 2] }
      i = i + 2
    elseif k == "--list-mutations" then
      for name, m in vim.spairs(MUTATIONS) do
        io.stdout:write(("%-28s %s\n"):format(name, m.issue))
      end
      os.exit(0)
    end
    i = i + 1
  end
end

local dict_text = table.concat({
  ";; okuri-ari entries.",
  "わるk /悪/",
  ";; okuri-nasi entries.",
  "かん /缶/感/漢/幹/管/館/観/",
  "かんじ /漢字/幹事/",
  "なか /中/",
  "",
}, "\n")

local SETUP = [[
  local dir, dict, mutation = ...
  vim.o.textwidth = 78
  for _, k in ipairs({ "K", "q", "Q", "gQ" }) do vim.keymap.set("n", k, "<Nop>") end
  require("skkeleton").setup({
    globalDictionaries = { { dict, "utf-8" } },
    userDictionary = dir .. "/user",
    databasePath = dir .. "/db",
    indicator = {},
  })
  vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
  local function sentinel()
    vim.keymap.set("i", "<C-g>", "<Nop>", { buffer = true, desc = "user-sentinel" })
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
  sentinel()
  vim.cmd("botright new")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "xy" })
  sentinel()
  vim.cmd("wincmd p")
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  -- ":" のコマンドラインは開くだけで実行しない（:q や :n でウィンドウやバッファが変わらないように）
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    pattern = ":",
    command = "let v:event.abort = v:true",
  })
  if mutation then
    assert(loadstring(mutation))()
  end
]]

local function new_child()
  return MiniTest.new_child_neovim()
end

local function start(child, mutation)
  child.restart({ "-u", root .. "/tests/minimal_init.lua" })
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local dict = dir .. "/dict"
  local f = assert(io.open(dict, "w"))
  f:write(dict_text)
  f:close()
  child.lua(SETUP, { dir, dict, mutation and MUTATIONS[mutation].code or nil })
  child.type_keys("i")
end

-- 流したキーが全部処理されるまで待つ。入力待ち（input() など）で止まったら false
local function settle(child)
  local quiet = 0
  for _ = 1, 1000 do
    if child.is_blocked() then
      return false
    end
    if child.lua_get("vim.fn.getchar(1)") == 0 then
      quiet = quiet + 1
      if quiet >= 3 then
        return true
      end
    else
      quiet = 0
    end
    vim.uv.sleep(1)
  end
  error("settle: the child still has pending input")
end

local function snapshot(child)
  return child.lua_get([[require("formal.observe").snapshot()]])
end

-- 抽象化: 同じ値になる状態は 1 度しか広げない
local function abstract(s)
  local col = s.cursor[2]
  local len = #(s.lines[s.cursor[1]] or "")
  local pos = col == 0 and "bol" or col >= len and "eol" or "mid"
  return table.concat({
    s.vim_mode,
    tostring(s.enabled),
    s.skk_mode,
    s.state.type .. "/" .. tostring(s.state.mode),
    math.min(vim.fn.strchars(s.ctx_text), 3),
    #s.popup,
    pos,
    math.min(#s.lines, 3),
    s.buf,
    s.cmdline and ((s.cmdtype or "") .. (s.cmdline == "" and "0" or "1")) or "-",
  }, "|")
end

local function check(base, prev, key, s)
  local out = {}
  for name, f in vim.spairs(spec.state) do
    local ok, msg = pcall(f, s, base)
    if not ok or msg then
      out[#out + 1] = { name = name, msg = tostring(msg) }
    end
  end
  if prev then
    for name, f in vim.spairs(spec.action) do
      local ok, msg = pcall(f, prev, key, s)
      if not ok or msg then
        out[#out + 1] = { name = name, msg = tostring(msg) }
      end
    end
  end
  return out
end

-- キー列を流して、各キーのあとで性質を確かめる。最初の違反で止まる
-- every = false なら最後のキーだけ確かめる（それより前は探索で確かめ済み）
local function run(child, keys, mutation, every)
  start(child, mutation)
  settle(child)
  local base = snapshot(child)
  local prev = base
  if every then
    local v = check(base, nil, nil, base)
    if #v > 0 then
      return { steps = 0, violations = v, abstract = abstract(base) }
    end
  end
  for i, key in ipairs(keys) do
    local last = i == #keys
    if (every or last) and prev == nil then
      -- 前の観測が要る
      prev = snapshot(child)
    end
    -- normal の n や cmdline の <CR> などで Neovim 本体が出すエラー（E35 など）は違反にしない。
    -- skkeleton の Lua のエラーは違反にする
    local ok, err = pcall(child.type_keys, key)
    if not ok and (tostring(err):find("skkeleton", 1, true) or not tostring(err):find("E%d+:")) then
      return { steps = i, violations = { { name = "error", msg = tostring(err) } }, abstract = "error" }
    end
    if not settle(child) then
      -- 入力待ち（辞書登録の input() など）。ここから先は広げない
      return { steps = i, blocked = true, abstract = "blocked" }
    end
    if every or last then
      local s = snapshot(child)
      local v = check(base, prev, key, s)
      if #v > 0 then
        return { steps = i, violations = v, abstract = abstract(s), snapshot = s, prev = prev }
      end
      prev = s
      if last then
        return { steps = i, abstract = abstract(s) }
      end
    else
      prev = nil
    end
  end
  return { steps = 0, abstract = abstract(base) }
end

-- worker: 入力ファイルのキー列を流して、結果を JSON で書く
if opts.worker then
  local items = vim.json.decode(table.concat(vim.fn.readfile(opts.worker.input), "\n"))
  local child = new_child()
  local out = {}
  for _, item in ipairs(items) do
    local ok, res = pcall(run, child, item.keys, item.mutation, item.every)
    if not ok then
      res = { steps = #item.keys, violations = { { name = "error", msg = tostring(res) } }, abstract = "error" }
    end
    res.keys = item.keys
    out[#out + 1] = vim.json.encode(res)
  end
  vim.fn.writefile(out, opts.worker.output)
  child.stop()
  vim.cmd("qall!")
end

-- items を jobs 個の worker に分けて流す
local function run_parallel(items)
  local tmp = vim.fn.tempname()
  local procs = {}
  local n = math.min(opts.jobs, #items)
  for j = 1, n do
    local chunk = {}
    for i = j, #items, n do
      chunk[#chunk + 1] = items[i]
    end
    local input, output = ("%s.%d.in"):format(tmp, j), ("%s.%d.out"):format(tmp, j)
    vim.fn.writefile({ vim.json.encode(chunk) }, input)
    procs[j] = {
      output = output,
      proc = vim.system({
        vim.v.progpath,
        "--headless",
        "-u",
        "NONE",
        "-i",
        "NONE",
        "-l",
        here .. "/check.lua",
        "--worker",
        input,
        output,
      }, { env = { MINI_PATH = mini } }),
    }
  end
  local results = {}
  for _, p in ipairs(procs) do
    local r = p.proc:wait()
    if vim.fn.filereadable(p.output) == 0 then
      error("worker failed: " .. (r.stderr or ""))
    end
    for _, l in ipairs(vim.fn.readfile(p.output)) do
      results[#results + 1] = vim.json.decode(l)
    end
  end
  return results
end

local function keys_str(keys)
  return table.concat(keys, " ")
end

-- 反例を、そのまま tests/ に貼れる回帰テストの形でも出す
local function report(res)
  print(("\n✗ 反例（%d キー）: %s"):format(#res.keys, keys_str(res.keys)))
  for _, v in ipairs(res.violations) do
    print(("  - %s\n      %s"):format(v.name, v.msg))
  end
  if res.snapshot then
    local s = res.snapshot
    print(
      ("  状態: mode=%s enabled=%s skk=%s state=%s/%s pre-edit=%q 行=%q カーソル=%s"):format(
        s.vim_mode,
        tostring(s.enabled),
        s.skk_mode,
        s.state.type,
        tostring(s.state.mode),
        s.ctx_text,
        s.lines[s.cursor[1]] or "",
        vim.inspect(s.cursor)
      )
    )
  end
end

-- ddmin で反例のキー列を縮める
local function shrink(keys, mutation)
  local function fails(ks)
    local r = run_parallel({ { keys = ks, mutation = mutation, every = true } })[1]
    return r.violations and #r.violations > 0 and r or nil
  end
  local best = fails(keys)
  local n = 2
  while #keys >= 2 do
    local size = math.ceil(#keys / n)
    local reduced = false
    for i = 1, #keys, size do
      local rest = {}
      for j, k in ipairs(keys) do
        if j < i or j >= i + size then
          rest[#rest + 1] = k
        end
      end
      local r = #rest > 0 and fails(rest)
      if r then
        keys, best, n, reduced = rest, r, math.max(n - 1, 2), true
        break
      end
    end
    if not reduced then
      if n >= #keys then
        break
      end
      n = math.min(n * 2, #keys)
    end
  end
  return best
end

local t0 = vim.uv.hrtime()
local function elapsed()
  return (vim.uv.hrtime() - t0) / 1e9
end

local found = {}

if opts.keys then
  -- 1 本のキー列を流して、キーごとの観測を出す（反例を追うため）
  local child = new_child()
  start(child, opts.mutate)
  settle(child)
  local base = snapshot(child)
  local prev = base
  for _, key in ipairs(opts.keys) do
    pcall(child.type_keys, key)
    if not settle(child) then
      print(key, "入力待ち")
      break
    end
    local s = snapshot(child)
    print(
      ("%-12s mode=%s pre-edit=%q 行=%q カーソル=%s popup=%d bufs=%d wins=%d"):format(
        key,
        s.vim_mode,
        s.ctx_text,
        s.lines[s.cursor[1]] or "",
        vim.inspect(s.cursor),
        #s.popup,
        s.bufs,
        s.wins
      )
    )
    for _, v in ipairs(check(base, prev, key, s)) do
      print("  ✗ " .. v.name .. ": " .. v.msg)
      found[v.name] = found[v.name] or { keys = opts.keys, violations = { v } }
    end
    prev = s
  end
  child.stop()
elseif opts.random then
  -- ランダムなキー列（深い状態に届く）。違反したら ddmin で縮める
  math.randomseed(opts.seed)
  local items = {}
  for _ = 1, opts.random do
    local ks = {}
    for i = 1, opts.length do
      ks[i] = ALPHABET[math.random(#ALPHABET)]
    end
    items[#items + 1] = { keys = ks, mutation = opts.mutate, every = true }
  end
  for _, r in ipairs(run_parallel(items)) do
    if r.violations then
      local prefix = vim.list_slice(r.keys, 1, r.steps)
      local key = r.violations[1].name
      if not found[key] then
        found[key] = shrink(prefix, opts.mutate) or r
      end
    end
  end
  print(("random: %d 本 × %d キー、%.1f 秒"):format(opts.random, opts.length, elapsed()))
else
  -- 幅優先。frontier の各状態から、すべてのキーを 1 つずつ試す
  local visited = {}
  local frontier = { {} }
  local first = run_parallel({ { keys = {}, mutation = opts.mutate, every = true } })[1]
  visited[first.abstract] = true
  if first.violations then
    first.keys = {}
    found[first.violations[1].name] = first
  end
  local transitions = 0
  for depth = 1, opts.depth do
    local items = {}
    for _, path in ipairs(frontier) do
      for _, key in ipairs(ALPHABET) do
        local ks = vim.list_extend(vim.list_slice(path), { key })
        items[#items + 1] = { keys = ks, mutation = opts.mutate, every = false }
      end
    end
    transitions = transitions + #items
    local next_frontier = {}
    local blocked = 0
    for _, r in ipairs(run_parallel(items)) do
      if r.violations then
        local name = r.violations[1].name
        -- 同じ性質の反例は最初（最短）のものだけ
        if not found[name] then
          found[name] = r
        end
      elseif r.blocked then
        blocked = blocked + 1
      elseif not visited[r.abstract] then
        visited[r.abstract] = true
        next_frontier[#next_frontier + 1] = r.keys
      end
    end
    local nstates = vim.tbl_count(visited)
    print(
      ("depth %d: 遷移 %d、新しい抽象状態 %d（計 %d）、入力待ち %d、%.1f 秒"):format(
        depth,
        #items,
        #next_frontier,
        nstates,
        blocked,
        elapsed()
      )
    )
    frontier = next_frontier
    if #frontier == 0 or nstates >= opts.max_states then
      break
    end
  end
  print(("計 %d 遷移、%d 抽象状態"):format(transitions, vim.tbl_count(visited)))
end

if opts.mutate then
  print(("mutation %s（%s）"):format(opts.mutate, MUTATIONS[opts.mutate].issue))
end
if vim.tbl_isempty(found) then
  print("✓ 違反なし")
  vim.cmd("qall!")
else
  for _, r in vim.spairs(found) do
    report(r)
  end
  vim.cmd("cquit 1")
end

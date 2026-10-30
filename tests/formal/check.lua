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
local profiles = require("formal.profiles")

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
local opts = {
  profile = "default",
  depth = 3,
  -- 2 コアは残す（ほかの作業が重くならないように）
  jobs = math.max(1, #vim.uv.cpu_info() - 2),
  mutate = nil,
  random = nil,
  length = 12,
  seed = 1,
  worker = nil,
  max_states = 400,
}
do
  local i = 1
  while i <= #arg do
    local k = arg[i]
    local v = arg[i + 1]
    if k == "--depth" then
      opts.depth, i = tonumber(v), i + 1
    elseif k == "--jobs" then
      opts.jobs, i = math.min(tonumber(v), math.max(1, #vim.uv.cpu_info() - 2)), i + 1
    elseif k == "--mutate" then
      opts.mutate, i = v, i + 1
    elseif k == "--config" then
      -- 再生のときの設定（ファジングの反例の「設定:」をそのまま渡す）
      opts.config, i = assert(loadstring("return " .. v))(), i + 1
    elseif k == "--no-cache" then
      opts.no_cache = true
    elseif k == "--fuzz" then
      opts.fuzz, i = tonumber(v), i + 1
    elseif k == "--seed-depth" then
      opts.seed_depth, i = tonumber(v), i + 1
    elseif k == "--random" then
      opts.random, i = tonumber(v), i + 1
    elseif k == "--length" then
      opts.length, i = tonumber(v), i + 1
    elseif k == "--seed" then
      opts.seed, i = tonumber(v), i + 1
    elseif k == "--profile" then
      opts.profile, i = v, i + 1
    elseif k == "--list-profiles" then
      for _, name in ipairs(profiles.names) do
        io.stdout:write(("%-10s %s\n"):format(name, profiles[name].doc))
      end
      os.exit(0)
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

local profile = assert(profiles[opts.profile], "unknown profile: " .. opts.profile)

-- 同じところを何度も調べないためのキャッシュ（git に入らない .tests/formal-cache/）。
-- 幅優先の結果はコードのハッシュごとに覚え、同じなら流さない。ファジングはコーパスを引き継いで前回の続きから
local CACHE = root .. "/.tests/formal-cache"
local function code_hash()
  local files = vim.fn.globpath(root, "lua/**/*.lua", true, true)
  vim.list_extend(files, vim.fn.globpath(root, "plugin/*", true, true))
  for _, f in ipairs({ "spec.lua", "observe.lua", "profiles.lua", "check.lua" }) do
    files[#files + 1] = root .. "/tests/formal/" .. f
  end
  table.sort(files)
  local parts = {}
  for _, f in ipairs(files) do
    parts[#parts + 1] = f:sub(#root + 2) .. "\0" .. table.concat(vim.fn.readfile(f, "b"), "\n")
  end
  return vim.fn.sha256(table.concat(parts, "\0")):sub(1, 16)
end
local function cache_read(name)
  local path = CACHE .. "/" .. name
  if opts.no_cache or vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and data or nil
end
local function cache_write(name, data)
  if opts.no_cache then
    return
  end
  vim.fn.mkdir(CACHE, "p")
  vim.fn.writefile({ vim.json.encode(data) }, CACHE .. "/" .. name)
end
local ALPHABET = profile.alphabet
local INITS = profile.inits
local INIT_NAMES = vim.tbl_keys(INITS)
table.sort(INIT_NAMES)

local SETUP = [[
  local dir, dict, mutation, extra, init, extra_code = ...
  vim.o.textwidth = 78
  for _, k in ipairs({ "K", "Q", "gQ" }) do vim.keymap.set({ "n", "x" }, k, "<Nop>") end
  -- マクロのプロファイルのほかは q（記録）も止める
  if not init.allow_q then vim.keymap.set({ "n", "x" }, "q", "<Nop>") end
  require("skkeleton").setup(vim.tbl_deep_extend("force", {
    globalDictionaries = { { dict, "utf-8" } },
    userDictionary = dir .. "/user",
    databasePath = dir .. "/db",
    indicator = {},
  }, extra))
  vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
  -- User イベントの回数（イベントの性質で使う）
  _G.formal_events = {}
  for _, name in ipairs({ "skkeleton-enable-post", "skkeleton-disable-post", "skkeleton-mode-changed" }) do
    _G.formal_events[name] = 0
    vim.api.nvim_create_autocmd("User", {
      pattern = name,
      callback = function()
        _G.formal_events[name] = _G.formal_events[name] + 1
      end,
    })
  end
  local function sentinel()
    vim.keymap.set("i", "<C-g>", "<Nop>", { buffer = true, desc = "user-sentinel" })
    vim.b.formal_sentinel = true
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, init.lines)
  sentinel()
  vim.cmd("botright new")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "xy" })
  sentinel()
  vim.cmd("wincmd p")
  vim.api.nvim_win_set_cursor(0, init.cursor)
  if init.cmd then
    vim.cmd(init.cmd)
  end
  -- ":" のコマンドラインは開くだけで実行しない（:q や :n でウィンドウやバッファが変わらないように）
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    pattern = ":",
    command = "let v:event.abort = v:true",
  })
  if mutation then
    assert(loadstring(mutation))()
  end
  -- プロファイルの追加の設定（blink.cmp を読むなど）
  if extra_code then
    assert(loadstring(extra_code))()
  end
]]

local function new_child()
  return MiniTest.new_child_neovim()
end

-- 初期状態（TLA+ の Init に当たる）は profiles.lua にある。キー列の先頭の "#mid" などで選ぶ

local function start(child, mutation, init, config)
  child.restart({ "-u", root .. "/tests/minimal_init.lua" })
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local dict = dir .. "/dict"
  local f = assert(io.open(dict, "w"))
  f:write(profile.dict)
  f:close()
  local it = vim.deepcopy(INITS[init] or INITS[INIT_NAMES[1]])
  it.allow_q = profile.allow_q
  child.lua(SETUP, {
    dir,
    dict,
    mutation and MUTATIONS[mutation].code or false,
    vim.tbl_deep_extend("force", profile.config, config or {}),
    it,
    profile.setup or false,
  })
  child.type_keys(it.keys)
end

-- 流したキーが全部処理されるまで待つ。入力待ち（input() など）で止まったら false
local function settle_once(child)
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

-- terminal ではシェルの表示が遅れて追いつくので、落ち着いたあと少し待ってもう一度待つ
local function settle(child)
  if not settle_once(child) then
    return false
  end
  -- 問い合わせを止めて少し待ち、SafeState や vim.schedule で動く処理（normal に戻ったあとの片付けなど）を走らせる。
  -- RPC で問い合わせ続けていると、Neovim が入力待ちにならず SafeState が来ない
  vim.uv.sleep(20)
  if not settle_once(child) then
    return false
  end
  -- 非同期に描くもの（blink.cmp のメニューなど）を待つ
  if profile.wait_ms then
    vim.uv.sleep(profile.wait_ms)
    if not settle_once(child) then
      return false
    end
  end
  if child.lua_get("vim.bo.buftype") == "terminal" then
    vim.uv.sleep(200)
    return settle_once(child)
  end
  return true
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
    s.menu and "menu" or "-",
  }, "|")
end

local function check(base, prev, key, s, hist)
  local out = {}
  -- 表示幅は子の nvim の 'ambiwidth' で数える（検査する側をそろえる）
  local saved_ambi = vim.o.ambiwidth
  vim.o.ambiwidth = s.ambiwidth or saved_ambi
  for name, f in vim.spairs(spec.state) do
    local ok, msg = pcall(f, s, base)
    if not ok or msg then
      out[#out + 1] = { name = name, msg = tostring(msg) }
    end
  end
  if prev then
    for name, f in vim.spairs(spec.action) do
      local ok, msg = pcall(f, prev, key, s, hist)
      if not ok or msg then
        out[#out + 1] = { name = name, msg = tostring(msg) }
      end
    end
  end
  vim.o.ambiwidth = saved_ambi
  return out
end

-- キー列を流して、各キーのあとで性質を確かめる。最初の違反で止まる
-- every = false なら最後のキーだけ確かめる（それより前は探索で確かめ済み）。
-- 観測は毎回取り、2 手以上をまたぐ性質のために履歴（hist）を渡す
local function run(child, keys, mutation, every, config)
  local init = keys[1] and INITS[keys[1]] and keys[1] or nil
  start(child, mutation, init, config)
  settle(child)
  local base = snapshot(child)
  local hist = {}
  spec.observe(hist, nil, base)
  if every or #keys == 0 or (init and #keys == 1) then
    local v = check(base, nil, nil, base, hist)
    if #v > 0 then
      return { steps = 0, violations = v, abstract = abstract(base) }
    end
  end
  local prev = base
  -- 通った抽象状態（ファジングのカバレッジに使う）
  local seen = { abstract(base) }
  for i, key in ipairs(keys) do
    if not (i == 1 and init) then
      -- normal の n や cmdline の <CR> などで Neovim 本体が出すエラー（E35 など）は違反にしない。
      -- skkeleton の Lua のエラーは違反にする
      local ok, err = pcall(child.type_keys, profiles.expand(key))
      if not ok and (tostring(err):find("skkeleton", 1, true) or not tostring(err):find("E%d+:")) then
        return { steps = i, violations = { { name = "error", msg = tostring(err) } }, abstract = "error" }
      end
      if not settle(child) then
        -- 入力待ち（confirm() など）。ここから先は広げない
        return { steps = i, blocked = true, abstract = "blocked", seen = seen }
      end
      local s = snapshot(child)
      if every or i == #keys then
        local v = check(base, prev, key, s, hist)
        if #v > 0 then
          return { steps = i, violations = v, abstract = abstract(s), snapshot = s, prev = prev, seen = seen }
        end
      end
      s.key = key
      spec.observe(hist, prev, s)
      -- 辺（前の抽象状態・キー・次の抽象状態）を記録する
      seen[#seen + 1] = abstract(prev) .. " >" .. key .. "> " .. abstract(s)
      prev = s
    end
  end
  return { steps = #keys, abstract = abstract(prev), seen = seen }
end

-- worker: 入力ファイルのキー列を流して、結果を JSON で書く
if opts.worker then
  local items = vim.json.decode(table.concat(vim.fn.readfile(opts.worker.input), "\n"))
  local child = new_child()
  local out = {}
  for _, item in ipairs(items) do
    local ok, res = pcall(run, child, item.keys, item.mutation, item.every, item.config)
    if not ok then
      res = { steps = #item.keys, violations = { { name = "error", msg = tostring(res) } }, abstract = "error" }
    end
    res.keys = item.keys
    res.config = item.config
    -- 観測そのものは大きいので、反例のときだけ返す
    if not res.violations then
      res.snapshot, res.prev = nil, nil
    end
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
        "--profile",
        opts.profile,
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
  if res.config and next(res.config) then
    print("  設定: " .. vim.inspect(res.config, { newline = " ", indent = "" }))
    print(
      ("  再生: --config '%s' --keys '%s'"):format(
        vim.inspect(res.config, { newline = " ", indent = "" }),
        table.concat(res.keys, ",")
      )
    )
  end
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
local function shrink(keys, mutation, config)
  local function fails(ks)
    local r = run_parallel({ { keys = ks, mutation = mutation, every = true, config = config } })[1]
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

-- 反例を性質ごとに 1 つ覚える。既知のものと既知でないものは分けて覚える（既知の反例で隠れないように）
local function slot(name, keys, msg)
  return spec.is_known(name, keys, msg) and (name .. "\0known") or name
end

if opts.keys then
  -- 1 本のキー列を流して、キーごとの観測を出す（反例を追うため）
  local child = new_child()
  local init = INITS[opts.keys[1]] and table.remove(opts.keys, 1) or nil
  start(child, opts.mutate, init, opts.config)
  settle(child)
  local base = snapshot(child)
  local prev = base
  local hist = {}
  spec.observe(hist, nil, base)
  for _, key in ipairs(opts.keys) do
    pcall(child.type_keys, profiles.expand(key))
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
    if os.getenv("FORMAL_DEBUG") then
      print(
        "  "
          .. vim.inspect(
            { screen = s.screen, popup = s.popup, indicator = s.indicator, win_pos = s.win_pos },
            { newline = " ", indent = "" }
          )
      )
    end
    for _, v in ipairs(check(base, prev, key, s, hist)) do
      print("  ✗ " .. v.name .. ": " .. v.msg)
      local k = slot(v.name, opts.keys, v.msg)
      found[k] = found[k] or { keys = opts.keys, violations = { v } }
    end
    s.key = key
    spec.observe(hist, prev, s)
    prev = s
  end
  child.stop()
elseif opts.fuzz then
  -- カバレッジを手がかりにしたファジング（AFL の考え方を抽象状態に当てはめたもの）と、スウォームテスト。
  -- 新しい抽象状態に届いたキー列をコーパスに取っておき、まれな状態に届いた列ほど選んで、
  -- 後ろにキーを足す・途中で切って足す・別の列とつなぐ、で伸ばす。1 本ごとに、キーの集合の一部と
  -- 設定の組み合わせ（スウォーム）を選んで流す。--fuzz N は流すキー列の本数
  math.randomseed(opts.seed)
  local SWARM_CONFIG = {
    eggLikeNewline = { true, false },
    keepState = { true, false },
    showCandidatesCount = { 1, 4 },
    immediatelyCancel = { true, false },
    acceptIllegalResult = { true, false },
    popupBorder = { "none", "rounded" },
    keepMode = { true, false },
    -- upstream #33（絵文字のマーカー）と #103（空のマーカー）
    markerHenkan = { "▽", "", "🍣", "<<" },
    markerHenkanSelect = { "▼", "", "👍🏽", "[[" },
  }
  local function swarm()
    local keys = {}
    for _, k in ipairs(ALPHABET) do
      if math.random() < 0.8 then
        keys[#keys + 1] = k
      end
    end
    if #keys == 0 then
      keys = vim.list_slice(ALPHABET)
    end
    local config = {}
    for name, values in pairs(SWARM_CONFIG) do
      if math.random() < 0.5 then
        config[name] = values[math.random(#values)]
      end
    end
    return { keys = keys, config = config }
  end
  local function pick(list)
    return list[math.random(#list)]
  end
  local hits = {} -- 辺 -> 届いた回数
  local corpus = {} -- { keys, config, swarm, rare }
  local executed, steps_total = 0, 0
  -- 前回のファジングの続きから。コードが変わっていたら届いた辺の回数は数え直す（コーパスは使う）
  local fuzz_cache_name = ("fuzz-%s-%s.json"):format(opts.profile, opts.mutate or "none")
  local hash = code_hash()
  local saved = not opts.mutate and cache_read(fuzz_cache_name)
  if saved then
    corpus = saved.corpus or {}
    if saved.hash == hash then
      hits = saved.hits or {}
    end
    print(("fuzz: 前回のコーパス %d 本を引き継ぐ（辺 %d）"):format(#corpus, vim.tbl_count(hits)))
  end
  -- 浅い深さまで幅優先で調べ、抽象状態ごとに最短のキー列を 1 本ずつコーパスに入れる。
  -- キー列ではなく状態から均等に伸ばすので、まれな状態の先にも届きやすい
  if (opts.seed_depth or 0) > 0 then
    local visited, frontier = {}, {}
    for _, name in ipairs(INIT_NAMES) do
      frontier[#frontier + 1] = { name }
    end
    for _ = 1, opts.seed_depth do
      local items = {}
      for _, path in ipairs(frontier) do
        for _, key in ipairs(ALPHABET) do
          items[#items + 1] =
            { keys = vim.list_extend(vim.list_slice(path), { key }), mutation = opts.mutate, every = false }
        end
      end
      frontier = {}
      for _, r in ipairs(run_parallel(items)) do
        steps_total = steps_total + (r.steps or 0)
        if r.violations then
          local k = slot(r.violations[1].name, r.keys, r.violations[1].msg)
          found[k] = found[k] or r
        elseif not r.blocked and not visited[r.abstract] then
          visited[r.abstract] = true
          frontier[#frontier + 1] = r.keys
          corpus[#corpus + 1] = { keys = r.keys, config = {}, swarm = ALPHABET, rare = r.abstract }
        end
      end
    end
    print(
      ("fuzz: 幅優先（深さ %d）で抽象状態 %d をコーパスに、%.1f 秒"):format(
        opts.seed_depth,
        #corpus,
        elapsed()
      )
    )
  end
  local batch = opts.jobs * 6
  while executed < opts.fuzz do
    local items = {}
    for _ = 1, math.min(batch, opts.fuzz - executed) do
      local item
      if #corpus == 0 or math.random() < 0.25 then
        local sw = swarm()
        local ks = { INIT_NAMES[math.random(#INIT_NAMES)] }
        for _ = 1, math.random(4, opts.length) do
          ks[#ks + 1] = pick(sw.keys)
        end
        item = { keys = ks, config = sw.config, swarm = sw.keys }
      else
        -- まれな状態に届いた列ほど選ぶ（重みは 1 / 届いた回数）
        local total = 0
        for _, c in ipairs(corpus) do
          c.w = 1 / (hits[c.rare] or 1)
          total = total + c.w
        end
        local x, base = math.random() * total, corpus[#corpus]
        for _, c in ipairs(corpus) do
          x = x - c.w
          if x <= 0 then
            base = c
            break
          end
        end
        local ks = vim.list_slice(base.keys)
        local r = math.random()
        if r < 0.5 then
          for _ = 1, math.random(1, 12) do
            ks[#ks + 1] = pick(base.swarm)
          end
        elseif r < 0.8 then
          ks = vim.list_slice(ks, 1, math.random(1, #ks))
          for _ = 1, math.random(1, 12) do
            ks[#ks + 1] = pick(base.swarm)
          end
        else
          local other = pick(corpus)
          for j = 2, #other.keys do
            ks[#ks + 1] = other.keys[j]
          end
        end
        while #ks > opts.length * 2 do
          table.remove(ks, 2)
        end
        item = { keys = ks, config = base.config, swarm = base.swarm }
      end
      item.mutation = opts.mutate
      item.every = true
      items[#items + 1] = item
    end
    local results = run_parallel(items)
    executed = executed + #items
    for idx, r in ipairs(results) do
      local item = items[idx]
      steps_total = steps_total + (r.steps or 0)
      local new, rare, rare_hits = false, nil, math.huge
      for _, a in ipairs(r.seen or {}) do
        hits[a] = (hits[a] or 0) + 1
        if hits[a] == 1 then
          new = true
        end
        if hits[a] < rare_hits then
          rare, rare_hits = a, hits[a]
        end
      end
      if r.violations then
        local prefix = vim.list_slice(r.keys, 1, r.steps)
        local key = slot(r.violations[1].name, prefix, r.violations[1].msg)
        if not found[key] then
          local best = shrink(prefix, opts.mutate, item.config) or r
          best.config = item.config
          found[key] = best
        end
      elseif new and rare then
        corpus[#corpus + 1] = { keys = r.keys, config = item.config, swarm = item.swarm, rare = rare }
      end
    end
    print(
      ("fuzz: %d 本、辺 %d、コーパス %d、%.1f 秒"):format(executed, vim.tbl_count(hits), #corpus, elapsed())
    )
  end
  print(("計 %d 遷移、%d 辺"):format(steps_total, vim.tbl_count(hits)))
  if not opts.mutate then
    -- コーパスは大きくなりすぎないよう、新しい 400 本まで
    while #corpus > 400 do
      table.remove(corpus, 1)
    end
    cache_write(fuzz_cache_name, { hash = hash, corpus = corpus, hits = hits })
  end
elseif opts.random then
  -- ランダムなキー列（深い状態に届く）。違反したら ddmin で縮める
  math.randomseed(opts.seed)
  local items = {}
  for _ = 1, opts.random do
    local ks = { INIT_NAMES[math.random(#INIT_NAMES)] }
    for _ = 1, opts.length do
      ks[#ks + 1] = ALPHABET[math.random(#ALPHABET)]
    end
    items[#items + 1] = { keys = ks, mutation = opts.mutate, every = true }
  end
  local states = {}
  for _, r in ipairs(run_parallel(items)) do
    for _, a in ipairs(r.seen or {}) do
      states[a] = true
    end
    if r.violations then
      local prefix = vim.list_slice(r.keys, 1, r.steps)
      local key = slot(r.violations[1].name, prefix, r.violations[1].msg)
      if not found[key] then
        found[key] = shrink(prefix, opts.mutate) or r
      end
    end
  end
  print(
    ("random: %d 本 × %d キー、辺 %d、%.1f 秒"):format(
      opts.random,
      opts.length,
      vim.tbl_count(states),
      elapsed()
    )
  )
else
  -- 幅優先。同じコード・同じ深さで調べ済みなら流さない
  local bfs_cache_name = ("bfs-%s-d%d-%s-%s.json"):format(opts.profile, opts.depth, opts.mutate or "none", code_hash())
  local hit = cache_read(bfs_cache_name)
  if hit then
    print(
      ("（キャッシュ）同じコードで調べ済み: 計 %d 遷移、%d 抽象状態"):format(
        hit.transitions,
        hit.states
      )
    )
    print(hit.ok and "\n✓ 既知のもの以外に違反なし" or ("\n✗ 前回の違反: " .. (hit.summary or "")))
    vim.cmd(hit.ok and "qall!" or "cquit 1")
  end
  _G.formal_bfs_cache_name = bfs_cache_name
  -- frontier の各状態から、すべてのキーを 1 つずつ試す
  local visited = {}
  local frontier = {}
  local roots = {}
  for _, name in ipairs(INIT_NAMES) do
    roots[#roots + 1] = { keys = { name }, mutation = opts.mutate, every = true }
  end
  for _, r in ipairs(run_parallel(roots)) do
    if r.violations then
      local k = slot(r.violations[1].name, r.keys, r.violations[1].msg)
      found[k] = found[k] or r
    elseif not visited[r.abstract] then
      visited[r.abstract] = true
      frontier[#frontier + 1] = r.keys
    end
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
        local k = slot(name, r.keys, r.violations[1].msg)
        if not found[k] then
          found[k] = r
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
  _G.formal_bfs_stats = { transitions = transitions, states = vim.tbl_count(visited) }
end

print(("profile %s（%s）"):format(opts.profile, profile.doc))
if opts.mutate then
  print(("mutation %s（%s）"):format(opts.mutate, MUTATIONS[opts.mutate].issue))
end
local failed = false
for slot_name, r in vim.spairs(found) do
  local name = slot_name:gsub("%z.*", "")
  local known = spec.is_known(
    name,
    vim.list_slice(r.keys, 1, (r.steps and r.steps > 0) and r.steps or #r.keys),
    r.violations[1].msg
  )
  if known then
    print(("\n△ 既知: %s\n  %s\n  反例: %s"):format(name, known.reason, keys_str(r.keys)))
  else
    failed = true
    report(r)
  end
end
if _G.formal_bfs_cache_name and _G.formal_bfs_stats then
  local names = {}
  for slot_name in pairs(found) do
    names[#names + 1] = (slot_name:gsub("%z.*", ""))
  end
  cache_write(_G.formal_bfs_cache_name, {
    transitions = _G.formal_bfs_stats.transitions,
    states = _G.formal_bfs_stats.states,
    ok = not failed,
    summary = table.concat(names, " / "),
  })
end
if not failed then
  print("\n✓ 既知のもの以外に違反なし")
  vim.cmd("qall!")
else
  vim.cmd("cquit 1")
end

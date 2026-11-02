-- 形式検証の PoC: 入力エンジン（core）だけを、nvim の子を使わずに同じプロセスの中で動かして調べる。
-- 本物のキーの振り分け（keymap.handle_key）を通し、UI へ出るところ（host）だけを差し替える。
-- 1 キーが数十マイクロ秒で済むので、子の nvim を使う check.lua よりずっと深く広く調べられる。
--
-- 調べる性質:
--   - どのキー列でも Lua のエラーにならない
--   - cmdline と terminal で使う「BS で消して書き直す」出力（PreEdit:output）を仮想の行に当てると、
--     行はいつも「確定した文字列 + pre-edit」になる。確定した文字列は <BS> のほかでは縮まない
--   - 確定した文字列にマーカー（▽ ▼）が入らない
--   - 状態が整っている（▼ なら候補があり、番号が範囲内。pre-edit のマーカーと状態が合う）
--
-- 使い方: nvim --headless -u NONE -i NONE -l tests/formal/core.lua [--depth D] [--random N --length L --seed S]
--   [--keys 'K,a,n,<space>']   1 本を流して、キーごとの状態を出す
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path

local opts = { depth = 4, random = nil, length = 30, seed = 1, keys = nil, max_states = 3000 }
do
  local i = 1
  while i <= #arg do
    local k, v = arg[i], arg[i + 1]
    if k == "--depth" then
      opts.depth, i = tonumber(v), i + 1
    elseif k == "--random" then
      opts.random, i = tonumber(v), i + 1
    elseif k == "--length" then
      opts.length, i = tonumber(v), i + 1
    elseif k == "--seed" then
      opts.seed, i = tonumber(v), i + 1
    elseif k == "--max-states" then
      opts.max_states, i = tonumber(v), i + 1
    elseif k == "--differential" then
      opts.differential, i = tonumber(v), i + 1
    elseif k == "--metamorphic" then
      opts.metamorphic, i = tonumber(v), i + 1
    elseif k == "--kanatable" then
      -- かなテーブルへの登録（rom に足す。文字だけ。例: '{ ["z,"] = { "‥" } }'。関数はキーマップに置く #67）
      opts.kanatable, i = assert(loadstring("return " .. v))(), i + 1
    elseif k == "--keymap" then
      -- キーマップの登録（例: '{ { "input", ";", "henkanPoint" } }'）
      opts.keymap, i = assert(loadstring("return " .. v))(), i + 1
    elseif k == "--config" then
      opts.config, i = assert(loadstring("return " .. v))(), i + 1
    elseif k == "--keys" then
      opts.keys, i = vim.split(v, ",", { plain = true }), i + 1
    end
    i = i + 1
  end
end

local config = require("skkeleton.config")
local host = require("skkeleton.host")
local store = require("skkeleton.store")
local keymap = require("skkeleton.keymap")
local kana = require("skkeleton.kana")
local notation = require("skkeleton.notation")
local Fake = require("core_helpers").FakeLibrary

-- 辞書（読み -> 候補）。数値変換・接頭辞・接尾辞・注釈つきの候補も入れる
local DICT = {
  ["okurinasi:かん"] = { "缶", "感", "漢", "幹", "管", "館", "観" },
  ["okurinasi:かんじ"] = { "漢字", "幹事;取りまとめ役" },
  ["okurinasi:なか"] = { "中" },
  ["okurinasi:#ばい"] = { "#1倍", "#3倍" },
  ["okurinasi:abc"] = { "ＡＢＣ" },
  ["okurinasi:し>"] = { "新" },
  ["okurinasi:>てき"] = { "的" },
  ["okuriari:わるk"] = { "悪" },
  ["okuriari:かえr"] = { "帰", "返" },
  ["okuriari:のt"] = { "乗" },
  ["okuriari:かk"] = { "書", "掛" },
}
-- 変身関係の検査が、辞書の一部を差し替えるときに使う（new_run が DICT に重ねる）
local extra_dict = {}

-- UI の差し替え。辞書登録は、キー列で決めた答え（"" なら取り消し）を返す
local register_answer = ""
local events = {}
host.mode_changed = function(mode)
  vim.g["skkeleton#mode"] = mode
end
host.disable = function()
  events[#events + 1] = "disable"
end
host.show_candidates = function() end
host.keep_state_on_insert_enter = function() end
host.confirm = function()
  return true
end
-- 入れ子の辞書登録を模すための答えの列。空でなければ host.input は先頭から 1 つ取る。
-- 文字列ならその語を答え、キーの表なら、入力欄の中でそのキーを新しい Context に打って、確定した行を答える
-- （本物の host.input も、入力欄の中は store.init_context() した新しい Context で、終わると元の Context に戻す）
local register_queue = {}
local step_in_prompt
host.input = function()
  events[#events + 1] = "input"
  if #register_queue == 0 then
    return register_answer
  end
  local a = table.remove(register_queue, 1)
  if type(a) == "string" then
    return a
  end
  local outer = store.context()
  local inner = { ctx = store.init_context(), line = "", committed = "" }
  inner.ctx.vim_mode = "c"
  for _, k in ipairs(a) do
    step_in_prompt(inner, k)
  end
  store.set_context(outer)
  return inner.line
end

local function markers()
  return { config.options.markerHenkan, config.options.markerHenkanSelect }
end

-- キーの集合。ローマ字・大文字（変換の始まり）・モードの切り替え・変換の操作・記号・数字
local ALPHABET = {
  "a",
  "i",
  "u",
  "e",
  "o",
  "k",
  "n",
  "s",
  "t",
  "j",
  "x",
  "w",
  "r",
  "b",
  "K",
  "N",
  "A",
  "W",
  "R",
  "Q",
  "X",
  "q",
  "l",
  "L",
  "/",
  ">",
  "-",
  ",",
  ".",
  "1",
  "#",
  "@",
  "&",
  "z",
  ";",
  "!",
  "<space>",
  "<cr>",
  "<bs>",
  "<c-g>",
  "<c-h>",
  "<c-j>",
  "<c-q>",
  "<esc>",
  "<tab>",
}

-- 1 文字を消す。Neovim の <BS> と同じく、合成文字（半角カナの濁点 ﾞ など）は前の文字ごと消す（'delcombine' は off）
local function drop_last(str)
  if str == "" then
    return str
  end
  local n = vim.fn.strchars(str, 1)
  return vim.fn.strcharpart(str, 0, n - 1, 1)
end

-- 仮想の行に BS で消して書き直す出力を当てる
local function apply(line, out)
  for _, ch in ipairs(vim.fn.split(out, "\\zs")) do
    if ch == "\b" then
      line = drop_last(line)
    else
      line = line .. ch
    end
  end
  return line
end

local function new_run(answer)
  config.set(vim.tbl_extend("force", { markerHenkan = "▽", markerHenkanSelect = "▼" }, opts.config or {}))
  local lib = Fake.new()
  lib.data = vim.tbl_extend("force", vim.deepcopy(DICT), vim.deepcopy(extra_dict))
  -- 本物の辞書（dictionary.Library）と同じく、数値変換（#0〜#9）を通して引く
  local plain = Fake.get_henkan_result
  local wrapped = require("skkeleton.dictionary.numeral").wrap({
    get_henkan_result = function(_, kind, word)
      return plain(lib, kind, word)
    end,
  })
  lib.get_henkan_result = function(_, kind, word)
    return wrapped:get_henkan_result(kind, word)
  end
  store.set_library(lib)
  kana.reset()
  keymap.reset()
  if opts.kanatable then
    kana.register("rom", opts.kanatable)
  end
  for _, km in ipairs(opts.keymap or {}) do
    keymap.register(km[1], km[2], km[3])
  end
  kana.set_current("rom")
  local ctx = store.init_context()
  ctx.vim_mode = "c"
  register_answer = answer
  register_queue = {}
  events = {}
  return { ctx = ctx, line = "", committed = "", lib = lib }
end

local function abstract(run)
  local st = run.ctx.state
  return table.concat({
    st.type,
    tostring(st.mode),
    run.ctx.mode,
    #(st.feed or "") > 0 and "f" or "-",
    #(st.henkan_feed or "") > 0 and "h" or "-",
    #(st.okuri_feed or "") > 0 and "o" or "-",
    st.type == "henkan" and math.min(st.candidate_index or 0, 5) or "-",
    st.affix or "-",
  }, "|")
end

local function check_state(run, key, prev_committed)
  local ctx = run.ctx
  local st = ctx.state
  local pre = ctx:to_string()
  if run.line:sub(-#pre) ~= pre and pre ~= "" then
    return ("行 %q が pre-edit %q で終わらない"):format(run.line, pre)
  end
  local committed = pre == "" and run.line or run.line:sub(1, #run.line - #pre)
  for _, m in ipairs(markers()) do
    if m ~= "" and committed:find(m, 1, true) then
      return ("確定した文字列 %q に %s が入った"):format(committed, m)
    end
  end
  if key ~= "<bs>" and key ~= "<c-h>" and #committed < #prev_committed then
    return ("確定した文字列が %q から %q に縮んだ"):format(prev_committed, committed)
  end
  if key ~= "<bs>" and key ~= "<c-h>" and committed:sub(1, #prev_committed) ~= prev_committed then
    return ("確定した文字列 %q が %q で始まらない（前の確定が書き換わった）"):format(
      committed,
      prev_committed
    )
  end
  if st.type == "henkan" then
    if not st.candidates or #st.candidates == 0 then
      return "▼ なのに候補が無い"
    end
    if st.candidate_index < 0 or st.candidate_index >= #st.candidates then
      return ("候補の番号 %d が範囲外（候補 %d 個）"):format(st.candidate_index, #st.candidates)
    end
    local sel = config.options.markerHenkanSelect
    if not vim.startswith(pre, sel) then
      return ("▼ の状態なのに pre-edit %q"):format(pre)
    end
  elseif st.type == "input" then
    -- マーカーも今のモードの変換（カタカナなど）を通る（upstream の toString と同じ）
    local mh = config.options.markerHenkan
    if st.converter then
      mh = st.converter(mh)
    end
    local marked = mh ~= "" and vim.startswith(pre, mh)
      or (mh == "" and (st.mode == "okurinasi" or st.mode == "okuriari"))
    local want = st.mode == "okurinasi" or st.mode == "okuriari"
    if marked ~= want then
      return ("状態 %s なのに pre-edit %q"):format(st.mode, pre)
    end
  end
  run.committed = committed
end

-- 1 キー流して確かめる。違反なら説明を返す
-- かなテーブルに無い記号
SYMBOLS = { ["&"] = true, ["@"] = true, ["%"] = true }

local function step(run, key)
  local prev_committed = run.committed
  local pst = run.ctx.state
  -- 全英（zenkaku）では記号が全角になり、abbrev では文字のまま読みに入るので、ひらがな・カタカナのときだけ
  prev_direct = pst.type == "input" and pst.mode == "direct" and (run.ctx.mode == "hira" or run.ctx.mode == "kata")
  local ok, err = pcall(keymap.handle_key, run.ctx, notation.normalize(key))
  if not ok then
    return "Lua のエラー: " .. tostring(err)
  end
  -- 辞書登録や escape などで Context が作り直されていたら、それを使う
  run.ctx = store.context()
  if run.ctx.state.type == "escape" then
    -- <Esc> で抜けた。行はそこで終わり（以降は新しい Context）
    local out = run.ctx.preedit:output("")
    run.line = apply(run.line, out)
    -- 有効にし直すときと同じく、かなテーブルを設定の値に戻す（main.lua の enable）
    kana.set_current(config.options.kanaTable or "rom")
    run.ctx = store.init_context()
    run.ctx.vim_mode = "c"
    run.committed = run.line
    return nil
  end
  local prev_line = run.line
  local out = run.ctx.preedit:output(run.ctx:to_string())
  run.line = apply(run.line, out)
  -- かなテーブルに無い記号を、▽ でない直接入力で打つと、その記号はちょうど 1 つ増える（upstream #235 の型）
  if SYMBOLS[key] and prev_direct then
    local function count(str)
      local _, n = str:gsub(vim.pesc(key), "")
      return n
    end
    local d = count(run.line) - count(prev_line)
    if d ~= 1 then
      return ("記号 %s を打つと %d 個増えた（行 %q -> %q）"):format(key, d, prev_line, run.line)
    end
  end
  return check_state(run, key, prev_committed)
end

step_in_prompt = step

-- キー列の最初の要素は登録の答え（"=" なら取り消し、"=語" ならその語を登録する）
local function run_keys(keys)
  local answer = ""
  local first = 1
  if keys[1] and keys[1]:sub(1, 1) == "=" then
    answer = keys[1]:sub(2)
    first = 2
  end
  local run = new_run(answer)
  for i = first, #keys do
    local msg = step(run, keys[i])
    if msg then
      return run, i, msg
    end
  end
  return run
end

local function fmt(keys)
  return table.concat(keys, " ")
end

-- ddmin で縮める
local function shrink(keys)
  local function fails(ks)
    local _, at, msg = run_keys(ks)
    return at and msg
  end
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
      if #rest > 0 and fails(rest) then
        keys, n, reduced = rest, math.max(n - 1, 2), true
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
  return keys
end

local found = {}
local function record(keys, at, msg)
  local prefix = vim.list_slice(keys, 1, at)
  local kind = msg:gsub('%b""', "…"):gsub("%d+", "N")
  if not found[kind] then
    found[kind] = { keys = shrink(prefix), msg = msg }
  end
end

local t0 = vim.uv.hrtime()

-- 差分の検査: 同じキー列を insert（"i"）と cmdline（"c"）の Context に流すと、確定した文字列と pre-edit は同じになる。
-- なぜ成り立つか: 入力エンジンは vim_mode を見て変わるところが 2 つしかない（c の <C-g> が ^C を足す、i の確定に undo point
-- "\x07u" を足す）。どちらも表示の都合なので、取り除けば同じ。upstream の preedit.ts も、確定と pre-edit を作る側は
-- モードを見ない。cmdline（`:` と `/`）と terminal は同じ出力（BS で書き直す）なので、c で代表させる。
if opts.differential then
  math.randomseed(opts.seed)
  local function trace(keys, vm)
    local run = new_run("")
    run.ctx.vim_mode = vm
    local line, out = "", {}
    for i, key in ipairs(keys) do
      local ok, err = pcall(keymap.handle_key, run.ctx, notation.normalize(key))
      if not ok then
        return out, "Lua のエラー: " .. tostring(err)
      end
      run.ctx = store.context()
      run.ctx.vim_mode = vm
      local pre
      if run.ctx.state.type == "escape" then
        local o = vm == "c" and (run.ctx.preedit:output(""):gsub("\3", ""))
          or (run.ctx.preedit:take_kakutei():gsub("\7u", ""))
        line = apply(line, o)
        kana.set_current(config.options.kanaTable or "rom")
        run.ctx = store.init_context()
        run.ctx.vim_mode = vm
        pre = ""
      else
        pre = run.ctx:to_string()
        if vm == "c" then
          -- ^C は cmdline を閉じるキーで、文字として残らない（BS に消されないよう外す）
          line = apply(line, (run.ctx.preedit:output(pre):gsub("\3", "")))
        else
          -- undo point（<C-g>u）はキーであって文字ではない。BS に消されないよう、先に外す
          line = apply(line, (run.ctx.preedit:take_kakutei():gsub("\7u", "")))
        end
      end
      local base = vm == "c" and line:sub(1, #line - #pre) or line
      local committed = base:gsub("\3", ""):gsub("\7u", "")
      out[i] = { committed = committed, pre = pre, abs = abstract(run) }
    end
    return out
  end
  local function differs(keys)
    local a, ea = trace(keys, "i")
    local b, eb = trace(keys, "c")
    if ea or eb then
      return #keys, ("Lua のエラー i=%s c=%s"):format(tostring(ea), tostring(eb))
    end
    for i = 1, #keys do
      local x, y = a[i], b[i]
      if x.committed ~= y.committed or x.pre ~= y.pre or x.abs ~= y.abs then
        return i,
          ("insert と cmdline で違う: insert 確定 %q pre-edit %q / cmdline 確定 %q pre-edit %q"):format(
            x.committed,
            x.pre,
            y.committed,
            y.pre
          )
      end
    end
  end
  local checked = 0
  for _ = 1, opts.differential do
    local ks = {}
    for j = 1, opts.length do
      ks[j] = ALPHABET[math.random(#ALPHABET)]
    end
    local at, msg = differs(ks)
    if at then
      local prefix = vim.list_slice(ks, 1, at)
      local n = 2
      while #prefix >= 2 do
        local size = math.ceil(#prefix / n)
        local reduced = false
        for i = 1, #prefix, size do
          local rest = {}
          for j, k in ipairs(prefix) do
            if j < i or j >= i + size then
              rest[#rest + 1] = k
            end
          end
          if #rest > 0 and differs(rest) then
            prefix, n, reduced = rest, math.max(n - 1, 2), true
            break
          end
        end
        if not reduced then
          if n >= #prefix then
            break
          end
          n = math.min(n * 2, #prefix)
        end
      end
      local _, m = differs(prefix)
      local kind = msg:gsub('%b""', "…")
      if not found[kind] then
        found[kind] = { keys = prefix, msg = m or msg }
      end
    end
    checked = checked + 1
  end
  print(("differential: %d 本 × %d キー、%.1f 秒"):format(checked, opts.length, (vim.uv.hrtime() - t0) / 1e9))
  if vim.tbl_isempty(found) then
    print("✓ 違反なし")
    vim.cmd("qall!")
  end
  for _, f in pairs(found) do
    print(("\n✗ 反例（%d キー）: %s\n    %s"):format(#f.keys, fmt(f.keys), f.msg))
  end
  vim.cmd("cquit 1")
end

if opts.keys then
  local run = new_run(opts.keys[1]:sub(1, 1) == "=" and table.remove(opts.keys, 1):sub(2) or "")
  for _, key in ipairs(opts.keys) do
    local msg = step(run, key)
    print(
      ("%-8s 状態=%s/%s pre-edit=%q 行=%q%s"):format(
        key,
        run.ctx.state.type,
        tostring(run.ctx.state.mode),
        run.ctx:to_string(),
        run.line,
        msg and ("  ✗ " .. msg) or ""
      )
    )
    if msg then
      break
    end
  end
  vim.cmd("qall!")
end

-- 変身関係（metamorphic relation）の検査。正解を知らなくても、意味が同じになるはずの 2 つのキー列の結果を比べる
if opts.metamorphic then
  math.randomseed(opts.seed)
  local hira_to_kata = require("skkeleton.kana.hira_kata").hira_to_kata
  local LETTERS = vim.split("aiueokstnhmyrwgzdbpjfcv-", "")
  -- 読み、ひらがな、候補の数
  local READINGS = { { "kan", "かん", 7 }, { "kanji", "かんじ", 2 }, { "naka", "なか", 1 } }
  local function romaji(n)
    local t = {}
    for i = 1, n do
      t[i] = LETTERS[math.random(#LETTERS)]
    end
    return t
  end
  local function line_of(keys)
    local run, at, msg = run_keys(keys)
    return run, at and msg
  end
  local function concat(...)
    local out = { "=" }
    for _, list in ipairs({ ... }) do
      vim.list_extend(out, list)
    end
    return out
  end
  local function fail(name, keys, detail)
    local kind = name
    if not found[kind] then
      found[kind] = { keys = keys, msg = name .. ": " .. detail }
    end
  end

  -- 数値変換の正解（numeral.lua とは別に書いた規則）。作れない型・数は nil
  local KJ = { [0] = "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九" }
  local ZEN = { [0] = "０", "１", "２", "３", "４", "５", "６", "７", "８", "９" }
  -- 位取りの漢数字。10 進の文字列を上の桁から 1 桁ずつ見る（numeral.lua の「4 桁ずつの数に直して」とは別の書き方）。
  -- 十・百・千の前の 1 は書かない（十、百二）。万・億・兆の前は、その 4 桁が 1 だけのとき「一」を書く（一万、一億）。
  -- upstream（@geolonia/japanese-numeral）の number2kanji と 600 個の乱数で突き合わせて同じになることを確かめた。
  -- 15 桁までなら JavaScript の数で正確に表せる（それより上は upstream の側が丸める）ので、検査もそこまで
  local function classic(d)
    d = d:gsub("^0+", "")
    if d == "" then
      return KJ[0]
    end
    local PLACE = { [0] = "", "十", "百", "千" }
    local BIG = { [0] = "", "万", "億", "兆" }
    local n, out = #d, ""
    for g = math.ceil(n / 4) - 1, 0, -1 do
      local chunk = d:sub(math.max(1, n - g * 4 - 3), n - g * 4)
      local piece = ""
      for i = 1, #chunk do
        local dg, pos = tonumber(chunk:sub(i, i)), #chunk - i
        if dg > 0 then
          piece = piece .. ((dg == 1 and pos > 0) and "" or KJ[dg]) .. PLACE[pos]
        end
      end
      if piece ~= "" then
        if g > 0 and chunk:gsub("^0+", "") == "1" then
          piece = KJ[1]
        end
        out = out .. piece .. BIG[g]
      end
    end
    return out
  end
  local function roman(n)
    local out = ("M"):rep(math.floor(n / 1000))
    n = n % 1000
    for _, r in ipairs({
      { 900, "CM" },
      { 500, "D" },
      { 400, "CD" },
      { 100, "C" },
      { 90, "XC" },
      { 50, "L" },
      { 40, "XL" },
      { 10, "X" },
      { 9, "IX" },
      { 5, "V" },
      { 4, "IV" },
      { 1, "I" },
    }) do
      while n >= r[1] do
        out = out .. r[2]
        n = n - r[1]
      end
    end
    return out
  end
  local DAIJI = {
    ["一"] = "壱",
    ["二"] = "弐",
    ["三"] = "参",
    ["四"] = "肆",
    ["五"] = "伍",
    ["六"] = "陸",
    ["七"] = "漆",
    ["八"] = "捌",
    ["九"] = "玖",
    ["十"] = "拾",
    ["百"] = "佰",
    ["千"] = "阡",
    ["万"] = "萬",
    ["〇"] = "零",
  }
  -- 数字の列 d（先頭の 0 を含みうる）と型 #ty から、候補の中の #ty が置き換わる文字列。作れない（upstream の結果が
  -- 決まっていない）ときは nil。upstream は parseInt(d) の値で変換するので、#0〜#9 のうち数として読む型は先頭の 0 を落とす。
  -- 落とさないのは #0 と #4（そのまま）だけ。決まっていないのは、ローマ数字の 0（upstream は文章を返す）と
  -- 6 桁以上（upstream は M を 10 万個作ろうとして止まる）
  local function numeral_oracle(ty, d)
    local s = d:gsub("^0+", "")
    if s == "" then
      s = "0"
    end
    local n = tonumber(s)
    local function each(map, str)
      return (str:gsub("%d", function(c)
        return map[tonumber(c)]
      end))
    end
    if ty == 0 or ty == 4 then
      return d
    elseif ty == 1 then
      return each(ZEN, s)
    elseif ty == 2 then
      return each(KJ, s)
    elseif ty == 3 then
      return classic(s)
    elseif ty == 5 then
      -- Lua のパターンはバイト単位なので、1 文字ずつ置き換える
      local out = {}
      for _, ch in ipairs(vim.fn.split(classic(s), "\\zs")) do
        out[#out + 1] = DAIJI[ch] or ch
      end
      return table.concat(out)
    elseif ty == 8 and n >= 1 and #s <= 5 then
      return roman(n)
    elseif ty == 9 then
      -- 棋譜は 11〜99（どちらの桁も 1〜9）だけ「３四」にし、ほかは数の文字列のまま（先頭の 0 は落ちる）
      if s:match("^[1-9][1-9]$") then
        return ZEN[tonumber(s:sub(1, 1))] .. KJ[tonumber(s:sub(2, 2))]
      end
      return s
    end
  end
  local checked = 0
  for _ = 1, opts.metamorphic do
    -- M1: カタカナで打った結果は、ひらがなで打った結果をカタカナにしたもの（最後に l で残りを確定する）
    local word = romaji(math.random(1, 12))
    local h_keys = concat(word, { "l" })
    local k_keys = concat({ "q" }, word, { "l" })
    local h, herr = line_of(h_keys)
    local k, kerr = line_of(k_keys)
    if herr or kerr then
      fail("違反", herr and h_keys or k_keys, herr or kerr)
    elseif k.line ~= hira_to_kata(h.line) then
      fail(
        "M1 カタカナ",
        k_keys,
        ("カタカナ %q、ひらがな %q をカタカナにすると %q"):format(
          k.line,
          h.line,
          hira_to_kata(h.line)
        )
      )
    end
    -- M2: ▽ で打ってから <C-g> で取り消すと、確定済みの文字列は変わらない
    local pre = romaji(math.random(0, 8))
    local tail = romaji(math.random(1, 8))
    -- 最後の確定は <c-j>（l だと直前の z とつながって zl の「→」になる）
    -- 打ちかけ（pre の最後の k など）は K で捨てられるので、先に <c-j> で確定しておく
    local a = line_of(concat(pre, { "<c-j>" }))
    local b_keys = concat(pre, { "<c-j>", "K" }, tail, { "<c-g>", "<c-j>" })
    local b, berr = line_of(b_keys)
    if not berr and a.line ~= b.line then
      fail("M2 ▽ の取り消し", b_keys, ("取り消したあと %q、▽ の前は %q"):format(b.line, a.line))
    end
    -- M3: 変換してから <C-g> で取り消すと ▽ と読みに戻る。M4: <Space> n 回のあと x は n−1 回と同じ候補
    local r = READINGS[math.random(#READINGS)]
    -- 候補一覧（showCandidatesCount を超えたところ）はページ単位で進むので、1 つずつ進む範囲で比べる
    local n = math.random(2, math.max(2, math.min(r[3], config.options.showCandidatesCount)))
    local spaces = {}
    for i = 1, n do
      spaces[i] = "<space>"
    end
    local head = { "K" }
    for c in r[1]:sub(2):gmatch(".") do
      head[#head + 1] = c
    end
    head[1] = r[1]:sub(1, 1):upper()
    local c_keys = concat(head, { "<space>", "<c-g>" })
    local c = line_of(c_keys)
    -- immediatelyCancel（既定は true）なら ▼ ごと消す。false のときだけ ▽ に戻る（upstream の cancel と同じ）
    if not config.options.immediatelyCancel and c.ctx:to_string() ~= "▽" .. r[2] then
      fail(
        "M3 ▼ の取り消し",
        c_keys,
        ("取り消したあと %q、期待 %q"):format(c.ctx:to_string(), "▽" .. r[2])
      )
    end
    local x_keys = concat(head, spaces, { "x" })
    local y_keys = concat(head, vim.list_slice(spaces, 1, n - 1))
    local x = line_of(x_keys)
    local y = line_of(y_keys)
    if r[3] >= 2 and x.ctx:to_string() ~= y.ctx:to_string() then
      fail(
        "M4 前候補",
        x_keys,
        ("x のあと %q、<Space> %d 回なら %q"):format(x.ctx:to_string(), n - 1, y.ctx:to_string())
      )
    end
    -- M5: ▼ で候補を X で削除すると、同じ読みをもう一度変換しても、その候補は出てこない
    if r[3] >= 2 then
      local k = math.random(1, math.min(r[3], config.options.showCandidatesCount))
      local sp = {}
      for i = 1, k do
        sp[i] = "<space>"
      end
      local first = line_of(concat(head, sp))
      local purged = first.ctx:to_string():gsub("^" .. vim.pesc(config.options.markerHenkanSelect), "")
      local again_keys = concat(head, sp, { "X" }, head, { "<space>" })
      local all = {}
      local again = line_of(again_keys)
      for _ = 1, r[3] do
        all[#all + 1] = again.ctx:to_string():gsub("^" .. vim.pesc(config.options.markerHenkanSelect), "")
        if again.ctx.state.type ~= "henkan" then
          break
        end
        require("skkeleton.keymap").handle_key(again.ctx, "<space>")
      end
      if purged ~= "" and vim.tbl_contains(all, purged) then
        fail(
          "M5 候補の削除",
          again_keys,
          ("%q を削除したのに、また出てきた（%s）"):format(purged, table.concat(all, " "))
        )
      end
    end

    -- M6: 数値変換。読みの数字 d と型 #N から、候補は独立に書いた規則（numeral_oracle）で決まる
    -- （#0・#4 そのまま、#1 全角、#2 漢数字、#3 位取りの漢数字、#5 大字、#8 ローマ数字、#9 棋譜）。
    -- 数字は 1〜15 桁で、0 そのもの・先頭の 0（007）・大きな数（万・億・兆の位取り）を含む。
    -- 読みに数字が 2 つ以上あるとき（#と#）は、候補の i 番目の # が読みの i 番目の数字で置き換わる。
    -- ; は henkanPoint（数字から読みを始めるため）
    do
      local function digits()
        local len = ({ 1, 1, 2, 3, 4, 5, 8, 12, 15 })[math.random(9)]
        local t = {}
        for i = 1, len do
          -- 0 を多めに混ぜる（0 だけ・先頭の 0・位の抜け）
          t[i] = math.random(3) == 1 and "0" or tostring(math.random(0, 9))
        end
        return table.concat(t)
      end
      local TYPES = { 0, 1, 2, 3, 4, 5, 8, 9 }
      local d = digits()
      local ty = TYPES[math.random(#TYPES)]
      local want = numeral_oracle(ty, d)
      if want then
        extra_dict = { ["okurinasi:#ばい"] = { "#" .. ty .. "倍" } }
        local keys = { "=", ";" }
        for ch in d:gmatch(".") do
          keys[#keys + 1] = ch
        end
        vim.list_extend(keys, { "b", "a", "i", "<space>" })
        local n_run = line_of(keys)
        if n_run.ctx:to_string() ~= "▼" .. want .. "倍" then
          fail(
            "M6 数値変換",
            keys,
            ("%s倍 の #%d で %q、期待 %q"):format(d, ty, n_run.ctx:to_string(), "▼" .. want .. "倍")
          )
        end
      end
      -- 数字が 2 つの読み（#と#）は、それぞれの数字がそれぞれの型で変換される（#1月#1日 のように型が同じでもよい）
      local d1, d2 = digits(), digits()
      local t1, t2 = TYPES[math.random(#TYPES)], TYPES[math.random(#TYPES)]
      local w1, w2 = numeral_oracle(t1, d1), numeral_oracle(t2, d2)
      if w1 and w2 then
        extra_dict = { ["okurinasi:#と#"] = { ("#%dと#%d"):format(t1, t2) } }
        local k2 = { "=", ";" }
        for ch in (d1 .. "to" .. d2):gmatch(".") do
          k2[#k2 + 1] = ch
        end
        k2[#k2 + 1] = "<space>"
        local r2 = line_of(k2)
        local want2 = "▼" .. w1 .. "と" .. w2
        if r2.ctx:to_string() ~= want2 then
          fail(
            "M6 数値変換（数字が 2 つ）",
            k2,
            ("#%dと#%d の %s と %s で %q、期待 %q"):format(t1, t2, d1, d2, r2.ctx:to_string(), want2)
          )
        end
      end
      extra_dict = {}
    end
    -- M13: 辞書の本文の 1 つの候補（"/…/" の 1 要素）を読み込んで変換すると、▼ の候補は「語」になり、注釈は出ない。
    -- SKK の辞書の形式では、語や注釈に ; や / を含めるときは (concat "\073") のように書く（skk-jisyo の仕様）。
    -- だから (concat "a\073b") の語は "a;b" で、注釈の区切りではない。注釈の区切りは式の外の最初の ; だけ。
    -- 読み込んだ結果（skk.split_candidates）を、語と注釈を分ける前の文字列 "a;b" のまま渡すと、
    -- 語の ; まで注釈と見なして "a" になる。expected は独立に書いた規則（式の外の ; で分け、式は後で展開）。
    do
      local skk = require("skkeleton.dictionary.skk")
      local RAW = {
        { [[plain]], "plain" },
        { [[w;注釈]], "w" },
        { [[(concat "a\073b")]], "a;b" },
        { [[(concat "a\073b");注釈]], "a;b" },
        { [[x;(concat "n\073m")]], "x" },
        { [[(concat "p\057q");(concat "r\057s")]], "p/q" },
        { [[(concat "\057")]], "/" },
      }
      local r = RAW[math.random(#RAW)]
      local cands = skk.split_candidates("/" .. r[1] .. "/")
      extra_dict = { ["okurinasi:てす"] = cands }
      local keys = { "=", ";", "t", "e", "s", "u", "<space>" }
      local run = line_of(keys)
      if run.ctx:to_string() ~= "▼" .. r[2] then
        fail(
          "M13 辞書の候補の語と注釈",
          keys,
          ("辞書の %s が %q に読まれ、▼ は %q（期待 %q）"):format(
            r[1],
            cands[1],
            run.ctx:to_string(),
            "▼" .. r[2]
          )
        )
      end
      extra_dict = {}
    end
    -- M14: 候補の選び方（ページ送りと選択キー）。候補が showCandidatesCount を超えると、<Space> は 7 個ずつ進み、
    -- 7 個の一覧が出る。そこでは selectCandidateKeys（asdfjkl）の n 番目のキーが、一覧の n 番目を確定する。
    -- x は 7 個戻り、showCandidatesCount − 1 より前には戻らない。正解は henkan.lua を見ずに、この規則だけで書いた
    -- 「今の候補の番号 p」の表で決める（p = -1 は ▽）。一覧の中身（host.show_candidates に渡る行）も同じ表と比べる。
    -- 候補を使い切った <Space> は辞書登録の欄になる（ここでは取り消しの答えなので p は変わらない）。
    do
      local n = math.random(1, 20)
      local C = ({ 1, 2, 3, 4, 4, 5, 7, 9 })[math.random(8)]
      local K = ({ "asdfjkl", "asdfjkl", "1234567", "hjklasd" })[math.random(4)]
      local keys7 = vim.split(K, "")
      local cands, words = {}, {}
      for i = 1, n do
        words[i] = ("候%02d"):format(i)
        -- 奇数番目には注釈をつける（確定する語は注釈を含まない）
        cands[i] = i % 2 == 1 and (words[i] .. ";注" .. i) or words[i]
      end
      extra_dict = { ["okurinasi:てす"] = cands }
      local saved = opts.config
      opts.config = vim.tbl_extend("force", saved or {}, { showCandidatesCount = C, selectCandidateKeys = K })
      local run = new_run("")
      local shown
      local orig_show = host.show_candidates
      host.show_candidates = function(lines)
        shown = lines
      end
      local trace = {}
      local function go(key)
        trace[#trace + 1] = key
        shown = nil
        return step(run, key)
      end
      local ok = true
      for _, k in ipairs({ "T", "e", "s", "u", "<space>" }) do
        ok = go(k) == nil and ok
      end
      local p = 0
      local committed_word
      local ops = {}
      for _ = 1, math.random(1, 10) do
        local r = math.random(10)
        ops[#ops + 1] = r <= 5 and "<space>" or r <= 7 and "x" or keys7[math.random(7)]
      end
      for _, op in ipairs(ops) do
        if not ok or committed_word then
          break
        end
        local want_p, shown_expected = p, false
        if op == "<space>" then
          want_p = p >= C and p + 7 or p + 1
          if want_p >= n then
            want_p = p -- 使い切ったら登録の欄（取り消し）で、番号は変わらない
          end
          shown_expected = want_p >= C and want_p ~= p
        elseif op == "x" then
          want_p = p >= C and math.max(p - 7, C - 1) or p - 1
          shown_expected = want_p >= C
        elseif p >= C then
          local idx = p + (vim.fn.stridx(K, op)) -- 選択キーの 0 始まりの位置
          if idx < n then
            committed_word = words[idx + 1]
          else
            shown_expected = true -- 候補が足りないキーは、何も確定せず一覧を出し直す
          end
        else
          -- 一覧が出ていないとき、選択キーは普通のキー（今の候補を確定して打ち込まれる）。この検査では扱わない
          break
        end
        local msg = go(op)
        if msg then
          fail("M14 候補の選択", concat(trace), msg)
          ok = false
          break
        end
        local st = run.ctx.state
        if committed_word then
          if not (run.line:sub(1, #committed_word) == committed_word) then
            fail(
              "M14 候補の選択",
              concat(trace),
              ("showCandidatesCount=%d キー %s、候補 %d 個、番号 %d から %s で %q が確定するはずが、行は %q"):format(
                C,
                K,
                n,
                p,
                op,
                committed_word,
                run.line
              )
            )
          end
        elseif want_p < 0 then
          if st.type ~= "input" then
            fail("M14 候補の選択", concat(trace), ("x で ▽ に戻るはずが状態は %s"):format(st.type))
          end
          ok = false -- ▽ に戻ったので、ここで終わり
        elseif st.type ~= "henkan" or st.candidate_index ~= want_p then
          fail(
            "M14 候補の選択",
            concat(trace),
            ("showCandidatesCount=%d 候補 %d 個、%s のあとの番号は %s（期待 %d）"):format(
              C,
              n,
              op,
              st.type == "henkan" and st.candidate_index or st.type,
              want_p
            )
          )
          ok = false
        else
          if want_p >= C and (shown_expected or op ~= "<space>") then
            local want_lines = {}
            for i = 0, 6 do
              if want_p + i >= n then
                break
              end
              want_lines[#want_lines + 1] = ("%s: %s"):format(keys7[i + 1], words[want_p + i + 1])
            end
            -- 注釈つきの候補は、一覧に出る語から注釈を除いた形（候補の表示は注釈を別に持つ）
            if shown ~= nil and not vim.deep_equal(shown, want_lines) then
              fail(
                "M14 候補の一覧",
                concat(trace),
                ("番号 %d の一覧が %s（期待 %s）"):format(want_p, vim.inspect(shown), vim.inspect(want_lines))
              )
            elseif shown == nil and shown_expected then
              fail("M14 候補の一覧", concat(trace), ("番号 %d で一覧が出ていない"):format(want_p))
            end
          end
        end
        p = want_p
      end
      host.show_candidates = orig_show
      opts.config = saved
      extra_dict = {}
    end
    -- M7: 送り仮名。大文字の子音で送りが始まり、続く母音で送り仮名が決まる。
    -- 子音を重ねると「っ」が先に付く（NoTte = 乗って）。送りありの辞書の見出し（わるk など）で引く
    do
      local E = {
        { head = { "W", "a", "r", "u" }, c = "k", cand = "悪" },
        { head = { "N", "o" }, c = "t", cand = "乗" },
        { head = { "K", "a", "e" }, c = "r", cand = "帰" },
        { head = { "K", "a" }, c = "k", cand = "書" },
      }
      local KANA = {
        k = { a = "か", i = "き", u = "く", e = "け", o = "こ" },
        t = { a = "た", i = "ち", u = "つ", e = "て", o = "と" },
        r = { a = "ら", i = "り", u = "る", e = "れ", o = "ろ" },
      }
      local e = E[math.random(#E)]
      local v = ({ "a", "i", "u", "e", "o" })[math.random(5)]
      local sokuon = math.random(2) == 1
      local keys = { "=" }
      vim.list_extend(keys, e.head)
      keys[#keys + 1] = e.c:upper()
      if sokuon then
        keys[#keys + 1] = e.c
      end
      keys[#keys + 1] = v
      keys[#keys + 1] = "<c-j>"
      local o_run, oerr = line_of(keys)
      local want = e.cand .. (sokuon and "っ" or "") .. KANA[e.c][v]
      if not oerr and o_run.line ~= want then
        fail("M7 送り仮名", keys, ("得た %q、期待 %q"):format(o_run.line, want))
      end
    end
    -- M8: abbrev（/）。入れた文字はローマ字に変えずそのまま読みになり、<C-j> で確定すると文字のまま入って、
    -- ひらがなのモードに戻る。<C-g> で抜けると何も入らずひらがなのモードに戻る
    do
      local w = {}
      for _ = 1, math.random(1, 6) do
        w[#w + 1] = ({ "a", "b", "k", "n", "z", "1", "-", "w" })[math.random(8)]
      end
      local ws = table.concat(w)
      local k_commit = concat({ "/" }, w, { "<c-j>", "a" })
      local r1 = line_of(k_commit)
      if r1.line ~= ws .. "あ" then
        fail("M8 abbrev の確定", k_commit, ("得た %q、期待 %q"):format(r1.line, ws .. "あ"))
      end
      local k_exit = concat({ "/" }, w, { "<c-g>", "a" })
      local r2 = line_of(k_exit)
      if r2.line ~= "あ" or r2.ctx.mode ~= "hira" then
        fail(
          "M8 abbrev を <C-g> で抜ける",
          k_exit,
          ('得た %q（モード %s）、期待 "あ"'):format(r2.line, r2.ctx.mode)
        )
      end
      local k_conv = { "=", "/", "a", "b", "c", "<space>", "<c-j>", "a" }
      local r3 = line_of(k_conv)
      if r3.line ~= "ＡＢＣあ" then
        fail("M8 abbrev の変換", k_conv, ("得た %q、期待 %q"):format(r3.line, "ＡＢＣあ"))
      end
    end
    -- M9: 接頭辞・接尾辞。し> を引くと「新」、>てき（henkanPoint のあと）を引くと「的」
    do
      local k_pre = { "=", "S", "h", "i", ">", "<c-j>" }
      local r1 = line_of(k_pre)
      if r1.line ~= "新" then
        fail("M9 接頭辞", k_pre, ('得た %q、期待 "新"'):format(r1.line))
      end
      local k_suf = { "=", ";", ">", "t", "e", "k", "i", "<space>", "<c-j>" }
      local r2 = line_of(k_suf)
      if r2.line ~= "的" then
        fail("M9 接尾辞", k_suf, ('得た %q、期待 "的"'):format(r2.line))
      end
    end
    -- M10: 削除（X）と再登録。1 つしかない候補を削除すると辞書から消え、同じ読みを引くと登録の欄になる。
    -- そこで答えた語（w）は先頭の候補になり、確定した行にも入る。もう一度引くと w が出る
    do
      local w = ({ "語", "中", "仲", "名" })[math.random(4)]
      local nak = { "N", "a", "k", "a" }
      local k = concat(nak, { "<space>", "X" }, nak, { "<space>" })
      k[1] = "=" .. w
      local r1, e1 = line_of(k)
      local k2 = vim.list_slice(k)
      vim.list_extend(k2, nak)
      vim.list_extend(k2, { "<space>" })
      local r2 = line_of(k2)
      local data = r1.lib.data["okurinasi:なか"] or {}
      if not e1 and (r1.line ~= w or data[1] ~= w or (w ~= "中" and vim.tbl_contains(data, "中"))) then
        fail(
          "M10 削除と再登録",
          k,
          ("行 %q、辞書 %s（行も辞書の先頭も %q のはず）"):format(r1.line, vim.inspect(data), w)
        )
      elseif not e1 and r2.ctx:to_string() ~= "▼" .. w then
        fail("M10 再登録した語が出ない", k2, ("得た %q、期待 %q"):format(r2.ctx:to_string(), "▼" .. w))
      end
    end
    -- M11: 入れ子の辞書登録。登録の入力欄の中で、辞書に無い読みを変換すると、もう一段の登録の入力欄になる。
    -- 内側の語 wi を答え、入力欄の続きに「あ」を打って外側の語 wi.."あ" を登録すると、
    -- 辞書には内側の読み -> wi、外側の読み -> wi.."あ" の両方が入り、バッファには外側の語だけが残る（マーカーは残らない）
    do
      local READ = {
        { { "H", "a" }, "は" },
        { { "M", "e" }, "め" },
        { { "S", "e" }, "せ" },
        { { "Y", "u" }, "ゆ" },
        { { "Z", "a" }, "ざ" },
      }
      local WORDS = { "内", "外", "葉", "目", "湯" }
      local o = READ[math.random(#READ)]
      local i = READ[math.random(#READ)]
      if o[2] ~= i[2] then
        local wi = WORDS[math.random(#WORDS)]
        local inner_keys = vim.list_slice(i[1])
        vim.list_extend(inner_keys, { "<space>", "a" })
        local keys = vim.list_slice(o[1])
        keys[#keys + 1] = "<space>"
        local run = new_run("")
        register_queue = { inner_keys, wi }
        local nerr
        for idx, key in ipairs(keys) do
          nerr = step(run, key)
          if nerr then
            nerr = ("%d キー目: %s"):format(idx, nerr)
            break
          end
        end
        local full = { "=" }
        vim.list_extend(full, keys)
        local out = wi .. "あ"
        local od = run.lib.data["okurinasi:" .. o[2]] or {}
        local id = run.lib.data["okurinasi:" .. i[2]] or {}
        if nerr then
          fail("M11 入れ子の登録（違反）", full, nerr)
        elseif od[1] ~= out or id[1] ~= wi then
          fail(
            "M11 入れ子の登録が辞書に入らない",
            full,
            ("%s -> %s、%s -> %s（外側 %q、内側 %q のはず）"):format(
              o[2],
              vim.inspect(od),
              i[2],
              vim.inspect(id),
              out,
              wi
            )
          )
        elseif run.line ~= out or run.ctx:to_string() ~= "" then
          fail(
            "M11 入れ子の登録のあとのバッファ",
            full,
            ("行 %q、pre-edit %q（外側の語 %q だけのはず）"):format(run.line, run.ctx:to_string(), out)
          )
        end
      end
    end
    -- M12: 送り仮名つきの辞書登録。辞書に無い送りありの読み（ひk に送り仮名）を変換して語 w を登録すると、
    -- 行には w と送り仮名が入り、辞書の送りありの見出し（ひk）の先頭に w が入る。同じ読みをもう一度変換すると w が先頭に出る
    do
      local HEAD = { { { "H", "i" }, "ひ" }, { { "M", "i" }, "み" }, { { "S", "a" }, "さ" } }
      local OK = {
        k = { a = "か", i = "き", u = "く", e = "け", o = "こ" },
        r = { a = "ら", i = "り", u = "る", e = "れ", o = "ろ" },
        t = { a = "た", i = "ち", u = "つ", e = "て", o = "と" },
      }
      local h = HEAD[math.random(#HEAD)]
      local c = ({ "k", "r", "t" })[math.random(3)]
      local v = ({ "a", "i", "u", "e", "o" })[math.random(5)]
      local w = ({ "見", "引", "差", "日" })[math.random(4)]
      local conv = vim.list_slice(h[1])
      -- 送りの母音を打った時点で変換が始まる（<Space> は要らない）
      vim.list_extend(conv, { c:upper(), v })
      local k1 = { "=" .. w }
      vim.list_extend(k1, conv)
      local r1, e1 = line_of(k1)
      local key = "okuriari:" .. h[2] .. c
      local d = r1.lib.data[key] or {}
      local want = w .. OK[c][v]
      if not e1 and (r1.line ~= want or d[1] ~= w) then
        fail(
          "M12 送り仮名つきの登録",
          k1,
          ("行 %q（期待 %q）、%s -> %s（先頭が %q のはず）"):format(r1.line, want, key, vim.inspect(d), w)
        )
      elseif not e1 then
        -- 2 回目も答えは w のままなので、w が先頭に出なければ、また登録の欄になって「▼w」でなく確定した状態になる
        local k2 = vim.list_slice(k1)
        vim.list_extend(k2, conv)
        local r2 = line_of(k2)
        if r2.ctx:to_string() ~= "▼" .. want then
          fail(
            "M12 送り仮名つきで登録した語が出ない",
            k2,
            ("得た %q、期待 %q"):format(r2.ctx:to_string(), "▼" .. want)
          )
        end
      end
    end
    -- M16: 送り仮名の端のケース。読み R（ひらがな）を大文字で始めて打ち、そのあとに「打ちかけの子音 p」（なくてもよい）と
    -- 大文字で始まる送り仮名 O を打つ。期待する結果は、次の規則だけで書いた独立の表（okuri_model）で決める。
    --   1. 送りありの辞書の見出しは「読み + 送りの子音」。子音は送り仮名の最初の「っ以外の仮名」の行で決まる
    --      （る は r、って は て の t、んだ は ん の n、ぁ は x）。送り仮名が「っ」だけのときは t とみなす。
    --      upstream の okuri.ts の getOkuriStr と同じ。例: SiNda は しn、KiTte は きt、TuKka は つk、KaXtu は かt
    --   2. 打ちかけの子音 p が、大文字の子音と同じなら、p は読みに入って促音「っ」になる（n なら「ん」）。
    --      n が違う子音の前に残っていたら「ん」になる（KanKa）。t・k・s が違う子音の前に残っていたら捨てられる（KakTa）
    --   3. 打ちかけの t・k・s のあとの大文字の母音は、子音と母音で 1 つの仮名になる（KatA は た）
    --   4. 送り仮名の打ちかけがなくなった時点（仮名が全部できた）で、辞書を引いて ▼ になる。N だけのときは <Space> で ん になる
    -- 辞書には期待する見出し 1 つだけを置くので、見出しの子音か読みがずれると、▼ にならずに辞書登録の欄になる
    do
      local READ = {
        { "Ka", "か" },
        { "Si", "し" },
        { "Ha", "は" },
        { "Ki", "き" },
        { "Tu", "つ" },
        { "Mi", "み" },
      }
      -- { 打つキー, 送り仮名, 打ちかけの子音と同じ子音で始まらない（p を前に置ける） , 末尾に <Space> が要るか }
      local UNIT = {
        { "Ru", "る" },
        { "Ki", "き" },
        { "Ta", "た" },
        { "Shi", "し" },
        { "Tsu", "つ" },
        { "Cha", "ちゃ" },
        { "Kya", "きゃ" },
        { "Nu", "ぬ" },
        { "Nn", "ん" },
        { "Nda", "んだ" },
        { "Tte", "って" },
        { "Kka", "っか" },
        { "Sshi", "っし" },
        { "Xa", "ぁ" },
        { "Xya", "ゃ" },
        { "Xtu", "っ" },
        { "Xtsu", "っ" },
        { "N", "ん", true },
        { "A", "あ" },
        { "I", "い" },
      }
      local ROW = {
        ["る"] = "r",
        ["き"] = "k",
        ["か"] = "k",
        ["た"] = "t",
        ["し"] = "s",
        ["さ"] = "s",
        ["つ"] = "t",
        ["ち"] = "t",
        ["ぬ"] = "n",
        ["ん"] = "n",
        ["て"] = "t",
        ["あ"] = "a",
        ["い"] = "i",
        ["ぁ"] = "x",
        ["ゃ"] = "x",
      }
      local function okuri_row(okuri)
        if okuri == "っ" then
          return "t"
        end
        for _, ch in ipairs(vim.fn.split(okuri, "\\zs")) do
          if ch ~= "っ" then
            return ROW[ch]
          end
        end
      end
      local rd = READ[math.random(#READ)]
      local u = UNIT[math.random(#UNIT)]
      local lead = u[1]:sub(1, 1):lower()
      local vowel_start = lead:match("[aiueo]") ~= nil
      -- 打ちかけの子音（母音で始まる送り仮名の前には t・k・s だけ。ん の前の n は規則 2 の場合だけ）
      local p = ""
      local roll = math.random(1, 4)
      if roll == 1 then
        p = ({ "t", "k", "s", "n" })[math.random(4)]
      end
      local reading, okuri_typed, okuri = rd[2], u[1], u[2]
      local skip = false
      if p ~= "" then
        if vowel_start then
          -- 規則 3。母音は あ・い のうち a だけを使う（ta・ka・sa）。n は na で「な」になる経路が別なので使わない
          if p == "n" or u[1] ~= "A" then
            skip = true
          else
            okuri = ({ t = "た", k = "か", s = "さ" })[p]
          end
        elseif u[1]:sub(2, 2):lower() == lead then
          skip = true -- Tte・Kka・Sshi は二重子音の組み立てが変わるので、p は付けない
        elseif p == lead then
          reading = reading .. (p == "n" and "ん" or "っ")
        elseif p == "n" then
          reading = reading .. "ん"
        elseif not ("trkn"):find(lead, 1, true) then
          -- ts・sh・ky のように、p と合わせて 1 つのローマ字の頭になる組は、別の経路（打ちかけがつながる）なので避ける
          skip = true
        end -- 違う子音の t・k・s は捨てられる（読みはそのまま）
      end
      if not skip then
        local key = reading .. okuri_row(okuri)
        extra_dict = { ["okuriari:" .. key] = { "語" } }
        local keys = { "=" }
        for ch in (rd[1] .. p .. okuri_typed):gmatch(".") do
          keys[#keys + 1] = ch
        end
        if u[3] then
          keys[#keys + 1] = "<space>"
        end
        local want = "▼語" .. okuri
        local r = line_of(keys)
        if r.ctx:to_string() ~= want then
          fail("M16 送り仮名", keys, ("見出し %s で %q、期待 %q"):format(key, r.ctx:to_string(), want))
        end
        extra_dict = {}
      end
    end
    checked = checked + 1
  end
  print(("metamorphic: %d 組、%.1f 秒"):format(checked, (vim.uv.hrtime() - t0) / 1e9))
  if vim.tbl_isempty(found) then
    print("✓ 違反なし")
    vim.cmd("qall!")
  end
  local failed = false
  for _, f in pairs(found) do
    -- M13 の #49（(concat "\073") の語の ; が注釈の区切りになる）は直ったので、既知の扱いをやめた
    failed = true
    print(("\n✗ 反例（%d キー）: %s\n    %s"):format(#f.keys, fmt(f.keys), f.msg))
  end
  vim.cmd(failed and "cquit 1" or "qall!")
end

local answers = { "=", "=語" }
if opts.random then
  math.randomseed(opts.seed)
  for _ = 1, opts.random do
    local ks = { answers[math.random(#answers)] }
    for _ = 1, opts.length do
      ks[#ks + 1] = ALPHABET[math.random(#ALPHABET)]
    end
    local _, at, msg = run_keys(ks)
    if at then
      record(ks, at, msg)
    end
  end
  print(("random: %d 本 × %d キー、%.1f 秒"):format(opts.random, opts.length, (vim.uv.hrtime() - t0) / 1e9))
else
  local visited = {}
  local frontier = {}
  for _, a in ipairs(answers) do
    frontier[#frontier + 1] = { a }
  end
  local transitions = 0
  for depth = 1, opts.depth do
    local next_frontier = {}
    for _, path in ipairs(frontier) do
      for _, key in ipairs(ALPHABET) do
        local ks = vim.list_extend(vim.list_slice(path), { key })
        transitions = transitions + 1
        local run, at, msg = run_keys(ks)
        if at then
          record(ks, at, msg)
        else
          local a = path[1] .. "|" .. abstract(run)
          if not visited[a] then
            visited[a] = true
            next_frontier[#next_frontier + 1] = ks
          end
        end
      end
    end
    frontier = next_frontier
    print(
      ("depth %d: 新しい抽象状態 %d（計 %d）、%.1f 秒"):format(
        depth,
        #next_frontier,
        vim.tbl_count(visited),
        (vim.uv.hrtime() - t0) / 1e9
      )
    )
    if #frontier == 0 or vim.tbl_count(visited) >= opts.max_states then
      break
    end
  end
  print(("計 %d 遷移、%d 抽象状態"):format(transitions, vim.tbl_count(visited)))
end

if vim.tbl_isempty(found) then
  print("✓ 違反なし")
  vim.cmd("qall!")
end
-- 見つかったが、まだ直っていないもの
local function known(f)
  if f.msg:find("0 個増えた", 1, true) and vim.tbl_contains(f.keys, "L") then
    return 40 -- 全英のモードで <C-q> を押すと、モードはひらがなになるのに全角の文字が入る
  end
  if f.msg:find("2 個増えた", 1, true) and opts.kanatable then
    return 41 -- かなテーブルで henkanFirst を割り当てたキーのあとの記号が 2 つ入る
  end
  -- #42・#43（かなテーブルやキーマップを変えたときの変換のキーの扱い）は直った。今の性質では違反にならない
  -- （再現は issue の --keys の手順で確かめる）
end
local failed = false
for _, f in pairs(found) do
  local k = known(f)
  if k then
    print(("\n△ 既知 #%d: %s"):format(k, fmt(f.keys)))
  else
    failed = true
    print(("\n✗ 反例（%d キー）: %s\n    %s"):format(#f.keys, fmt(f.keys), f.msg))
  end
end
if not failed then
  print("\n✓ 既知のもの以外に違反なし")
end
vim.cmd(failed and "cquit 1" or "qall!")

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
    elseif k == "--metamorphic" then
      opts.metamorphic, i = tonumber(v), i + 1
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
}

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
host.input = function()
  events[#events + 1] = "input"
  return register_answer
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
  lib.data = vim.deepcopy(DICT)
  store.set_library(lib)
  kana.set_current("rom")
  local ctx = store.init_context()
  ctx.vim_mode = "c"
  register_answer = answer
  events = {}
  return { ctx = ctx, line = "", committed = "" }
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
    if committed:find(m, 1, true) then
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
    if not vim.startswith(pre, config.options.markerHenkanSelect) then
      return ("▼ の状態なのに pre-edit %q"):format(pre)
    end
  elseif st.type == "input" then
    local marked = vim.startswith(pre, config.options.markerHenkan)
    local want = st.mode == "okurinasi" or st.mode == "okuriari"
    if marked ~= want then
      return ("状態 %s なのに pre-edit %q"):format(st.mode, pre)
    end
  end
  run.committed = committed
end

-- 1 キー流して確かめる。違反なら説明を返す
local function step(run, key)
  local prev_committed = run.committed
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
    run.ctx = store.init_context()
    run.ctx.vim_mode = "c"
    run.committed = run.line
    return nil
  end
  local out = run.ctx.preedit:output(run.ctx:to_string())
  run.line = apply(run.line, out)
  return check_state(run, key, prev_committed)
end

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
    checked = checked + 1
  end
  print(("metamorphic: %d 組、%.1f 秒"):format(checked, (vim.uv.hrtime() - t0) / 1e9))
  if vim.tbl_isempty(found) then
    print("✓ 違反なし")
    vim.cmd("qall!")
  end
  for _, f in pairs(found) do
    print(("\n✗ 反例（%d キー）: %s\n    %s"):format(#f.keys, fmt(f.keys), f.msg))
  end
  vim.cmd("cquit 1")
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
for _, f in pairs(found) do
  print(("\n✗ 反例（%d キー）: %s\n    %s"):format(#f.keys, fmt(f.keys), f.msg))
end
vim.cmd("cquit 1")

-- SKK の入力エンジン（core）の参照モデル（#260、親は #179）
--
-- 素の Lua 5.1（LuaJIT）。vim.* も require("skkeleton...") も使わない。
-- 分岐ごとに rules.lua の id を書き、通った規則を out.rules に積む。
-- status = "current" の規則は今の動きのまま、"undefined" の規則は推奨の動きで書いてある
-- （R-CK-14、R-RG-08、R-EN-09。R-RG-09 は step の外の話なので、ここには出てこない）。
--
--   M.initial(C)                      -> σ      有効にした直後（読みなし、ひらがな）
--   M.step(C, D, oracle, σ, key)      -> σ', out
--   M.observe(σ)                      -> { phase, henkanFeed, preedit, mode }
--   M.keys                            検証で流すキーの有限集合
--   M.config(overrides)               -> C      既定の設定
--   M.tables                          かなテーブルの小さな部分集合（検証では実装にも同じものを入れる）
--
-- C      設定（core に効くものだけ）
-- D      辞書。{ ["okurinasi:かき"] = { "柿", ... }, ["okuriari:かk"] = { "書" } }。step は D を書き換えない。
--        覚えた語は σ.user に持つ（tests/core_helpers.lua の FakeLibrary と同じ並び：覚えた語が先頭）
-- oracle host の答え。
--          oracle.input(prompt, depth)  -> 語 / nil（取り消し）/ { keys = { ... } }（内側の機械に流すキー列）
--          oracle.confirm(msg)          -> boolean
--          oracle.in_expression()       -> boolean（省略可。<C-r>= の式の中か）
-- key    正規化したキーの表記（"a"、"K"、"<space>"、"<nl>" = <C-j>、"<cr>"、"<bs>"、"<c-g>"、"<esc>"、"<c-q>"）
--        と、キーでない入力 "@enable" / "@disable"
-- out    { commit = 確定した文字列（"\b" は 1 文字消す、"\n" は改行）, calls = host への呼び出し, rules = 通った規則 }

local M = {}

------------------------------------------------------------------------
-- 設定とかなテーブル
------------------------------------------------------------------------
function M.config(overrides)
  local C = {
    acceptIllegalResult = false,
    eggLikeNewline = false,
    immediatelyCancel = true,
    immediatelyOkuriConvert = true,
    kanaTable = "rom",
    keepMode = false,
    keepState = false,
    lowercaseMap = {},
    markerHenkan = "▽",
    markerHenkanSelect = "▼",
    registerConvertResult = false,
    selectCandidateKeys = "asdfjkl",
    showCandidatesCount = 4,
  }
  for k, v in pairs(overrides or {}) do
    C[k] = v
  end
  return C
end

-- 実装のテーブルの小さな部分集合。全部のテーブルとの違いは CORE.md の §3
M.tables = {
  rom = {
    kana_functions = true,
    entries = {
      a = { "あ", "" },
      i = { "い", "" },
      u = { "う", "" },
      e = { "え", "" },
      o = { "お", "" },
      ka = { "か", "" },
      ki = { "き", "" },
      sa = { "さ", "" },
      si = { "し", "" },
      n = { "ん", "" },
      nn = { "ん", "" },
      xtu = { "っ", "" },
      tt = { "っ", "t" },
    },
  },
  zen = {
    entries = {
      a = { "ａ", "" },
      i = { "ｉ", "" },
      k = { "ｋ", "" },
      s = { "ｓ", "" },
      n = { "ｎ", "" },
      t = { "ｔ", "" },
      x = { "ｘ", "" },
      l = { "ｌ", "" },
      q = { "ｑ", "" },
      [">"] = { "＞", "" },
      ["<s-a>"] = { "Ａ", "" },
      ["<s-n>"] = { "Ｎ", "" },
      ["<s-k>"] = { "Ｋ", "" },
      ["<s-s>"] = { "Ｓ", "" },
      ["<s-l>"] = { "Ｌ", "" },
      ["<s-x>"] = { "Ｘ", "" },
    },
  },
  abbrev = { entries = {} },
}

local KATA = { ["あ"] = "ア", ["い"] = "イ", ["う"] = "ウ", ["え"] = "エ", ["お"] = "オ", ["か"] = "カ", ["き"] = "キ", ["さ"] = "サ", ["し"] = "シ", ["ん"] = "ン", ["っ"] = "ッ" }
local HANKATA = { ["あ"] = "ｱ", ["い"] = "ｲ", ["う"] = "ｳ", ["え"] = "ｴ", ["お"] = "ｵ", ["か"] = "ｶ", ["き"] = "ｷ", ["さ"] = "ｻ", ["し"] = "ｼ", ["ん"] = "ﾝ", ["っ"] = "ｯ" }
-- 送りの最初のかな -> 辞書の見出しに付ける子音（okuri.lua の部分集合）
local OKURI = { ["あ"] = "a", ["い"] = "i", ["う"] = "u", ["え"] = "e", ["お"] = "o", ["か"] = "k", ["き"] = "k", ["さ"] = "s", ["し"] = "s", ["ん"] = "n", ["っ"] = "x" }

M.keys = {
  "a", "i", "k", "s", "n", "t", "x", "z", -- z はテーブルに無い文字
  "K", "S", "A", "N", "X",
  "l", "q", ";", "/", "L",
  "<space>", ">", "<c-q>", "<bs>", "<c-g>", "<nl>", "<cr>", "<esc>",
  "@enable", "@disable",
}

local CHAR = { ["<space>"] = " ", ["<nl>"] = "\n", ["<cr>"] = "\r", ["<bs>"] = "\b", ["<esc>"] = "\27", ["<c-g>"] = "\7", ["<c-q>"] = "\17" }
local NOTATION = {}
for k, v in pairs(CHAR) do
  NOTATION[v] = k
end

------------------------------------------------------------------------
-- 小さな道具
------------------------------------------------------------------------
local function chars(s)
  local t = {}
  for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    t[#t + 1] = c
  end
  return t
end

local function last_char(s)
  local t = chars(s)
  return t[#t] or ""
end

local function drop_last_char(s)
  local t = chars(s)
  t[#t] = nil
  return table.concat(t)
end

local function copy(v)
  if type(v) ~= "table" then
    return v
  end
  local t = {}
  for k, x in pairs(v) do
    t[k] = copy(x)
  end
  return t
end

local function convert_with(name, s)
  local map = name == "kata" and KATA or name == "hankata" and HANKATA or nil
  if not map then
    return s
  end
  local t = chars(s)
  for i, c in ipairs(t) do
    t[i] = map[c] or c
  end
  return table.concat(t)
end

local function conv(s, str)
  return convert_with(s.conv, str)
end

local function tbl(s)
  return M.tables[s.table]
end

-- 前方一致の件数と、完全一致の結果（kana/init.lua の KanaTable:node）
local function node(t, prefix)
  local count, n = 0, #prefix
  for from in pairs(t.entries) do
    if from:sub(1, n) == prefix then
      count = count + 1
    end
  end
  if count == 0 then
    return nil
  end
  return { count = count, result = t.entries[prefix] }
end

-- 注釈と、接頭辞・接尾辞の > を落とす（candidate.lua の modify）
local function modify(cand, affix)
  if cand == nil then
    return nil
  end
  local strip = cand:gsub(";.*", "")
  if affix == "prefix" then
    strip = strip:gsub(">$", "")
  elseif affix == "suffix" then
    strip = strip:gsub("^>", "")
  end
  return strip
end

local function okuri_str(word, okuri)
  if okuri == "っ" then
    return word .. "t"
  end
  local first
  for _, ch in ipairs(chars(okuri)) do
    if ch ~= "っ" then
      first = ch
      break
    end
  end
  return word .. (OKURI[first or ""] or "")
end

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------
local function initialize(s, ignore) -- state.lua の initialize
  local kept = {}
  for _, k in ipairs(ignore or {}) do
    kept[k] = s[k]
  end
  s.type, s.imode, s.affix, s.direct_input = "input", "direct", nil, false
  s.table, s.conv = s.g.current, nil
  s.feed, s.hf, s.of, s.prev = "", "", "", false
  for k, v in pairs(kept) do
    s[k] = v
  end
  s.word, s.cands, s.idx = nil, nil, nil
  return s
end

-- 新しい Context。g（機械の外にある値）と user（覚えた語）は呼ぶ側のものを使う
local function new_context(g, user)
  local s = { enabled = true, mode = "hira", g = g, user = user, last = { type = "okurinasi", word = "", candidate = "" } }
  return initialize(s)
end

function M.initial(C)
  return new_context({ current = (C or M.config()).kanaTable, last_mode = "hira" }, {})
end

-- 使う人の言葉の状態（rules.lua の states の id）
local function stage(C, s)
  if not s.enabled or s.type == "escape" then
    return "off"
  elseif s.type == "henkan" then
    return s.idx >= C.showCandidatesCount and "list" or "sel"
  elseif s.imode == "direct" then
    return s.feed == "" and "direct" or "pending"
  elseif s.imode == "okurinasi" then
    return s.feed ~= "" and "prep" or s.hf == "" and "pre0" or "pre"
  end
  return s.feed == "" and "oku" or "okup"
end
M.stage = stage

local function rule(X, id)
  X.out.rules[#X.out.rules + 1] = id
end

local function emit(X, str)
  X.out.commit = X.out.commit .. str
end

local function call(X, name, arg)
  X.out.calls[#X.out.calls + 1] = { name, arg }
end

local function lookup(X, kind, word)
  local key = kind .. ":" .. word
  return copy(X.s.user[key] or X.D[key] or {})
end

local function register(X, kind, word, cand)
  local list = {}
  for _, c in ipairs(lookup(X, kind, word)) do
    if c ~= cand then
      list[#list + 1] = c
    end
  end
  table.insert(list, 1, cand)
  X.s.user[kind .. ":" .. word] = list
end

local function purge(X, kind, word, cand)
  local list = {}
  for _, c in ipairs(lookup(X, kind, word)) do
    if c ~= cand then
      list[#list + 1] = c
    end
  end
  X.s.user[kind .. ":" .. word] = list
end

local function mode_change(X, mode) -- mode.lua の mode_change
  X.s.mode = mode
  call(X, "mode_changed", mode)
  if X.C.keepMode and mode ~= "abbrev" then
    X.s.g.last_mode = mode
  end
end

local function initialize_with_abbrev(X, ignore) -- mode.lua の initialize_state_with_abbrev
  ignore = ignore or {}
  if X.s.mode == "abbrev" then
    rule(X, "R-MD-10") -- abbrev が終わると、いつも ひらがな に戻る
    mode_change(X, "hira")
    ignore = {}
  end
  initialize(X.s, ignore)
end

-- 相互に呼ぶので先に名前を置く
local kana_input, henkan_first, henkan_forward, kakutei, handle_key, hirakana, register_word

------------------------------------------------------------------------
-- 入力（function/input.lua）
------------------------------------------------------------------------
local function kakutei_kana(X, kana, feed)
  local s = X.s
  if s.imode == "direct" then
    emit(X, conv(s, kana))
  elseif s.imode == "okurinasi" then
    s.hf = s.hf .. kana
  elseif s.imode == "okuriari" then
    if feed ~= "" and s.prev then
      s.hf = s.hf .. kana
    else
      s.of = s.of .. kana
    end
    s.prev = false
  end
  s.feed = feed
end

-- 片付け方 fold：かなになる打ちかけだけ、かなにする
local function kakutei_feed(X)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  local r = tbl(s).entries[s.feed]
  if r then
    kakutei_kana(X, r[1], "")
  end
end

local function accept_result(X, result)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  kakutei_kana(X, result[1], result[2])
  if s.imode == "okuriari" and result[2] == "" then
    if last_char(s.of) == "っ" then
      if X.C.immediatelyOkuriConvert then
        henkan_first(X, "")
      end
    else
      henkan_first(X, "") -- R-OK-01 の「続けて変換」
    end
  end
end

-- 片付け方 flush
local function flush_feed(X)
  local s = X.s
  local cur = tbl(s).entries[s.feed]
  if cur then
    accept_result(X, cur)
  elseif X.C.acceptIllegalResult then
    kakutei_kana(X, s.feed, "")
  else
    s.feed = ""
  end
end

local function henkan_point(X)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  local nd = node(tbl(s), s.feed)
  if s.imode == "okurinasi" and s.hf == "" then
    return -- R-PR-10：読みが空なら送りは始まらない
  end
  if s.imode == "direct" then
    -- R-IN-09 / R-IN-10 / R-MD-06
    if not nd then
      emit(X, s.feed)
      s.feed = ""
    end
    call(X, "undo_point")
    s.imode = "okurinasi"
  elseif s.imode == "okurinasi" then
    -- R-PR-11 / R-PR-12 / R-PR-13 / R-PR-14
    if s.feed == "" or not nd then
      s.feed = ""
    elseif nd.result then
      s.hf = s.hf .. nd.result[1]
      s.feed = ""
    else
      s.prev = true
    end
    s.imode = "okuriari"
  end
  -- okuriari では何もしない（R-OK-06 / R-OK-07）
end

local UPPER = { direct = "R-IN-09", pending = "R-IN-09", pre0 = "R-PR-10", pre = "R-PR-11", prep = "R-PR-13", oku = "R-OK-06", okup = "R-OK-06" }
local EXACT = { direct = "R-IN-01", pending = "R-IN-01", pre0 = "R-PR-01", pre = "R-PR-01", prep = "R-PR-01", oku = "R-OK-01", okup = "R-OK-01" }
local REST = { pending = "R-IN-03", prep = "R-PR-03", okup = "R-OK-03" }
local FEED = { direct = "R-IN-02", pending = "R-IN-02", pre0 = "R-PR-02", pre = "R-PR-02", prep = "R-PR-02", oku = "R-OK-02", okup = "R-OK-02" }
local NOCONT = { pending = "R-IN-04", prep = "R-PR-04", okup = "R-OK-04" }
local RAW = { direct = "R-IN-05", pre0 = "R-PR-05", pre = "R-PR-05", oku = "R-OK-05" }

function kana_input(X, char)
  local s, C = X.s, X.C
  s.type = "input"
  local lower = C.lowercaseMap[char] or char:lower()
  if not s.direct_input and char ~= lower then
    local with_shift = "<s-" .. lower .. ">"
    if node(tbl(s), s.feed .. with_shift) then
      char = with_shift
    else
      local st = stage(C, s)
      rule(X, (st == "prep" and s.hf == "") and "R-PR-10" or UPPER[st])
      henkan_point(X)
      return kana_input(X, lower) -- 小文字で打ち直す
    end
  end

  local st = stage(C, s)
  local special = s.table == "abbrev" and "R-MD-08" or s.table == "zen" and "R-MD-11" or nil
  local nxt = s.feed .. char
  local nd = node(tbl(s), nxt)
  if nd and nd.count == 1 and nd.result then
    rule(X, special or (nd.result[2] == "" and EXACT[st] or REST[st]))
    accept_result(X, nd.result)
  elseif nd then
    rule(X, special or FEED[st])
    s.feed = nxt
  elseif s.feed ~= "" then
    rule(X, special or NOCONT[st])
    flush_feed(X)
    return kana_input(X, char) -- 同じキーを打ち直す
  else
    rule(X, special or RAW[st])
    kakutei_kana(X, char, "")
  end
end

-- l q ; / L の包み（kana_function）
local function kana_function(fn)
  return function(X, char)
    local s = X.s
    local t = tbl(s)
    local key = char:match("^[A-Z]$") and ("<s-" .. char:lower() .. ">") or char
    local before = stage(X.C, s)
    if not t.kana_functions or (s.feed == "" and node(t, key)) then
      return kana_input(X, char)
    end
    if s.feed ~= "" then
      if s.imode == "okuriari" and t.entries[s.feed] then
        rule(X, "R-ST-01") -- ん が送りに入って変換が走る
      end
      flush_feed(X)
    end
    s.type = "input"
    s.feed = ""
    fn(X, char, before)
  end
end

local function delete_char(X)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  if s.feed ~= "" then
    rule(X, s.imode == "direct" and "R-IN-08" or s.imode == "okurinasi" and "R-PR-09" or "R-OK-09")
    s.feed = drop_last_char(s.feed)
    if s.feed == "" then
      s.prev = false
    end
  elseif s.imode == "okuriari" then
    rule(X, "R-OK-08")
    if s.of ~= "" then
      s.of = drop_last_char(s.of)
    else
      s.imode = "okurinasi"
      s.prev = false
    end
  elseif s.imode == "okurinasi" then
    if s.hf ~= "" then
      rule(X, "R-PR-08")
      s.hf = drop_last_char(s.hf)
    else
      rule(X, "R-PR-07")
      initialize_with_abbrev(X, { "conv" })
    end
  else
    rule(X, "R-IN-07")
    emit(X, "\b")
  end
end

local function prefix(X, key)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  if not s.direct_input and s.hf ~= "" and (s.imode == "okurinasi" or s.imode == "okuriari") then
    rule(X, s.imode == "okurinasi" and "R-HK-06" or "R-HK-07")
    kakutei_feed(X)
    accept_result(X, { ">", "" }) -- 送りありでは、ここで 1 度目の変換が走る
    X.s.affix = "prefix"
    henkan_first(X, key)
    return
  end
  -- R-IN-06 / R-PR-06 / R-MD-08：文字として打つ
  if s.imode == "direct" and s.table ~= "zen" then
    rule(X, "R-IN-06")
  elseif s.imode == "okurinasi" and s.table ~= "abbrev" then
    rule(X, "R-PR-06")
  end
  kana_input(X, key)
end

------------------------------------------------------------------------
-- 変換（function/henkan.lua）
------------------------------------------------------------------------
function henkan_first(X, key)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  if s.feed ~= "" and node(tbl(s), s.feed .. key) then
    return kana_input(X, key)
  end
  kakutei_feed(X) -- 片付け方 fold
  if s.imode == "direct" then
    if key ~= "" and s.table ~= "zen" then
      rule(X, "R-IN-06")
    end
    return kana_input(X, key)
  end
  if s.hf == "" then
    rule(X, "R-HK-03") -- 何も起きない。打ちかけは残る
    return
  end
  if s.feed ~= "" then
    rule(X, "R-HK-04") -- 打ちかけを持ったまま変換に入る（今の動き）
  end
  if s.imode == "okuriari" and s.of == "" then
    rule(X, "R-HK-05") -- 空の送りで引く（今の動き）
  end
  s.type = "henkan"
  s.cands = {}
  s.idx = -1
  local word = s.hf
  if s.imode ~= "okurinasi" then
    word = okuri_str(s.hf, s.of)
  end
  s.word = word
  if s.affix == nil and not s.direct_input then
    if s.hf:match(">$") then
      s.affix = "prefix"
    elseif s.hf:match("^>") then
      s.affix = "suffix"
    end
  end
  s.cands = lookup(X, s.imode, word)
  henkan_forward(X)
end

local function show_candidates(X)
  call(X, "show_candidates", X.s.idx)
end

function henkan_forward(X)
  local s, C = X.s, X.C
  if s.type ~= "henkan" then
    return
  end
  local old = s.idx
  if s.idx >= C.showCandidatesCount then
    s.idx = s.idx + 7
  else
    s.idx = s.idx + 1
  end
  if #s.cands <= s.idx then
    if X.oracle.in_expression and X.oracle.in_expression() then
      rule(X, "R-HK-11")
      emit(X, conv(s, s.hf .. s.of))
      call(X, "undo_point")
      initialize_with_abbrev(X, { "conv", "table" })
      return
    end
    rule(X, old == -1 and "R-HK-02" or "R-HK-10")
    if register_word(X) then
      return
    end
    s.idx = old
    if s.idx == -1 then
      rule(X, "R-RG-04")
      s.type = "input"
    else
      rule(X, "R-RG-05")
    end
  else
    rule(X, old == -1 and "R-HK-01" or old >= C.showCandidatesCount and "R-HK-09" or "R-HK-08")
  end
  if s.idx >= C.showCandidatesCount then
    show_candidates(X)
  end
end

local function henkan_backward(X)
  local s, C = X.s, X.C
  if s.type ~= "henkan" then
    return
  end
  if s.idx >= C.showCandidatesCount then
    rule(X, "R-HK-13")
    s.idx = math.max(s.idx - 7, C.showCandidatesCount - 1)
  else
    rule(X, "R-HK-12")
    s.idx = s.idx - 1
  end
  if s.idx < 0 then
    s.type = "input"
    return
  end
  if s.idx >= C.showCandidatesCount then
    show_candidates(X)
  end
end

local function henkan_input(X, key)
  local s, C = X.s, X.C
  if s.idx >= C.showCandidatesCount then
    local pos
    for i, k in ipairs(chars(C.selectCandidateKeys)) do
      if k == key then
        pos = i
        break
      end
    end
    if pos then
      if s.idx + pos - 1 < #s.cands then
        rule(X, "R-HK-14")
        s.idx = s.idx + pos - 1
        kakutei(X)
      else
        rule(X, "R-HK-15")
        show_candidates(X)
      end
      return
    end
  end
  rule(X, key == "\b" and "R-CK-13" or "R-CK-12") -- 暗黙の確定
  kakutei(X)
  handle_key(X, NOTATION[key] or key)
end

local function suffix(X)
  local s = X.s
  if s.type ~= "henkan" then
    return
  end
  rule(X, "R-HK-16")
  kakutei(X)
  henkan_point(X)
  accept_result(X, { ">", "" })
  X.s.affix = "suffix"
end

------------------------------------------------------------------------
-- 辞書登録（function/dictionary.lua と host.input）
------------------------------------------------------------------------
-- 内側の機械にキー列を流して、欄の答えを作る。取り消しなら nil
local function run_inner(X, keys)
  -- R-RG-01：内側は ひらがな の読みなしで始まる。g（今のテーブルの名前、last_mode）と覚えた語は外と共有する
  rule(X, "R-RG-01")
  local inner = new_context(X.s.g, X.s.user)
  local text = ""
  for _, key in ipairs(keys) do
    if key == "<c-g>" or key == "<esc>" then
      rule(X, "R-RG-06") -- host が欄の <C-g> <Esc> を、登録の取り消しに割り当てている（今の動き）
      return nil
    end
    local IX = { C = X.C, D = X.D, oracle = X.oracle, s = inner, out = { commit = "", calls = {}, rules = {} }, depth = X.depth + 1 }
    if not inner.enabled then
      -- R-RG-08（未定義。推奨の動き）：内側だけ無効。キーはそのまま欄に入る
      rule(X, "R-RG-08")
      IX.out.commit = key == "<cr>" and "\n" or (CHAR[key] or key)
    else
      rule(X, "R-RG-02")
      handle_key(IX, key)
    end
    for _, c in ipairs(chars(IX.out.commit)) do
      if c == "\n" then
        return text ~= "" and text or nil
      elseif c == "\b" then
        text = drop_last_char(text)
      else
        text = text .. c
      end
    end
  end
  return nil -- 欄を閉じるキーが無ければ、取り消しとして扱う
end

function register_word(X)
  local s = X.s
  local prompt = "[辞書登録] " .. s.hf .. (s.imode == "okuriari" and ("*" .. s.of) or "") .. ": "
  call(X, "input", prompt)
  local ok, ans = pcall(X.oracle.input, prompt, X.depth)
  if not ok then
    return false -- 中断は取り消しと同じ（R-RG-04 / R-RG-05）
  end
  if type(ans) == "table" then
    ans = run_inner(X, ans.keys or {})
  end
  if ans == nil or ans == "" then
    return false
  end
  rule(X, "R-RG-03")
  s.cands = { ans }
  s.idx = 0
  kakutei(X)
  return true
end

------------------------------------------------------------------------
-- 確定と取り消し（function/common.lua）
------------------------------------------------------------------------
function kakutei(X)
  local s = X.s
  if s.type == "henkan" then
    local cand = s.cands[s.idx + 1]
    if cand and cand ~= "" then
      register(X, s.imode, s.word, cand)
      s.last = { type = s.imode, word = s.word, candidate = cand }
    end
    if cand then
      emit(X, modify(cand, s.affix) .. conv(s, s.of))
    else
      -- R-CK-14（未定義。推奨の動き）：error ではなく、読み＋送りを確定する
      rule(X, "R-CK-14")
      emit(X, conv(s, s.hf .. s.of))
    end
    call(X, "undo_point")
  elseif s.type == "input" then
    kakutei_feed(X)
    emit(X, conv(s, s.hf .. s.of .. s.feed)) -- 片付け方 raw
  end
  initialize_with_abbrev(X, { "conv", "table" })
end

local function kakutei_key(X)
  local s = X.s
  if s.type == "input" and s.imode == "direct" and s.feed == "" then
    rule(X, "R-CK-05")
    hirakana(X)
    return
  end
  rule(X, s.type == "henkan" and "R-CK-08" or s.imode == "direct" and "R-CK-06" or "R-CK-07")
  kakutei(X)
end

local function newline(X)
  local s = X.s
  local in_reading = s.type == "henkan" or (s.type == "input" and s.imode ~= "direct")
  rule(X, s.type == "henkan" and "R-CK-11" or s.imode == "direct" and "R-CK-09" or "R-CK-10")
  kakutei(X)
  if not (X.C.eggLikeNewline and in_reading) then
    emit(X, "\n")
  end
end

local function cancel(X)
  local s = X.s
  -- cmdline の読みなしで host へ <C-c> を渡す分岐は、Vim のモードの話なので入れていない
  if X.C.immediatelyCancel then
    rule(X, s.type == "henkan" and "R-CK-03" or s.imode == "direct" and "R-CK-01" or "R-CK-02")
    initialize_with_abbrev(X, { "conv" })
    return
  end
  if s.type == "input" then
    rule(X, s.imode == "direct" and "R-CK-01" or "R-CK-02")
    initialize_with_abbrev(X, { "conv" })
  elseif s.type == "henkan" then
    rule(X, "R-CK-04")
    s.type = "input"
  end
end

local function purge_candidate(X)
  local s = X.s
  local kind, word, cand
  if s.type == "input" then
    kind, word, cand = s.last.type, s.last.word, s.last.candidate
  elseif s.type == "henkan" then
    kind, word, cand = s.imode, s.word, s.cands[s.idx + 1]
  else
    return
  end
  if word == "" or not cand or cand == "" then
    return
  end
  local msg = ("Really purge? %s /%s/"):format(word, cand)
  call(X, "confirm", msg)
  if X.oracle.confirm(msg) then
    rule(X, "R-PG-01") -- converter も消える（今の動き）
    purge(X, kind, word, cand)
    initialize(s)
    s.last.word = ""
  else
    rule(X, "R-PG-02")
  end
end

------------------------------------------------------------------------
-- 無効（function/disable.lua）
------------------------------------------------------------------------
local function disable(X)
  kakutei(X)
  call(X, "disable")
  X.s.enabled = false -- 実装では host が g:skkeleton#enabled に持つ
  initialize(X.s)
end

local function escape(X)
  rule(X, "R-EN-02")
  if X.C.keepState then
    call(X, "keep_state_on_insert_enter")
  end
  disable(X)
  X.s.type = "escape"
  call(X, "pass_key", "<esc>")
end

------------------------------------------------------------------------
-- モード（function/mode.lua）
------------------------------------------------------------------------
local function abbrev(X)
  local s = X.s
  if s.type ~= "input" or s.imode ~= "direct" then
    rule(X, "R-MD-07") -- 何も起きない
    return
  end
  rule(X, "R-MD-06")
  henkan_point(X)
  s.table = "abbrev"
  s.direct_input = true
  mode_change(X, "abbrev")
end

function hirakana(X)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  if s.imode ~= "direct" then
    kakutei(X)
  end
  s.g.current = X.C.kanaTable
  initialize(s)
  mode_change(X, "hira")
end

local function to_converter_mode(X, name)
  local s = X.s
  if s.type ~= "input" or s.mode == "abbrev" then
    rule(X, "R-MD-09")
    return
  end
  local active = s.conv ~= nil and (name == "kata" or s.conv == name)
  if s.imode ~= "direct" then
    -- R-MD-03：読み＋送りを逆のかなで確定する。打ちかけの子音は消える
    rule(X, "R-MD-03")
    kakutei_feed(X)
    local kana_str = s.hf .. s.of
    local result = kana_str
    if not active then
      result = convert_with(name, result)
      if X.C.registerConvertResult then
        register(X, "okurinasi", kana_str, result)
        s.last = { type = "okurinasi", word = kana_str, candidate = result }
      end
    end
    emit(X, result)
    call(X, "undo_point")
    initialize(s, { "conv" })
    return
  end
  rule(X, name == "kata" and "R-MD-01" or "R-MD-02")
  if s.g.current == "zen" then
    s.g.current = X.C.kanaTable
    s.table = s.g.current
  end
  if active then
    s.conv = nil
    mode_change(X, "hira")
  else
    s.conv = name
    mode_change(X, name)
  end
end

local function katakana(X)
  to_converter_mode(X, "kata")
end

local function hankatakana(X)
  to_converter_mode(X, "hankata")
end

local function zenkaku(X)
  local s = X.s
  if s.type ~= "input" then
    return
  end
  if s.imode ~= "direct" then
    rule(X, "R-MD-05")
    kakutei(X)
  else
    rule(X, "R-MD-04")
  end
  s.conv = nil
  s.g.current = "zen"
  s.table = "zen"
  mode_change(X, "zenkaku")
end

local MODE_FUNCTIONS = { hira = hirakana, kata = katakana, hankata = hankatakana, zenkaku = zenkaku }

------------------------------------------------------------------------
-- キーマップ（keymap.lua）
------------------------------------------------------------------------
local function wrap(id, fn)
  return function(X, char)
    rule(X, id)
    fn(X, char)
  end
end

local KEYMAP = {
  input = {
    default = kana_input,
    map = {
      ["<bs>"] = delete_char,
      ["<c-g>"] = cancel,
      ["<cr>"] = newline,
      ["<esc>"] = escape,
      ["<nl>"] = kakutei_key,
      ["<c-q>"] = hankatakana,
      [">"] = prefix,
      ["<space>"] = henkan_first,
      ["l"] = kana_function(wrap("R-EN-01", disable)),
      ["q"] = kana_function(katakana),
      [";"] = kana_function(function(X, _, before)
        local st = stage(X.C, X.s)
        rule(X, st == "direct" and "R-IN-10" or st == "pre0" and "R-PR-10" or st == "pre" and (before == "prep" and "R-PR-14" or "R-PR-12") or "R-OK-07")
        henkan_point(X)
      end),
      ["/"] = kana_function(abbrev),
      ["L"] = kana_function(zenkaku),
    },
  },
  henkan = {
    default = henkan_input,
    map = {
      ["<c-g>"] = cancel,
      ["<cr>"] = newline,
      ["<nl>"] = kakutei_key,
      ["<space>"] = henkan_forward,
      ["x"] = henkan_backward,
      ["X"] = purge_candidate,
      [">"] = suffix,
    },
  },
}

function handle_key(X, key)
  local s = X.s
  if not s.enabled or s.type == "escape" then
    -- R-EN-08：届かない。R-EN-09（未定義。推奨の動き）：<Esc> の直後に届いても何も起きない
    rule(X, s.type == "escape" and "R-EN-09" or "R-EN-08")
    return
  end
  local keymap = KEYMAP[s.type]
  local char = CHAR[key] or key
  local func = keymap.map[key]
  -- 打ちかけ＋キーがかなテーブルにあれば、かなテーブルを先に使う（#42 #43 #67）
  if func and s.type == "input" then
    local nd = node(tbl(s), s.feed .. char)
    if nd and (s.feed ~= "" or nd.result == nil or nd.count > 1) then
      func = nil
    end
  end
  func = func or keymap.default;
  func(X, char)
end

------------------------------------------------------------------------
-- 有効と無効（main.lua の enable / disable）
------------------------------------------------------------------------
local function enable(X)
  local s = X.s
  local function recreate(carry)
    s.g.current = X.C.kanaTable
    local fresh = new_context(s.g, s.user)
    X.s = fresh
    emit(X, carry or "")
    local fn = MODE_FUNCTIONS[fresh.g.last_mode]
    if fn then
      fn(X, "")
    end
  end
  if s.enabled and s.type == "henkan" then
    rule(X, "R-EN-06")
    kakutei(X)
    local carry = X.out.commit
    X.out.commit = ""
    recreate(carry)
  elseif s.enabled and s.type == "input" and (s.imode ~= "direct" or s.feed ~= "") then
    rule(X, "R-EN-05") -- 何も起きない
  else
    rule(X, s.enabled and s.type ~= "escape" and "R-EN-04" or "R-EN-03")
    recreate()
  end
  -- keepMode で前のモードに戻すときは、モードの関数が積む印（R-MD-01 など）も out.rules に残る
end

------------------------------------------------------------------------
-- 外に出す関数
------------------------------------------------------------------------
function M.step(C, D, oracle, sigma, key)
  local X = { C = C, D = D, oracle = oracle or {}, s = copy(sigma), out = { commit = "", calls = {}, rules = {} }, depth = 0 }
  if key == "@enable" then
    enable(X)
  elseif key == "@disable" then
    if X.s.enabled and X.s.type ~= "escape" then
      rule(X, "R-EN-07")
      disable(X)
    else
      rule(X, "R-EN-08")
    end
  else
    handle_key(X, key)
  end
  return X.s, X.out
end

-- pre-edit の文字列（state.lua の to_string）
local function to_string(C, s)
  if s.type == "escape" then
    return ""
  elseif s.type == "henkan" then
    return C.markerHenkanSelect .. (modify(s.cands and s.cands[s.idx + 1], s.affix) or "error") .. conv(s, s.of)
  elseif s.imode == "direct" then
    return s.feed
  end
  local out = conv(s, C.markerHenkan) .. conv(s, s.hf)
  if s.imode == "okuriari" then
    if s.prev then
      return out .. s.feed .. "*"
    end
    return out .. conv(s, "*" .. s.of) .. s.feed
  end
  return out .. s.feed
end

-- g:skkeleton#state と g:skkeleton#mode と同じ形。C を省くと既定の設定で見る
function M.observe(sigma, C)
  C = C or M.config()
  local phase
  if sigma.type == "input" then
    phase = sigma.imode == "okurinasi" and "input:okurinasi" or sigma.imode == "okuriari" and "input:okuriari" or "input"
  else
    phase = sigma.type
  end
  return {
    phase = phase,
    henkanFeed = sigma.hf or "",
    preedit = to_string(C, sigma),
    mode = sigma.enabled and sigma.mode or "",
  }
end

-- キー列を内側の機械に流す oracle を作る（入れ子の登録の検証用）。
-- answers[depth + 1] が、その深さの欄に流すキー列。無ければ取り消し
function M.oracle_keys(answers, confirm)
  return {
    input = function(_, depth)
      local keys = answers[depth + 1]
      return keys and { keys = keys } or nil
    end,
    confirm = function()
      return confirm == true
    end,
  }
end

return M

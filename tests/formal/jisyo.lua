-- 形式検証の PoC: SKK 辞書ファイルの読み込みを、生成した辞書と「意図した中身」の正解に並べて確かめる。
-- 辞書ファイルを「行の列（項目）」として作り、書き出した文字列と、その中身の正解を同時に持つ。
-- 読み込みの実装（skk.lua の parse / split_candidates / decode_concat）から独立した、SKK 辞書の形式からの正解:
--   - 行は LF か CRLF で終わる（最後の行は改行が無くてもよい）。行末の空白は無視する
--   - `;; okuri-ari entries.` と `;; okuri-nasi entries.` の行（完全一致）で節が替わる。節の前の行、
--     節の見出しが 1 つも無い辞書の行は無視する（upstream の loadString と同じ。mode == -1 の間は読み飛ばす）。
--     節は並びも回数も自由（okuri-nasi が先でも、同じ節が 2 回でもよい）
--   - `;;` で始まる行（コメント）、空行、空白だけの行、空白の無い行、先頭が空白の行は読み飛ばす
--   - 行は「見出し」+ 空白 1 つ + `/候補/候補/…/`。候補は `語;注釈` の形で、読み込んだ文字列は注釈つきのまま返る
--     （注釈を落とすのは candidate.modify の仕事）
--   - 候補の中の `/` と `;` は `(concat "…\057…\073…")` で書く（`\\` と `\"` もこの中で使う）。語でも注釈でもよい。
--     読むと式が展開される。語の中の `;` は注釈の区切りと混ざらないよう、実装によって `;` のまま返す（A）か、
--     `\073` のまま返す（B、#49 の直し）。どちらも許す
--   - 送りありの `[く/候補/…/]` は、全体で 1 つの候補（`[` で始まる 1 つの文字列）として返る（user.lua の filter が
--     `[` で始まるものをブロックとして見分けるため）
--   - 空の候補（`//`）と、候補の無い行（`見出し /`、`見出し //`、`見出し `）は候補にならない。upstream は空文字の候補を返すが、
--     変換で選ぶ意味が無いので、ここは skkeleton.nvim の仕様とする
--   - 1 行の中で同じ候補が重ねて出ても、Library を通すと最初の 1 つだけになる
--   - 同じ見出しが 2 行あるとき: あとの行を使う（upstream と同じ。#48 で決めた）
--   - 前方一致（get_prefix）と補完（Library:get_completion_result）は、候補のある見出しをバイト順に返す。補完は
--     1 文字なら完全一致だけ、2 文字以上は前方一致
--   - 文字コード: encoding の指定があればそれ、無ければ先頭のコメントの `coding:`、それも無ければ UTF-8 と
--     見える中身は UTF-8（EUC-JP の判別は確かでないので、ここでは指定か `coding:` があるときだけ見る）。UTF-8 の BOM は無視する
--   - DB のキャッシュ（db.lua）は、元の辞書を直して mtime が変わったら作り直す。メモリ読み（load_memory）、DB、
--     小分けに作る DB（tick つき）の 3 通りで、同じ結果になる
--   - JSON（`okuri_ari` / `okuri_nasi` が 見出し → 候補の配列）は配列の中身をそのまま返す
--   - yaml・msgpack は v1 で扱わない（黙って空の辞書にせず、エラーにする）
-- 使い方: nvim --headless -u NONE -i NONE -l tests/formal/jisyo.lua [--random N] [--seed S]
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")
vim.opt.rtp:prepend(root)

local opts = { random = 300, seed = 1 }
do
  local i = 1
  while i <= #arg do
    local k, v = arg[i], arg[i + 1]
    if k == "--random" then
      opts.random, i = tonumber(v), i + 1
    elseif k == "--seed" then
      opts.seed, i = tonumber(v), i + 1
    elseif k == "--coverage" then
      -- lua/skkeleton/ の通った行を .tests/formal-cov/<名前>/ に書く（coverage.lua で集計）
      opts.coverage, i = v, i + 1
    end
    i = i + 1
  end
end

if opts.coverage then
  local cov = dofile(here .. "/cov.lua")
  cov.install(root)
  cov.write_at_exit(root, opts.coverage, cov.new())
end

local skk = require("skkeleton.dictionary.skk")
local db = require("skkeleton.dictionary.db")
local Library = require("skkeleton.dictionary").Library

local function pick(list)
  return list[math.random(#list)]
end

-- バイト順の比較（ロケールに左右されない。正解の側の並べ替えに使う）
local function bytelt(a, b)
  local n = math.min(#a, #b)
  for i = 1, n do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then
      return x < y
    end
  end
  return #a < #b
end

local function startswith(s, p)
  return s:sub(1, #p) == p
end

-- 語（候補の本体）と注釈の素材。EUC-JP に変換できる文字だけを使う。`/` と `;` を含むものは concat で書く
local WORDS = {
  "漢",
  "感",
  "缶",
  "幹事",
  "a",
  "b c",
  "x)y",
  'q"r',
  "c\\d",
  "全角；",
  "全角／",
  "a(b",
  "中",
  "ア",
  "ＡＢＣ",
  "x:y",
  "1",
  "a/b",
  "c;d",
  "e/f;g",
  "(括弧)",
  "end)",
}
local ANNS = { "注釈", "ちゅう;しゃく", "a b", "x/y", "", "(括弧)", 'q"u', "取りまとめ役" }
local BLOCK_CANDS = { "感", "缶", "漢;注", "a b", "中" }
local OKURI = { "く", "か", "る", "ん" }

-- 見出し。前方一致する組と、# と > を含むもの、ASCII と日本語を混ぜる
local KEYS = {
  okurinasi = {
    "かん",
    "かんじ",
    "かんしゃ",
    "a",
    "ab",
    "#ばい",
    "だい>",
    ">か",
    "あ",
    "ん",
    "か",
    "漢字",
    "A",
    "a-b",
    "!",
  },
  okuriari = { "わるk", "かえr", "おくt", "ほしi", "かk", "かん" },
}
local ABSENT = { "ぞ", "zz", "かんじや", "#" }
local PREFIXES = {
  "か",
  "かん",
  "かんじ",
  "かんし",
  "a",
  "ab",
  "a-",
  "#",
  "#ば",
  "だ",
  "だい",
  ">",
  "漢",
  "漢字",
  "あ",
  "ん",
  "A",
  "わ",
  "わる",
  "かえ",
  "お",
  "ほし",
  "zz",
}

local QUERIES = {}
for kind, keys in pairs(KEYS) do
  QUERIES[kind] = vim.list_extend(vim.deepcopy(keys), ABSENT)
end

------------------------------------------------------------------------------
-- 書き込み側: 論理的な候補 → SKK 辞書の文字列
------------------------------------------------------------------------------
local function chars(s)
  return s == "" and {} or vim.fn.split(s, [[\zs]])
end

local function esc(s)
  s = s:gsub('[\\"]', "\\%0")
  s = s:gsub("/", "\\057")
  s = s:gsub(";", "\\073")
  return s
end

-- (concat "…" "…") に書く。文字列を 1〜3 個に割る
local function concat_of(s)
  local cs = chars(s)
  local n = math.min(#cs, math.random(3))
  local parts, from = {}, 1
  for i = 1, n do
    local to = i == n and #cs or math.random(from - 1, #cs - (n - i))
    parts[#parts + 1] = '"' .. esc(table.concat(cs, "", from, to)) .. '"'
    from = to + 1
  end
  return "(concat " .. table.concat(parts, " ") .. ")"
end

local function needs_concat(s)
  return s:find("[/;]") ~= nil
end

local function raw_token(tok)
  if tok.t == "empty" then
    return ""
  elseif tok.t == "block" then
    return "[" .. tok.okuri .. "/" .. table.concat(tok.cands, "/") .. "/]"
  end
  local w = (tok.wconcat or needs_concat(tok.word)) and concat_of(tok.word) or tok.word
  if tok.annot == nil then
    return w
  end
  local a = (tok.aconcat or tok.annot:find("/", 1, true)) and concat_of(tok.annot) or tok.annot
  if tok.annot == "" then
    a = ""
  end
  return w .. ";" .. a
end

-- 読み込んで返るはずの文字列。variant A は語の中の ; をそのまま、B は \073 のまま
local function tok_strings(tok, variant)
  if tok.t == "empty" then
    return {}
  elseif tok.t == "block" then
    return { "[" .. tok.okuri .. "/" .. table.concat(tok.cands, "/") .. "/]" }
  end
  local w = tok.word
  if variant == "B" then
    w = w:gsub(";", "\\073")
  end
  return { w .. (tok.annot ~= nil and (";" .. tok.annot) or "") }
end

------------------------------------------------------------------------------
-- 生成
------------------------------------------------------------------------------
local function gen_tok(kind, prev)
  local r = math.random()
  if r < 0.08 then
    return { t = "empty" }
  elseif r < 0.18 and kind == "okuriari" or r < 0.04 then
    local cands = {}
    for _ = 1, math.random(3) do
      cands[#cands + 1] = pick(BLOCK_CANDS)
    end
    return { t = "block", okuri = pick(OKURI), cands = cands }
  elseif r < 0.3 and #prev > 0 then
    local p = pick(prev)
    if p.t == "c" then
      return vim.deepcopy(p) -- 同じ候補の重複
    end
  end
  local tok = { t = "c", word = pick(WORDS) }
  if math.random() < 0.3 then
    tok.annot = pick(ANNS)
  end
  tok.wconcat = math.random() < 0.15
  tok.aconcat = math.random() < 0.15
  return tok
end

local function gen_entry(kind)
  local toks = {}
  for _ = 1, pick({ 0, 1, 1, 1, 2, 2, 3, 4 }) do
    toks[#toks + 1] = gen_tok(kind, toks)
  end
  return {
    t = "entry",
    key = pick(KEYS[kind]),
    toks = toks,
    shape = pick({ "/", "//", "" }), -- 候補が無いときの書き方
    trail = math.random() < 0.1 and pick({ " ", "  " }) or "",
  }
end

local function gen_noise()
  return pick({
    { t = "comment", text = ";; 辞書のコメント" },
    { t = "comment", text = ";; かん /漢/" },
    { t = "comment", text = ";;" },
    -- 節の見出しに似ているが、完全一致ではないので、ただのコメント（節は替わらない）
    { t = "comment", text = ";; okuri-ari entries" },
    { t = "comment", text = ";; okuri-nasi entries. " },
    { t = "comment", text = ";;okuri-nasi entries." },
    { t = "blank" },
    { t = "blank" },
    { t = "spaces" },
    { t = "nospace", text = pick(KEYS.okurinasi) },
    { t = "leadsp" },
    { t = "dirty" },
  })
end

local ENCS = {
  { name = "utf8" },
  { name = "utf8" },
  { name = "utf8bom", bom = true },
  { name = "utf8hdr", header = ";; -*- coding: utf-8 -*-" },
  { name = "utf8x", arg = { "utf-8", "UTF-8", "utf8" } },
  { name = "eucx", euc = true, arg = { "euc-jp", "EUC-JP", "eucjp", "euc_jp" } },
  { name = "euchdr", euc = true, header = ";; -*- coding: euc-jp -*-" },
}
local LAYOUTS = {
  { "okuriari", "okurinasi" },
  { "okuriari", "okurinasi" },
  { "okurinasi", "okuriari" },
  { "okurinasi" },
  { "okuriari" },
  {},
  { "okurinasi", "okuriari", "okurinasi" },
  { "okuriari", "okuriari" },
}

local function gen_case()
  local enc = pick(ENCS)
  local c = {
    items = {},
    enc = enc,
    arg = enc.arg and pick(enc.arg) or nil,
    eol = pick({ "lf", "lf", "crlf", "mixed" }),
    final_nl = math.random() > 0.2,
    stale = math.random() < 0.4,
    rseed = math.random(1, 1e9),
  }
  local items = c.items
  local function add(it)
    items[#items + 1] = it
  end
  local function noise(p)
    while math.random() < p do
      add(gen_noise())
    end
  end
  noise(0.5)
  if math.random() < 0.2 then
    add(gen_entry("okurinasi")) -- 節の前の行は無視される
  end
  for _, kind in ipairs(LAYOUTS[math.random(#LAYOUTS)]) do
    add({ t = "marker", sec = kind })
    noise(0.3)
    for _ = 1, math.random(0, 6) do
      add(gen_entry(kind))
      noise(0.2)
    end
    if math.random() < 0.3 and #items > 0 then
      -- 同じ見出しの 2 行目（#48）。別の節に出ることもある
      local last
      for i = #items, 1, -1 do
        if items[i].t == "entry" then
          last = items[i]
          break
        end
      end
      if last then
        local dup = gen_entry(kind)
        dup.key = last.key
        add(dup)
      end
    end
  end
  return c
end

------------------------------------------------------------------------------
-- 書き出し
------------------------------------------------------------------------------
local MARKERS = { okuriari = ";; okuri-ari entries.", okurinasi = ";; okuri-nasi entries." }

local function render_item(it)
  if it.t == "marker" then
    return MARKERS[it.sec]
  elseif it.t == "comment" then
    return it.text
  elseif it.t == "blank" then
    return ""
  elseif it.t == "spaces" then
    return "   "
  elseif it.t == "nospace" then
    return it.text
  elseif it.t == "leadsp" then
    return " /x/"
  elseif it.t == "dirty" then
    -- 見出しに空白が入った行。upstream も本実装も最初の空白で見出しを切る（残りは候補にならない並び）。
    -- ぬ はほかの見出しに使わないので、ほかの項目には影響しない。読み込みが落ちないことだけを見る
    return "ぬ x /y/"
  end
  local raws = {}
  for _, t in ipairs(it.toks) do
    raws[#raws + 1] = raw_token(t)
  end
  if #raws == 0 then
    return it.key .. " " .. it.shape .. it.trail
  end
  return it.key .. " /" .. table.concat(raws, "/") .. "/" .. it.trail
end

local function render(c)
  math.randomseed(c.rseed) -- concat の割り方と改行の混ぜ方を、書き出すたびに同じにする
  local lines = {}
  if c.enc.header then
    lines[1] = c.enc.header
  end
  for _, it in ipairs(c.items) do
    lines[#lines + 1] = render_item(it)
  end
  local out = {}
  for i, l in ipairs(lines) do
    local nl = c.eol == "crlf" and "\r\n" or (c.eol == "mixed" and pick({ "\n", "\r\n" })) or "\n"
    if i == #lines and not c.final_nl then
      nl = ""
    end
    out[#out + 1] = l .. nl
  end
  local text = table.concat(out)
  if c.enc.euc then
    text = assert(vim.iconv(text, "utf-8", "euc-jp"), "iconv to euc-jp failed")
  elseif c.enc.bom then
    text = "\239\187\191" .. text
  end
  return text
end

------------------------------------------------------------------------------
-- 正解（中身）: kind -> 見出し -> 行（候補の部品の配列）の配列
------------------------------------------------------------------------------
local function model_of(c)
  local m = { okuriari = {}, okurinasi = {} }
  local cur
  for _, it in ipairs(c.items) do
    if it.t == "marker" then
      cur = it.sec
    elseif it.t == "entry" and cur then
      m[cur][it.key] = m[cur][it.key] or {}
      table.insert(m[cur][it.key], it.toks)
    end
  end
  return m
end

local function has_dup(m)
  for _, map in pairs(m) do
    for _, lines in pairs(map) do
      if #lines > 1 then
        return true
      end
    end
  end
end

-- 見出しの候補（重複なし）。policy "last" はあとの行だけ（#48）、"merge" は全部の行
local function expected(lines, policy, variant)
  local out, seen = {}, {}
  if not lines then
    return out
  end
  for li, toks in ipairs(lines) do
    if policy == "last" and li < #lines then
      goto continue
    end
    for _, t in ipairs(toks) do
      for _, s in ipairs(tok_strings(t, variant)) do
        if not seen[s] then
          seen[s] = true
          out[#out + 1] = s
        end
      end
    end
    ::continue::
  end
  return out
end

local function dedupe(list)
  local out, seen = {}, {}
  for _, s in ipairs(list) do
    if not seen[s] then
      seen[s] = true
      out[#out + 1] = s
    end
  end
  return out
end

local function show(x)
  return vim.inspect(x, { newline = " ", indent = "" })
end

-- 辞書 d を、正解 model（variant と policy で決まる）と比べる。食い違いがあれば説明を返す
-- model[kind][key] は expected() に渡せる行の配列
local function battery(d, model, variant, policy, ex)
  local lib = Library.new({ d })
  for kind, qs in pairs(QUERIES) do
    for _, key in ipairs(qs) do
      local want = ex(model[kind][key], policy, variant)
      local got = lib:get_henkan_result(kind, key)
      if table.concat(got, "\0") ~= table.concat(want, "\0") then
        return ("%s %q の候補 %s、正解 %s"):format(kind, key, show(got), show(want))
      end
    end
    -- 前方一致: 候補のある見出しが、バイト順で
    for _, p in ipairs(PREFIXES) do
      local keys = {}
      for k, lines in pairs(model[kind]) do
        if startswith(k, p) and #ex(lines, policy, variant) > 0 then
          keys[#keys + 1] = k
        end
      end
      table.sort(keys, bytelt)
      local want = {}
      for _, k in ipairs(keys) do
        want[#want + 1] = k .. "=" .. table.concat(ex(model[kind][k], policy, variant), "|")
      end
      local got = {}
      for _, e in ipairs(d:get_prefix(kind, p)) do
        local cands = dedupe(e[2])
        if #cands > 0 then
          got[#got + 1] = e[1] .. "=" .. table.concat(cands, "|")
        end
      end
      if table.concat(got, "\0") ~= table.concat(want, "\0") then
        return ("%s の前方一致 %q: %s、正解 %s"):format(kind, p, show(got), show(want))
      end
    end
  end
  -- 補完（送りなしだけ）
  for _, p in ipairs(PREFIXES) do
    local keys = {}
    local exact = vim.fn.strchars(p) == 1
    for k, lines in pairs(model.okurinasi) do
      if (exact and k == p or not exact and startswith(k, p)) and #ex(lines, policy, variant) > 0 then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, bytelt)
    local want = {}
    for _, k in ipairs(keys) do
      want[#want + 1] = k .. "=" .. table.concat(ex(model.okurinasi[k], policy, variant), "|")
    end
    local got = {}
    for _, e in ipairs(lib:get_completion_result(p, "")) do
      got[#got + 1] = e[1] .. "=" .. table.concat(e[2], "|")
    end
    if table.concat(got, "\0") ~= table.concat(want, "\0") then
      return ("補完 %q: %s、正解 %s"):format(p, show(got), show(want))
    end
  end
end

-- 結果: nil（一致）、KNOWN（#48 だけの食い違い）、文字列（本物の食い違い）
local KNOWN = {}
local function judge(d, model, ex)
  local first_msg
  for _, variant in ipairs({ "A", "B" }) do
    local msg = battery(d, model, variant, "last", ex)
    if not msg then
      return nil
    end
    first_msg = first_msg or msg
  end
  return first_msg
end

------------------------------------------------------------------------------
-- 1 件の検査
------------------------------------------------------------------------------
local function write(path, data, mtime)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
  vim.uv.fs_utime(path, mtime, mtime)
end

local function worse(a, b)
  if type(a) == "string" then
    return a
  elseif type(b) == "string" then
    return b
  end
  return a or b
end

-- 3 通りの読み込みで、c の中身を確かめる。stale のときは、書き換えて DB を使い直す
local function check_text(c, dir, path, cache, label)
  local model = model_of(c)
  local res
  local function try(name, open)
    local ok, d = pcall(open)
    if not ok then
      res = worse(res, ("%s: 読み込みでエラー %s"):format(name, tostring(d)))
      return
    end
    local ok2, r = pcall(judge, d, model, expected)
    if d.close then
      d:close()
    end
    if not ok2 then
      r = ("%s: 検索でエラー %s"):format(name, tostring(r))
    elseif type(r) == "string" then
      r = name .. ": " .. r
    end
    res = worse(res, r)
  end
  try("メモリ" .. label, function()
    return skk.load_memory(path, c.arg)
  end)
  try("DB" .. label, function()
    return db.open_dictionary(path, { encoding = c.arg, dir = cache })
  end)
  try("小分けの DB" .. label, function()
    local dst = dir .. "/tick" .. label .. ".db"
    local n = 0
    db.build(path, dst, c.arg, function()
      n = n + 1
    end)
    return db.open(dst)
  end)
  return res
end

local function run(c)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/dict"
  local cache = dir .. "/cache"
  write(path, render(c), 1000000000)
  local res = check_text(c, dir, path, cache, "")
  if c.stale and not (type(res) == "string") then
    -- 元の辞書が書き換わったら、DB を作り直して新しい中身を返す。奇数番目の項目を落とした版にする
    local c2 = vim.deepcopy(c)
    c2.items = {}
    for i, it in ipairs(c.items) do
      if i % 2 == 0 then
        c2.items[#c2.items + 1] = it
      end
    end
    write(path, render(c2), 1000000007)
    res = worse(res, check_text(c2, dir, path, cache, "（書き換えたあと）"))
  end
  vim.fn.delete(dir, "rf")
  return res
end

------------------------------------------------------------------------------
-- JSON
------------------------------------------------------------------------------
local JSON_CANDS = { "漢", "感;注釈", "a/b", "x;y", '(concat "a")', "b c", 'q"r', "c\\d", "中" }

local function gen_json()
  local j = { okuri_ari = {}, okuri_nasi = {} }
  local model = { okuriari = {}, okurinasi = {} }
  for jk, kind in pairs({ okuri_ari = "okuriari", okuri_nasi = "okurinasi" }) do
    for _, key in ipairs(KEYS[kind]) do
      if math.random() < 0.5 then
        local arr = {}
        for _ = 1, math.random(0, 4) do
          arr[#arr + 1] = pick(JSON_CANDS)
        end
        j[jk][key] = arr
        model[kind][key] = { arr }
      end
    end
  end
  return j, model
end

local function json_ex(lines, _, _)
  local out = {}
  if lines then
    out = dedupe(lines[1])
  end
  return out
end

local function run_json(j, model)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/dict.json"
  local enc = {
    okuri_ari = next(j.okuri_ari) and j.okuri_ari or vim.empty_dict(),
    okuri_nasi = next(j.okuri_nasi) and j.okuri_nasi or vim.empty_dict(),
  }
  write(path, vim.json.encode(enc), 1000000000)
  local ok, d = pcall(skk.load_memory, path)
  local res
  if not ok then
    res = "JSON の読み込みでエラー " .. tostring(d)
  else
    local ok2, r = pcall(judge, d, model, json_ex)
    res = ok2 and r or ("JSON の検索でエラー " .. tostring(r))
    if ok2 and r == nil then
      res = nil
    end
  end
  vim.fn.delete(dir, "rf")
  return type(res) == "string" and res or nil
end

------------------------------------------------------------------------------
-- 縮める
------------------------------------------------------------------------------
local function shrink(c)
  local items = c.items
  local n = 2
  local function fails(list)
    local c2 = vim.tbl_extend("force", c, { items = list })
    return type(run(c2)) == "string"
  end
  while #items >= 2 do
    local size = math.ceil(#items / n)
    local reduced = false
    for i = 1, #items, size do
      local rest = {}
      for j, o in ipairs(items) do
        if j < i or j >= i + size then
          rest[#rest + 1] = o
        end
      end
      if #rest > 0 and fails(rest) then
        items, n, reduced = rest, math.max(n - 1, 2), true
        break
      end
    end
    if not reduced then
      if n >= #items then
        break
      end
      n = math.min(n * 2, #items)
    end
  end
  return vim.tbl_extend("force", c, { items = items })
end

------------------------------------------------------------------------------
-- 固定の確認: 扱わない形式はエラーにする
------------------------------------------------------------------------------
local function fixed_checks()
  for _, name in ipairs({ "a.yaml", "a.yml", "a.YML", "a.mpk" }) do
    local ok = pcall(skk.load_memory, "/nonexistent/" .. name)
    if ok then
      return name .. " を黙って読んだ"
    end
  end
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  -- 空のファイルと、節の見出しが無い辞書は、エラーにならずに空の辞書になる
  for name, body in pairs({ empty = "", nomarker = "かん /漢/\nあ /ア/\n", only_marker = ";; okuri-nasi entries." }) do
    local p = dir .. "/" .. name
    write(p, body, 1000000000)
    local ok, d = pcall(skk.load_memory, p, "utf-8")
    if not ok then
      return name .. " の読み込みでエラー " .. tostring(d)
    end
    if #d:get_henkan_result("okurinasi", "かん") > 0 or #d:get_prefix("okurinasi", "か") > 0 then
      return name .. " に候補がある"
    end
  end
  vim.fn.delete(dir, "rf")
end

------------------------------------------------------------------------------
-- 実行
------------------------------------------------------------------------------
local t0 = vim.uv.hrtime()
local found, known = {}, nil
local msg0 = fixed_checks()
if msg0 then
  found["fixed"] = { msg = msg0, text = "" }
end
for i = 1, opts.random do
  math.randomseed(opts.seed * 100000 + i)
  local c = gen_case()
  local res = run(c)
  if res == KNOWN then
    -- 最小の例を 1 つだけ覚える。縮めるときは「本物の失敗」だけを見るので、known は縮めない
    if not known or #c.items < #known.items then
      known = c
    end
  elseif type(res) == "string" then
    local kind = res:gsub('%b""', "…"):gsub("%b{}", "…"):gsub("%d+", "N")
    if not found[kind] then
      local small = shrink(c)
      found[kind] = { msg = run(small), text = render(small), arg = small.arg, enc = small.enc.name }
    end
  end
  if i % 3 == 0 then
    local j, model = gen_json()
    local r = run_json(j, model)
    if r then
      found["json:" .. r:gsub('%b""', "…"):gsub("%b{}", "…")] = { msg = r, text = vim.json.encode(j) }
    end
  end
end
print(("jisyo: %d 件、%.1f 秒"):format(opts.random, (vim.uv.hrtime() - t0) / 1e9))

local failed = false
if known then
  print(
    ("\n△ 既知 #48: 同じ見出しの行が複数ある辞書（先の行だけが使われる）\n    %q"):format(
      render(known)
    )
  )
end
for _, f in pairs(found) do
  failed = true
  print(("\n✗ 反例（%s、encoding=%s）\n    %q\n    %s"):format(f.enc or "-", tostring(f.arg), f.text, f.msg))
end
if not failed then
  print("\n✓ 既知のもの以外に違反なし")
end
vim.cmd(failed and "cquit 1" or "qall!")

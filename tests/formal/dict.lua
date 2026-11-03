-- 形式検証の PoC: ユーザー辞書を、Lua の表で書いた正解のモデルと並べてランダムに操作し、食い違いを探す。
-- 操作: 登録（register_henkan_result）、削除（purge_candidate）、保存して新しいユーザー辞書に読み直す（save → load）。
--   さらに Library 越しの保存（libsave。immediatelyDictionaryRW の真偽）と即時書き込み（rwreg / rwpurge）、
--   completionRankFile への補完のランクの保存と読み直し
-- 性質:
--   - 補完のランクの順は、保存して読み直す前後で同じ（登録した候補が最新、削除で消える）
--   - 引いた候補（get_henkan_result）はモデルと同じ（登録した候補が先頭、重複なし、削除したものは出ない）
--   - 保存して読み直しても、どの読みの候補も同じ（SKK の辞書の形式で特別な / ; [ などを含む候補も）
--   - 保存したファイルは、SKK の辞書として読める形（1 行 1 読み、送りあり・送りなしの見出し）
-- 使い方: nvim --headless -u NONE -i NONE -l tests/formal/dict.lua [--random N] [--length L] [--seed S]
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")
vim.opt.rtp:prepend(root)

local opts = { random = 2000, length = 20, seed = 1 }
do
  local i = 1
  while i <= #arg do
    local k, v = arg[i], arg[i + 1]
    if k == "--random" then
      opts.random, i = tonumber(v), i + 1
    elseif k == "--length" then
      opts.length, i = tonumber(v), i + 1
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

local User = require("skkeleton.dictionary.user")

-- 読みと候補。SKK の辞書の形式で特別な文字（/ ; [ ] と空白、数値変換の #）も混ぜる
local WORDS = { okurinasi = { "かん", "かんじ", "a", "#ばい", "ん" }, okuriari = { "わるk", "かえr" } }
local CANDS =
  { "漢", "感", "缶;注釈", "a/b", "[x]", "c d", "#1倍", "；", "全角／", "x;y;z", '(concat "a")', "" }

-- 正解のモデル: kind -> word -> 候補の配列（登録した候補が先頭、重複なし）
local function model_register(m, kind, word, cand)
  if cand == "" then
    return
  end
  local list = { cand }
  for _, c in ipairs(m[kind][word] or {}) do
    if c ~= cand then
      list[#list + 1] = c
    end
  end
  m[kind][word] = list
end

-- 補完のランクの正解: 登録した候補ほど後ろ（新しい）。登録し直すと最新になる。
-- 候補を削除してもランクは消えない（upstream と同じ。#129）
local function rank_bump(m, cand)
  if cand == "" then
    return
  end
  m.ranks = vim.tbl_filter(function(c)
    return c ~= cand
  end, m.ranks)
  m.ranks[#m.ranks + 1] = cand
end

local function rank_drop(_, _)
  -- 削除してもランクは残る（#129）
end

local function model_purge(m, kind, word, cand)
  local rest = {}
  for _, c in ipairs(m[kind][word] or {}) do
    if c ~= cand then
      rest[#rest + 1] = c
    end
  end
  m[kind][word] = #rest > 0 and rest or nil
end

-- 送りありのブロック（[ で始まるもの）は引くときに除かれる（user.lua の filter と同じ）
local function visible(list)
  return vim.tbl_filter(function(c)
    return c:sub(1, 1) ~= "["
  end, list or {})
end

local function compare(dict, model, where)
  for kind, words in pairs(WORDS) do
    for _, w in ipairs(words) do
      local got = dict:get_henkan_result(kind, w)
      local want = visible(model[kind][w])
      if table.concat(got, "\0") ~= table.concat(want, "\0") then
        return ("%s: %s %q の候補 %s、モデル %s"):format(
          where,
          kind,
          w,
          vim.inspect(got, { newline = " ", indent = "" }),
          vim.inspect(want, { newline = " ", indent = "" })
        )
      end
    end
  end
end

-- 補完（Library:get_completion_result）の正解。upstream の Library.getCompletionResult（dictionary.ts）と同じ規則を、
-- 辞書の中身から独立に書く:
--   - 読みが空なら空。1 文字なら送りなしの完全一致だけ。2 文字以上は前方一致（読みのバイト順）
--   - 辞書ごとに順に集め、同じ読みの候補は重複なしで先の辞書の順に並べる
--   - 数字の入った読み（1ば）は、数字を # に替えた読み（#ば）でも引く（NumberConvertWrapper.getCompletionResult。
--     候補の数値変換はここでは見ない）。ユーザー辞書の [ で始まるブロックは候補に出ない
local GLOBAL = {
  { "a", { "ア" } },
  { "abc", { "ＡＢＣ" } },
  { "#ばい", { "#1倍", "#3倍" } },
  { "かん", { "缶", "感", "漢" } },
  { "かんじ", { "漢字", "幹事;取りまとめ役" } },
  { "なか", { "中" } },
  { "ん", { "ン" } },
}
local PREFIXES = { "a", "ab", "か", "かん", "かんじ", "#ば", "1ば", "12ば", "な", "ん", "んx" }

local function global_dict()
  local g = {}
  function g:get_henkan_result(kind, w)
    if kind == "okurinasi" then
      for _, e in ipairs(GLOBAL) do
        if e[1] == w then
          return vim.deepcopy(e[2])
        end
      end
    end
    return {}
  end
  function g:get_prefix(kind, p)
    local out = {}
    if kind == "okurinasi" then
      for _, e in ipairs(GLOBAL) do
        if vim.startswith(e[1], p) then
          out[#out + 1] = { e[1], vim.deepcopy(e[2]) }
        end
      end
      table.sort(out, function(a, b)
        return a[1] < b[1]
      end)
    end
    return out
  end
  return g
end

local function model_completion(model, prefix)
  local function base(p)
    if p == "" then
      return {}
    end
    local order, map = {}, {}
    local function add(k, cands)
      if #cands == 0 then
        return
      end
      if not map[k] then
        map[k] = {}
        order[#order + 1] = k
      end
      for _, c in ipairs(cands) do
        if not vim.tbl_contains(map[k], c) then
          map[k][#map[k] + 1] = c
        end
      end
    end
    local user = {}
    for k, list in pairs(model.okurinasi) do
      user[#user + 1] = { k, visible(list) }
    end
    local glob = {}
    for _, e in ipairs(GLOBAL) do
      glob[#glob + 1] = e
    end
    for _, src in ipairs({ user, glob }) do
      table.sort(src, function(a, b)
        return a[1] < b[1]
      end)
      for _, e in ipairs(src) do
        local hit = vim.fn.strchars(p) == 1 and e[1] == p or (vim.fn.strchars(p) > 1 and vim.startswith(e[1], p))
        if hit then
          add(e[1], e[2])
        end
      end
    end
    return order
  end
  local real = prefix:gsub("%d+", "#")
  local keys = base(real)
  if real ~= prefix then
    -- #50 の直しで、# の読みで見つかった見出しの # は、入力した数字に置き換えて返す（"#ばい" → "1ばい"）。
    -- upstream は # のまま返すが、補完の見出しとしては入力に合わせた形の方が自然なので、この違いは仕様とする
    local digits = prefix:match("%d+")
    keys = vim.tbl_map(function(k)
      return (k:gsub("#", digits, 1))
    end, keys)
    keys = vim.list_extend(base(prefix), keys)
  end
  return keys
end

local function compare_ranks(dict, model, where)
  local entries = {}
  for w, r in pairs(dict:get_ranks()) do
    entries[#entries + 1] = { w, r }
  end
  table.sort(entries, function(a, b)
    return a[2] < b[2]
  end)
  local got = vim.tbl_map(function(e)
    return e[1]
  end, entries)
  if table.concat(got, "\0") ~= table.concat(model.ranks, "\0") then
    return ("%s: ランク %s、モデル %s"):format(
      where,
      vim.inspect(got, { newline = " ", indent = "" }),
      vim.inspect(model.ranks, { newline = " ", indent = "" })
    )
  end
end

-- Library 越しに引いた結果（ユーザー辞書だけを持つ Library）も、モデルと同じか
local function compare_library(lib, model, where)
  for kind, words in pairs(WORDS) do
    for _, w in ipairs(words) do
      local got = lib:get_henkan_result(kind, w)
      local want = visible(model[kind][w])
      if table.concat(got, "\0") ~= table.concat(want, "\0") then
        return ("%s: Library %s %q の候補 %s、モデル %s"):format(
          where,
          kind,
          w,
          vim.inspect(got, { newline = " ", indent = "" }),
          vim.inspect(want, { newline = " ", indent = "" })
        )
      end
    end
  end
end

local function compare_completion(dict, model, where)
  -- 本物の組み立て（dictionary/init.lua）と同じく、全体辞書も数値変換のラッパーで包む
  local lib =
    require("skkeleton.dictionary").Library.new({ require("skkeleton.dictionary.numeral").wrap(global_dict()) }, dict)
  for _, p in ipairs(PREFIXES) do
    local got = vim.tbl_map(function(e)
      return e[1]
    end, lib:get_completion_result(p, ""))
    local want = model_completion(model, p)
    -- 数字の入った読みは先に # の読みの候補が並ぶので、順は見ずに集合で比べる
    if p:find("%d") then
      table.sort(got)
      table.sort(want)
      want = vim.fn.uniq(want)
    end
    if table.concat(got, "\0") ~= table.concat(want, "\0") then
      return ("%s: 補完 %q の読み %s、モデル %s"):format(
        where,
        p,
        vim.inspect(got, { newline = " ", indent = "" }),
        vim.inspect(want, { newline = " ", indent = "" })
      )
    end
  end
end

local function run(ops)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/user"
  local rank_path = dir .. "/ranks.json"
  local config = require("skkeleton.config")
  local Library = require("skkeleton.dictionary").Library
  local saved_rank_file = config.options.completionRankFile
  config.options.completionRankFile = rank_path
  local function finish(i, msg)
    config.options.completionRankFile = saved_rank_file
    vim.fn.delete(dir, "rf")
    return i, msg
  end
  local dict = User.new()
  dict:load({ path = path })
  local model = { okurinasi = {}, okuriari = {}, ranks = {} }
  -- 保存先から新しいユーザー辞書を作り直す
  local function fresh_from_files()
    local fresh = User.new()
    fresh:load({ path = path })
    fresh:load_ranks(rank_path)
    return fresh
  end
  for i, op in ipairs(ops) do
    if op[1] == "reg" then
      dict:register_henkan_result(op[2], op[3], op[4])
      model_register(model, op[2], op[3], op[4])
      rank_bump(model, op[4])
    elseif op[1] == "purge" then
      dict:purge_candidate(op[2], op[3], op[4])
      model_purge(model, op[2], op[3], op[4])
      rank_drop(model, op[4])
    elseif op[1] == "reload" then
      -- ユーザー辞書を直接 save / save_ranks して、読み直す
      dict:save()
      dict:save_ranks(rank_path)
      local fresh = fresh_from_files()
      local msg = compare(fresh, model, "保存して読み直したあと")
        or compare_ranks(fresh, model, "保存して読み直したあと")
      if msg then
        return finish(i, msg)
      end
      dict = fresh
    elseif op[1] == "libsave" then
      -- Library:save()（ユーザー辞書と、completionRankFile へのランク）。immediatelyDictionaryRW は op[2]
      local lib = Library.new({}, dict, op[2])
      lib:save()
      local fresh = fresh_from_files()
      local where = "Library:save のあと（immediatelyDictionaryRW=" .. tostring(op[2]) .. "）"
      local msg = compare(fresh, model, where)
        or compare_ranks(fresh, model, where)
        or compare_library(Library.new({}, fresh, op[2]), model, where)
      if msg then
        return finish(i, msg)
      end
      dict = fresh
    elseif op[1] == "rwreg" or op[1] == "rwpurge" then
      -- immediatelyDictionaryRW が真の Library で登録・削除する。save は呼ばない（そのたびに書かれるはず）
      local lib = Library.new({}, dict, true)
      if op[1] == "rwreg" then
        lib:register_henkan_result(op[2], op[3], op[4])
        model_register(model, op[2], op[3], op[4])
        rank_bump(model, op[4])
      else
        lib:purge_candidate(op[2], op[3], op[4])
        model_purge(model, op[2], op[3], op[4])
        rank_drop(model, op[4])
      end
      local fresh = fresh_from_files()
      local msg = compare(fresh, model, "即時書き込みのあと")
        or compare_ranks(fresh, model, "即時書き込みのあと")
        or compare_library(Library.new({}, fresh_from_files(), true), model, "即時書き込みのあと")
      if msg then
        return finish(i, msg)
      end
    end
    local msg = compare(dict, model, "操作のあと")
      or compare_ranks(dict, model, "操作のあと")
      or compare_completion(dict, model, "操作のあと")
    if msg then
      return finish(i, msg)
    end
  end
  return finish()
end

local function pick(list)
  return list[math.random(#list)]
end

local function random_ops(n)
  local ops = {}
  for i = 1, n do
    local r = math.random()
    local kind = math.random() < 0.7 and "okurinasi" or "okuriari"
    local word, cand = pick(WORDS[kind]), pick(CANDS)
    if r < 0.4 then
      ops[i] = { "reg", kind, word, cand }
    elseif r < 0.5 then
      ops[i] = { "rwreg", kind, word, cand }
    elseif r < 0.62 then
      ops[i] = { "purge", kind, word, cand }
    elseif r < 0.67 then
      ops[i] = { "rwpurge", kind, word, cand }
    elseif r < 0.78 then
      ops[i] = { "reload" }
    else
      ops[i] = { "libsave", math.random() < 0.5 }
    end
  end
  return ops
end

local function fmt(ops)
  return table.concat(
    vim.tbl_map(function(o)
      if o[1] == "reload" then
        return "reload"
      elseif o[1] == "libsave" then
        return ("libsave(rw=%s)"):format(tostring(o[2]))
      end
      return ("%s(%s %s %q)"):format(o[1], o[2], o[3], o[4])
    end, ops),
    " "
  )
end

-- ddmin で縮める
local function shrink(ops)
  local n = 2
  while #ops >= 2 do
    local size = math.ceil(#ops / n)
    local reduced = false
    for i = 1, #ops, size do
      local rest = {}
      for j, o in ipairs(ops) do
        if j < i or j >= i + size then
          rest[#rest + 1] = o
        end
      end
      if #rest > 0 and run(rest) then
        ops, n, reduced = rest, math.max(n - 1, 2), true
        break
      end
    end
    if not reduced then
      if n >= #ops then
        break
      end
      n = math.min(n * 2, #ops)
    end
  end
  return ops
end

-- DB（グローバル辞書のキャッシュ）の検査。普通に作り直したとき、rename の前で nvim を止めたとき、
-- 1 時間より古い .tmp を消すときを見る。辞書の中身はメモリの辞書と比べる (#138)
local function db_check()
  local db = require("skkeleton.dictionary.db")
  local skk = require("skkeleton.dictionary.skk")
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local function finish(msg)
    vim.fn.delete(dir, "rf")
    return msg
  end
  local text = table.concat({
    ";; okuri-ari entries.",
    "わるk /悪/",
    ";; okuri-nasi entries.",
    "かん /缶/感/",
    "にほん /日本/",
    "",
  }, "\n")
  local function write(src)
    local f = assert(io.open(src, "wb"))
    f:write(text)
    f:close()
  end
  local function files(dbdir)
    local out = {}
    for _, p in ipairs(vim.fn.glob(dbdir .. "/*", false, true)) do
      out[#out + 1] = vim.fs.basename(p)
    end
    table.sort(out)
    return out
  end
  local function check_content(src, dbdir, where)
    local mem = skk.load_memory(src)
    local ok, disk = pcall(db.open_dictionary, src, { dir = dbdir })
    if not ok then
      return ("%s: DB を開けない: %s"):format(where, disk)
    end
    for _, w in ipairs({ "かん", "にほん" }) do
      local a = mem:get_henkan_result("okurinasi", w)
      local b = disk:get_henkan_result("okurinasi", w)
      if not vim.deep_equal(a, b) then
        return ("%s: %q の候補 %s、メモリ %s"):format(where, w, vim.inspect(b), vim.inspect(a))
      end
    end
  end

  -- 1. 普通に作り直す。置き場には .db だけが残る
  local src, dbdir = dir .. "/dict", dir .. "/db"
  write(src)
  local dst = db.ensure(src, { dir = dbdir, force = true })
  local fs = files(dbdir)
  if #fs ~= 1 or not fs[1]:match("%.db$") then
    return finish(("作り直したあとの DB の置き場に .db 以外がある: %s"):format(vim.inspect(fs)))
  end
  local msg = check_content(src, dbdir, "作り直したあと")
  if msg then
    return finish(msg)
  end

  -- 2. rename の前で nvim を kill する。.tmp が残り、DB はまだ無い。
  -- そのあと開き直すと、DB を作り直してメモリの辞書と同じになる
  local src2, dbdir2 = dir .. "/dict2", dir .. "/db2"
  write(src2)
  local dst2 = db.path_for(src2, dbdir2)
  local script = dir .. "/kill.lua"
  local f = assert(io.open(script, "wb"))
  f:write(([[
      vim.opt.rtp:prepend(%q)
      local uv = vim.uv
      local pid = uv.os_getpid()
      local rename = uv.fs_rename
      uv.fs_rename = function(...)
        uv.kill(pid, "sigkill")
        return rename(...)
      end
      require("skkeleton.dictionary.db").build(%q, %q)
    ]]):format(root, src2, dst2))
  f:close()
  local r = vim
    .system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", script }, { text = true })
    :wait()
  local killed_tmp
  for _, name in ipairs(files(dbdir2)) do
    if name:match("%.tmp$") then
      killed_tmp = dbdir2 .. "/" .. name
    end
  end
  if not killed_tmp then
    return finish(
      ("rename の前で止めたのに .tmp が残っていない（終了コード %s）: %s"):format(
        tostring(r.code),
        tostring(r.stderr or r.stdout or "")
      )
    )
  end
  if vim.uv.fs_stat(dst2) then
    return finish("rename の前で止めたのに .db ができている")
  end
  db.ensure(src2, { dir = dbdir2 })
  msg = check_content(src2, dbdir2, "止めたあとに開き直したとき")
  if msg then
    return finish(msg)
  end
  -- 新しい .tmp は、まだ 1 時間たっていないので残ってよい（#138）
  if not vim.uv.fs_stat(killed_tmp) then
    return finish("止めた直後の新しい .tmp が消えた")
  end
  -- 1 時間より古い .tmp は、次の作り直しで消える
  local old = os.time() - 7200
  vim.uv.fs_utime(killed_tmp, old, old)
  db.ensure(src2, { dir = dbdir2, force = true })
  if vim.uv.fs_stat(killed_tmp) then
    return finish("1 時間より古い .tmp が残っている")
  end
  local rest = files(dbdir2)
  for _, name in ipairs(rest) do
    if name:match("%.tmp$") then
      return finish("掃除のあとに .tmp が残っている: " .. vim.inspect(rest))
    end
  end
  return finish()
end

math.randomseed(opts.seed)
local found = {}
local t0 = vim.uv.hrtime()
for _ = 1, opts.random do
  local ops = random_ops(opts.length)
  local at, msg = run(ops)
  if at then
    local kind = msg:gsub('%b""', "…"):gsub("{.-}", "…")
    if not found[kind] then
      local small = shrink(vim.list_slice(ops, 1, at))
      local _, m2 = run(small)
      found[kind] = { ops = small, msg = m2 or msg }
    end
  end
end
print(("dict: %d 本 × %d 操作、%.1f 秒"):format(opts.random, opts.length, (vim.uv.hrtime() - t0) / 1e9))
local db_msg = db_check()
if db_msg then
  print("\n✗ db: " .. db_msg)
end
if vim.tbl_isempty(found) and not db_msg then
  print("✓ 違反なし")
  vim.cmd("qall!")
end
-- 見つかったが、まだ直っていないもの（issue の番号と、反例の操作で見分ける）。
-- #37・#49・#50・#53 は直った。新しい未修正の件はここに { issue = N, match = function(f) … end } で足す
local KNOWN = {}
local failed = db_msg ~= nil
for _, f in pairs(found) do
  local known
  for _, k in ipairs(KNOWN) do
    if k.match(f) then
      known = k.issue
    end
  end
  if known then
    print(("\n△ 既知 #%d: %s"):format(known, fmt(f.ops)))
  else
    failed = true
    print(("\n✗ 反例（%d 操作）: %s\n    %s"):format(#f.ops, fmt(f.ops), f.msg))
  end
end
if not failed then
  print("\n✓ 既知のもの以外に違反なし")
end
vim.cmd(failed and "cquit 1" or "qall!")

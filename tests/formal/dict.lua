-- 形式検証の PoC: ユーザー辞書を、Lua の表で書いた正解のモデルと並べてランダムに操作し、食い違いを探す。
-- 操作: 登録（register_henkan_result）、削除（purge_candidate）、保存して新しいユーザー辞書に読み直す（save → load）。
-- 性質:
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
    end
    i = i + 1
  end
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

local function run(ops)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/user"
  local dict = User.new()
  dict:load({ path = path })
  local model = { okurinasi = {}, okuriari = {} }
  for i, op in ipairs(ops) do
    if op[1] == "reg" then
      dict:register_henkan_result(op[2], op[3], op[4])
      model_register(model, op[2], op[3], op[4])
    elseif op[1] == "purge" then
      dict:purge_candidate(op[2], op[3], op[4])
      model_purge(model, op[2], op[3], op[4])
    elseif op[1] == "reload" then
      dict:save()
      local fresh = User.new()
      fresh:load({ path = path })
      local msg = compare(fresh, model, "保存して読み直したあと")
      if msg then
        vim.fn.delete(dir, "rf")
        return i, msg
      end
      dict = fresh
    end
    local msg = compare(dict, model, "操作のあと")
    if msg then
      vim.fn.delete(dir, "rf")
      return i, msg
    end
  end
  vim.fn.delete(dir, "rf")
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
    if r < 0.6 then
      ops[i] = { "reg", kind, word, cand }
    elseif r < 0.8 then
      ops[i] = { "purge", kind, word, cand }
    else
      ops[i] = { "reload" }
    end
  end
  return ops
end

local function fmt(ops)
  return table.concat(
    vim.tbl_map(function(o)
      return o[1] == "reload" and "reload" or ("%s(%s %s %q)"):format(o[1], o[2], o[3], o[4])
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
if vim.tbl_isempty(found) then
  print("✓ 違反なし")
  vim.cmd("qall!")
end
-- 見つかったが、まだ直っていないもの（issue の番号と、反例の操作で見分ける）
local KNOWN = {
  {
    -- (concat "…") という文字列そのものを語として登録すると、読み直したときに式として読まれる（#37 の残り）
    issue = 37,
    match = function(f)
      for _, o in ipairs(f.ops) do
        if o[1] == "reg" and o[4]:find("^%(concat") then
          return true
        end
      end
    end,
  },
  {
    issue = 37,
    match = function(f)
      for _, o in ipairs(f.ops) do
        if o[1] == "reg" and o[4]:find("/", 1, true) then
          return true
        end
      end
    end,
  },
}
local failed = false
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

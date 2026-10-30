-- Ported from skkeleton (denops/skkeleton/sources/skk_dictionary.ts, util.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua. Parsing is split into small steps so that it can run in a coroutine.
--
-- SKK 辞書の読み込みと、メモリ上の辞書（JSON 用、DB を作れないときの代わり）。
local M = {}

M.OKURI_ARI_MARKER = ";; okuri-ari entries."
M.OKURI_NASI_MARKER = ";; okuri-nasi entries."
M.KINDS = { "okuriari", "okurinasi" }

local function noop() end

---@param path string
---@return string data, table stat
function M.read_file(path)
  local fd, err = vim.uv.fs_open(path, "r", 438)
  if not fd then
    error(("cannot open %s (%s)"):format(path, err), 0)
  end
  local stat = assert(vim.uv.fs_fstat(fd))
  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  if not data or #data ~= stat.size then
    error(("cannot read %s"):format(path), 0)
  end
  return data, stat
end

local ALIASES = {
  utf8 = "utf-8",
  eucjp = "euc-jp",
  euc_jp = "euc-jp",
  ["euc-jp-1990"] = "euc-jp",
  ["euc-japan"] = "euc-jp",
}

function M.normalize_encoding(name)
  name = name:lower()
  return ALIASES[name] or name
end

-- 最初の非 ASCII のあたりが正しい UTF-8 か。EUC-JP の文字は UTF-8 としては必ず不正になるので見分けられる
---@param data string
local function looks_like_utf8(data)
  local p = data:find("[\128-\255]")
  if not p then
    return false
  end
  local last = math.min(#data, p + 63)
  while p <= last do
    local b = data:byte(p)
    local n
    if b < 0x80 then
      n = 0
    elseif b >= 0xc2 and b <= 0xdf then
      n = 1
    elseif b >= 0xe0 and b <= 0xef then
      n = 2
    elseif b >= 0xf0 and b <= 0xf4 then
      n = 3
    else
      return false
    end
    for i = 1, n do
      local c = data:byte(p + i)
      if c == nil then
        return true -- 窓の端で切れただけ
      elseif c < 0x80 or c > 0xbf then
        return false
      end
    end
    p = p + n + 1
  end
  return true
end

-- 文字コードを決める。指定があればそれ、無ければ先頭のコメントの `coding:`、
-- それも無ければ EUC-JP（ただし中身がはっきり UTF-8 のときは UTF-8）
---@param data string
---@param encoding? string
---@return string
function M.detect_encoding(data, encoding)
  if encoding and encoding ~= "" then
    return M.normalize_encoding(encoding)
  end
  for line in data:sub(1, 4096):gmatch("[^\n]+") do
    if line:byte(1) ~= 59 then -- ';'
      break
    end
    local c = line:lower():match("coding:%s*([%w_%-]+)")
    if c then
      return M.normalize_encoding(c)
    end
  end
  return looks_like_utf8(data) and "utf-8" or "euc-jp"
end

-- UTF-8 の文字列にする
---@param data string
---@param encoding? string
---@return string
function M.decode(data, encoding)
  local enc = M.detect_encoding(data, encoding)
  if enc == "utf-8" then
    return (data:gsub("^\239\187\191", ""))
  end
  local text = vim.iconv(data, enc, "utf-8")
  if text == nil or (text == "" and #data > 0) then
    error(("cannot convert from %s"):format(enc), 0)
  end
  return text
end

-- "/a/[b/c]/d/" を { "a", "[b/c]", "d" } に分ける（ブロックは中に "/" があっても 1 つにする）。
-- 最後の "/" のあとの空文字や空白のみのトークンは無視する
---@param value string
---@return string[]
function M.split_candidates(value)
  local out = {}
  local i = 1
  local len = #value
  while i <= len do
    if value:byte(i) == 47 then -- '/'
      i = i + 1
      if value:sub(i):match("^%s*$") then
        break
      end
    else
      local a, b = value:find("^%[[^%]]+%]", i)
      if not a then
        a, b = value:find("^[^/]+", i)
      end
      if not a then
        break
      end
      local tok = value:sub(a, b)
      if b < len or not tok:match("^%s*$") then
        out[#out + 1] = tok
      end
      i = b + 1
    end
  end
  return out
end

-- 辞書の本文を {okuriari = {[読み] = "/候補/…/"}, okurinasi = {...}} に分ける。
-- 同じ読みが 2 回出てきたら先のものを使う。tick は一定の間隔で呼ぶ（コルーチンで譲るため）
---@param text string
---@param tick? fun()
function M.parse(text, tick)
  tick = tick or noop
  local maps = { okuriari = {}, okurinasi = {} }
  local cur
  local pos, len, n = 1, #text, 0
  while pos <= len do
    local nl = text:find("\n", pos, true) or (len + 1)
    local e = nl - 1
    if e >= pos and text:byte(e) == 13 then -- "\r\n"
      e = e - 1
    end
    local line = text:sub(pos, e)
    pos = nl + 1
    if line == M.OKURI_ARI_MARKER then
      cur = maps.okuriari
    elseif line == M.OKURI_NASI_MARKER then
      cur = maps.okurinasi
    elseif cur and line ~= "" and line:sub(1, 2) ~= ";;" then
      local sp = line:find(" ", 1, true)
      if sp and sp > 1 then
        local key = line:sub(1, sp - 1)
        if cur[key] == nil then
          cur[key] = line:sub(sp + 1):gsub("%s+$", "")
        end
      end
    end
    n = n + 1
    if n % 4096 == 0 then
      tick()
    end
  end
  return maps
end

-- バイト順にソートした読みの配列。先頭の 3 バイト（かなの 1 文字）で分けてからソートし、途中で譲れるようにする
---@param map table<string, any>
---@param tick? fun()
---@return string[]
function M.sorted_keys(map, tick)
  tick = tick or noop
  local buckets, order = {}, {}
  local n = 0
  for k in pairs(map) do
    local p = k:sub(1, 3)
    local b = buckets[p]
    if not b then
      b = {}
      buckets[p] = b
      order[#order + 1] = p
    end
    b[#b + 1] = k
    n = n + 1
    if n % 8192 == 0 then
      tick()
    end
  end
  table.sort(order)
  local out = {}
  for _, p in ipairs(order) do
    local b = buckets[p]
    table.sort(b)
    for i = 1, #b do
      out[#out + 1] = b[i]
    end
    tick()
  end
  return out
end

---@class skkeleton.MemoryDictionary
---@field maps table<string, table<string, string|string[]>>
local Memory = {}
Memory.__index = Memory
M.Memory = Memory

-- maps の値は "/候補/…/" の文字列か、候補の配列
function Memory.new(maps)
  maps = maps or {}
  return setmetatable({ maps = { okuriari = maps.okuriari or {}, okurinasi = maps.okurinasi or {} } }, Memory)
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@return string[]
function Memory:get_henkan_result(kind, word)
  local v = self.maps[kind][word]
  if v == nil then
    return {}
  end
  if type(v) == "string" then
    return M.split_candidates(v)
  end
  return vim.list_slice(v)
end

-- 前方一致する読みを、バイト順に limit 件まで。{ { 読み, 候補の配列 }, ... }
---@param kind "okuriari"|"okurinasi"
---@param prefix string
---@param limit? integer
function Memory:get_prefix(kind, prefix, limit)
  local hits = {}
  for k in pairs(self.maps[kind]) do
    if vim.startswith(k, prefix) then
      hits[#hits + 1] = k
    end
  end
  table.sort(hits)
  local out = {}
  for i = 1, math.min(#hits, limit or #hits) do
    out[i] = { hits[i], self:get_henkan_result(kind, hits[i]) }
  end
  return out
end

function Memory:close() end

-- upstream の skk_dictionary の loadJson と同じ形の JSON（okuri_ari / okuri_nasi が 読み → 候補の配列）
---@param path string
function M.load_json(path)
  local data = M.read_file(path)
  local ok, jisyo = pcall(vim.json.decode, data)
  if not ok or type(jisyo) ~= "table" then
    error(("invalid JSON dictionary: %s"):format(path), 0)
  end
  if jisyo.okuri_ari == nil and jisyo.okuri_nasi == nil then
    error(("invalid JSON dictionary (both okuri_ari and okuri_nasi are missing): %s"):format(path), 0)
  end
  local maps = {}
  for json_key, kind in pairs({ okuri_ari = "okuriari", okuri_nasi = "okurinasi" }) do
    local entries = jisyo[json_key]
    if entries == nil then
      maps[kind] = {}
    elseif type(entries) ~= "table" then
      error(("invalid JSON dictionary (%s is not an object): %s"):format(json_key, path), 0)
    else
      maps[kind] = {}
      for k, v in pairs(entries) do
        if type(v) ~= "table" then
          error(("invalid JSON dictionary (%s.%s is not an array): %s"):format(json_key, k, path), 0)
        end
        maps[kind][k] = v
      end
    end
  end
  return Memory.new(maps)
end

-- yaml と msgpack の辞書は v1 では扱わない
---@param path string
function M.check_supported(path)
  local lower = path:lower()
  if lower:match("%.ya?ml$") or lower:match("%.mpk$") then
    error(("unsupported dictionary format (yaml and msgpack are not supported): %s"):format(path), 0)
  end
end

-- SKK 形式のファイルをメモリに読む（DB を使わないとき用）。.json は JSON として読む
---@param path string
---@param encoding? string
function M.load_memory(path, encoding)
  M.check_supported(path)
  if path:lower():match("%.json$") then
    return M.load_json(path)
  end
  local data = M.read_file(path)
  return Memory.new(M.parse(M.decode(data, encoding)))
end

return M

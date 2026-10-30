-- Ported from skkeleton (denops/skkeleton/kana.ts, kana/type.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua. The kana table is a trie.
local M = {}

-- かなテーブルの結果は { かな, 次の feed } か、function/ の関数
---@alias skkeleton.KanaResult string[]|fun(ctx: table, char: string)

-- 前方一致の件数と完全一致の結果を、キーの長さに比例する時間で引ける trie
---@class skkeleton.KanaTable
---@field root table
---@field map table<string, skkeleton.KanaResult>
local KanaTable = {}
KanaTable.__index = KanaTable
M.KanaTable = KanaTable

-- entries は { { from, result }, ... }。同じ from が複数あれば先のものを使う
---@param entries { [1]: string, [2]: skkeleton.KanaResult }[]
---@return skkeleton.KanaTable
function KanaTable.new(entries)
  local self = setmetatable({ root = { count = 0, children = {} }, map = {} }, KanaTable)
  for _, e in ipairs(entries) do
    self:insert(e[1], e[2])
  end
  return self
end

function KanaTable:insert(from, result)
  if self.map[from] ~= nil then
    return
  end
  self.map[from] = result
  local node = self.root
  node.count = node.count + 1
  for i = 1, #from do
    local b = from:byte(i)
    local child = node.children[b]
    if not child then
      child = { count = 0, children = {} }
      node.children[b] = child
    end
    child.count = child.count + 1
    node = child
  end
  node.result = result
end

-- prefix に前方一致するキーの件数（node.count）と、完全一致の結果（node.result）。なければ nil
---@param prefix string
---@return { count: integer, result: skkeleton.KanaResult? }?
function KanaTable:node(prefix)
  local node = self.root
  for i = 1, #prefix do
    node = node.children[prefix:byte(i)]
    if not node then
      return nil
    end
  end
  if node.count == 0 then
    return nil
  end
  return node
end

---@param from string
---@return skkeleton.KanaResult?
function KanaTable:find(from)
  return self.map[from]
end

-- pred(from, result) が真のものだけの新しいテーブル
---@param pred fun(from: string, result: skkeleton.KanaResult): boolean
---@return skkeleton.KanaTable
function KanaTable:filter(pred)
  local entries = {}
  for from, result in pairs(self.map) do
    if pred(from, result) then
      entries[#entries + 1] = { from, result }
    end
  end
  return KanaTable.new(entries)
end

-- 全エントリ（順不同）
---@return fun(): string?, skkeleton.KanaResult?
function KanaTable:entries()
  return pairs(self.map)
end

function KanaTable:count()
  return self.root.count
end

local tables ---@type table<string, skkeleton.KanaTable>?

local function get_tables()
  if not tables then
    tables = {
      rom = require("skkeleton.kana.rom_hira").new(),
      zen = require("skkeleton.kana.rom_zen").new(),
    }
  end
  return tables
end

M.current_name = "rom"

---@param name string
function M.set_current(name)
  M.current_name = name
end

---@param name? string
---@return skkeleton.KanaTable
function M.get_table(name)
  name = name or M.current_name
  local t = get_tables()[name]
  if not t then
    error("undefined table: " .. name, 0)
  end
  return t
end

-- 文字列は関数の登録名、配列は { かな, feed }、false/nil は削除（nil を返す）
local function as_kana_result(result)
  local t = type(result)
  if t == "string" then
    local fn = require("skkeleton.function").functions[result]
    if not fn then
      error("function not found: " .. result, 0)
    end
    return fn
  elseif t == "table" and #result >= 1 then
    for _, v in ipairs(result) do
      if type(v) ~= "string" then
        error("Illegal result: " .. vim.inspect(result), 0)
      end
    end
    return { result[1], result[2] or "" }
  elseif not result or result == vim.NIL then
    return nil
  end
  error("Illegal result: " .. vim.inspect(result), 0)
end

-- name のテーブルに entries を足す。同じキーは足したほうが優先で、結果が nil のものは削除になる
-- entries は { { from, result|nil }, ... }
local function inject(name, entries, create)
  local t = get_tables()
  local old = t[name]
  if not old and not create then
    error(("table %s is not found."):format(name), 0)
  end
  local merged = KanaTable.new({})
  local seen = {}
  for _, e in ipairs(entries) do
    if not seen[e[1]] then
      seen[e[1]] = true
      if e[2] ~= nil then
        merged:insert(e[1], e[2])
      end
    end
  end
  if old then
    for from, result in old:entries() do
      if not seen[from] then
        merged:insert(from, result)
      end
    end
  end
  t[name] = merged
end

-- 大文字のキーは <s-x> に、文字列の結果は関数の登録名として解決する
---@param name string
---@param raw table<string, any>
---@param create? boolean
function M.register(name, raw, create)
  if type(raw) ~= "table" then
    error("kana table must be a table", 0)
  end
  local entries = {}
  for kana, result in pairs(raw) do
    local lower = kana:lower()
    if kana ~= lower then
      kana = "<s-" .. lower .. ">"
    end
    entries[#entries + 1] = { kana, as_kana_result(result) }
  end
  inject(name, entries, create)
end

local function utf8_valid(s)
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = 0
    if c < 0x80 then
      len = 1
    elseif c >= 0xc2 and c < 0xe0 then
      len = 2
    elseif c >= 0xe0 and c < 0xf0 then
      len = 3
    elseif c >= 0xf0 and c < 0xf5 then
      len = 4
    end
    if len == 0 or i + len - 1 > n then
      return false
    end
    for j = i + 1, i + len - 1 do
      local b = s:byte(j)
      if b < 0x80 or b > 0xbf then
        return false
      end
    end
    i = i + len
  end
  return true
end

local function read_file(path, encoding)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  if encoding == nil or encoding == "" then
    -- 指定がなければ UTF-8 として読め、だめなら EUC-JP とみなす
    encoding = utf8_valid(s) and "utf-8" or "euc-jp"
  end
  local enc = encoding:lower()
  if enc ~= "utf-8" and enc ~= "utf8" then
    s = vim.iconv(s, enc, "utf-8") or s
  end
  return s
end

-- "from,to" の行のファイルを読む。# から始まる行と空行は読み飛ばす
local function parse_file(path, encoding)
  local entries = {}
  for line in (read_file(path, encoding) .. "\n"):gmatch("(.-)\r?\n") do
    if line:sub(1, 1) ~= "#" and not line:match("^%s*$") then
      local from, result = line:match("^([^,]*),?([^,]*)")
      entries[#entries + 1] = { from, { result, "" } }
    end
  end
  return entries
end

---@param name string
---@param path string
---@param encoding? string
---@param create? boolean
function M.load_file(name, path, encoding, create)
  inject(name, parse_file(path, encoding), create)
end

-- globalKanaTableFiles の読み込み。"rom" に足す
---@param files (string|string[])[]
function M.load_files(files)
  local entries = {}
  for _, v in ipairs(files) do
    local path, encoding
    if type(v) == "table" then
      path, encoding = v[1], v[2]
    else
      path = v
    end
    vim.list_extend(entries, parse_file(path, encoding))
  end
  if #entries > 0 then
    inject("rom", entries)
  end
end

-- テスト用。組み込みのテーブルに戻す
function M.reset()
  tables = nil
  M.current_name = "rom"
end

return M

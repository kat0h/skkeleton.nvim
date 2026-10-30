-- Ported from skkeleton (denops/skkeleton/dictionary.ts: NumberConvertWrapper, convertNumber)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua. The numeral conversions are written from the notation rules.
--
-- SKK の数値変換。見出し語の数字を "#" に置き換えて辞書を引き、候補の "#0"〜"#9" を元の数字で埋める。
--   #0 そのまま  #1 全角  #2 漢数字（位取りなし）  #3 漢数字（位取りあり）
--   #4 #6 #7 そのまま（未対応）  #5 大字  #8 ローマ数字  #9 棋譜（"３四" のような 2 桁）
local util = require("skkeleton.util")

local M = {}

local ZENKAKU = { "０", "１", "２", "３", "４", "５", "６", "７", "８", "９" }
local KANJI_MODERN = { "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九" }

-- 先頭の 0 を落とした 10 進の文字列（upstream の parseInt(e).toString() に当たる）
---@param digits string
local function strip(digits)
  local s = digits:gsub("^0+", "")
  return s == "" and "0" or s
end

---@param digits string
function M.to_zenkaku(digits)
  return (strip(digits):gsub("%d", function(c)
    return ZENKAKU[tonumber(c) + 1]
  end))
end

---@param digits string
function M.to_kanji_modern(digits)
  return (strip(digits):gsub("%d", function(c)
    return KANJI_MODERN[tonumber(c) + 1]
  end))
end

-- 棋譜: 1〜9 の 2 桁だけ "３四" のように変える。それ以外はそのまま
---@param digits string
function M.to_kifu(digits)
  local s = strip(digits)
  local x, y = s:match("^([1-9])([1-9])$")
  if x then
    return ZENKAKU[tonumber(x) + 1] .. KANJI_MODERN[tonumber(y) + 1]
  end
  return s
end

local UNITS = { "", "万", "億", "兆", "京", "垓", "秭", "穣", "溝", "澗", "正", "載", "極" }

-- 4 桁以下の数（0〜9999）を千・百・十で位取りする。1 は千・百・十の前では書かない
---@param g integer
local function group_kanji(g)
  local out = {}
  local places = { { 1000, "千" }, { 100, "百" }, { 10, "十" } }
  for _, p in ipairs(places) do
    local d = math.floor(g / p[1]) % 10
    if d > 0 then
      out[#out + 1] = (d > 1 and KANJI_MODERN[d + 1] or "") .. p[2]
    end
  end
  local ones = g % 10
  if ones > 0 then
    out[#out + 1] = KANJI_MODERN[ones + 1]
  end
  return table.concat(out)
end

-- 漢数字（位取りあり）: 101 → 百一、10000 → 一万、110000 → 十一万。万・億・兆の前の 1 は書く
---@param digits string
function M.to_kanji_classic(digits)
  local s = strip(digits)
  if not s:match("^%d+$") then
    return digits
  end
  if s == "0" then
    return "〇"
  end
  local ngroups = math.ceil(#s / 4)
  if ngroups > #UNITS then
    return s
  end
  local out = {}
  for gi = ngroups, 1, -1 do
    local to = #s - (gi - 1) * 4
    local g = tonumber(s:sub(math.max(1, to - 3), to))
    if g > 0 then
      local unit = UNITS[gi]
      out[#out + 1] = (gi > 1 and g == 1) and ("一" .. unit) or (group_kanji(g) .. unit)
    end
  end
  return table.concat(out)
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
  ["〇"] = "零",
  ["十"] = "拾",
  ["百"] = "佰",
  ["千"] = "阡",
  ["万"] = "萬",
}

-- 大字: 漢数字（位取りあり）の字を置き換える
---@param digits string
function M.to_daiji(digits)
  local out = {}
  for _, ch in ipairs(util.chars(M.to_kanji_classic(digits))) do
    out[#out + 1] = DAIJI[ch] or ch
  end
  return table.concat(out)
end

local ROMAN = {
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
}

-- ローマ数字: 千の位は M を並べる（4000 は MMMM）。0 と大きすぎる数（10 万以上）は変換しない
---@param digits string
function M.to_roman(digits)
  local s = strip(digits)
  if s == "0" or #s > 5 then
    return s
  end
  local n = tonumber(s)
  local out = { ("M"):rep(math.floor(n / 1000)) }
  n = n % 1000
  for _, r in ipairs(ROMAN) do
    while n >= r[1] do
      out[#out + 1] = r[2]
      n = n - r[1]
    end
  end
  return table.concat(out)
end

-- JavaScript の String.prototype.split(/(pat)/g) と同じ。マッチした部分も含めて { 地, マッチ, 地, ..., 地 } を返す
---@param s string
---@param pat string
local function split_with_captures(s, pat)
  local out, pos = {}, 1
  while true do
    local a, b = s:find(pat, pos)
    if not a then
      out[#out + 1] = s:sub(pos)
      return out
    end
    out[#out + 1] = s:sub(pos, a - 1)
    out[#out + 1] = s:sub(a, b)
    pos = b + 1
  end
end

local CONVERTERS = {
  ["#9"] = M.to_kifu,
  ["#1"] = M.to_zenkaku,
  ["#2"] = M.to_kanji_modern,
  ["#3"] = M.to_kanji_classic,
  ["#8"] = M.to_roman,
  ["#5"] = M.to_daiji,
}

-- 候補 pattern のプレースホルダ（#[0-9] または英数字直後でない '#'）と地の文に分ける
---@param pattern string
---@return string[]
local function split_pattern(pattern)
  local out = {}
  local pos = 1
  local len = #pattern
  local last_pos = 1
  while pos <= len do
    local hash = pattern:find("#", pos, true)
    if not hash then
      break
    end
    local next_ch = pattern:sub(hash + 1, hash + 1)
    local is_digit = next_ch:match("^[0-9]$") ~= nil
    local prev_ch = hash > 1 and pattern:sub(hash - 1, hash - 1) or ""
    local is_alphanumeric = prev_ch:match("^%w$") ~= nil

    if is_digit then
      out[#out + 1] = pattern:sub(last_pos, hash - 1)
      out[#out + 1] = pattern:sub(hash, hash + 1)
      pos = hash + 2
      last_pos = pos
    elseif not is_alphanumeric then
      out[#out + 1] = pattern:sub(last_pos, hash - 1)
      out[#out + 1] = "#"
      pos = hash + 1
      last_pos = pos
    else
      -- "C#" などのリテラル '#'
      pos = hash + 1
    end
  end
  out[#out + 1] = pattern:sub(last_pos)
  return out
end

-- 候補 pattern の "#N" を、見出し語 entry の数字で置き換える
---@param pattern string  例: "#3番"
---@param entry string  例: "101ばん"
---@return string
function M.convert_number(pattern, entry)
  local p = split_pattern(pattern)
  local e = split_with_captures(entry, "[0-9]+")
  local out = {}
  for i = 1, #p do
    local k = p[i]
    local v = e[i]
    local conv = CONVERTERS[k]
    if conv and v and v:match("^[0-9]+$") then
      out[i] = conv(v)
    elseif v and (k == "#" or k == "#0" or k == "#4" or k == "#6" or k == "#7") then
      out[i] = v
    else
      out[i] = k
    end
  end
  return table.concat(out)
end

---@class skkeleton.NumberConvertWrapper
---@field inner table
local Wrapper = {}
Wrapper.__index = Wrapper

-- 辞書を数値変換つきにする。数字を含む語は、数字を "#" にした語の候補を変換して返す
---@param dict table
function M.wrap(dict)
  return setmetatable({ inner = dict }, Wrapper)
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@return string[]
function Wrapper:get_henkan_result(kind, word)
  local real_word = word:gsub("[0-9]+", "#")
  local candidates = self.inner:get_henkan_result(kind, real_word)
  if word == real_word then
    return candidates
  end
  -- 数字のままの語の候補が先
  local merged = self.inner:get_henkan_result(kind, word)
  vim.list_extend(merged, candidates)
  for i, c in ipairs(merged) do
    merged[i] = M.convert_number(c, word)
  end
  return merged
end

function Wrapper:get_prefix(kind, prefix, limit)
  return self.inner:get_prefix(kind, prefix, limit)
end

function Wrapper:close()
  if self.inner.close then
    self.inner:close()
  end
end

return M

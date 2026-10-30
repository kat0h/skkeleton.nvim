-- Ported from skkeleton (denops/skkeleton/okuri.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local util = require("skkeleton.util")

local M = {}

-- 送り仮名 -> 辞書の見出しに付ける子音
local okuri_table = {}
for consonant, kanas in pairs({
  x = "ぁぃぅぇぉっゃゅょゎゐゑ",
  a = "あ",
  i = "い",
  u = "う",
  e = "え",
  o = "お",
  k = "かきくけこ",
  g = "がぎぐげご",
  s = "さしすせそ",
  z = "ざずぜぞ",
  j = "じ",
  t = "たちつてと",
  d = "だぢづでど",
  n = "なにぬねのん",
  h = "はひふへほ",
  b = "ばびぶべぼ",
  p = "ぱぴぷぺぽ",
  m = "まみむめも",
  y = "やゆよ",
  r = "らりるれろ",
  w = "わを",
  v = "ゔ",
}) do
  for _, ch in ipairs(util.chars(kanas)) do
    okuri_table[ch] = consonant
  end
end

-- 見出し語に送り仮名の子音を付ける
---@param word string
---@param okuri string
---@return string
function M.get_okuri_str(word, okuri)
  -- 「送っ」のような段階で変換する際は、タ行の入力がされているように振る舞う
  -- libskk などはこの動作を行う
  -- 根拠として、促音のほとんどがタ行という調査結果が挙げられる
  -- https://blog.atusy.net/2023/08/01/skk-azik-and-sokuon-okuri/
  if okuri == "っ" then
    return word .. "t"
  end
  local first
  for _, ch in ipairs(util.chars(okuri)) do
    if ch ~= "っ" then
      first = ch
      break
    end
  end
  return word .. (okuri_table[first or ""] or "")
end

return M

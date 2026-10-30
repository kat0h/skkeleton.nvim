-- Ported from skkeleton (denops/skkeleton/notation.ts, autoload/skkeleton/notation.vim)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local M = {}

local function termcodes(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- 実際の文字 -> 表記。同じ文字を指す表記が複数あるときは、先に書いたものを使う
local key_to_notation = {
  ["\n"] = "<nl>",
  ["\r"] = "<cr>",
  ["\b"] = "<bs>",
  ["\27"] = "<esc>",
  [" "] = "<space>",
  ["\t"] = "<tab>",
  ["<"] = "<lt>",
  ["\\"] = "<bslash>",
  ["|"] = "<bar>",
}
-- 表記 -> 実際の文字（to_key のキャッシュも兼ねる）
local notation_to_key = {}

local function add_key_notation(name)
  local key = termcodes(name)
  if key_to_notation[key] == nil then
    key_to_notation[key] = name
  end
  notation_to_key[name] = key
end

local function init()
  for i = 1, 26 do
    local ch = string.char(i)
    if key_to_notation[ch] == nil then
      key_to_notation[ch] = "<c-" .. string.char(96 + i) .. ">"
    end
  end
  local names = {
    "<nul>",
    "<s-tab>",
    "<ff>",
    "<return>",
    "<s-space>",
    "<c-space>",
    "<del>",
    "<csi>",
    "<xcsi>",
    "<eol>",
    "<ignore>",
    "<nop>",
    "<up>",
    "<down>",
    "<left>",
    "<right>",
    "<s-up>",
    "<s-down>",
    "<s-left>",
    "<s-right>",
    "<c-left>",
    "<c-right>",
    "<help>",
    "<undo>",
    "<insert>",
    "<home>",
    "<end>",
    "<pageup>",
    "<pagedown>",
    "<kup>",
    "<kdown>",
    "<kleft>",
    "<kright>",
    "<khome>",
    "<kend>",
    "<korigin>",
    "<kpageup>",
    "<kpagedown>",
    "<kdel>",
    "<kplus>",
    "<kminus>",
    "<kmultiply>",
    "<kdivide>",
    "<kpoint>",
    "<kcomma>",
    "<kequal>",
    "<kenter>",
    "<bs>",
    "<tab>",
    "<nl>",
    "<cr>",
    "<esc>",
    "<space>",
    "<lt>",
    "<bslash>",
    "<bar>",
  }
  for _, name in ipairs(names) do
    add_key_notation(name)
  end
  for i = 1, 12 do
    add_key_notation("<f" .. i .. ">")
    add_key_notation("<s-f" .. i .. ">")
  end
  for i = 0, 9 do
    add_key_notation("<k" .. i .. ">")
  end
  for i = 0, 25 do
    local c = string.char(97 + i)
    for _, prefix in ipairs({ "s", "c", "m", "a", "d" }) do
      add_key_notation("<" .. prefix .. "-" .. c .. ">")
    end
  end
  -- <s-a> は "A" になる。大文字はそのまま使うので、A -> <s-a> の変換は消す
  for c = 65, 90 do
    key_to_notation[string.char(c)] = nil
  end
end

init()

-- キーの表記を正規化する（"<C-j>" -> "<nl>"、"<BS>" -> "<bs>"、"A" -> "A"）
---@param lhs string
---@return string
function M.normalize(lhs)
  local key = lhs
  if #key > 1 and key:sub(1, 1) == "<" then
    key = termcodes(key)
  end
  if not key:match("^[A-Z]$") then
    key = key_to_notation[key] or key
  end
  if #key ~= 1 then
    key = key:lower()
  end
  return key
end

-- 表記から実際の文字へ（"<space>" -> " "、"<lt>" -> "<"）。表記でなければそのまま返す
---@param notation string
---@return string
function M.to_key(notation)
  local key = notation_to_key[notation]
  if key == nil then
    if #notation > 1 and notation:sub(1, 1) == "<" then
      key = termcodes(notation)
    else
      key = notation
    end
    notation_to_key[notation] = key
  end
  return key
end

-- 実際の文字から表記へ。対応がなければそのまま返す（大文字も "A" のまま）
---@param key string
---@return string
function M.from_key(key)
  return key_to_notation[key] or key
end

return M

-- Ported from skkeleton (denops/skkeleton/candidate.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local M = {}

-- 注釈（; 以降）を落とし、接頭辞・接尾辞の > を取り除く。
-- 語の中の \073 は ';' に戻す (#49)
---@param candidate string?
---@param affix? "prefix"|"suffix"
---@return string?
function M.modify(candidate, affix)
  if candidate == nil then
    return nil
  end
  local strip = candidate:gsub(";.*", "")
  if affix == "prefix" then
    strip = strip:gsub(">$", "")
  elseif affix == "suffix" then
    strip = strip:gsub("^>", "")
  end
  return (strip:gsub("\\073", ";"))
end

-- 候補文字列から { word, annotation } を取り出す (#49)
---@param cand string?
---@return string? word, string? annotation
function M.pair(cand)
  if cand == nil then
    return nil, nil
  end
  local semi = cand:find(";", 1, true)
  if semi then
    local word = cand:sub(1, semi - 1):gsub("\\073", ";")
    local note = cand:sub(semi + 1)
    return word, note
  end
  return (cand:gsub("\\073", ";")), nil
end

return M

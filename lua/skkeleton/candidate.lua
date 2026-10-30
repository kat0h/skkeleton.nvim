-- Ported from skkeleton (denops/skkeleton/candidate.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local M = {}

-- 注釈（; 以降）を落とし、接頭辞・接尾辞の > を取り除く
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
  return strip
end

return M

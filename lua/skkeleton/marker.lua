-- 辞書登録の入力欄の取り消しの印と、設定したマーカーを見分ける。
-- 入力値の判定と履歴の掃除を、ここ 1 か所にまとめる。
local options = require("skkeleton.config").options

local M = {}

-- 辞書登録の入力欄で <Esc> / <C-g> を押したときに返る取り消しの印
M.CANCEL = "__skkeleton_return__"

-- 取り消しの印か、設定した変換のマーカーを含むか
---@param s any
---@return boolean
function M.contains_marker(s)
  if type(s) ~= "string" or s == "" then
    return false
  end
  if s:find(M.CANCEL, 1, true) then
    return true
  end
  for _, marker in ipairs({ options.markerHenkan, options.markerHenkanSelect }) do
    if type(marker) == "string" and marker ~= "" and s:find(marker, 1, true) then
      return true
    end
  end
  return false
end

-- 履歴の最後の項目がマーカーを含むなら消す
---@param hist_type string
function M.drop_marker_history(hist_type)
  local ok, item = pcall(vim.fn.histget, hist_type, -1)
  if ok and M.contains_marker(item) then
    pcall(vim.fn.histdel, hist_type, -1)
  end
end

return M

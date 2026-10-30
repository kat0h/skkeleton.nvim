-- skkeleton.nvim: 補完候補の 3 段階ソート
-- 1. 読みの長さ（短い順）
-- 2. ユーザーの選択頻度ランク（高い順）
-- 3. 辞書の並び順（出現順）
local M = {}

---@param completion_result { [1]: string, [2]: string[] }[]
---@param ranks? table<string, integer>
---@return { kana: string, word: string, rank: integer }[]
function M.sort_completions(completion_result, ranks)
  ranks = ranks or {}
  local items = {}
  local seen = {}
  local dict_order = 0

  for _, entry in ipairs(completion_result or {}) do
    local kana = entry[1]
    local candidates = entry[2] or {}
    local kana_len = vim.fn.strchars(kana)
    for _, word in ipairs(candidates) do
      local key = kana .. "\0" .. word
      if not seen[key] then
        seen[key] = true
        dict_order = dict_order + 1
        local user_rank = ranks[word] or (word:find(";", 1, true) and ranks[word:match("^([^;]*)")]) or 0
        items[#items + 1] = {
          kana = kana,
          word = word,
          rank = user_rank,
          kana_len = kana_len,
          dict_order = dict_order,
        }
      end
    end
  end

  table.sort(items, function(a, b)
    if a.kana_len ~= b.kana_len then
      return a.kana_len < b.kana_len
    end
    if a.rank ~= b.rank then
      return a.rank > b.rank
    end
    return a.dict_order < b.dict_order
  end)

  return items
end

return M

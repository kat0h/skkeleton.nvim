-- skkeleton.nvim: 補完候補の並べ替え
-- denops 版（denops/@ddc-sources/skkeleton/main.ts）に合わせて、選択履歴のランクの大きい順に
-- 並べる。rank がない候補は読みの辞書順に並べる (#159)
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
    for _, word in ipairs(candidates) do
      local key = kana .. "\0" .. word
      if not seen[key] then
        seen[key] = true
        dict_order = dict_order + 1
        local pure_word = word:find(";", 1, true) and word:match("^([^;]*)") or word
        local user_rank = ranks[word] or ranks[pure_word] or ranks[pure_word:gsub("\\073", ";")]
        items[#items + 1] = {
          kana = kana,
          word = word,
          rank = user_rank,
          dict_order = dict_order,
        }
      end
    end
  end

  -- rank がない候補は、読みの辞書順に後ろから -1, -2, ... と振る
  local unranked = {}
  for _, item in ipairs(items) do
    if item.rank == nil then
      unranked[#unranked + 1] = item
    end
  end
  table.sort(unranked, function(a, b)
    if a.kana ~= b.kana then
      return a.kana < b.kana
    end
    return a.dict_order < b.dict_order
  end)
  for i, item in ipairs(unranked) do
    item.rank = -i
  end

  table.sort(items, function(a, b)
    if a.rank ~= b.rank then
      return a.rank > b.rank
    end
    return a.dict_order < b.dict_order
  end)

  return items
end

return M

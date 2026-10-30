-- Ported from skkeleton (denops/@ddc-sources/skkeleton/main.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua as a blink.cmp source.
--
-- skkeleton.nvim: blink.cmp の source。
-- 使い方は providers = { skkeleton = { name = "skkeleton", module = "skkeleton.completion.blink" } }。
local completion = require("skkeleton.completion")

---@class skkeleton.BlinkSource: blink.cmp.Source
local source = {}
source.__index = source

local TEXT_KIND = 1

function source.new(opts)
  return setmetatable({ opts = opts or {} }, source)
end

-- ▽ の入力中だけ候補を返す
function source:enabled()
  return completion.options.enabled and completion.is_pending()
end

---@param ctx blink.cmp.Context
---@param callback fun(response: blink.cmp.CompletionResponse)
function source:get_completions(ctx, callback)
  local ok, result = pcall(function()
    return require("skkeleton").get_completion_result()
  end)
  local items = {}
  if ok and completion.is_pending() then
    -- pre-edit はバッファに無いので、blink のキーワードはカーソルの前の文字（ふつうは空）。
    -- 候補の filterText をそれに揃えて、絞り込みで落とされないようにする
    local keyword = ctx.get_keyword()
    local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
    -- 何も挿入しない編集にして、auto_insert の試し挿入でバッファが変わらないようにする。確定は execute が行う
    local range = { start = { line = row, character = col }, ["end"] = { line = row, character = col } }
    local skkeleton = require("skkeleton")
    local sort = require("skkeleton.completion.sort")
    local sorted = sort.sort_completions(result, skkeleton.get_completion_ranks())
    for idx, entry in ipairs(sorted) do
      local kana = entry.kana
      local cand = entry.word
      local word, annotation = cand:match("^([^;]*);(.*)$")
      word = word or cand
      local item = {
        label = word,
        labelDetails = { description = kana },
        kind = TEXT_KIND,
        filterText = keyword,
        sortText = ("%06d"):format(idx),
        textEdit = { newText = "", range = range },
        data = { skkeleton = true, kana = kana, word = cand },
      }
      if annotation and annotation ~= "" then
        item.documentation = { kind = "plaintext", value = annotation }
      end
      items[#items + 1] = item
    end
  end
  -- 絞り込みは skkeleton が済ませているので、blink には毎回取り直させる
  callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
  return function() end
end

-- 選んだ語で確定する。blink の挿入は使わない
function source:execute(_, item, callback)
  local data = item.data or {}
  if data.skkeleton and data.kana and data.word then
    require("skkeleton").complete(data.kana, data.word)
  end
  if callback then
    callback()
  end
end

return source

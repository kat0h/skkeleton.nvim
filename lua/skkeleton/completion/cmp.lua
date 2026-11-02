-- skkeleton.nvim: nvim-cmp の source。
local completion = require("skkeleton.completion")

---@class skkeleton.CmpSource
local source = {}
source.__index = source

function source.new(opts)
  return setmetatable({ opts = opts or {} }, source)
end

function source:is_available()
  return completion.options.enabled and completion.can_complete()
end

function source:get_PositionEncodingKind()
  return "utf-8"
end

function source:get_trigger_characters()
  return {}
end

function source:get_keyword_pattern()
  return [[\%(\k\|[^\x00-\x7f]\)\+]]
end

---@param params table
---@param callback fun(response: table)
function source:complete(params, callback)
  if not self:is_available() then
    callback({ items = {}, isIncomplete = true })
    return
  end
  local common_items = completion.items()
  local items = {}
  for idx, entry in ipairs(common_items) do
    local item = {
      label = entry.word,
      detail = entry.kana,
      filterText = entry.word,
      sortText = string.format("%06d", idx),
      dup = 1,
      data = { skkeleton = true, kana = entry.kana, word = entry.raw },
    }
    if entry.annotation then
      item.documentation = {
        kind = "plaintext",
        value = entry.annotation,
      }
    end
    items[#items + 1] = item
  end
  callback({ items = items, isIncomplete = true })
end

---@param completion_item table
---@param callback? fun(completion_item?: table)
function source:execute(completion_item, callback)
  local data = completion_item.data or completion_item.user_data or {}
  if data.kana and data.word then
    require("skkeleton").complete_callback(data.kana, data.word)
  end
  if callback then
    callback(completion_item)
  end
end

local M = {}
M.new = source.new

function M.register()
  local ok, cmp = pcall(require, "cmp")
  if ok and cmp and cmp.register_source then
    pcall(cmp.register_source, "skkeleton", source.new())
  end
end

return setmetatable(M, {
  __index = source,
})

-- Ported from skkeleton (denops/skkeleton/state.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local candidate = require("skkeleton.candidate")
local options = require("skkeleton.config").options
local util = require("skkeleton.util")

local kana = util.lazy("skkeleton.kana")

local M = {}

---@alias skkeleton.HenkanType "okuriari"|"okurinasi"

---@class skkeleton.InputState
---@field type "input"
---@field mode "direct"|skkeleton.HenkanType
---@field affix? "prefix"|"suffix"
---@field direct_input boolean 真なら大文字が打たれても変換ポイントを切らない（abbrev に必要）
---@field table skkeleton.KanaTable
---@field converter? fun(s: string): string
---@field feed string
---@field henkan_feed string
---@field okuri_feed string
---@field previous_feed boolean かなフィードが変換ポイントの前にあるかどうか。「察し」などを変換するのに必要

---@class skkeleton.HenkanState: skkeleton.InputState
---@field type "henkan"
---@field word string
---@field candidates string[]
---@field candidate_index integer 0 起点（upstream と同じ数え方。-1 は未選択）

---@class skkeleton.EscapeState
---@field type "escape"

---@alias skkeleton.State skkeleton.InputState|skkeleton.HenkanState|skkeleton.EscapeState

-- 初期化で戻すフィールド。converter と affix は nil に戻る
local fields = {
  "type",
  "mode",
  "affix",
  "direct_input",
  "table",
  "converter",
  "feed",
  "henkan_feed",
  "okuri_feed",
  "previous_feed",
}

local function default_input_state()
  return {
    type = "input",
    mode = "direct",
    direct_input = false,
    table = kana.get_table(),
    feed = "",
    henkan_feed = "",
    okuri_feed = "",
    previous_feed = false,
  }
end

-- st を入力の初期状態に戻す。ignore に挙げたキーは今の値を残す
---@param st table
---@param ignore? string[]
---@return skkeleton.InputState
function M.initialize(st, ignore)
  local ignored = {}
  for _, key in ipairs(ignore or {}) do
    ignored[key] = st[key]
  end
  local def = default_input_state()
  for _, key in ipairs(fields) do
    st[key] = def[key]
  end
  for key, value in pairs(ignored) do
    st[key] = value
  end
  return st
end

---@param st skkeleton.InputState
local function input_state_to_string(st)
  local ret = ""
  if st.mode ~= "direct" then
    ret = options.markerHenkan .. st.henkan_feed
  end
  if st.mode == "okuriari" then
    if st.previous_feed then
      return ret .. st.feed .. "*"
    end
    ret = ret .. "*" .. st.okuri_feed
  end
  if st.converter then
    ret = st.converter(ret)
  end
  return ret .. st.feed
end

---@param st skkeleton.HenkanState
---@return string
function M.henkan_state_to_string(st)
  local cand = candidate.modify(st.candidates[st.candidate_index + 1], st.affix) or "error"
  local okuri = st.okuri_feed
  if st.converter then
    okuri = st.converter(okuri)
  end
  return options.markerHenkanSelect .. cand .. okuri
end

---@param st skkeleton.State
---@return string
function M.to_string(st)
  if st.type == "input" then
    return input_state_to_string(st)
  elseif st.type == "henkan" then
    return M.henkan_state_to_string(st)
  elseif st.type == "escape" then
    return "\27"
  end
  return ""
end

return M

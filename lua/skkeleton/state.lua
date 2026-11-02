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
  st.word = nil
  st.candidates = nil
  st.candidate_index = nil
  return st
end

---@alias skkeleton.SegmentRole "marker"|"body"|"romaji"|"okuri"

---@class skkeleton.Segment
---@field text string
---@field hl skkeleton.SegmentRole

---@param segments skkeleton.Segment[]
---@param text string
---@param hl skkeleton.SegmentRole
local function push_segment(segments, text, hl)
  if text ~= "" then
    segments[#segments + 1] = { text = text, hl = hl }
  end
end

-- input の pre-edit を色の役割つきの断片に分ける。converter はここだけでかける
---@param st skkeleton.InputState
---@return skkeleton.Segment[]
local function input_segments(st)
  local segments = {}
  if st.mode == "direct" then
    push_segment(segments, st.feed, "romaji")
    return segments
  end
  local function convert(s)
    return st.converter and st.converter(s) or s
  end
  push_segment(segments, convert(options.markerHenkan), "marker")
  push_segment(segments, convert(st.henkan_feed), "body")
  if st.mode == "okuriari" then
    if st.previous_feed then
      push_segment(segments, st.feed, "romaji")
      push_segment(segments, "*", "okuri")
    else
      push_segment(segments, convert("*" .. st.okuri_feed), "okuri")
      push_segment(segments, st.feed, "romaji")
    end
  else
    push_segment(segments, st.feed, "romaji")
  end
  return segments
end

-- henkan の pre-edit を色の役割つきの断片に分ける。注釈は render が足す
---@param st skkeleton.HenkanState
---@return skkeleton.Segment[]
local function henkan_segments(st)
  local segments = {}
  local cand = candidate.modify(st.candidates and st.candidates[st.candidate_index + 1], st.affix) or "error"
  push_segment(segments, options.markerHenkanSelect, "marker")
  push_segment(segments, cand, "body")
  push_segment(segments, st.converter and st.converter(st.okuri_feed) or st.okuri_feed, "okuri")
  return segments
end

---@param st skkeleton.State
---@return skkeleton.Segment[]
function M.segments(st)
  if st.type == "input" then
    return input_segments(st)
  elseif st.type == "henkan" then
    return henkan_segments(st)
  elseif st.type == "escape" then
    return { { text = "\27", hl = "body" } }
  end
  return {}
end

---@param st skkeleton.State
---@return string
function M.to_string(st)
  local parts = {}
  for i, segment in ipairs(M.segments(st)) do
    parts[i] = segment.text
  end
  return table.concat(parts)
end

return M

-- Ported from skkeleton (denops/skkeleton/function/input.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local options = require("skkeleton.config").options
local mode = require("skkeleton.mode")
local util = require("skkeleton.util")

local henkan = util.lazy("skkeleton.function.henkan")

local M = {}

-- feed が仮名に変換できる場合は確定
---@param ctx skkeleton.Context
function M.kakutei_feed(ctx)
  if ctx.state.type ~= "input" then
    return
  end
  local state = ctx.state
  local queue_as_kana = state.table:find(state.feed)
  if type(queue_as_kana) == "table" then
    M.kakutei_kana(state, ctx.preedit, queue_as_kana[1], "")
  end
end

---@param state skkeleton.InputState
---@param preedit skkeleton.PreEdit
---@param kana string
---@param feed string
function M.kakutei_kana(state, preedit, kana, feed)
  if state.mode == "direct" then
    if state.converter then
      kana = state.converter(kana)
    end
    preedit:do_kakutei(kana)
  elseif state.mode == "okurinasi" then
    state.henkan_feed = state.henkan_feed .. kana
  elseif state.mode == "okuriari" then
    if feed ~= "" and state.previous_feed then
      state.henkan_feed = state.henkan_feed .. kana
    else
      state.okuri_feed = state.okuri_feed .. kana
    end
    state.previous_feed = false
  end
  state.feed = feed
end

---@param ctx skkeleton.Context
---@param kana string
---@param feed string
local function do_kakutei(ctx, kana, feed)
  local state = ctx.state
  if state.type ~= "input" then
    return
  end
  M.kakutei_kana(state, ctx.preedit, kana, feed)
  if state.mode == "okuriari" and feed == "" then
    if util.last_char(state.okuri_feed) == "っ" then
      -- immediatelyOkuriConvert が有効になっていない場合
      -- 直接入力などで「使った」のように打つ時「つかっ」の段階では変換をしない
      if options.immediatelyOkuriConvert then
        henkan.henkan_first(ctx, "")
      end
    else
      henkan.henkan_first(ctx, "")
    end
  end
end

---@param ctx skkeleton.Context
---@param result skkeleton.KanaResult
---@param feed string
function M.accept_result(ctx, result, feed)
  if type(result) == "table" then
    do_kakutei(ctx, result[1], result[2])
  else
    ctx.state.feed = ""
    result(ctx, feed)
  end
end

---@param ctx skkeleton.Context
---@param char string
function M.kana_input(ctx, char)
  ctx.state.type = "input"
  local state = ctx.state

  local lower = options.lowercaseMap[char] or char:lower()
  if not state.direct_input and char ~= lower then
    local with_shift = "<s-" .. lower .. ">"
    if state.table:node(state.feed .. with_shift) then
      char = with_shift
    else
      M.henkan_point(ctx)
      M.kana_input(ctx, lower)
      return
    end
  end

  local nxt = state.feed .. char
  local node = state.table:node(nxt)
  if node and node.count == 1 and node.result ~= nil then
    -- 正確にマッチした場合はそのまま確定
    M.accept_result(ctx, node.result, nxt)
  elseif node then
    -- テーブルに残余があったら feed に積む
    state.feed = nxt
  elseif state.feed ~= "" then
    -- テーブルとマッチせず feed が存在した場合は
    -- feed を確定し、もう一度 kana_input に通す
    local current = state.table:find(state.feed)
    if current then
      M.accept_result(ctx, current, nxt)
    elseif options.acceptIllegalResult then
      M.kakutei_kana(state, ctx.preedit, state.feed, "")
    else
      state.feed = ""
    end
    M.kana_input(ctx, char)
  else
    -- feed が無い場合(=テーブルに存在しない文字)
    -- そのまま確定してしまう
    M.kakutei_kana(state, ctx.preedit, char, "")
  end
end

---@param ctx skkeleton.Context
function M.henkan_point(ctx)
  if ctx.state.type ~= "input" then
    return
  end
  local state = ctx.state
  local node = state.table:node(state.feed)
  -- 変換対象が空のときは送り仮名モードに移らない
  if state.mode == "okurinasi" and state.henkan_feed == "" then
    return
  end
  if state.mode == "direct" then
    if not node then
      ctx:kakutei(state.feed)
      state.feed = ""
    end
    ctx:kakutei_with_undo_point("")
    state.mode = "okurinasi"
  elseif state.mode == "okurinasi" then
    if state.feed == "" or not node then
      state.feed = ""
    elseif node.result ~= nil then
      if type(node.result) == "table" then
        state.henkan_feed = state.henkan_feed .. node.result[1]
      end
      state.feed = ""
    else
      state.previous_feed = true
    end
    state.mode = "okuriari"
  end
end

---@param ctx skkeleton.Context
function M.delete_char(ctx)
  if ctx.state.type ~= "input" then
    return
  end
  local state = ctx.state
  if state.feed ~= "" then
    state.feed = util.drop_last_char(state.feed)
  elseif state.mode == "okuriari" then
    if state.okuri_feed ~= "" then
      state.okuri_feed = util.drop_last_char(state.okuri_feed)
    else
      state.mode = "okurinasi"
    end
  elseif state.mode == "okurinasi" then
    if state.henkan_feed ~= "" then
      state.henkan_feed = util.drop_last_char(state.henkan_feed)
    else
      mode.initialize_state_with_abbrev(ctx, { "converter" })
    end
  else
    ctx:kakutei("\b")
  end
end

---@param ctx skkeleton.Context
---@param key string
function M.prefix(ctx, key)
  if ctx.state.type ~= "input" then
    return
  end

  local state = ctx.state
  if not state.direct_input and state.henkan_feed ~= "" and (state.mode == "okurinasi" or state.mode == "okuriari") then
    M.accept_result(ctx, { ">", "" }, "")
    ctx.state.affix = "prefix"
    henkan.henkan_first(ctx, key)
    return
  end

  M.kana_input(ctx, key)
end

return M

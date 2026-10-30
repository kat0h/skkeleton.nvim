-- Ported from skkeleton (denops/skkeleton/function/common.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local candidate = require("skkeleton.candidate")
local host = require("skkeleton.host")
local mode = require("skkeleton.mode")
local options = require("skkeleton.config").options
local state = require("skkeleton.state")
local store = require("skkeleton.store")
local util = require("skkeleton.util")

local input = util.lazy("skkeleton.function.input")
local fmode = util.lazy("skkeleton.function.mode")

local M = {}

---@param ctx skkeleton.Context
function M.kakutei(ctx)
  local st = ctx.state
  if st.type == "henkan" then
    local cand = st.candidates[st.candidate_index + 1]
    local cand_mod = candidate.modify(cand, st.affix)
    if cand and cand ~= "" then
      store.library():register_henkan_result(st.mode, st.word, cand)
      ctx.last_candidate = { type = st.mode, word = st.word, candidate = cand }
    end
    local okuri_str = st.okuri_feed
    if st.converter then
      okuri_str = st.converter(okuri_str)
    end
    ctx:kakutei_with_undo_point((cand_mod or "error") .. okuri_str)
  elseif st.type == "input" then
    input.kakutei_feed(ctx)
    local result = st.henkan_feed .. st.okuri_feed .. st.feed
    if st.converter then
      result = st.converter(result)
    end
    ctx:kakutei(result)
  else
    vim.notify("initializing unknown phase state: " .. vim.inspect(st), vim.log.levels.WARN)
  end
  mode.initialize_state_with_abbrev(ctx, { "converter", "table" })
end

-- 確定キーの処理には強制的にひらがな入力に戻す物があるが、内部的な確定では必要ないため分けておく
---@param ctx skkeleton.Context
function M.kakutei_key(ctx)
  local st = ctx.state
  -- 確定する物が無い状態で確定しようとした際にモードを解除する
  -- この動作は ddskk に存在する
  if st.type == "input" and st.mode == "direct" and st.feed == "" then
    fmode.hirakana(ctx)
    return
  end
  M.kakutei(ctx)
end

---@param ctx skkeleton.Context
function M.newline(ctx)
  local st = ctx.state
  local insert_newline = not (
    options.eggLikeNewline and (st.type == "henkan" or (st.type == "input" and st.mode ~= "direct"))
  )
  M.kakutei(ctx)
  if insert_newline then
    ctx:kakutei("\n")
  end
end

---@param ctx skkeleton.Context
function M.cancel(ctx)
  local st = ctx.state
  if st.type == "input" and st.mode == "direct" and ctx.vim_mode == "c" then
    ctx:kakutei("\x03")
  end
  if options.immediatelyCancel then
    mode.initialize_state_with_abbrev(ctx)
    return
  end
  if st.type == "input" then
    mode.initialize_state_with_abbrev(ctx)
  elseif st.type == "henkan" then
    ctx.state.type = "input"
  end
end

---@param ctx skkeleton.Context
function M.purge_candidate(ctx)
  local st = ctx.state
  local type, word, cand
  if st.type == "input" then
    type = ctx.last_candidate.type
    word = ctx.last_candidate.word
    cand = ctx.last_candidate.candidate
  elseif st.type == "henkan" then
    type = st.mode
    word = st.word
    cand = st.candidates[st.candidate_index + 1]
  else
    vim.notify("purgeCandidate: reach illegal state", vim.log.levels.WARN)
    return
  end
  if word == "" then
    return
  end
  local msg = ("Really purge? %s /%s/"):format(word, cand)
  if host.confirm(msg) then
    store.library():purge_candidate(type, word, cand)
    state.initialize(st)
    ctx.last_candidate.word = ""
  end
end

return M

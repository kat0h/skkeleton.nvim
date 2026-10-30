-- Ported from skkeleton (denops/skkeleton/function/henkan.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local candidate = require("skkeleton.candidate")
local host = require("skkeleton.host")
local notation = require("skkeleton.notation")
local okuri = require("skkeleton.okuri")
local options = require("skkeleton.config").options
local store = require("skkeleton.store")
local util = require("skkeleton.util")

local common = util.lazy("skkeleton.function.common")
local dictionary = util.lazy("skkeleton.function.dictionary")
local input = util.lazy("skkeleton.function.input")
local keymap = util.lazy("skkeleton.keymap")

local M = {}

-- henkan_first の再入を防ぐ
local locked = false

---@param ctx skkeleton.Context
---@param key string
function M.henkan_first(ctx, key)
  if ctx.state.type ~= "input" then
    return
  end

  input.kakutei_feed(ctx)

  if ctx.state.mode == "direct" then
    -- Note: ユーザーが key 単体に henkanFirst を振ってると無限ループが起こるので
    --       繰り返し呼ばれた場合は直接入力にフォールバックする
    if locked then
      ctx:kakutei(key)
    else
      locked = true
      local ok, err = pcall(input.kana_input, ctx, key)
      locked = false
      if not ok then
        error(err, 0)
      end
    end
    return
  end

  if ctx.state.henkan_feed == "" then
    return
  end

  ---@type skkeleton.HenkanState
  local state = ctx.state ---@diagnostic disable-line: assign-type-mismatch
  state.type = "henkan"
  state.candidates = {}
  state.candidate_index = -1

  local lib = store.library()
  local word = state.mode == "okurinasi" and state.henkan_feed or okuri.get_okuri_str(state.henkan_feed, state.okuri_feed)
  state.word = word
  if state.affix == nil and not state.direct_input and (state.mode == "okurinasi" or state.mode == "okuriari") then
    -- ユーザーが手動で henkanPoint を使うと、`>prefix` や `suffix>` のような
    -- henkan_feed が affix 未設定のままここに来る
    if state.henkan_feed:match(">$") then
      state.affix = "prefix"
    elseif state.henkan_feed:match("^>") then
      state.affix = "suffix"
    end
  end
  state.candidates = lib:get_henkan_result(state.mode, word)
  M.henkan_forward(ctx)
end

---@param state skkeleton.HenkanState
local function show_candidates(state)
  local idx = state.candidate_index
  local lines = {}
  for i = 0, 6 do
    local c = state.candidates[idx + i + 1]
    if c == nil then
      break
    end
    lines[#lines + 1] = ("%s: %s"):format(options.selectCandidateKeys:sub(i + 1, i + 1), candidate.modify(c, state.affix))
  end
  host.show_candidates(lines)
end

---@param ctx skkeleton.Context
function M.henkan_forward(ctx)
  local state = ctx.state
  if state.type ~= "henkan" then
    return
  end
  local old_index = state.candidate_index
  if state.candidate_index >= options.showCandidatesCount then
    state.candidate_index = state.candidate_index + 7
  else
    state.candidate_index = state.candidate_index + 1
  end
  if #state.candidates <= state.candidate_index then
    if dictionary.register_word(ctx) then
      return
    end
    state.candidate_index = old_index
    if state.candidate_index == -1 then
      ctx.state.type = "input"
    end
  end
  if state.candidate_index >= options.showCandidatesCount then
    show_candidates(state)
  end
end

---@param ctx skkeleton.Context
function M.henkan_backward(ctx)
  local state = ctx.state
  if state.type ~= "henkan" then
    return
  end
  if state.candidate_index >= options.showCandidatesCount then
    state.candidate_index = math.max(state.candidate_index - 7, options.showCandidatesCount - 1)
  else
    state.candidate_index = state.candidate_index - 1
  end
  if state.candidate_index < 0 then
    ctx.state.type = "input"
    return
  end
  if state.candidate_index >= options.showCandidatesCount then
    show_candidates(state)
  end
end

---@param ctx skkeleton.Context
---@param key string
function M.henkan_input(ctx, key)
  local state = ctx.state
  if state.candidate_index >= options.showCandidatesCount then
    local pos = options.selectCandidateKeys:find(key, 1, true)
    if pos then
      local cand_idx = pos - 1
      if state.candidate_index + cand_idx < #state.candidates then
        state.candidate_index = state.candidate_index + cand_idx
        common.kakutei(ctx)
      end
      return
    end
  end

  common.kakutei(ctx)
  keymap.handle_key(ctx, notation.from_key(key))
end

---@param ctx skkeleton.Context
function M.suffix(ctx)
  if ctx.state.type ~= "henkan" then
    return
  end

  common.kakutei(ctx)
  input.henkan_point(ctx)
  input.accept_result(ctx, { ">", "" }, "")
  ctx.state.affix = "suffix"
end

return M

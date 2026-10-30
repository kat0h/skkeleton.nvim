-- Ported from skkeleton (denops/skkeleton/function/mode.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local hira_to_hankata = require("skkeleton.kana.hira_hankata").hira_to_hankata
local hira_to_kata = require("skkeleton.kana.hira_kata").hira_to_kata
local kana = require("skkeleton.kana")
local mode = require("skkeleton.mode")
local options = require("skkeleton.config").options
local state = require("skkeleton.state")
local store = require("skkeleton.store")
local util = require("skkeleton.util")

local common = util.lazy("skkeleton.function.common")
local henkan = util.lazy("skkeleton.function.henkan")
local input = util.lazy("skkeleton.function.input")

local M = {}

---@param ctx skkeleton.Context
function M.abbrev(ctx)
  if ctx.state.type ~= "input" or ctx.state.mode ~= "direct" then
    return
  end
  input.henkan_point(ctx)
  local s = ctx.state
  local henkan_first = henkan.henkan_first
  s.table = s.table:filter(function(_, func)
    return func == henkan_first
  end)
  s.direct_input = true
  mode.mode_change(ctx, "abbrev")
end

---@param ctx skkeleton.Context
function M.hirakana(ctx)
  if ctx.state.type ~= "input" then
    return
  end
  local st = ctx.state
  if st.mode ~= "direct" then
    common.kakutei(ctx)
  end
  kana.set_current(options.kanaTable)
  if st.type == "input" then
    st.converter = nil
  end
  state.initialize(st, { "converter" })
  mode.mode_change(ctx, "hira")
end

-- 変換前の文字列を converter で変換して確定する。already が真なら変換しない。
-- registerConvertResult なら辞書にも登録する
---@param ctx skkeleton.Context
---@param converter fun(s: string): string
---@param already boolean すでにその converter で入力中か
local function convert_and_kakutei(ctx, converter, already)
  local st = ctx.state
  input.kakutei_feed(ctx)
  local kana_str = st.henkan_feed .. st.okuri_feed
  local result = kana_str
  if not already then
    result = converter(result)
    if options.registerConvertResult then
      store.library():register_henkan_result("okurinasi", kana_str, result)
      ctx.last_candidate = { type = "okurinasi", word = kana_str, candidate = result }
    end
  end
  ctx:kakutei_with_undo_point(result)
  state.initialize(st, { "converter" })
end

---@param ctx skkeleton.Context
function M.katakana(ctx)
  if ctx.state.type ~= "input" then
    return
  end
  local st = ctx.state
  if st.mode == "direct" then
    if st.converter then
      st.converter = nil
      mode.mode_change(ctx, "hira")
    else
      st.converter = hira_to_kata
      mode.mode_change(ctx, "kata")
    end
    return
  end
  convert_and_kakutei(ctx, hira_to_kata, st.converter ~= nil)
end

---@param ctx skkeleton.Context
function M.hankatakana(ctx)
  if ctx.state.type ~= "input" then
    return
  end
  local st = ctx.state
  if st.mode == "direct" then
    if st.converter == hira_to_hankata then
      st.converter = nil
      mode.mode_change(ctx, "hira")
    else
      if kana.current_name == "zen" then
        kana.set_current(options.kanaTable)
        st.table = kana.get_table()
      end
      st.converter = hira_to_hankata
      mode.mode_change(ctx, "hankata")
    end
    return
  end
  convert_and_kakutei(ctx, hira_to_hankata, st.converter == hira_to_hankata)
end

---@param ctx skkeleton.Context
function M.zenkaku(ctx)
  if ctx.state.type ~= "input" then
    return
  end
  local st = ctx.state
  if st.mode ~= "direct" then
    common.kakutei(ctx)
  end
  kana.set_current("zen")
  st.table = kana.get_table()
  mode.mode_change(ctx, "zenkaku")
end

return M

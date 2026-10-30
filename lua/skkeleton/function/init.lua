-- Ported from skkeleton (denops/skkeleton/function.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local util = require("skkeleton.util")

local common = util.lazy("skkeleton.function.common")
local disable = util.lazy("skkeleton.function.disable")
local henkan = util.lazy("skkeleton.function.henkan")
local input = util.lazy("skkeleton.function.input")
local mode = util.lazy("skkeleton.function.mode")

local M = {}

---@alias skkeleton.Func fun(ctx: skkeleton.Context, char: string)

-- 関数の登録名（キーマップやかなテーブルで文字列で指すもの）。内容は初めて参照したときに作る
local function build_functions()
  return {
    -- common
    kakutei = common.kakutei_key,
    newline = common.newline,
    cancel = common.cancel,
    purgeCandidate = common.purge_candidate,
    -- disable
    disable = disable.disable,
    escape = disable.escape,
    -- henkan
    henkanFirst = henkan.henkan_first,
    henkanForward = henkan.henkan_forward,
    henkanBackward = henkan.henkan_backward,
    henkanInput = henkan.henkan_input,
    suffix = henkan.suffix,
    -- input
    kakuteiFeed = input.kakutei_feed,
    henkanPoint = input.henkan_point,
    deleteChar = input.delete_char,
    prefix = input.prefix,
    -- mode
    abbrev = mode.abbrev,
    hirakana = mode.hirakana,
    katakana = mode.katakana,
    hankatakana = mode.hankatakana,
    zenkaku = mode.zenkaku,
  }
end

-- モード名 -> モードを切り替える関数（store.variables.last_mode から復元するときに使う）
local function build_mode_functions()
  return {
    abbrev = mode.abbrev,
    hankata = mode.hankatakana,
    hira = mode.hirakana,
    kata = mode.katakana,
    zenkaku = mode.zenkaku,
  }
end

local cache = {}

setmetatable(M, {
  __index = function(_, k)
    if k == "functions" or k == "mode_functions" then
      if not cache[k] then
        cache[k] = k == "functions" and build_functions() or build_mode_functions()
      end
      return cache[k]
    end
  end,
})

return M

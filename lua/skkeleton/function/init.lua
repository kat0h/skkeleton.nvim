-- Ported from skkeleton (denops/skkeleton/function.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local common = require("skkeleton.function.common")
local disable = require("skkeleton.function.disable")
local henkan = require("skkeleton.function.henkan")
local input = require("skkeleton.function.input")
local mode = require("skkeleton.function.mode")

local M = {}

---@alias skkeleton.Func fun(ctx: skkeleton.Context, char: string)

-- 関数の登録名（キーマップやかなテーブルで文字列で指すもの）
M.functions = {
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

-- モード名 -> モードを切り替える関数（store.variables.last_mode から復元するときに使う）
M.mode_functions = {
  abbrev = mode.abbrev,
  hankata = mode.hankatakana,
  hira = mode.hirakana,
  kata = mode.katakana,
  zenkaku = mode.zenkaku,
}

return M

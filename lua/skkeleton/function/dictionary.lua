-- Ported from skkeleton (denops/skkeleton/function/dictionary.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
-- マッピングの退避や仮想編集の設定など、入力のための UI は host.input が受け持つ。
local host = require("skkeleton.host")
local options = require("skkeleton.config").options
local util = require("skkeleton.util")

local common = util.lazy("skkeleton.function.common")

local M = {}

-- 辞書登録。入力があれば、それを唯一の候補にして確定し true を返す。取り消しなら false
---@param ctx skkeleton.Context
---@return boolean
function M.register_word(ctx)
  local state = ctx.state ---@type skkeleton.HenkanState
  local base = "[辞書登録] " .. state.henkan_feed
  local okuri = state.mode == "okuriari" and ("*" .. state.okuri_feed) or ""
  local ok, input = pcall(host.input, base .. okuri .. ": ")
  if not ok then
    if options.debug then
      vim.notify("registerWord interrupted: " .. tostring(input), vim.log.levels.DEBUG)
    end
    return false
  end
  if input == nil or input == "" or input:find("__skkeleton_return__", 1, true) then
    return false
  end
  state.candidates = { input }
  state.candidate_index = 0
  common.kakutei(ctx)
  return true
end

return M

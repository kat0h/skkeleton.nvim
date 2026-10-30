-- Ported from skkeleton (denops/skkeleton/context.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local options = require("skkeleton.config").options
local PreEdit = require("skkeleton.preedit")
local state = require("skkeleton.state")

---@class skkeleton.Context
---@field state skkeleton.State
---@field mode string g:skkeleton#mode の写し。mode.mode_change が設定する
---@field preedit skkeleton.PreEdit
---@field vim_mode string "i"|"c"|"t"|""
---@field last_candidate { type: skkeleton.HenkanType, word: string, candidate: string }
local Context = {}
Context.__index = Context

---@return skkeleton.Context
function Context.new()
  return setmetatable({
    state = state.initialize({}),
    mode = "hira",
    preedit = PreEdit.new(),
    vim_mode = "",
    last_candidate = { type = "okurinasi", word = "", candidate = "" },
  }, Context)
end

---@param str string
function Context:kakutei(str)
  self.preedit:do_kakutei(str)
end

-- insert モードでは undo point を付けて確定する
---@param str string
function Context:kakutei_with_undo_point(str)
  if options.setUndoPoint and self.vim_mode == "i" then
    str = str .. "\x07u"
  end
  self.preedit:do_kakutei(str)
end

---@return string
function Context:to_string()
  return state.to_string(self.state)
end

return Context

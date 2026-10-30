-- Ported from skkeleton (denops/skkeleton/function/disable.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local host = require("skkeleton.host")
local options = require("skkeleton.config").options
local state = require("skkeleton.state")
local util = require("skkeleton.util")

local common = util.lazy("skkeleton.function.common")

local M = {}

---@param ctx skkeleton.Context
function M.disable(ctx)
  common.kakutei(ctx)
  host.disable()
  state.initialize(ctx.state)
end

---@param ctx skkeleton.Context
function M.escape(ctx)
  if options.keepState then
    host.keep_state_on_insert_enter()
  end
  M.disable(ctx)
  ctx.state.type = "escape"
end

return M

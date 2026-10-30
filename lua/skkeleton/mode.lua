-- Ported from skkeleton (denops/skkeleton/mode.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local host = require("skkeleton.host")
local options = require("skkeleton.config").options
local state = require("skkeleton.state")
local store = require("skkeleton.store")

local M = {}

-- ctx.mode を変えて、host に知らせる
---@param ctx skkeleton.Context
---@param mode string
function M.mode_change(ctx, mode)
  ctx.mode = mode
  host.mode_changed(mode)
  if options.keepMode then
    store.variables.last_mode = mode
  end
end

-- abbrev モードなら、ひらがなに戻してから初期化する
---@param ctx skkeleton.Context
---@param ignore? string[]
function M.initialize_state_with_abbrev(ctx, ignore)
  ignore = ignore or {}
  if ctx.mode == "abbrev" then
    M.mode_change(ctx, "hira")
    ignore = vim.tbl_filter(function(key)
      return key ~= "converter" and key ~= "table"
    end, ignore)
  end
  state.initialize(ctx.state, ignore)
end

return M

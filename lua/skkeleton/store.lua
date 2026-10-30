-- Ported from skkeleton (denops/skkeleton/store.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local M = {}

local current_context ---@type skkeleton.Context?
local current_library ---@type table?

M.variables = {
  last_mode = "hira",
}

-- 今の Context（なければ作る）
---@return skkeleton.Context
function M.context()
  if not current_context then
    current_context = require("skkeleton.context").new()
  end
  return current_context
end

-- Context を作り直して返す
---@return skkeleton.Context
function M.init_context()
  current_context = require("skkeleton.context").new()
  return current_context
end

---@param ctx skkeleton.Context
function M.set_context(ctx)
  current_context = ctx
end

-- 今の Library。未設定なら config から作る
function M.library()
  if not current_library then
    current_library = require("skkeleton.dictionary").load(require("skkeleton.config").options)
  end
  return current_library
end

-- Library の差し替え（テスト用）
function M.set_library(lib)
  current_library = lib
end

return M

-- Ported from skkeleton (denops/skkeleton/keymap.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local notation = require("skkeleton.notation")
local options = require("skkeleton.config").options
local util = require("skkeleton.util")

local functions = util.lazy("skkeleton.function")

local M = {}

---@class skkeleton.KeyMap
---@field default skkeleton.Func
---@field map table<string, skkeleton.Func>

local keymaps ---@type table<string, skkeleton.KeyMap>?

-- 関数は初めて使うときに引く（function/ とは循環するため）
local function get_keymaps()
  if not keymaps then
    local f = functions.functions
    keymaps = {
      input = {
        default = require("skkeleton.function.input").kana_input,
        map = {
          ["<bs>"] = f.deleteChar,
          ["<c-g>"] = f.cancel,
          ["<c-h>"] = f.deleteChar,
          ["<cr>"] = f.newline,
          ["<esc>"] = f.escape,
          ["<nl>"] = f.kakutei,
          ["<c-q>"] = f.hankatakana,
          [">"] = f.prefix,
        },
      },
      henkan = {
        default = f.henkanInput,
        map = {
          ["<c-g>"] = f.cancel,
          ["<cr>"] = f.newline,
          ["<nl>"] = f.kakutei,
          ["<space>"] = f.henkanForward,
          ["x"] = f.henkanBackward,
          ["X"] = f.purgeCandidate,
          [">"] = f.suffix,
        },
      },
    }
  end
  return keymaps
end

-- 表記 notation のキーを、今の state のキーマップで処理する。関数には実際の文字を渡す
---@param ctx skkeleton.Context
---@param key string 正規化した表記
function M.handle_key(ctx, key)
  local keymap = get_keymaps()[ctx.state.type]
  if not keymap then
    error("Illegal State: " .. tostring(ctx.state.type), 0)
  end
  if options.debug then
    vim.notify("handleKey: " .. key, vim.log.levels.DEBUG)
  end
  local func = keymap.map[key] or keymap.default
  func(ctx, notation.to_key(key))
end

-- state ("input"|"henkan") のキーマップに key を登録する。func は関数の登録名か関数。nil/false なら削除
---@param state string
---@param key string 正規化した表記
---@param func string|skkeleton.Func|false|nil
function M.register(state, key, func)
  local keymap = get_keymaps()[state]
  if not keymap then
    error("unknown state: " .. tostring(state), 0)
  end
  if not func or func == "" then
    keymap.map[key] = nil
    return
  end
  local fn = func
  if type(func) == "string" then
    fn = functions.functions[func]
    if not fn then
      error("unknown function: " .. func, 0)
    end
  end
  keymap.map[key] = fn
end

-- テスト用。既定のキーマップに戻す
function M.reset()
  keymaps = nil
end

return M

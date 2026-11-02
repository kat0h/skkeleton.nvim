local config = require("skkeleton.config")

local M = {}

---@type (fun(lines: string[], phase: integer?): boolean)?
local original_paste = nil

-- 'undolevels' を設定し直すことで、新しい undo ブロックを開始する（:h undo-blocks）
-- buffer-local の 'undolevels' が -123456（グローバルの値を使う）なら、その状態を保つ
local function break_undo()
  local ul = vim.api.nvim_get_option_value("undolevels", { scope = "local", buf = 0 })
  if ul == -123456 then
    local gul = vim.api.nvim_get_option_value("undolevels", { scope = "global" })
    vim.bo.undolevels = gul
    vim.bo.undolevels = -123456
  else
    vim.bo.undolevels = ul
  end
end

-- skkeleton が有効な insert モードか
local function is_active_insert()
  local enabled = vim.g["skkeleton#enabled"]
  if enabled ~= true and enabled ~= 1 then
    return false
  end
  local m = vim.api.nvim_get_mode().mode
  return m:sub(1, 1) == "i"
end

function M.init()
  if original_paste then
    return
  end
  original_paste = vim.paste
  vim.paste = function(lines, phase)
    if config.options.setUndoPointOnPaste and is_active_insert() then
      if phase == -1 or phase == 1 or phase == nil then
        break_undo()
      end
    end
    return original_paste(lines, phase)
  end
end

-- テストやリセット用
function M.get_original_paste()
  return original_paste
end

function M.restore()
  if original_paste then
    vim.paste = original_paste
    original_paste = nil
  end
end

return M

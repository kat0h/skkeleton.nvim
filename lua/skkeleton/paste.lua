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
    local first = phase == -1 or phase == 1 or phase == nil
    if first then
      -- pre-edit があれば、貼る前に <Esc> と同じ形で確定する (#125)
      local enabled = vim.g["skkeleton#enabled"]
      local state = vim.g["skkeleton#state"]
      if (enabled == true or enabled == 1) and type(state) == "table" and (state.preedit or "") ~= "" then
        local render = require("skkeleton.render")
        local cleanup = require("skkeleton.cleanup")
        if render.preedit_position() then
          -- insert は extmark の位置に同期して書く（貼り付けより先に確定する）
          local text, _, row, col = cleanup.commit_preedit_now()
          if text and text ~= "" then
            local lines = vim.split(text, "\n", { plain = true })
            local win = vim.api.nvim_get_current_win()
            if #lines == 1 then
              vim.api.nvim_win_set_cursor(win, { row + 1, col + #text })
            else
              vim.api.nvim_win_set_cursor(win, { row + #lines, #lines[#lines] })
            end
          end
          render.clear()
          cleanup.update_state_variable()
        else
          require("skkeleton.main").commit_preedit()
        end
      end
      if config.options.setUndoPointOnPaste and is_active_insert() then
        break_undo()
      end
    end
    return original_paste(lines, phase)
  end
end

return M

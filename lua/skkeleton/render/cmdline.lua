-- cmdline / terminal の pre-edit（本物の文字として書いて BS で消し直す）の記録と片付け。
-- insert の inline extmark とは別の状態だけを持つ。
local M = {}

local options = require("skkeleton.config").options

-- cmdline に書いた pre-edit の位置と、書いた直後の cmdline 全体
---@type { text: string, start_pos: integer, end_pos: integer, line: string }?
local cmd_mark

-- cmdline に書いた pre-edit の先頭のマーカーから、マーカーと読みを取り除く。
-- マーカーの後ろに貼り付けた文字が挟まっていても、挟まった文字は残す（#12）。
---@param line string 今の cmdline
---@param pos integer 今のカーソル（1 起点のバイト位置）
---@param cm { text: string, start_pos: integer, end_pos: integer, line: string }
---@return string? new_line, integer? new_pos
local function drop_marker_and_reading(line, pos, cm)
  local select_marker = options.markerHenkanSelect
  local henkan_marker = options.markerHenkan
  local marker, reading
  if select_marker ~= "" and cm.text:sub(1, #select_marker) == select_marker then
    marker, reading = select_marker, cm.text:sub(#select_marker + 1)
  elseif henkan_marker ~= "" and cm.text:sub(1, #henkan_marker) == henkan_marker then
    marker, reading = henkan_marker, cm.text:sub(#henkan_marker + 1)
  else
    return nil
  end

  -- カーソルより前で、いちばん後ろにあるマーカーを探す
  local head = line:sub(1, pos - 1)
  local mstart
  local init = 1
  while true do
    local s = head:find(marker, init, true)
    if not s then
      break
    end
    mstart = s
    init = s + 1
  end
  if not mstart then
    return nil
  end
  local mend = mstart + #marker - 1

  -- マーカーの後ろで読みを探す。貼り付いた文字が間に入ってもよい
  local rstart, rend
  if reading ~= "" then
    rstart, rend = line:find(reading, mend + 1, true)
    if not rstart then
      return nil
    end
  end

  local new_line = line:sub(1, mstart - 1)
    .. line:sub(mend + 1, (rstart or mend + 1) - 1)
    .. line:sub((rend or mend) + 1)
  local new_pos = pos
  local function adjust(s, e)
    if pos > e then
      new_pos = new_pos - (e - s + 1)
    elseif pos > s then
      new_pos = new_pos - (pos - s)
    end
  end
  adjust(mstart, mend)
  if rstart then
    adjust(rstart, rend)
  end
  return new_line, math.max(1, new_pos)
end

-- cmdline に書いた pre-edit を覚える。text が空なら忘れる
---@param text string
function M.remember(text)
  if text == "" then
    -- <C-r>= の式の入力中は、外側の cmdline の記録を消さない (#206)
    if vim.fn.getcmdtype() ~= "=" then
      cmd_mark = nil
    end
    return
  end
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  cmd_mark = {
    text = text,
    start_pos = math.max(1, pos - #text),
    end_pos = pos,
    line = line,
  }
end

-- 覚えた pre-edit が、今の cmdline と合わなくなっているか
---@param pre string 今の pre-edit
---@return boolean
function M.is_stale(pre)
  if not cmd_mark then
    local line = vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1)
    return line:sub(-#pre) ~= pre
  end
  return vim.fn.getcmdline() ~= cmd_mark.line or vim.fn.getcmdpos() ~= cmd_mark.end_pos
end

-- cmdline に書いた pre-edit が、そのあとの編集でずれているか
---@return boolean
function M.has_stale()
  if not cmd_mark or vim.api.nvim_get_mode().mode:sub(1, 1) ~= "c" then
    return false
  end
  return vim.fn.getcmdline() ~= cmd_mark.line or vim.fn.getcmdpos() ~= cmd_mark.end_pos
end

-- cmdline で pre-edit が残ったままカーソル移動や部分削除が起きたとき、残っている pre-edit を取り除く
function M.clean()
  if not cmd_mark then
    return
  end
  local cm = cmd_mark
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local before = cm.line:sub(1, cm.start_pos - 1)
  local after = cm.line:sub(cm.end_pos)
  local new_line, new_pos

  local s, e
  if #cm.text > 0 and line:sub(cm.start_pos, cm.start_pos + #cm.text - 1) == cm.text then
    s = cm.start_pos
    e = cm.start_pos + #cm.text - 1
  elseif #cm.text > 0 then
    s, e = line:find(cm.text, 1, true)
  end

  if s then
    new_line = line:sub(1, s - 1) .. line:sub(e + 1)
    new_pos = pos > s and math.max(s, pos - #cm.text) or pos
  else
    new_line, new_pos = drop_marker_and_reading(line, pos, cm)
  end

  if new_line == nil then
    if line:sub(1, #before) == before and (#after == 0 or line:sub(-#after) == after) and #line >= #before + #after then
      local mid = line:sub(#before + 1, #line - #after)
      if mid ~= "" and (cm.text:sub(1, #mid) == mid or cm.text:sub(-#mid) == mid) then
        new_line = before .. after
        new_pos = cm.start_pos
      end
    elseif (#after == 0 or line:sub(-#after) == after) and #line >= #after then
      local rem = line:sub(1, #line - #after)
      if rem ~= "" and cm.text:sub(-#rem) == rem then
        new_line = after
        new_pos = 1
      end
    end
  end

  if new_line ~= nil and pcall(vim.fn.setcmdline, new_line, new_pos) then
    cmd_mark = nil
  end
  -- 見つからないときは cmd_mark を残し、次の CmdlineChanged でもう一度試す（CmdlineLeave で捨てる）
end

-- cmdline を抜けるときに、片付けられなかった記録を捨てる
function M.reset()
  cmd_mark = nil
end

return M

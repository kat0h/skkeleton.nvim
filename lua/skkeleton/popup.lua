-- Ported from skkeleton (autoload/skkeleton/popup.vim)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
-- 候補一覧の popup。描画のあとに開き、次のキー入力の最初で閉じる。
local M = {}

---@type string[]?
local pending
---@type integer[]
local windows = {}

-- 次の open で開く候補を覚える
---@param lines string[]
function M.set(lines)
  pending = lines
end

function M.has_pending()
  return pending ~= nil
end

local function open_float(lines, cfg)
  if #lines == 0 then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  local width = 1
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local win = vim.api.nvim_open_win(
    buf,
    false,
    vim.tbl_extend("force", {
      border = "none",
      width = width,
      height = #lines,
      style = "minimal",
      focusable = false,
      noautocmd = true,
    }, cfg)
  )
  vim.w[win].skkeleton_popup = true
  windows[#windows + 1] = win
end

-- cmdline では画面の下、cmdline のすぐ上に出す
local function open_cmdline(lines)
  if #lines == 0 then
    return
  end
  local width = 1
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local top = vim.o.lines - math.max(1, vim.o.cmdheight) - #lines
  open_float(lines, {
    relative = "editor",
    col = math.max(0, math.min(vim.fn.getcmdscreenpos() - 1, vim.o.columns - width)),
    row = math.max(0, top),
  })
  vim.cmd("redraw")
end

-- 覚えた候補を開く
function M.open()
  local lines = pending
  pending = nil
  if not lines or #lines == 0 then
    return
  end
  M.close()
  if vim.fn.mode() == "c" then
    open_cmdline(lines)
    return
  end
  local spos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  -- cmdheight 分は echo area なので、浮動ウィンドウを被せない
  local invert = vim.o.lines - spos.row - vim.o.cmdheight < #lines
  open_float(lines, {
    relative = "cursor",
    col = 0,
    row = invert and 0 or 1,
    anchor = invert and "SW" or "NW",
  })
end

function M.close()
  pending = nil
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  windows = {}
end

return M

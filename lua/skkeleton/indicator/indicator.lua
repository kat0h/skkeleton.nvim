-- Ported from skkeleton_indicator.nvim (lua/skkeleton_indicator/indicator.lua)
-- Copyright (c) 2021 Yasushi Jinnouchi, zlib license (see LICENSES/skkeleton_indicator.nvim.txt)
-- Modified for skkeleton.nvim: 状態を g:skkeleton#mode / g:skkeleton#enabled から読み、
-- 後片付け（destroy）を足し、非推奨の nvim_buf_add_highlight をやめた。

local Modes = require("skkeleton.indicator.modes")
local config = require("skkeleton.indicator.config")

local NAME = "skkeleton-indicator"

---@class skkeleton.Indicator
---@field ns integer
---@field modes skkeleton.IndicatorModes
---@field timer uv.uv_timer_t
---@field winid integer[]
---@field group integer
local Indicator = {}
Indicator.__index = Indicator

---@return skkeleton.Indicator
function Indicator.new()
  local self = setmetatable({
    ns = vim.api.nvim_create_namespace(NAME),
    modes = Modes.new(),
    timer = assert(vim.uv.new_timer()),
    winid = {},
  }, Indicator)
  self.group = vim.api.nvim_create_augroup(NAME, {})
  local defs = {
    { "InsertEnter", "*", self:method("open") },
    { "InsertLeave", "*", self:method("close") },
    { "CursorMovedI", "*", self:method("move") },
    { "CmdlineEnter", "*", self:method("on_cmdline_enter") },
    { "CmdlineLeave", "*", self:method("on_cmdline_leave") },
    { "TextChangedP", "*", self:method("move") },
    { "CompleteChanged", "*", self:method("move") },
    { "WinScrolled", "*", self:method("move") },
    { "WinResized", "*", self:method("move") },
    { "ModeChanged", "*", self:method("on_mode_changed") },
    { "User", "skkeleton-mode-changed", self:method("update") },
    { "User", "skkeleton-disable-post", self:method("update") },
    { "User", "skkeleton-enable-post", self:method("update") },
    { "OptionSet", "background", self:method("refresh") },
    { "ColorScheme", "*", self:method("refresh") },
  }
  for _, def in ipairs(defs) do
    vim.api.nvim_create_autocmd(def[1], { group = self.group, pattern = def[2], callback = def[3] })
  end
  return self
end

-- autocmd に渡すコールバックを作る（true を返すと autocmd が消えるので nil を返す）
---@param name string
---@return fun(): nil
function Indicator:method(name)
  return function()
    self[name](self)
  end
end

---@return boolean
local function skkeleton_enabled()
  local enabled = vim.g["skkeleton#enabled"]
  return enabled == true or enabled == 1
end

-- 今のバッファでは出さない設定か
---@return boolean
function Indicator:is_disabled()
  if not config.always_shown and not skkeleton_enabled() then
    return true
  end
  if Modes.is_cmdline() then
    return not config.show_in_cmdline
  end
  local buf = vim.api.nvim_get_current_buf()
  return vim.tbl_contains(config.ignore_ft, vim.bo[buf].filetype) or not config.buf_filter(buf)
end

-- バッファの中身とハイライトを書き換え、閉じるタイマーを張り直す
---@param buf integer
---@param mode skkeleton.IndicatorMode
function Indicator:set_text(buf, mode)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { mode.text })
  vim.api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
  if config.style == "pill" and mode.cap_hl_name and mode.left_cap and mode.right_cap then
    local left_len = #mode.left_cap
    local right_start = #mode.text - #mode.right_cap
    vim.api.nvim_buf_set_extmark(buf, self.ns, 0, 0, {
      end_row = 0,
      end_col = left_len,
      hl_group = mode.cap_hl_name,
    })
    vim.api.nvim_buf_set_extmark(buf, self.ns, 0, left_len, {
      end_row = 0,
      end_col = right_start,
      hl_group = mode.hl_name,
    })
    vim.api.nvim_buf_set_extmark(buf, self.ns, 0, right_start, {
      end_row = 0,
      end_col = #mode.text,
      hl_group = mode.cap_hl_name,
    })
  else
    vim.api.nvim_buf_set_extmark(buf, self.ns, 0, 0, {
      end_row = 0,
      end_col = #mode.text,
      hl_group = mode.hl_name,
    })
  end
  self.timer:stop()
  self.fade_epoch = (self.fade_epoch or 0) + 1
  local epoch = self.fade_epoch
  if config.fade_out_ms > 0 then
    -- タイマーは luv のコールバックなので、API を呼ぶ前に schedule する
    self.timer:start(
      config.fade_out_ms,
      0,
      vim.schedule_wrap(function()
        if self.fade_epoch == epoch then
          self:close()
        end
      end)
    )
  end
end

---@param mode skkeleton.IndicatorMode
---@return skkeleton.IndicatorBorder?
function Indicator:border(mode)
  local border_opt = config.border
  if type(border_opt) == "function" then
    return border_opt({ mode = mode.name }) or { " " }
  end
  return border_opt
end

---@param winid integer
---@param mode skkeleton.IndicatorMode
function Indicator:border_highlight(winid, mode)
  if config.style == "pill" then
    -- winblend > 0 にすると背景色(bg)だけブレンドされ半円グリフの前景色(fg)と色がズレるため 0 に固定する
    vim.wo[winid].winblend = 0
    vim.wo[winid].winhighlight = "Normal:Normal,NormalFloat:Normal,FloatBorder:" .. mode.hl_name
  else
    vim.wo[winid].winblend = config.winblend or 0
    vim.wo[winid].winhighlight = "FloatBorder:" .. mode.hl_name
  end
end

---@param mode skkeleton.IndicatorMode
---@param for_open? boolean
---@return vim.api.keyset.win_config
function Indicator:win_pos_config(mode, for_open)
  local border = self:border(mode)
  if Modes.is_cmdline() then
    local screen_col = vim.fn.getcmdscreenpos()
    if screen_col <= 0 then
      screen_col = 1
    end
    local has_border = border ~= nil and border ~= "none" and border ~= "shadow"
    local height_rows = 1 + (has_border and 2 or 0)
    local row = math.max(0, vim.o.lines - math.max(1, vim.o.cmdheight) - height_rows)
    local col = math.max(0, math.min(screen_col - 1 + config.col, vim.o.columns - mode.width))
    return {
      relative = "editor",
      row = row,
      col = col,
      width = mode.width,
      height = 1,
      border = border,
    }
  end
  local rect = self:insert_rect(mode, border)
  if not rect then
    -- 画面上の位置が分からないとき（ウィンドウが見えていないなど）
    return {
      relative = "cursor",
      row = config.row,
      col = config.col,
      width = mode.width,
      height = 1,
      border = border,
    }
  end
  return {
    relative = "editor",
    row = rect[1],
    col = rect[2],
    width = mode.width,
    height = 1,
    border = border,
  }
end

-- 2 つの矩形 { 行, 列, 高さ, 幅 } が重なるか
---@param a integer[]
---@param b integer[]
---@return boolean
local function overlaps(a, b)
  return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end

-- insert モードで、インジケータ（枠を含む）の左上の画面上の位置 { 行, 列 }（0 起点）を決める。
-- pre-edit の終わりの画面上の位置から row / col だけずらして置く。そこが画面に収まらないとき、
-- またはカーソルや pre-edit を隠すときは、隠さない側（下、上、左）へ移す。
-- relative = "cursor" は、カーソルがタブの上にあると最後のセルを基準にし、画面の端で押し戻され、
-- pre-edit の折り返しも知らないので、screenpos() から自分で数える
---@param mode skkeleton.IndicatorMode
---@param border skkeleton.IndicatorBorder?
---@return integer[]?
function Indicator:insert_rect(mode, border)
  local win = vim.api.nvim_get_current_win()
  local cur = vim.api.nvim_win_get_cursor(win)
  local line = vim.api.nvim_buf_get_lines(0, cur[1] - 1, cur[1], false)[1] or ""
  local sp = vim.fn.screenpos(win, cur[1], math.min(cur[2], #line) + 1)
  if sp.row == 0 then
    return nil
  end
  local info = vim.fn.getwininfo(win)[1]
  local text_left = info.wincol - 1 + info.textoff -- テキスト領域の左端（0 起点の画面の桁）
  local text_w = info.width - info.textoff
  local width = vim.fn.strdisplaywidth(require("skkeleton.render").preedit_text())
  local row, rel = sp.row - 1, sp.col - 1 - text_left
  -- pre-edit のセルの範囲 { 行, 列, 高さ, 幅 }。inline の virtual text は、全角文字も含めて
  -- 1 桁ずつ次の画面の行へ折り返す（バッファの文字のように行末で詰めない）。
  -- 行がちょうど右端まで埋まったとき、カーソルは次の画面の行の左端に出る
  local occupied = {}
  local left = width
  local wrap = vim.wo[win].wrap
  while left > 0 do
    local n = wrap and math.min(left, text_w - rel) or left
    occupied[#occupied + 1] = { row, text_left + rel, 1, n }
    left = left - n
    rel = rel + n
    if wrap and rel >= text_w then
      row, rel = row + 1, 0
    end
  end
  -- カーソルのセル（pre-edit の直後）
  local ccol = text_left + rel
  local cursor_cell = { row, ccol, 1, 1 }
  local first_row = occupied[1] and occupied[1][1] or row

  local b = (border ~= nil and border ~= "none" and border ~= "shadow") and 1 or 0
  local h, w = 1 + 2 * b, mode.width + 2 * b
  local bottom = vim.o.lines - math.max(1, vim.o.cmdheight)
  local want = { row + config.row, ccol + config.col }
  local function ok(r, c)
    if r < 0 or c < 0 or r + h > bottom or c + w > vim.o.columns then
      return false
    end
    local rect = { r, c, h, w }
    if overlaps(rect, cursor_cell) then
      return false
    end
    for _, o in ipairs(occupied) do
      if overlaps(rect, o) then
        return false
      end
    end
    return true
  end
  local max_col = vim.o.columns - w
  -- 先に下と上（右端なら画面に収まるところまで左へ寄せる）を試し、打った文字を隠す左側は最後にする
  local rows = { want[1], row + 1, first_row - h, row - h }
  for _, r in ipairs(rows) do
    for _, c in ipairs({ want[2], math.min(want[2], max_col) }) do
      if ok(r, c) then
        return { r, c }
      end
    end
  end
  for _, r in ipairs({ row, row + 1, first_row - h }) do
    if ok(r, ccol - w) then
      return { r, ccol - w }
    end
  end
  -- どこも空いていないときは、画面に収まるところへ寄せる
  return { math.max(0, math.min(want[1], bottom - h)), math.max(0, math.min(want[2], max_col)) }
end

local function redraw_if_cmdline(winid)
  if Modes.is_cmdline() then
    if winid and vim.api.nvim__redraw then
      pcall(vim.api.nvim__redraw, { win = winid, valid = false, flush = false })
    else
      pcall(vim.cmd, "redraw")
    end
  end
end

function Indicator:open()
  if self:is_disabled() or vim.fn.getcmdwintype() ~= "" then
    if self:is_opened() then
      self:close()
    end
    return
  end
  if self:is_opened() then
    self:update()
    return
  end
  local mode = self.modes:detect()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  self:set_text(buf, mode)
  local win_cfg = vim.tbl_extend("force", self:win_pos_config(mode, true), {
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = config.zindex,
  })
  local winid = vim.api.nvim_open_win(buf, false, win_cfg)
  self:border_highlight(winid, mode)
  table.insert(self.winid, 1, winid)
end

function Indicator:on_cmdline_enter()
  vim.schedule(function()
    if Modes.is_cmdline() and not self:is_disabled() then
      self:open()
    end
  end)
end

function Indicator:on_cmdline_leave()
  self:close()
  vim.schedule(function()
    if Modes.is_insert() and not self:is_disabled() then
      self:open()
    end
  end)
end

-- <C-c> で insert を抜けたときなど InsertLeave が来ない場合も閉じる
function Indicator:on_mode_changed()
  if not Modes.is_active() and self:is_opened() then
    self:close()
  end
end

-- skkeleton の User イベントで呼ばれる。InsertLeave のときも mode-changed が来るので、
-- 現在のモードを確かめてから更新する（コマンドラインモード中は即座に反映して redraw する）
function Indicator:update()
  local function do_update()
    if not Modes.is_active() then
      -- <C-c> で insert を抜けたときは InsertLeave が来ないので、ここで閉じる
      if self:is_opened() then
        self:close()
      end
      return
    end
    if self:is_disabled() then
      self:close()
      return
    end
    if self:is_opened() then
      local winid = self.winid[1]
      local mode = self.modes:detect()
      self:set_text(vim.api.nvim_win_get_buf(winid), mode)
      pcall(vim.api.nvim_win_set_config, winid, self:win_pos_config(mode, false))
      self:border_highlight(winid, mode)
      redraw_if_cmdline(winid)
    else
      self:open()
      if self:is_opened() then
        redraw_if_cmdline(self.winid[1])
      end
    end
  end
  if Modes.is_cmdline() then
    do_update()
  else
    vim.schedule(do_update)
  end
end

-- カーソルに追従させる。
-- relative = "cursor" は画面上のカーソル位置を設定した時点で読むため、inline の pre-edit が
-- 描かれる前後で値が変わる。バッファ位置の画面上の位置に pre-edit の表示幅を足して決める
function Indicator:move()
  if Modes.is_cmdline() then
    -- コマンドライン中は文字入力ごとのカーソル追従（win_set_config + redraw）を
    -- 行わず、モード切り替え時のみ表示・更新することでカーソルのちらつきを防止する
    return
  end
  if self:is_opened() then
    local mode = self.modes:detect()
    -- ウィンドウがすでに消えていると失敗することがある
    local ok = pcall(vim.api.nvim_win_set_config, self.winid[1], self:win_pos_config(mode, false))
    if not ok then
      table.remove(self.winid, 1)
    end
  end
end

function Indicator:close()
  self.timer:stop()
  for _, winid in ipairs(self.winid) do
    if vim.api.nvim_win_is_valid(winid) then
      local buf = vim.api.nvim_win_get_buf(winid)
      pcall(vim.api.nvim_win_close, winid, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  self.winid = {}
end

---@return boolean
function Indicator:is_opened()
  -- ユーザーが閉じたウィンドウは数えない
  self.winid = vim.tbl_filter(vim.api.nvim_win_is_valid, self.winid)
  return #self.winid > 0
end

-- 色や文言の設定が変わったときに作り直す
function Indicator:refresh()
  self.modes = Modes.new()
  if self:is_opened() then
    self:update()
  elseif Modes.is_active() then
    self:open()
  end
end

-- autocmd、ウィンドウ、タイマーをすべて片付ける
function Indicator:destroy()
  self:close()
  if not self.timer:is_closing() then
    self.timer:close()
  end
  pcall(vim.api.nvim_del_augroup_by_id, self.group)
end

return Indicator

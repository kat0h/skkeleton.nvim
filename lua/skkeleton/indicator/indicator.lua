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
---@field opened_at? { buf: integer, row: integer, col: integer } 出したときのカーソル位置
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
    { "InsertEnter", "*", self:method("sync") },
    { "InsertLeave", "*", self:method("close") },
    -- 出したときの位置から動いたら消す。文字が入ったときもここで気づく
    { "CursorMovedI", "*", self:method("on_cursor_moved") },
    { "CmdlineEnter", "*", self:method("on_cmdline_enter") },
    { "CmdlineLeave", "*", self:method("on_cmdline_leave") },
    -- 出したあとの最初の変化で消す
    { "CmdlineChanged", "*", self:method("on_cmdline_changed") },
    { "ModeChanged", "*", self:method("on_mode_changed") },
    { "User", "skkeleton-mode-changed", self:method("on_skkeleton_changed") },
    { "User", "skkeleton-disable-post", self:method("on_skkeleton_changed") },
    { "User", "skkeleton-enable-post", self:method("on_skkeleton_changed") },
    -- 入力が始まったら消す
    { "User", "skkeleton-handled", self:method("on_handled") },
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
---@return vim.api.keyset.win_config
function Indicator:win_pos_config(mode)
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
  -- pre-edit が無いときだけ出すので、カーソルの右下に置くだけでよい
  return {
    relative = "cursor",
    row = config.row,
    col = config.col,
    width = mode.width,
    height = 1,
    border = border,
  }
end

local function redraw_if_cmdline(winid)
  if Modes.is_cmdline() then
    if winid and vim.api.nvim__redraw then
      pcall(vim.api.nvim__redraw, { win = winid, valid = false })
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
  local win_cfg = vim.tbl_extend("force", self:win_pos_config(mode), {
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = config.zindex,
  })
  local winid = vim.api.nvim_open_win(buf, false, win_cfg)
  self:border_highlight(winid, mode)
  table.insert(self.winid, 1, winid)
  local cur = vim.api.nvim_win_get_cursor(0)
  self.opened_at = { buf = vim.api.nvim_get_current_buf(), row = cur[1], col = cur[2] }
  redraw_if_cmdline(winid)
end

-- 出し直す。モードの文言・ハイライト・位置を今の値にする
function Indicator:update()
  local winid = self.winid[1]
  local mode = self.modes:detect()
  self:set_text(vim.api.nvim_win_get_buf(winid), mode)
  pcall(vim.api.nvim_win_set_config, winid, self:win_pos_config(mode))
  self:border_highlight(winid, mode)
  redraw_if_cmdline(winid)
end

-- pre-edit が出ているか（が出たか）。本体が公開する状態だけを見る
---@return boolean
local function has_preedit()
  local state = vim.g["skkeleton#state"]
  return type(state) == "table" and type(state.preedit) == "string" and state.preedit ~= ""
end

-- 出す・出し直す・消すを 1 か所で決める
function Indicator:sync()
  if not Modes.is_active() or self:is_disabled() or has_preedit() then
    if self:is_opened() then
      self:close()
    end
    return
  end
  self:open()
end

-- 出したときの位置からカーソルが動いたら消す。文字が入ったときもここで気づく。
-- insert に入った直後に CursorMovedI が来ることがあるので、位置が同じなら消さない
function Indicator:on_cursor_moved()
  if not self:is_opened() or not self.opened_at then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  if
    self.opened_at.buf ~= vim.api.nvim_get_current_buf()
    or self.opened_at.row ~= cur[1]
    or self.opened_at.col ~= cur[2]
  then
    self:close()
  end
end

-- pre-edit が出たら消す（入力が始まった）
function Indicator:on_handled()
  if has_preedit() then
    self:close()
  end
end

function Indicator:on_cmdline_enter()
  if Modes.is_cmdline() then
    self:sync()
  end
end

function Indicator:on_cmdline_leave()
  self:close()
  vim.schedule(function()
    if Modes.is_insert() then
      self:sync()
    end
  end)
end

-- コマンドラインは 1 文字ごとに追従しない。出したあとの最初の変化で消す
function Indicator:on_cmdline_changed()
  if self:is_opened() then
    self:close()
  end
end

-- <C-c> で insert を抜けたときなど InsertLeave が来ない場合も閉じる。
-- また、<Insert> で置換モードを経由して insert に戻ったときなど InsertEnter が
-- 来ない場合にも開き直す (#38)。
function Indicator:on_mode_changed()
  if not Modes.is_active() then
    if self:is_opened() then
      self:close()
    end
    return
  end
  self:sync()
end

-- skkeleton の User イベントで呼ばれる。g:skkeleton#state はキーを処理し終えてから
-- 更新されるので、schedule して今の状態で決める
function Indicator:on_skkeleton_changed()
  vim.schedule(function()
    if Modes.is_active() then
      self:sync()
    elseif self:is_opened() then
      self:close()
    end
  end)
end

function Indicator:close()
  self.timer:stop()
  self.opened_at = nil
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
  self:sync()
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

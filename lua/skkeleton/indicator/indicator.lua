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
    { "CmdlineEnter", "*", self:method("open") },
    { "CmdlineLeave", "*", self:method("on_cmdline_leave") },
    { "CmdlineChanged", "*", self:method("move") },
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
  local pre_w = require("skkeleton.render").preedit_width()
  if for_open and pre_w == 0 then
    return {
      relative = "cursor",
      row = config.row,
      col = config.col,
      width = mode.width,
      height = 1,
      border = border,
    }
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  return {
    relative = "win",
    win = vim.api.nvim_get_current_win(),
    bufpos = { pos[1] - 1, pos[2] },
    row = config.row,
    col = config.col + pre_w,
    width = mode.width,
    height = 1,
    border = border,
  }
end

local function redraw_if_cmdline()
  if Modes.is_cmdline() then
    pcall(vim.cmd, "redraw")
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
  redraw_if_cmdline()
end

function Indicator:on_cmdline_leave()
  self:close()
  vim.schedule(function()
    if Modes.is_insert() and not self:is_disabled() then
      self:open()
    end
  end)
end

-- skkeleton の User イベントで呼ばれる。InsertLeave のときも mode-changed が来るので、
-- 現在のモードを確かめてから更新する（コマンドラインモード中は即座に反映して redraw する）
function Indicator:update()
  local function do_update()
    if not Modes.is_active() then
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
      local new_cfg = self:win_pos_config(mode, false)
      local needs_move = true
      if Modes.is_cmdline() then
        local cur_cfg = vim.api.nvim_win_get_config(winid)
        if
          cur_cfg.relative == new_cfg.relative
          and cur_cfg.row == new_cfg.row
          and cur_cfg.col == new_cfg.col
          and cur_cfg.width == new_cfg.width
        then
          needs_move = false
        end
      end
      if needs_move then
        pcall(vim.api.nvim_win_set_config, winid, new_cfg)
      end
      self:border_highlight(winid, mode)
      redraw_if_cmdline()
    else
      self:open()
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
-- 描かれる前後で値が変わる。バッファ位置（bufpos）に固定し、pre-edit の表示幅を足して決める
function Indicator:move()
  if self:is_opened() then
    local mode = self.modes:detect()
    local new_cfg = self:win_pos_config(mode, false)
    if Modes.is_cmdline() then
      local cur_cfg = vim.api.nvim_win_get_config(self.winid[1])
      if
        cur_cfg.relative == new_cfg.relative
        and cur_cfg.row == new_cfg.row
        and cur_cfg.col == new_cfg.col
        and cur_cfg.width == new_cfg.width
      then
        return
      end
    end
    -- ウィンドウがすでに消えていると失敗することがある
    local ok = pcall(vim.api.nvim_win_set_config, self.winid[1], new_cfg)
    if not ok then
      table.remove(self.winid, 1)
    else
      redraw_if_cmdline()
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
  redraw_if_cmdline()
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

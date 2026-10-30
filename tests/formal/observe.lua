-- 形式検証の PoC: 子の nvim の中で、検査に使う観測値を集める。
-- 実装の内部（store、render）と、実装に依らない観測（画面の文字、ウィンドウ、マッピング）の両方を取る
local M = {}

local function floats()
  local popup, indicator = {}, {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative ~= "" then
      local entry = {
        win = w,
        pos = vim.api.nvim_win_get_position(w),
        width = vim.api.nvim_win_get_width(w),
        height = vim.api.nvim_win_get_height(w),
        border = cfg.border ~= nil and cfg.border ~= "none" and #vim.tbl_flatten({ cfg.border }) > 0,
      }
      if vim.w[w].skkeleton_popup then
        entry.lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
        popup[#popup + 1] = entry
      else
        entry.text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false))
        indicator[#indicator + 1] = entry
      end
    end
  end
  return popup, indicator
end

local function marks(ns)
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })) do
        local text = ""
        for _, chunk in ipairs(m[4].virt_text or {}) do
          text = text .. chunk[1]
        end
        out[#out + 1] = { buf = b, row = m[2], col = m[3], text = text }
      end
    end
  end
  return out
end

-- 画面の 1 行（1 起点の screen row）の、col0 から width 桁の文字。cells は 1 桁ごと（全角の 2 桁目は ""）
local function screen_line(row, col0, width)
  local cells = {}
  local c = col0
  while c < col0 + width do
    local s = vim.fn.screenstring(row, c + 1)
    cells[#cells + 1] = s
    local w = math.max(1, vim.fn.strdisplaywidth(s))
    for _ = 2, w do
      cells[#cells + 1] = ""
    end
    c = c + w
  end
  return (table.concat(cells):gsub("%s+$", "")), cells
end

-- skkeleton が置いた（desc が skkeleton のもの）バッファローカルのマッピングの数
local function skk_maps(buf, mode)
  local n = 0
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.desc and m.desc:find("skkeleton", 1, true) then
      n = n + 1
    end
  end
  return n
end

function M.snapshot()
  vim.cmd("redraw")
  local store = require("skkeleton.store")
  local render = require("skkeleton.render")
  local ctx = store.context()
  local st = ctx.state
  local vm = vim.api.nvim_get_mode().mode
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local cur = vim.api.nvim_win_get_cursor(0)
  local wpos = vim.api.nvim_win_get_position(win)
  local textoff = vim.fn.getwininfo(win)[1].textoff
  local popup, indicator = floats()
  local all_skk_maps = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      all_skk_maps = all_skk_maps + skk_maps(b, "i") + skk_maps(b, "c")
    end
  end
  local sentinel = vim.fn.maparg("<C-g>", "i", false, true)
  local options = require("skkeleton.config").options
  -- 今の g:skkeleton#mode でインジケータに出るはずの文字列
  local ok_mode, want_indicator = pcall(function()
    return require("skkeleton.indicator.modes").new():detect().text
  end)
  -- 今の候補一覧のページで popup に出るはずの候補（"a: 候補" の「候補」の部分）
  local want_popup
  if st.type == "henkan" and st.candidates and st.candidate_index >= options.showCandidatesCount then
    want_popup = {}
    local cand = require("skkeleton.candidate")
    for i = 0, 6 do
      local c = st.candidates[st.candidate_index + i + 1]
      if not c then
        break
      end
      want_popup[#want_popup + 1] = cand.modify(c, st.affix)
    end
  end
  local srow = vim.fn.screenpos(win, cur[1], 1).row
  local sline, scells = screen_line(srow, wpos[2] + textoff, vim.api.nvim_win_get_width(win) - textoff)
  return {
    screen_line = sline,
    screen_cells = scells,
    vim_mode = vm,
    enabled = vim.g["skkeleton#enabled"] == true,
    skk_mode = vim.g["skkeleton#mode"] or "",
    g_state = vim.g["skkeleton#state"],
    state = {
      type = st.type,
      mode = st.mode,
      feed = st.feed or "",
      henkan_feed = st.henkan_feed or "",
      candidate_index = st.candidate_index,
    },
    ctx_text = ctx:to_string(),
    pending = render.is_pending(),
    handled = render.count,
    win = win,
    wins = #vim.api.nvim_tabpage_list_wins(0),
    buf = buf,
    bufs = #vim.api.nvim_list_bufs(),
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    cursor = cur,
    win_pos = wpos,
    textoff = textoff,
    win_width = vim.api.nvim_win_get_width(win),
    screen = { row = vim.fn.screenrow(), col = vim.fn.screencol() },
    screen_row = vim.fn.screenpos(win, cur[1], 1).row,
    preedit_marks = marks(render.ns),
    annot_marks = marks(render.ns_annot),
    popup = popup,
    indicator = indicator,
    skk_maps_here = skk_maps(buf, "i"),
    skk_maps_all = all_skk_maps,
    sentinel = type(sentinel) == "table" and sentinel.desc or nil,
    has_sentinel = vim.b[buf].formal_sentinel == true,
    buftype = vim.bo[buf].buftype,
    textwidth = vim.bo[buf].textwidth,
    opt = {
      showCandidatesCount = options.showCandidatesCount,
      markerHenkan = options.markerHenkan,
      markerHenkanSelect = options.markerHenkanSelect,
      keepState = options.keepState,
      keepMode = options.keepMode,
      eggLikeNewline = options.eggLikeNewline,
    },
    ind_cfg = (function()
      local c = require("skkeleton.indicator.config")
      return { always_shown = c.always_shown, row = c.row, col = c.col }
    end)(),
    columns = vim.o.columns,
    editor_lines = vim.o.lines,
    cmdheight = vim.o.cmdheight,
    want_indicator = ok_mode and want_indicator or nil,
    want_popup = want_popup,
    cmdpos = vm:sub(1, 1) == "c" and vim.fn.getcmdpos() or nil,
    cmdline = vm:sub(1, 1) == "c" and vim.fn.getcmdline() or nil,
    cmdtype = vm:sub(1, 1) == "c" and vim.fn.getcmdtype() or nil,
  }
end

return M

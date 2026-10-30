-- skkeleton.nvim: 表示。handle の結果を Neovim に出す。
-- insert モード: pre-edit は inline の extmark で出し、確定した文字列は feedkeys で流す。
-- cmdline と terminal: BS で消して書き直す文字列を feedkeys する。
local popup = require("skkeleton.popup")

local M = {}

local ns = vim.api.nvim_create_namespace("skkeleton-preedit")
M.ns = ns

-- 出し終えた回数（テストが処理の完了を待つために数える）
M.count = 0

-- 今出している extmark。tick は描いたときの changedtick
---@type { buf: integer, id: integer, row: integer, col: integer, tick: integer }?
local mark
-- finish で描く pre-edit と、そのときの vim_mode
local current_text = ""
local current_mode = "i"

local function termcodes(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- keys の K_SPECIAL (0x80) を逃がして流す。cmd があれば逃がさずにあとへ続ける。
-- 「、」のように 0x80 を含む文字が、特殊キーの始まりと読まれないようにするため
local function feed(keys, cmd)
  keys = keys:gsub("\128", "\128\254X")
  vim.api.nvim_feedkeys(keys .. (cmd or ""), "nit", false)
end

-- pre-edit の extmark を消す
function M.clear()
  if mark then
    if vim.api.nvim_buf_is_valid(mark.buf) then
      pcall(vim.api.nvim_buf_del_extmark, mark.buf, ns, mark.id)
    end
    mark = nil
  end
end

local function draw(text)
  M.clear()
  if text == "" then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  -- 右側に文字が入っても動かない gravity にして、補完などで文字が増えたことを検出できるようにする
  local id = vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
    virt_text = { { text, "SkkeletonPreedit" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
    right_gravity = false,
  })
  mark = { buf = buf, id = id, row = row, col = col, tick = vim.b[buf].changedtick }
end

-- いま出している pre-edit の表示幅（カーソルがまだ指している行・列のときだけ。なければ 0）。
-- relative = "cursor" のウィンドウは inline の virtual text の幅を含まないので、インジケータが足す
---@return integer
function M.preedit_width()
  if not mark or current_text == "" or not vim.api.nvim_buf_is_valid(mark.buf) then
    return 0
  end
  if mark.buf ~= vim.api.nvim_get_current_buf() then
    return 0
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  if pos[1] - 1 ~= mark.row or pos[2] ~= mark.col then
    return 0
  end
  return vim.fn.strdisplaywidth(current_text)
end

-- pre-edit が残っているのにバッファや cmdline がそれと合わなくなっているか
-- （矢印キーで動いた、補完で文字が入ったなど）
---@param ctx skkeleton.Context
---@param vim_mode string
---@return boolean
function M.is_stale(ctx, vim_mode)
  local pre = ctx:to_string()
  if pre == "" then
    return false
  end
  if vim_mode == "c" then
    local line = vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1)
    return line:sub(-#pre) ~= pre
  elseif vim_mode == "t" then
    return false
  end
  if not mark then
    return true
  end
  local buf = vim.api.nvim_get_current_buf()
  if mark.buf ~= buf then
    return true
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  return pos[1] - 1 ~= mark.row or pos[2] ~= mark.col or vim.b[buf].changedtick ~= mark.tick
end

-- 描画を終える。確定した文字列が入ったあとに呼ぶ
function M.finish()
  if current_mode == "i" and vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
    draw(current_text)
  else
    M.clear()
  end
  popup.open()
  -- pre-edit の幅が変わったので、インジケータを画面上のカーソルに寄せ直す
  require("skkeleton.indicator").move()
  M.count = M.count + 1
  vim.api.nvim_exec_autocmds("User", { pattern = "skkeleton-handled", modeline = false })
end

-- ctx の今の状態を出す。prefix は先に流すキー
---@param ctx skkeleton.Context
---@param prefix? string
function M.update(ctx, prefix)
  local vm = ctx.vim_mode
  local pre = ctx:to_string()
  local keys, esc
  if vm == "c" or vm == "t" then
    keys = (prefix or "") .. ctx.preedit:output(pre)
    current_mode = vm
    current_text = ""
  else
    local kakutei = ctx.preedit:take_kakutei()
    -- escape の state は <Esc> そのものを返す
    esc = pre == "\27"
    keys = (prefix or "") .. kakutei .. (esc and "\27" or "")
    current_mode = "i"
    current_text = esc and "" or pre
  end
  -- 流した文字が入ってから描く。Esc で抜けるときはその場で片付ける
  local deferred = keys ~= "" and not esc and (current_mode == "i" or popup.has_pending())
  if keys ~= "" then
    feed(keys, deferred and termcodes("<Cmd>lua require('skkeleton.render').finish()<CR>") or nil)
  end
  if not deferred then
    M.finish()
  end
end

vim.api.nvim_set_hl(0, "SkkeletonPreedit", { default = true })

return M

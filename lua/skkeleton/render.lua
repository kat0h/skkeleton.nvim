-- skkeleton.nvim: 表示。handle の結果を Neovim に出す。
-- insert モード: pre-edit は inline の extmark で出し、確定した文字列は feedkeys で流す。
-- cmdline と terminal: BS で消して書き直す文字列を feedkeys する。
local cmdline = require("skkeleton.render.cmdline")
local options = require("skkeleton.config").options
local popup = require("skkeleton.popup")
local state = require("skkeleton.state")

local M = {}

local ns = vim.api.nvim_create_namespace("skkeleton-preedit")
local ns_annot = vim.api.nvim_create_namespace("skkeleton-annotation")

-- 今出している extmark。line は描いたときの行の文字列
---@type { buf: integer, id: integer, annot_id?: integer, row: integer, col: integer, line: string }?
local mark
-- pre-edit の行が外部から書き換えられたフラグ
local mark_bytes_changed = false
---@type integer?
local attached_buf = nil
-- finish で描く pre-edit と、そのときの vim_mode
local current_text = ""
local current_cmd_text = ""
---@type string[][]?
local current_chunks = nil
local current_annot = ""
local current_mode = "i"
-- 流した確定文字列が入るのを待っているか（finish が走るまで）
local pending = false

local function ensure_highlights()
  vim.api.nvim_set_hl(0, "SkkeletonPreedit", { default = true })
  vim.api.nvim_set_hl(0, "SkkeletonMarkerHenkan", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "SkkeletonMarkerSelect", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "SkkeletonOkuri", { link = "Identifier", default = true })
  vim.api.nvim_set_hl(0, "SkkeletonRomaji", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "SkkeletonAnnotation", { link = "Comment", default = true })
end

-- 断片の役割をハイライト名に引き当てる
---@param role skkeleton.SegmentRole
---@param kind "input"|"henkan"|"escape"
---@return string
local function role_highlight(role, kind)
  if role == "marker" then
    return kind == "henkan" and "SkkeletonMarkerSelect" or "SkkeletonMarkerHenkan"
  elseif role == "romaji" then
    return "SkkeletonRomaji"
  elseif role == "okuri" then
    return "SkkeletonOkuri"
  end
  return "SkkeletonPreedit"
end

---@param ctx skkeleton.Context
---@param text string
---@return string[][] chunks, string annot
local function build_chunks(ctx, text)
  if text == "" then
    return {}, ""
  end
  local st = ctx.state
  local chunks = {}
  for _, segment in ipairs(state.segments(st)) do
    chunks[#chunks + 1] = { segment.text, role_highlight(segment.hl, st.type) }
  end
  local annot = ""
  if st.type == "henkan" then
    local raw_cand = st.candidates and st.candidates[st.candidate_index + 1] or nil
    if raw_cand and st.candidate_index >= 0 and st.candidate_index < options.showCandidatesCount then
      local semi = raw_cand:find(";", 1, true)
      if semi and #raw_cand > semi then
        annot = " ;" .. raw_cand:sub(semi + 1)
      end
    end
  end
  return chunks, annot
end

-- 確定文字列の反映待ちか
function M.is_pending()
  return pending
end

local FINISH_CMD = vim.api.nvim_replace_termcodes("<Cmd>lua require('skkeleton.render').finish()<CR>", true, true, true)

-- keys の K_SPECIAL (0x80) を逃がして流す。cmd があれば逃がさずにあとへ続ける。
-- 「、」のように 0x80 を含む文字が、特殊キーの始まりと読まれないようにするため。
-- insert モードでは "t" を外すことでマクロ記録（qa）やドットリピート（.）に
-- feedkeys で流した確定文字列や FINISH_CMD が混入するのを防ぐ (#36)。
-- cmdline や terminal では BS による再描画や制御文字の処理のために "t" を残す。
local function feed(keys, cmd, mode)
  keys = keys:gsub("\128", "\128\254X")
  local flags = (mode == "i") and "ni" or "nit"
  vim.api.nvim_feedkeys(keys .. (cmd or ""), flags, false)
end

-- 今出している pre-edit を書く位置（バッファと 0 起点の行・列）。出していなければ nil
---@return integer? buf, integer? row, integer? col
function M.preedit_position()
  if not mark or not vim.api.nvim_buf_is_valid(mark.buf) or mark.buf ~= vim.api.nvim_get_current_buf() then
    return nil
  end
  return mark.buf, mark.row, mark.col
end

-- pre-edit の extmark を消す
function M.clear()
  pending = false
  mark_bytes_changed = false
  if mark then
    if vim.api.nvim_buf_is_valid(mark.buf) then
      pcall(vim.api.nvim_buf_del_extmark, mark.buf, ns, mark.id)
      if mark.annot_id then
        pcall(vim.api.nvim_buf_del_extmark, mark.buf, ns_annot, mark.annot_id)
      end
    end
    mark = nil
  end
end

-- pre-edit を出している間、バッファの書き換えを on_bytes で受ける
local function attach_buf(buf)
  if attached_buf == buf then
    return
  end
  attached_buf = buf
  pcall(vim.api.nvim_buf_attach, buf, false, {
    on_bytes = function(_, _, b, start_row, _, _, old_end_row, _, _, new_end_row, _, _)
      if attached_buf ~= b then
        return true
      end
      if not mark or mark.buf ~= b then
        attached_buf = nil
        return true
      end
      if pending then
        return
      end
      local max_end_row = start_row + math.max(old_end_row, new_end_row)
      if start_row <= mark.row and mark.row <= max_end_row then
        mark_bytes_changed = true
        vim.schedule(function()
          if M.on_stale then
            M.on_stale()
          end
        end)
      end
    end,
    on_detach = function(_, b)
      if attached_buf == b then
        attached_buf = nil
      end
    end,
  })
end

local function draw(text, chunks, annot)
  M.clear()
  if text == "" then
    return
  end
  ensure_highlights()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local ok_pos, pos = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok_pos or not pos then
    return
  end
  local row, col = pos[1] - 1, pos[2]
  local virt_text = (chunks and #chunks > 0) and chunks or { { text, "SkkeletonPreedit" } }
  -- 右側に文字が入っても動かない gravity にして、補完などで文字が増えたことを検出できるようにする
  local ok_mark, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, col, {
    virt_text = virt_text,
    virt_text_pos = "inline",
    hl_mode = "combine",
    right_gravity = false,
  })
  if not ok_mark then
    return
  end
  local annot_id
  if annot and annot ~= "" then
    local ok_annot, aid = pcall(vim.api.nvim_buf_set_extmark, buf, ns_annot, row, col, {
      virt_text = { { annot, "SkkeletonAnnotation" } },
      virt_text_pos = "inline",
      hl_mode = "combine",
      right_gravity = true,
    })
    if ok_annot then
      annot_id = aid
    end
  end
  local cur_line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  mark = { buf = buf, id = id, annot_id = annot_id, row = row, col = col, line = cur_line }
  mark_bytes_changed = false
  attach_buf(buf)
end

-- いま出している pre-edit（注釈を含む）の文字列（カーソルがまだ指している行・列のときだけ。なければ ""）。
-- inline の virtual text は relative = "cursor" や screenpos() の位置に入らないので、
-- 画面からはみ出すかを確かめるときに使う
---@return string
local function preedit_text()
  if not mark or current_text == "" or not vim.api.nvim_buf_is_valid(mark.buf) then
    return ""
  end
  if mark.buf ~= vim.api.nvim_get_current_buf() then
    return ""
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  if pos[1] - 1 ~= mark.row or pos[2] ~= mark.col then
    return ""
  end
  return current_text .. (current_annot or "")
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
  if mark_bytes_changed then
    return true
  end
  if ctx.vim_mode ~= vim_mode then
    return true
  end
  if vim_mode == "c" then
    return cmdline.is_stale(pre)
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
  if pos[1] - 1 ~= mark.row or pos[2] ~= mark.col then
    return true
  end
  local em = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark.id, {})
  if #em == 0 or em[1] ~= mark.row or em[2] ~= mark.col then
    return true
  end
  local cur_line = vim.api.nvim_buf_get_lines(buf, mark.row, mark.row + 1, false)[1] or ""
  return cur_line ~= mark.line
end

-- pre-edit は出たままだが、カーソルだけが動いているか（insert）。
-- このときは捨てずに、元の位置に確定してから片付ける（cleanup.lua の reset_if_stale。#111）。
---@param ctx skkeleton.Context
---@param vim_mode string
---@return boolean
function M.is_cursor_only_stale(ctx, vim_mode)
  if vim_mode ~= "i" or mark_bytes_changed or ctx.vim_mode ~= vim_mode then
    return false
  end
  if ctx:to_string() == "" or not mark then
    return false
  end
  local buf = vim.api.nvim_get_current_buf()
  if mark.buf ~= buf then
    return false
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  if pos[1] - 1 == mark.row and pos[2] == mark.col then
    return false
  end
  local em = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark.id, {})
  if #em == 0 or em[1] ~= mark.row or em[2] ~= mark.col then
    return false
  end
  local cur_line = vim.api.nvim_buf_get_lines(buf, mark.row, mark.row + 1, false)[1] or ""
  return cur_line == mark.line
end

-- pre-edit の末尾がウィンドウ下端からはみ出している場合、収まるようにスクロールする (#34)
local function adjust_scroll()
  local win = vim.api.nvim_get_current_win()
  if not vim.wo[win].wrap then
    return
  end
  local preedit = preedit_text()
  if preedit == "" then
    return
  end
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return
  end
  local text_w = info.width - info.textoff
  if text_w <= 0 then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(win)
  local line = vim.api.nvim_buf_get_lines(0, cur[1] - 1, cur[1], false)[1] or ""
  local sp = vim.fn.screenpos(win, cur[1], math.min(cur[2], #line) + 1)
  local cursor_winrow = sp.row > 0 and (sp.row - info.winrow + 1) or vim.fn.winline()
  local text_left = info.wincol - 1 + info.textoff
  local rel = sp.col > 0 and (sp.col - 1 - text_left) or 0
  rel = math.max(0, math.min(text_w - 1, rel))

  local cur_row = cursor_winrow
  local cur_rel = rel
  for _, char in ipairs(vim.fn.split(preedit, [[\zs]])) do
    local w = vim.fn.strdisplaywidth(char)
    if cur_rel + w > text_w then
      cur_row = cur_row + 1
      cur_rel = 0
    end
    cur_rel = cur_rel + w
    if cur_rel >= text_w then
      cur_row = cur_row + 1
      cur_rel = 0
    end
  end

  local overflow = cur_row - info.height
  if overflow > 0 then
    local view = vim.fn.winsaveview()
    local line_count = vim.api.nvim_buf_line_count(0)
    if view.topline < view.lnum then
      view.topline = math.min(view.lnum, math.min(line_count, view.topline + overflow))
      vim.fn.winrestview(view)
    elseif vim.wo[win].smoothscroll then
      view.skipcol = view.skipcol + overflow * text_w
      vim.fn.winrestview(view)
    end
  end
end

-- 描画を終える。確定した文字列が入ったあとに呼ぶ
function M.finish()
  pending = false
  local vm = vim.api.nvim_get_mode().mode:sub(1, 1)
  if current_mode == "i" and vm == "i" then
    cmdline.reset()
    draw(current_text, current_chunks, current_annot)
    adjust_scroll()
    popup.open()
  elseif vm == "c" then
    M.clear()
    cmdline.remember(current_cmd_text)
    popup.open()
  else
    cmdline.reset()
    M.clear()
    popup.close()
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "skkeleton-handled", modeline = false })
end

-- ctx の今の状態を出す
---@param ctx skkeleton.Context
---@param pre? string ctx:to_string() の結果（呼び出し側で作ったもの）
function M.update(ctx, pre)
  local vm = ctx.vim_mode
  pre = pre or ctx:to_string()
  local keys, esc
  if vm == "c" or vm == "t" then
    esc = pre == "\27"
    keys = ctx.preedit:output(pre)
    current_mode = vm
    current_text = ""
    current_cmd_text = (vm == "c" and not esc) and pre or ""
    current_chunks = nil
    current_annot = ""
  else
    local kakutei = ctx.preedit:take_kakutei()
    -- escape の state は <Esc> そのものを返す
    esc = pre == "\27"
    keys = kakutei .. (esc and "\27" or "")
    current_mode = "i"
    current_text = esc and "" or pre
    current_cmd_text = ""
    current_chunks, current_annot = build_chunks(ctx, current_text)
  end
  -- 流した文字が入ってから描く。Esc や改行で cmdline を抜けるときはその場で片付ける
  local leaves_cmdline = vm == "c" and (esc or keys:find("[\r\n]$") ~= nil)
  local deferred = keys ~= ""
    and not esc
    and (current_mode == "i" or (current_mode == "c" and not leaves_cmdline) or popup.has_pending())
  pending = keys ~= "" and deferred
  if keys ~= "" then
    feed(keys, deferred and FINISH_CMD or nil, current_mode)
  end
  if not deferred then
    M.finish()
  end
end

ensure_highlights()

return M

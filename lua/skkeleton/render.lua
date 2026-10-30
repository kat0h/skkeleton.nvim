-- skkeleton.nvim: 表示。handle の結果を Neovim に出す。
-- insert モード: pre-edit は inline の extmark で出し、確定した文字列は feedkeys で流す。
-- cmdline と terminal: BS で消して書き直す文字列を feedkeys する。
local candidate = require("skkeleton.candidate")
local options = require("skkeleton.config").options
local popup = require("skkeleton.popup")

local M = {}

local ns = vim.api.nvim_create_namespace("skkeleton-preedit")
local ns_annot = vim.api.nvim_create_namespace("skkeleton-annotation")
M.ns = ns
M.ns_annot = ns_annot

-- 出し終えた回数（テストが処理の完了を待つために数える）
M.count = 0

-- 今出している extmark。line は描いたときの行の文字列
---@type { buf: integer, id: integer, annot_id?: integer, row: integer, col: integer, line: string }?
local mark
-- cmdline に書いた pre-edit の位置と、書いた直後の cmdline 全体
---@type { text: string, start_pos: integer, end_pos: integer, line: string }?
local cmd_mark
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

---@param chunks string[][]
---@param part string
---@param hl string
local function push_chunk(chunks, part, hl)
  if part and part ~= "" then
    chunks[#chunks + 1] = { part, hl }
  end
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
  local annot = ""
  if st.type == "input" then
    if st.mode == "direct" then
      push_chunk(chunks, st.feed, "SkkeletonRomaji")
    elseif st.mode == "okurinasi" then
      local marker = st.converter and st.converter(options.markerHenkan) or options.markerHenkan
      local body = st.converter and st.converter(st.henkan_feed) or st.henkan_feed
      push_chunk(chunks, marker, "SkkeletonMarkerHenkan")
      push_chunk(chunks, body, "SkkeletonPreedit")
      push_chunk(chunks, st.feed, "SkkeletonRomaji")
    elseif st.mode == "okuriari" then
      local marker = st.converter and st.converter(options.markerHenkan) or options.markerHenkan
      local body = st.converter and st.converter(st.henkan_feed) or st.henkan_feed
      push_chunk(chunks, marker, "SkkeletonMarkerHenkan")
      push_chunk(chunks, body, "SkkeletonPreedit")
      if st.previous_feed then
        push_chunk(chunks, st.feed, "SkkeletonRomaji")
        push_chunk(chunks, "*", "SkkeletonOkuri")
      else
        local okuri_part = "*" .. st.okuri_feed
        if st.converter then
          okuri_part = st.converter(okuri_part)
        end
        push_chunk(chunks, okuri_part, "SkkeletonOkuri")
        push_chunk(chunks, st.feed, "SkkeletonRomaji")
      end
    end
  elseif st.type == "henkan" then
    local raw_cand = st.candidates and st.candidates[st.candidate_index + 1] or nil
    local cand = candidate.modify(raw_cand, st.affix) or "error"
    local okuri = st.okuri_feed
    if st.converter then
      okuri = st.converter(okuri)
    end
    push_chunk(chunks, options.markerHenkanSelect, "SkkeletonMarkerSelect")
    push_chunk(chunks, cand, "SkkeletonPreedit")
    push_chunk(chunks, okuri, "SkkeletonOkuri")
    if raw_cand and st.candidate_index >= 0 and st.candidate_index < options.showCandidatesCount then
      local semi = raw_cand:find(";", 1, true)
      if semi and #raw_cand > semi then
        annot = " ;" .. raw_cand:sub(semi + 1)
      end
    end
  end

  local joined = ""
  for _, c in ipairs(chunks) do
    joined = joined .. c[1]
  end
  if joined ~= text then
    chunks = { { text, "SkkeletonPreedit" } }
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

-- pre-edit の extmark を消す
function M.clear()
  pending = false
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
end

-- いま出している pre-edit（注釈を含む）の文字列（カーソルがまだ指している行・列のときだけ。なければ ""）。
-- inline の virtual text は relative = "cursor" や screenpos() の位置に入らないので、インジケータが足す
---@return string
function M.preedit_text()
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

-- 上の文字列の表示幅
---@return integer
function M.preedit_width()
  return vim.fn.strdisplaywidth(M.preedit_text())
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
  if ctx.vim_mode ~= vim_mode then
    return true
  end
  if vim_mode == "c" then
    if not cmd_mark then
      local line = vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1)
      return line:sub(-#pre) ~= pre
    end
    return vim.fn.getcmdline() ~= cmd_mark.line or vim.fn.getcmdpos() ~= cmd_mark.end_pos
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

-- cmdline で pre-edit が残ったままカーソル移動や部分削除が起きたとき、残っている pre-edit を取り除く
function M.clean_stale_cmdline()
  if not cmd_mark then
    return
  end
  local cm = cmd_mark
  cmd_mark = nil
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local before = cm.line:sub(1, cm.start_pos - 1)
  local after = cm.line:sub(cm.end_pos)
  local new_line, new_pos
  if line == cm.line then
    new_line = before .. after
    if pos <= cm.start_pos then
      new_pos = pos
    elseif pos >= cm.end_pos then
      new_pos = pos - #cm.text
    else
      new_pos = cm.start_pos
    end
  elseif
    line:sub(1, #before) == before
    and (#after == 0 or line:sub(-#after) == after)
    and #line >= #before + #after
  then
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
  if new_line ~= nil then
    pcall(vim.fn.setcmdline, new_line, new_pos)
  end
end

-- pre-edit の末尾がウィンドウ下端からはみ出している場合、収まるようにスクロールする (#34)
local function adjust_scroll()
  local win = vim.api.nvim_get_current_win()
  if not vim.wo[win].wrap then
    return
  end
  local preedit = M.preedit_text()
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
    cmd_mark = nil
    draw(current_text, current_chunks, current_annot)
    adjust_scroll()
    popup.open()
    -- pre-edit の幅が変わったので、インジケータを画面上のカーソルに寄せ直す
    require("skkeleton.indicator").move()
  elseif vm == "c" then
    M.clear()
    if current_cmd_text ~= "" then
      local cmdline = vim.fn.getcmdline()
      local cmdpos = vim.fn.getcmdpos()
      cmd_mark = {
        text = current_cmd_text,
        start_pos = math.max(1, cmdpos - #current_cmd_text),
        end_pos = cmdpos,
        line = cmdline,
      }
    else
      cmd_mark = nil
    end
    popup.open()
  else
    cmd_mark = nil
    M.clear()
    popup.close()
  end
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
    esc = pre == "\27"
    keys = (prefix or "") .. ctx.preedit:output(pre)
    current_mode = vm
    current_text = ""
    current_cmd_text = (vm == "c" and not esc) and pre or ""
    current_chunks = nil
    current_annot = ""
  else
    local kakutei = ctx.preedit:take_kakutei()
    -- escape の state は <Esc> そのものを返す
    esc = pre == "\27"
    keys = (prefix or "") .. kakutei .. (esc and "\27" or "")
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

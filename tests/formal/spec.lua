-- 形式検証の PoC: 守るべき性質。
-- state: 1 つの観測（落ち着いた時点の snapshot）で成り立つべき性質（不変条件）
-- action: 1 キーの前後の観測の組 (prev, key, next) で成り立つべき性質（TLA+ の action に当たる）
-- どちらも違反なら説明の文字列を、成り立てば nil を返す
local M = {}

local SHOW_CANDIDATES = 4 -- config の showCandidatesCount の既定
local MARKERS = { "▽", "▼" }

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

local function short(v)
  return vim.inspect(v, { newline = " ", indent = "" })
end

local function mark_text(s)
  return s.preedit_marks[1] and s.preedit_marks[1].text or ""
end

local function annot_text(s)
  return s.annot_marks[1] and s.annot_marks[1].text or ""
end

local function cur_line(s)
  return s.lines[s.cursor[1]] or ""
end

local function insert_mode(s)
  return s.vim_mode:sub(1, 1) == "i"
end

-- 辞書登録の input() の中。元の行の pre-edit（▽っk など）は、登録が終わるまで元の位置に残してよい
-- （upstream ではバッファの文字なので、登録中も見えている）
local function registering(s)
  return s.cmdtype == "@"
end

M.state = {}

M.state["preedit: extmark は全バッファで高々 1 つ"] = function(s)
  if #s.preedit_marks > 1 or #s.annot_marks > 1 then
    return ("preedit marks=%d annot marks=%d"):format(#s.preedit_marks, #s.annot_marks)
  end
end

M.state["preedit: extmark は insert モードの今のバッファのカーソル位置にある"] = function(s)
  for _, m in ipairs(vim.list_extend(vim.list_slice(s.preedit_marks), s.annot_marks)) do
    if not insert_mode(s) and not registering(s) then
      return ("mode %s で extmark %s が残っている"):format(s.vim_mode, short(m))
    end
    if m.buf ~= s.buf then
      return ("extmark が別のバッファ %d にある（今は %d）"):format(m.buf, s.buf)
    end
    if m.row ~= s.cursor[1] - 1 or m.col ~= s.cursor[2] then
      return ("extmark (%d,%d) がカーソル (%d,%d) からずれている"):format(
        m.row,
        m.col,
        s.cursor[1] - 1,
        s.cursor[2]
      )
    end
  end
end

M.state["preedit: 表示は状態の文字列と一致する"] = function(s)
  if insert_mode(s) and not s.pending and mark_text(s) ~= s.ctx_text then
    return ("extmark %q と状態 %q が違う"):format(mark_text(s), s.ctx_text)
  end
end

-- 実装に依らない観測で確かめる: 画面の行は「カーソルの前 + pre-edit + 注釈 + カーソルの後」で、
-- 端末のカーソルは pre-edit の直後にある（upstream でバッファに文字を書いていたときと同じ見え方）
M.state["screen: 画面の行はバッファに pre-edit を差し込んだもの"] = function(s)
  if not insert_mode(s) or s.pending then
    return
  end
  local line = cur_line(s)
  local before, after = line:sub(1, s.cursor[2]), line:sub(s.cursor[2] + 1)
  local expect = (before .. mark_text(s) .. annot_text(s) .. after):gsub("%s+$", "")
  local avail = s.win_width - s.textoff
  if width(expect) <= avail and s.screen_line ~= expect then
    return ("画面 %q、期待 %q"):format(s.screen_line, expect)
  end
  local col = s.win_pos[2] + s.textoff + width(before .. mark_text(s)) + 1
  if width(before .. mark_text(s)) < avail and s.screen.col ~= col then
    return ("画面のカーソル列 %d、期待 %d"):format(s.screen.col, col)
  end
end

M.state["buffer: マーカーがバッファに漏れない"] = function(s)
  for i, l in ipairs(s.lines) do
    for _, m in ipairs(MARKERS) do
      if l:find(m, 1, true) then
        return ("%d 行目 %q に %s"):format(i, l, m)
      end
    end
  end
end

M.state["mode: normal に戻ったら片付いている"] = function(s)
  if s.vim_mode ~= "n" then
    return
  end
  if s.enabled then
    return "normal なのに enabled"
  end
  if s.ctx_text ~= "" or s.state.type ~= "input" or s.state.mode ~= "direct" then
    return ("normal なのに状態 %s %q が残っている"):format(short(s.state), s.ctx_text)
  end
  if s.textwidth ~= 78 then
    return ("'textwidth' が %d のまま（元は 78）"):format(s.textwidth)
  end
end

M.state["disabled: マッピング・インジケータ・popup が残らない"] = function(s)
  if s.enabled then
    return
  end
  if s.skk_maps_all > 0 then
    return ("無効なのに skkeleton のマッピングが %d 個"):format(s.skk_maps_all)
  end
  if s.sentinel ~= "user-sentinel" then
    return ("利用者の <C-g> のマッピングが戻っていない: %s"):format(tostring(s.sentinel))
  end
  if #s.popup > 0 then
    return "無効なのに popup が出ている"
  end
  if #s.preedit_marks > 0 then
    return "無効なのに pre-edit が出ている"
  end
end

M.state["mapping: 有効なら今のバッファにマッピングがある"] = function(s)
  if s.enabled and insert_mode(s) and s.skk_maps_here == 0 then
    return "有効なのに今のバッファにマッピングが無い"
  end
end

-- alwaysShown（既定 true）なので、無効でも insert モードでは出る。normal では出ない
M.state["indicator: insert では pre-edit の直後に 1 つ、normal では出ない"] = function(s)
  if s.vim_mode == "n" then
    if #s.indicator > 0 then
      return "normal なのにインジケータが出ている"
    end
    return
  end
  if not insert_mode(s) then
    return
  end
  if #s.indicator ~= 1 then
    return ("インジケータが %d 個"):format(#s.indicator)
  end
  -- 既定の row = 1、col = 1。画面のカーソル（pre-edit の直後）の 1 行下、1 桁右
  local expect = { s.screen.row, s.screen.col }
  local got = s.indicator[1].pos
  if got[1] ~= expect[1] or got[2] ~= expect[2] then
    return ("インジケータ %s、期待 %s"):format(short(got), short(expect))
  end
end

M.state["popup: 候補一覧は ▼ の 5 番目の候補から"] = function(s)
  if #s.popup > 1 then
    return ("popup が %d 個"):format(#s.popup)
  end
  local want = s.state.type == "henkan" and (s.state.candidate_index or 0) >= SHOW_CANDIDATES
  if insert_mode(s) and not s.pending and want ~= (#s.popup == 1) then
    return ("popup=%d、候補 %s"):format(#s.popup, tostring(s.state.candidate_index))
  end
end

M.state["resource: ウィンドウとバッファが漏れない"] = function(s, base)
  local floats = #s.popup + #s.indicator
  local base_wins = base.wins - #base.popup - #base.indicator
  if s.wins - floats ~= base_wins then
    return ("普通のウィンドウが %d（元は %d）"):format(s.wins - floats, base_wins)
  end
  -- float のバッファは float と一緒に消える（bufhidden=wipe）ので、普通のバッファの数は変わらない
  local base_bufs = base.bufs - #base.popup - #base.indicator
  if s.bufs - floats ~= base_bufs then
    return ("float 以外のバッファが %d（元は %d）"):format(s.bufs - floats, base_bufs)
  end
end

-- 無効にしたとき（ウィンドウを移ったときなど）は古い値が残る。upstream も handle のときにしか
-- 書き換えないので、有効なときだけ確かめる
M.state["g:skkeleton#state は有効なら状態と一致する"] = function(s)
  local g = s.g_state
  if not g or not s.enabled or registering(s) then
    return
  end
  if (g.henkanFeed or "") ~= s.state.henkan_feed then
    return ("henkanFeed %q、状態 %q"):format(g.henkanFeed, s.state.henkan_feed)
  end
end

M.action = {}

-- #8 の型。skkeleton が処理しなかったキー（<C-u>、矢印など）でバッファやカーソルが動いたら、
-- pre-edit は捨てる（upstream ではバッファの文字だったので、一緒に消えるか動いて無効になる）
M.action["frame: skkeleton の外でバッファやカーソルが動いたら pre-edit を捨てる"] = function(
  p,
  key,
  s
)
  if s.handled ~= p.handled or p.ctx_text == "" or not insert_mode(s) then
    return
  end
  local moved = p.buf ~= s.buf
    or p.cursor[1] ~= s.cursor[1]
    or p.cursor[2] ~= s.cursor[2]
    or table.concat(p.lines, "\n") ~= table.concat(s.lines, "\n")
  if moved and (s.ctx_text ~= "" or #s.preedit_marks > 0) then
    return ("%s のあと pre-edit %q が残っている"):format(key, s.ctx_text)
  end
end

-- 文字のずれ。skkeleton が処理したキーでは、カーソルの前と後ろの文字は変わらない
-- （確定した文字はカーソルの位置に入る）。<BS> は前の 1 文字、<CR> は改行だけ許す
M.action["frame: 確定はカーソル位置に入り、前後の文字を変えない"] = function(p, key, s)
  if s.handled == p.handled or not insert_mode(p) or not insert_mode(s) or p.buf ~= s.buf then
    return
  end
  if #p.lines ~= #s.lines or p.cursor[1] ~= s.cursor[1] then
    return
  end
  local pl, sl = cur_line(p), cur_line(s)
  local before, after = pl:sub(1, p.cursor[2]), pl:sub(p.cursor[2] + 1)
  if key == "<BS>" and p.ctx_text == "" then
    -- 素通しの <BS>。何文字消すかは Neovim（'smarttab' など）が決めるので、前は縮むだけ、後ろは変わらない
    local nb = sl:sub(1, #sl - #after)
    if sl:sub(#sl - #after + 1) ~= after or before:sub(1, #nb) ~= nb then
      return ("%s で %q -> %q（カーソル %d）"):format(key, pl, sl, p.cursor[2])
    end
    return
  end
  if sl:sub(1, #before) ~= before or (#after > 0 and sl:sub(-#after) ~= after) or #sl < #before + #after then
    return ("%s で %q -> %q（カーソル %d）"):format(key, pl, sl, p.cursor[2])
  end
end

return M

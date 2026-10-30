-- 形式検証の PoC: 守るべき性質。
-- state: 1 つの観測（落ち着いた時点の snapshot）で成り立つべき性質（不変条件）
-- action: 1 キーの前後の観測の組 (prev, key, next) で成り立つべき性質（TLA+ の action に当たる）
-- どちらも違反なら説明の文字列を、成り立てば nil を返す
local M = {}

-- 空のマーカー（upstream #103）は探せないので除く
local function markers(s)
  return vim.tbl_filter(function(m)
    return m ~= nil and m ~= ""
  end, { s.opt.markerHenkan, s.opt.markerHenkanSelect })
end

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
-- 文字列を画面の 1 桁ごとに分ける（全角の 2 桁目は ""）
local function cells_of(str)
  local out = {}
  for _, ch in ipairs(vim.fn.split(str, "\\zs")) do
    out[#out + 1] = ch
    for _ = 2, width(ch) do
      out[#out + 1] = ""
    end
  end
  return out
end

M.state["screen: 画面の行はバッファに pre-edit を差し込んだもの"] = function(s)
  -- float の中では headless の screenrow()/screencol() が正しい値を返さない
  -- 'list' のときは listchars（タブや行末の空白の記号）で画面が変わるので比べない
  if not insert_mode(s) or s.pending or s.screen_row <= 0 or s.win_float or s.list then
    return
  end
  local line = cur_line(s)
  if line:find("%c") then
    return
  end
  -- 折り返す行は 1 行の画面と比べられないので見ない（wrap のプロファイルでは他の性質で確かめる）
  if width(line .. mark_text(s) .. annot_text(s)) >= s.win_width - s.textoff then
    return
  end
  local before, after = line:sub(1, s.cursor[2]), line:sub(s.cursor[2] + 1)
  local expect = cells_of(before .. mark_text(s) .. annot_text(s) .. after)
  -- float（インジケータの枠など）が重なる桁から右は比べない
  local left0 = s.win_pos[2] + s.textoff
  local limit = s.win_width - s.textoff
  for _, f in ipairs(vim.list_extend(vim.list_slice(s.popup), s.indicator)) do
    local b = f.border and 1 or 0
    if s.screen_row - 1 >= f.pos[1] and s.screen_row - 1 < f.pos[1] + f.height + 2 * b then
      limit = math.min(limit, f.pos[2] - left0)
    end
  end
  for i = 1, math.min(limit, #expect) do
    local got = s.screen_cells[i] or ""
    local want = expect[i]
    if got ~= want and not (want == " " and got == "") then
      return ("画面 %q、期待 %q（%d 桁目）"):format(s.screen_line, table.concat(expect), i)
    end
  end
  -- 枠つきの float が出ていると、headless の screencol() は正しい値を返さない（端末では正しい。tui.lua で確かめる）
  for _, f in ipairs(vim.list_extend(vim.list_slice(s.popup), s.indicator)) do
    if f.border then
      return
    end
  end
  local col = s.win_pos[2] + s.textoff + width(before .. mark_text(s)) + 1
  if width(before .. mark_text(s)) < limit and s.screen.col ~= col then
    return ("画面のカーソル列 %d、期待 %d"):format(s.screen.col, col)
  end
end

M.state["buffer: マーカーがバッファに漏れない"] = function(s)
  -- terminal では pre-edit を本物の文字として流すので、pre-edit があるあいだは見ない
  if s.buftype == "terminal" and (s.ctx_text ~= "" or registering(s)) then
    return
  end
  -- terminal の前の行は動いているプログラムの出力（<C-c> で ^C つきで残るなど）なので、カーソルの行だけ見る
  if s.buftype == "terminal" then
    local l = s.lines[s.cursor[1]] or ""
    for _, m in ipairs(markers(s)) do
      if l:find(m, 1, true) then
        return ("terminal の今の行 %q に %s"):format(l, m)
      end
    end
    return
  end
  for i, l in ipairs(s.lines) do
    for _, m in ipairs(markers(s)) do
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
  if s.has_sentinel and s.sentinel ~= "user-sentinel" then
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

-- alwaysShown（既定 true）なら、無効でも insert モードでは出る。normal では出ない
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
  local want = (s.enabled or s.ind_cfg.always_shown) and 1 or 0
  if #s.indicator ~= want then
    return ("インジケータが %d 個（%d のはず）"):format(#s.indicator, want)
  end
  if want == 0 then
    return
  end
  -- 画面のカーソル（pre-edit の直後）から row 行下、col 桁右。枠があれば枠の分だけ中身がずれる。
  -- 画面の端で押し戻されるときは、位置は確かめない（「float: 画面に収まる」で確かめる）
  local ind = s.indicator[1]
  -- 位置は枠を含めた左上
  local b = ind.border and 1 or 0
  local expect = { s.screen.row - 1 + s.ind_cfg.row, s.screen.col - 1 + s.ind_cfg.col }
  -- float の中では headless の screenrow()/screencol() が正しい値を返さないので、位置は確かめない
  if s.win_float then
    return
  end
  local fits = expect[2] + ind.width + 2 * b <= s.columns
    and expect[1] + ind.height + 2 * b <= s.editor_lines - s.cmdheight
  local got = ind.pos
  if fits and (got[1] ~= expect[1] or got[2] ~= expect[2]) then
    return ("インジケータ %s、期待 %s"):format(short(got), short(expect))
  end
end

M.state["popup: 候補一覧は ▼ の 5 番目の候補から"] = function(s)
  if #s.popup > 1 then
    return ("popup が %d 個"):format(#s.popup)
  end
  local want = s.state.type == "henkan" and (s.state.candidate_index or 0) >= s.opt.showCandidatesCount
  if insert_mode(s) and not s.pending and want ~= (#s.popup == 1) then
    return ("popup=%d、候補 %s"):format(#s.popup, tostring(s.state.candidate_index))
  end
end

M.state["resource: ウィンドウとバッファが漏れない"] = function(s, base)
  -- 今のウィンドウが float（検査で開いたもの）のときは、その中でバッファが入れ替わることがあるので比べない
  if s.win_float then
    return
  end
  local floats = #s.popup + #s.indicator + (s.other_floats or 0)
  local base_wins = base.wins - #base.popup - #base.indicator - (base.other_floats or 0)
  if s.wins - floats ~= base_wins then
    return ("普通のウィンドウが %d（元は %d）"):format(s.wins - floats, base_wins)
  end
  -- float のバッファは float と一緒に消える（bufhidden=wipe）ので、普通のバッファの数は変わらない
  local base_bufs = base.bufs - #base.popup - #base.indicator - (base.other_float_bufs or 0)
  local float_bufs = #s.popup + #s.indicator + (s.other_float_bufs or 0)
  if s.bufs - float_bufs ~= base_bufs then
    return ("float 以外のバッファが %d（元は %d）"):format(s.bufs - float_bufs, base_bufs)
  end
end

-- 無効にしたとき（ウィンドウを移ったときなど）も含めて状態と一致する
M.state["g:skkeleton#state は有効なら状態と一致する"] = function(s)
  local g = s.g_state
  if not g or registering(s) then
    return
  end
  if (g.henkanFeed or "") ~= s.state.henkan_feed then
    return ("henkanFeed %q、状態 %q"):format(g.henkanFeed, s.state.henkan_feed)
  end
end

M.state["indicator: 表示は今のモードの文字列"] = function(s)
  local ind = s.indicator[1]
  if ind and s.want_indicator and ind.text ~= s.want_indicator then
    return ("インジケータ %q、モード %q なら %q"):format(ind.text, s.skk_mode, s.want_indicator)
  end
end

M.state["popup: 中身は今のページの候補"] = function(s)
  local p = s.popup[1]
  if not p or not s.want_popup or s.pending then
    return
  end
  local got = {}
  for _, l in ipairs(p.lines) do
    -- "a: 候補" や "a: 候補  ;注釈" の候補の部分
    got[#got + 1] = (l:gsub("^%S*: ", ""):gsub("%s+;.*$", ""):gsub("%s+$", ""))
  end
  local want = vim.tbl_map(function(c)
    return (c:gsub(";.*$", ""))
  end, s.want_popup)
  if table.concat(got, "/") ~= table.concat(want, "/") then
    return ("popup %s、ページ %s"):format(short(got), short(want))
  end
end

-- float（popup とインジケータ）は画面の中に収まり、カーソルのセルを隠さない
M.state["float: 画面に収まり、カーソルを隠さない"] = function(s)
  local bottom = s.editor_lines - s.cmdheight
  local all = {}
  for _, f in ipairs(s.popup) do
    all[#all + 1] = { f = f, kind = "popup" }
  end
  for _, f in ipairs(s.indicator) do
    all[#all + 1] = { f = f, kind = "インジケータ" }
  end
  for _, e in ipairs(all) do
    local f = e.f
    local b = f.border and 1 or 0
    local top, left = f.pos[1], f.pos[2]
    local h, w = f.height + 2 * b, f.width + 2 * b
    if top < 0 or left < 0 or left + w > s.columns or top + h > bottom then
      return ("%s (%d,%d) %dx%d が画面 %dx%d からはみ出す"):format(e.kind, top, left, h, w, bottom, s.columns)
    end
    local crow, ccol = s.screen.row - 1, s.screen.col - 1
    if s.vim_mode:sub(1, 1) == "i" and crow >= top and crow < top + h and ccol >= left and ccol < left + w then
      return ("%s%s (%d,%d) %dx%d がカーソル (%d,%d) を隠す"):format(
        e.kind,
        f.border and "（枠つき）" or "",
        top,
        left,
        h,
        w,
        crow,
        ccol
      )
    end
  end
end

-- cmdline の pre-edit は本物の文字なので、カーソルの前が pre-edit で終わる。
-- pre-edit が無いのにマーカーが残っていたら、消し忘れ（#12 の型）
M.state["cmdline: pre-edit が無ければマーカーを残さない"] = function(s)
  if not s.cmdline or not s.enabled then
    return
  end
  if s.ctx_text == "" then
    for _, m in ipairs(markers(s)) do
      if s.cmdline:find(m, 1, true) then
        return ("pre-edit が無いのに cmdline %q に %s が残っている"):format(s.cmdline, m)
      end
    end
  end
end

-- blink.cmp の skkeleton の候補は ▽ の入力中だけ（upstream の getCompletionResult と同じ）。
-- ▽ を抜けたら（確定、取り消し、変換）メニューは閉じる
M.state["blink: 有効なら、メニューは ▽ の入力中だけ"] = function(s)
  if s.menu == nil or not s.menu or not s.enabled or not insert_mode(s) then
    return
  end
  local st = s.state
  if not (st.type == "input" and st.mode == "okurinasi" and st.henkan_feed ~= "") then
    return ("状態 %s/%s %q でメニューが出ている: %s"):format(
      st.type,
      tostring(st.mode),
      st.henkan_feed,
      short(s.menu_items)
    )
  end
end

-- upstream #69: skkeleton#mode() と実際のモードが食い違う
M.state["mode: g:skkeleton#mode は内部のモードと同じ（無効なら空）"] = function(s)
  if registering(s) then
    return
  end
  if s.enabled and s.skk_mode ~= s.ctx_mode then
    return ("g:skkeleton#mode %q、内部のモード %q"):format(s.skk_mode, tostring(s.ctx_mode))
  end
  if not s.enabled and s.skk_mode ~= "" then
    return ("無効なのに g:skkeleton#mode が %q"):format(s.skk_mode)
  end
end

-- マクロ（#36 の型）: 記録したレジスタには、利用者が打ったキーだけが入り、skkeleton が内部で流したもの
-- （確定の文字列を入れたあとの finish() の呼び出し）は入らない
M.state["macro: レジスタに skkeleton が内部で流したものが入らない"] = function(s)
  if s.recording == "" and s.reg_a and s.reg_a:find("skkeleton.render", 1, true) then
    return ("レジスタ a に %q"):format(s.reg_a:sub(1, 60))
  end
end

-- 2 手以上をまたぐ性質のための履歴。各キーのあとに呼ぶ
-- hist.before_register: 辞書登録の input() に入る直前の観測
function M.observe(hist, prev, s)
  -- insert から normal へ抜けたときの、有効かとモード（keepState / keepMode の確かめに使う）
  if prev and insert_mode(prev) and s.vim_mode == "n" then
    hist.left_insert = { enabled = prev.enabled, mode = prev.skk_mode, buf = prev.buf, by_esc = s.key == "<Esc>" }
  elseif prev and prev.vim_mode == "n" and insert_mode(s) then
    hist.left_insert = nil
  end
  if registering(s) then
    if prev and not registering(prev) then
      hist.before_register = prev
    end
  else
    hist.before_register = nil
  end
end

M.action = {}

local function count(s, name)
  return (s.events or {})[name] or 0
end

-- upstream #130: 辞書登録から出るときに disable の autocmd が発火する。
-- disable-post は、有効から無効に変わったときだけ発火する
M.action["event: disable-post は無効になったときだけ"] = function(p, key, s)
  if not p.events or not s.events or registering(p) or registering(s) then
    return
  end
  local fired = count(s, "skkeleton-disable-post") > count(p, "skkeleton-disable-post")
  local disabled = p.enabled and not s.enabled
  if fired ~= disabled then
    return ("%s で disable-post %s、有効 %s -> %s"):format(
      key,
      fired and "が発火" or "が発火しない",
      tostring(p.enabled),
      tostring(s.enabled)
    )
  end
end

-- upstream #43: skkeleton-mode-changed がすぐに発火しない
M.action["event: モードが変わったら mode-changed が発火する"] = function(p, key, s)
  if not p.events or not s.events then
    return
  end
  if p.skk_mode ~= s.skk_mode and count(s, "skkeleton-mode-changed") == count(p, "skkeleton-mode-changed") then
    return ("%s でモードが %q -> %q になったのに mode-changed が来ない"):format(
      key,
      p.skk_mode,
      s.skk_mode
    )
  end
end

-- upstream #4・#45: toggle で無効にできない／二度押しが要る。
-- 打ちかけの無い入力中なら無効にし、無効ならひらがな（keepMode なら前のモード）で有効にする
M.action["toggle: <C-j> で有効・無効が切り替わる"] = function(p, key, s)
  if key ~= "<C-j>" or not insert_mode(p) or not insert_mode(s) or registering(p) then
    return
  end
  if not p.enabled then
    if not s.enabled then
      return "無効のときに <C-j> を押しても有効にならない"
    end
    return
  end
  local plain = p.state.type == "input" and p.state.mode == "direct" and p.state.feed == "" and p.ctx_text == ""
  if plain and (p.skk_mode == "hira" or p.skk_mode == "kata" or p.skk_mode == "hankata") and s.enabled then
    return ("モード %q の入力中に <C-j> を押しても無効にならない"):format(p.skk_mode)
  end
end

-- <Left> などでカーソルだけ動いたときは、次のキーで片付ける（#12 の修正）。
-- skkeleton がキーを処理した直後は、cmdline のカーソルの前が pre-edit で終わる
M.action["cmdline: skkeleton が処理したあと、カーソルの前は pre-edit で終わる"] = function(p, key, s)
  if not s.cmdline or not s.enabled or s.handled == p.handled or s.ctx_text == "" then
    return
  end
  local before = s.cmdline:sub(1, s.cmdpos - 1)
  if before:sub(-#s.ctx_text) ~= s.ctx_text then
    return ("%s のあと cmdline %q（位置 %d）が pre-edit %q で終わらない"):format(
      key,
      s.cmdline,
      s.cmdpos,
      s.ctx_text
    )
  end
end

M.action["keepState: 同じバッファで insert に戻ると有効になる（keepMode ならモードも戻る）"] = function(
  p,
  key,
  s,
  hist
)
  local l = hist and hist.left_insert
  -- upstream と同じく、抜けたバッファで insert に戻ったときだけ（InsertEnter <buffer>）
  -- keepState は skkeleton の <Esc>（escape）で抜けたときだけ効く（<C-c> などは skkeleton を通らない。upstream も同じ）
  if
    not (s.opt.keepState and l and l.enabled and l.by_esc and p.vim_mode == "n" and insert_mode(s) and s.buf == l.buf)
  then
    return
  end
  -- モードまで戻すのは keepMode のときだけ（upstream も lastMode を keepMode のときだけ覚える）
  if not s.enabled or (s.opt.keepMode and s.skk_mode ~= l.mode) then
    return ("%s で insert に戻ると enabled=%s mode=%q、抜ける前は %q"):format(
      key,
      tostring(s.enabled),
      s.skk_mode,
      l.mode
    )
  end
end

-- d5fc182 の型。辞書登録を <Esc> や <C-g> で取り消したら、登録に入る前の行・カーソル・pre-edit に戻る
M.action["register: 取り消すと登録の前に戻る"] = function(p, key, s, hist)
  local b = hist and hist.before_register
  if not (b and registering(p) and not registering(s) and (key == "<Esc>" or key == "<C-g>")) then
    return
  end
  -- terminal のバッファの行とカーソルは、動いているプログラムが決めるので比べない
  if s.buftype == "terminal" then
    return
  end
  -- 取り消したら ▼ の前の ▽ に戻る（upstream と同じ）。行とカーソルは変わらない
  if s.cursor[1] ~= b.cursor[1] or s.cursor[2] ~= b.cursor[2] then
    return ("カーソル %s、登録の前は %s"):format(short(s.cursor), short(b.cursor))
  end
  if table.concat(s.lines, "\n") ~= table.concat(b.lines, "\n") then
    return ("行 %q、登録の前は %q"):format(cur_line(s), cur_line(b))
  end
  -- insert で登録に入ったら insert に、cmdline の中で入ったら cmdline に戻る
  if s.ctx_text == "" or s.vim_mode:sub(1, 1) ~= b.vim_mode:sub(1, 1) then
    return ("pre-edit %q（mode %s）、登録の前は %q（mode %s）"):format(
      s.ctx_text,
      s.vim_mode,
      b.ctx_text,
      b.vim_mode
    )
  end
end

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

-- 見つかったが、今は直さないもの。反例の性質の名前と、キー列で見分ける。
-- 当てはまる違反は「既知」として出し、失敗にしない
M.known = {}

-- ウィンドウの最後の行の右端で入力すると、折り返した pre-edit が @@@ で隠れる（#34）
M.known[#M.known + 1] = {
  property = "screen: 画面の行はバッファに pre-edit を差し込んだもの",
  match = function(keys, msg)
    return keys[1] == "#corner" or keys[1] == "#bottom" or (msg and msg:find("@@", 1, true) ~= nil)
  end,
  reason = "#34: ウィンドウの最後の行の右端で入力すると、折り返した pre-edit が @@@ で隠れて見えない",
}

-- 'list' でカーソルの直後がタブのとき、端末のカーソルが pre-edit の上に描かれる（#35）
M.known[#M.known + 1] = {
  property = "indicator: insert では pre-edit の直後に 1 つ、normal では出ない",
  match = function(keys)
    return keys[1] == "#list"
  end,
  reason = "#35: 'list' でカーソルの直後がタブのとき、端末のカーソルが pre-edit の上に描かれる",
}

-- マクロに確定の文字列と finish() の呼び出しが入る（#36）
M.known[#M.known + 1] = {
  property = "macro: レジスタに skkeleton が内部で流したものが入らない",
  match = function()
    return true
  end,
  reason = "#36: skkeleton の入力をマクロに記録して再生すると、確定した文字列が二重に入って崩れる",
}

function M.is_known(name, keys, msg)
  for _, k in ipairs(M.known) do
    if k.property == name and k.match(keys, msg) then
      return k
    end
  end
end

return M

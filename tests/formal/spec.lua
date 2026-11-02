-- 形式検証の PoC: 守るべき性質。
-- state: 1 つの観測（落ち着いた時点の snapshot）で成り立つべき性質（不変条件）
-- action: 1 キーの前後の観測の組 (prev, key, next) で成り立つべき性質（TLA+ の action に当たる）
-- どちらも違反なら説明の文字列を、成り立てば nil を返す
local M = {}

-- インジケータの不具合は追わない（利用者の判断）が、性質は既定で入れてある。
-- FORMAL_INDICATOR=0 で「indicator:」の性質と「float:」のインジケータの部分を切る
local CHECK_INDICATOR = os.getenv("FORMAL_INDICATOR") ~= "0"

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
    -- 辞書登録のプロンプトの中でタイマーがカーソルを動かしても、pre-edit は元の位置に残す
    -- （host.input が終わったときにカーソルを戻す）。register プロファイルの <StealCursor>
    if not registering(s) and (m.row ~= s.cursor[1] - 1 or m.col ~= s.cursor[2]) then
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
  -- cmdline window の行は端末では "@ " などの印が頭に付く。skkeleton のバッファではないので見ない
  if s.cmdwin ~= "" then
    return
  end
  -- float の中では headless の screenrow()/screencol() が正しい値を返さない
  -- 'list' のときは listchars（タブや行末の空白の記号）で画面が変わるので比べない
  if not insert_mode(s) or s.pending or s.screen_row <= 0 or s.win_float or s.list then
    return
  end
  -- 検査の <StealFloat> が開いた float（skkeleton のものではない）が、カーソルの行の右側を覆うことがある。
  -- 位置を観測していないので、そのあいだは比べない（steal・register の fuzz の誤検出）
  if (s.other_floats or 0) > 0 then
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

M.state["buffer: マーカーがバッファに漏れない"] = function(s, _, hist)
  -- cmdline window（<C-f>）は、開く前の cmdline の文字（本物の ▽ を含む）をバッファに持つ。upstream も同じ
  if s.cmdwin ~= "" then
    return
  end
  -- terminal では pre-edit を本物の文字として流すので、pre-edit があるあいだは見ない
  if s.buftype == "terminal" and (s.ctx_text ~= "" or registering(s)) then
    return
  end
  -- terminal の前の行は動いているプログラムの出力（<C-c> で ^C つきで残るなど）なので、カーソルの行だけ見る
  if s.buftype == "terminal" then
    local l = s.lines[s.cursor[1]] or ""
    -- pre-edit のあいだに <C-r> を押すと、キーはジョブ（bash）に渡り、行に書いてあった本物の ▽ がそのまま残る。upstream も同じ
    if hist and hist.term_ctrl_r then
      return
    end
    -- bash の <C-r>（reverse-i-search）は、行に書いてあった ▼ を本物の文字として検索の入力に持つ。upstream も同じ
    if l:find("(failed reverse-i-", 1, true) or l:find("(reverse-i-", 1, true) then
      return
    end
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
  -- 辞書登録の欄の <C-f> で開く cmdline window は normal だが、欄は続いている（skkeleton は有効のまま）
  if s.enabled and s.cmdwin == "" then
    return "normal なのに enabled"
  end
  if s.cmdwin ~= "" then
    return
  end
  if s.ctx_text ~= "" or s.state.type ~= "input" or s.state.mode ~= "direct" then
    return ("normal なのに状態 %s %q が残っている"):format(short(s.state), s.ctx_text)
  end
  -- cmdline window（: の中の <C-f>）のバッファは、Vim が 'textwidth' を 0 にする（regcmd の検査で見つけた誤検出）
  if s.textwidth ~= 78 and s.cmdwin == "" then
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
  -- cmdline window の中は skkeleton のバッファではない（登録のプロンプトは続いている）。e91f913 の緩和と同じ
  if s.cmdwin ~= "" then
    return
  end
  if s.enabled and insert_mode(s) and s.skk_maps_here == 0 then
    return "有効なのに今のバッファにマッピングが無い"
  end
end

-- インジケータの決まり（#76）:
-- 出すのは insert・cmdline に入ったときと skkeleton のモードが変わったとき。出す場所はそのときのカーソルの右下で、
-- 出したあとは動かさない。pre-edit が出ているあいだは出さない。画面の端ではカーソルに重なってもよい。
-- fadeOutMs（既定 3000ms）は、1 キーの検査が数十 ms で終わる前提でたたないものとして扱う

-- alwaysShown（既定 true）なら、無効でも insert では出る。出ていれば 1 つで、中身は今のモードの文字列
M.state["indicator: 出ているのは insert・cmdline で pre-edit が無いときだけ、1 つで今のモードの文字列"] = function(
  s
)
  if #s.indicator == 0 then
    return
  end
  if #s.indicator > 1 then
    return ("インジケータが %d 個"):format(#s.indicator)
  end
  if not insert_mode(s) and not s.cmdline then
    return ("mode %s でインジケータが出ている"):format(s.vim_mode)
  end
  local pre = s.g_state and s.g_state.preedit or ""
  if pre ~= "" or s.ctx_text ~= "" then
    return ("pre-edit（g:skkeleton#state.preedit=%q、状態 %q）があるのにインジケータが出ている"):format(
      pre,
      s.ctx_text
    )
  end
  if not (s.enabled or s.ind_cfg.always_shown) then
    return "無効で alwaysShown = false なのにインジケータが出ている"
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
  -- 辞書登録のプロンプトの <C-f> で開く cmdline window は、閉じるまでの普通のウィンドウ（register プロファイル）
  if s.cmdwin ~= nil and s.cmdwin ~= "" then
    return
  end
  local floats = #s.popup + #s.indicator + (s.other_floats or 0)
  local base_wins = base.wins - #base.popup - #base.indicator - (base.other_floats or 0)
  if s.wins - floats ~= base_wins then
    return ("普通のウィンドウが %d（元は %d）"):format(s.wins - floats, base_wins)
  end
  -- バッファの漏れは「どのウィンドウにも出ていない unlisted バッファ」の増加で見る。
  -- 全バッファの数で比べると、検査の <StealFloat> で作った float や、その中の <C-^> が開く普通のバッファを
  -- 漏れと取り違える（#steal のファジングで見つかった誤検出）。skkeleton の popup・インジケータは unlisted の
  -- スクラッチで bufhidden=wipe なので、漏れればここに出る
  if (s.hidden_scratch or 0) > (base.hidden_scratch or 0) then
    return ("表示されていない unlisted バッファが %d（元は %d）"):format(
      s.hidden_scratch,
      base.hidden_scratch or 0
    )
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

-- float（popup とインジケータ）は画面の中に収まる。popup はカーソルのセルを隠さない（インジケータは画面の端で重なってよい）
M.state["float: 画面に収まり、popup はカーソルを隠さない"] = function(s)
  local bottom = s.editor_lines - s.cmdheight
  local all = {}
  for _, f in ipairs(s.popup) do
    all[#all + 1] = { f = f, kind = "popup" }
  end
  for _, f in ipairs(CHECK_INDICATOR and s.indicator or {}) do
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
    if
      e.kind == "popup"
      and s.vim_mode:sub(1, 1) == "i"
      and crow >= top
      and crow < top + h
      and ccol >= left
      and ccol < left + w
    then
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

-- #11: ▼ の候補に注釈があれば、候補一覧より前（showCandidatesCount 未満）の間は pre-edit の後ろに ;注釈 を薄く出す
M.state["annotation: 注釈は ▼ の今の候補のものだけ"] = function(s)
  if not insert_mode(s) or s.pending or s.want_annot == nil then
    return
  end
  local got = annot_text(s)
  if got ~= s.want_annot then
    return ("注釈の表示 %q、今の候補なら %q"):format(got, s.want_annot)
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
-- 矩形選択の I・A は、<Esc> で入力した文字を選んだ全部の行に繰り返す（Vim の仕様）。
-- block プロファイルの行は全部同じ文字列で始まるので、繰り返しが終わったあとも全部の行が同じになる。
-- skkeleton の確定やマーカーの掃除が繰り返しをずらしたり、マーカーが一部の行に混ざったりしないかを見る
M.state["block: 矩形選択の insert を抜けたら、全部の行が同じ"] = function(s)
  -- Vim 自身が繰り返さない場合は見ない（素の Vim でも同じ）。開始位置より前を <BS> で消すと、
  -- 繰り返しは 1 行目だけ（"XYb cd" / "aYb cd"）になる。<CR> で行が増えたときも、行をまたぐ入力は繰り返さない。
  -- 行頭の "a" が残っていて行数が変わらないときだけ、全部の行が同じになるはず
  if not s.block_done or not s.block_rows or #s.lines ~= 3 then
    return
  end
  -- 選んだ行（block_rows）だけを比べる。k・j で選ぶ行は変わる
  local top, bot = s.block_rows[1], s.block_rows[2]
  if s.lines[top]:sub(1, 1) ~= "a" then
    return
  end
  for i = top + 1, bot do
    if s.lines[i] ~= s.lines[top] then
      return ("行 %d と行 %d が違う: %s"):format(top, i, short(s.lines))
    end
  end
end

M.state["macro: レジスタに skkeleton が内部で流したものが入らない"] = function(s)
  if s.recording == "" and s.reg_a and s.reg_a:find("skkeleton.render", 1, true) then
    return ("レジスタ a に %q"):format(s.reg_a:sub(1, 60))
  end
end

-- #36・#44 の型: Vim のレジスタと履歴に、pre-edit のマーカーや skkeleton の内部のコマンドが漏れない
-- 辞書登録のプロンプトは、開いているあいだだけ input_depth が 1 以上になる。プロンプト（cmdline の "@"）も
-- cmdline window（<C-f>）も無いのに深さが残っていたら、入れ子が巻き戻っていない
M.state["register: プロンプトが無いのに登録の深さが残らない"] = function(s)
  if (s.input_depth or 0) > 0 and s.cmdtype ~= "@" and s.cmdwin == "" then
    return ("input_depth=%d だが、プロンプトも cmdline window も無い（mode %s）"):format(
      s.input_depth,
      s.vim_mode
    )
  end
  if (s.input_depth or 0) == 0 and s.cmdtype == "@" then
    return "input() の中なのに input_depth=0"
  end
end

M.state["global: レジスタと履歴にマーカーや内部のコマンドが漏れない"] = function(s, _, hist)
  if not s.globals or s.recording ~= "" then
    return
  end
  -- <C-r> で貼り付けたあとの cmdline に本物の ▽ が残っていたら、履歴にもそのまま入る（upstream も同じ）
  local pasted = hist and hist.pasted_marker
  for where, text in vim.spairs(s.globals) do
    -- 登録の取り消しの内部の語は @ だけでなく、外側の cmdline の履歴（: と /）にも入ってはいけない（regcmd）
    if where:find("^hist ") and text:find("__skkeleton_return__", 1, true) then
      return ("%s に登録の取り消しの内部の語 %q"):format(where, text)
    end
    if text:find("skkeleton.render", 1, true) then
      return ("%s に skkeleton の内部のコマンド %q"):format(where, vim.fn.strtrans(text):sub(1, 60))
    end
    for _, m in ipairs(markers(s)) do
      if text:find(m, 1, true) and not (pasted and (where:find("^hist ") or where == "reg /" or where == "reg :")) then
        return ("%s に %s（%q）"):format(where, m, vim.fn.strtrans(text):sub(1, 60))
      end
    end
  end
end

-- 2 手以上をまたぐ性質のための履歴。各キーのあとに呼ぶ
-- hist.before_register: 辞書登録の input() に入る直前の観測
function M.observe(hist, prev, s)
  -- 複数のキーをまとめた操作（Q1 など）のあいだにバッファが変わると、途中の状態（undo の区切り）を
  -- 観測していないので、そのあとの undo は確かめない
  local key = s.key or ""
  local multi = #key > 1 and not key:match("^<[^>]+>$")
  if prev and multi and table.concat(prev.lines, "\n") ~= table.concat(s.lines, "\n") then
    hist.unseen = true
  end
  -- これまでに観測したバッファの状態（undo の性質で使う）
  hist.texts = hist.texts or {}
  -- cmdline の中で <C-r> を押したとき、すでに本物の ▽ があった。その cmdline（と、閉じたあとの履歴の 1 手）では残ってよい
  -- <C-f> も同じ: cmdline の本物の ▽ が cmdline window の行になり、<CR> で履歴に入る（upstream も同じ）
  if prev and prev.buftype == "terminal" and prev.ctx_text ~= "" and (s.key or ""):find("^<C%-r>") then
    hist.term_ctrl_r = true
  end
  if prev and prev.cmdline and ((s.key or ""):find("^<C%-r>") or s.key == "<C-f>") then
    for _, m in ipairs(markers(s)) do
      if prev.cmdline:find(m, 1, true) then
        hist.pasted_marker = true
      end
    end
  elseif hist.pasted_marker and prev and not prev.cmdline and prev.cmdwin == "" then
    hist.pasted_marker = nil
  end
  if prev then
    hist.texts[(prev.buf or 0) .. ":" .. table.concat(prev.lines, "\n")] = true
  end
  hist.texts[(s.buf or 0) .. ":" .. table.concat(s.lines, "\n")] = true
  -- insert から normal へ抜けたときの、有効かとモード（keepState / keepMode の確かめに使う）
  if prev and insert_mode(prev) and s.vim_mode == "n" then
    hist.left_insert = { enabled = prev.enabled, mode = prev.skk_mode, buf = prev.buf, by_esc = s.key == "<Esc>" }
  elseif prev and prev.vim_mode == "n" and insert_mode(s) then
    hist.left_insert = nil
  end
  -- 入れ子の登録の外側に戻れるよう、プロンプトに入る直前の観測を積む（register の性質）
  hist.reg_stack = hist.reg_stack or {}
  local pd, sd = prev and prev.input_depth or 0, s.input_depth or 0
  if sd > pd and prev then
    -- 1 つのキーで開いたときだけ、直前の観測を「開く前」とみなす。Kan のようなマクロ遷移は、途中の
    -- 状態を観測していないので、false にして性質を確かめない
    -- 送り仮名で開く A A のようなキーは、開いたキーが外側の状態も変えるので、<Space> で開いたときだけ確かめる
    local k = s.key or ""
    if k ~= "<Space>" then
      hist.reg_stack[sd] = false
    else
      hist.reg_stack[sd] = prev
    end
  elseif sd < pd then
    for d = sd + 1, pd do
      hist.reg_stack[d] = nil
    end
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

-- 例外: <C-r> での貼り付け（hist.pasted_marker。regcmd の検査で見つけた誤検出）。skkeleton を通らない挿入は pre-edit の状態を捨てるが、
-- すでに cmdline に書いてあった ▽ は本物の文字として残る。upstream（denops 版）も同じ（"ab▽か" + <C-r>" は "ab▽かふが"）
M.action["cmdline: pre-edit が無ければマーカーを残さない"] = function(p, key, s, hist)
  if not s.cmdline or not s.enabled or (hist and hist.pasted_marker) or key:find("^<C%-r>") then
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

-- インジケータは、出したあとに動かさず、文字が入る・カーソルが動く・スクロールする・cmdline が変わるのどれかで閉じる
M.action["indicator: 出ているあいだ動かず、文字・カーソル・スクロールの変化で閉じる"] = function(
  p,
  key,
  s
)
  if not CHECK_INDICATOR or s.cmdwin ~= "" or registering(s) or registering(p) then
    return
  end
  for _, a in ipairs(p.indicator) do
    for _, b in ipairs(s.indicator) do
      if a.win == b.win then
        if a.pos[1] ~= b.pos[1] or a.pos[2] ~= b.pos[2] then
          return ("インジケータが %s から %s に動いた"):format(short(a.pos), short(b.pos))
        end
        if s.buf == p.buf and not s.win_float then
          if s.win == p.win and insert_mode(s) and not vim.deep_equal(p.lines, s.lines) then
            return "文字が入ったのにインジケータが残っている"
          end
          if insert_mode(s) and not vim.deep_equal(p.cursor, s.cursor) then
            return ("カーソルが %s から %s に動いたのにインジケータが残っている"):format(
              short(p.cursor),
              short(s.cursor)
            )
          end
          -- cmdline の最中は WinScrolled・WinResized が来ない（画面の大きさを変えても、cmdline を抜けるまで届かない）ので確かめない
          if
            insert_mode(s) and (p.topline ~= s.topline or p.win_height ~= s.win_height or p.win_width ~= s.win_width)
          then
            return "スクロールかウィンドウの大きさが変わったのにインジケータが残っている"
          end
          if p.cmdline ~= s.cmdline then
            return "cmdline が変わったのにインジケータが残っている"
          end
        end
      end
    end
  end
end

-- モードの切り替え（q、l、L、/、<C-j> など）のあと、pre-edit が無く、文字もカーソルも動いていなければ、インジケータが出ている
M.action["indicator: モードが変わったあと pre-edit が無ければ出ている"] = function(p, key, s)
  if not CHECK_INDICATOR or s.cmdwin ~= "" or registering(s) or s.pending or s.win_float then
    return
  end
  if not (insert_mode(s) or s.cmdline) or p.vim_mode ~= s.vim_mode then
    return
  end
  if p.skk_mode == s.skk_mode and p.enabled == s.enabled then
    return
  end
  if not (s.enabled or s.ind_cfg.always_shown) then
    return
  end
  local pre = s.g_state and s.g_state.preedit or ""
  if pre ~= "" or s.ctx_text ~= "" then
    return
  end
  if
    p.buf ~= s.buf
    or p.win ~= s.win
    or not vim.deep_equal(p.lines, s.lines)
    or not vim.deep_equal(p.cursor, s.cursor)
  then
    return
  end
  if #s.indicator ~= 1 then
    return ("モードが %s/%s から %s/%s に変わったのにインジケータが %d 個"):format(
      p.skk_mode,
      tostring(p.enabled),
      s.skk_mode,
      tostring(s.enabled),
      #s.indicator
    )
  end
end

-- 組み込みの補完（<C-x><C-u>）は pre-edit の読みだけを候補で置き換え、カーソルの前にあった文字は消さない
M.action["completion: <C-x><C-u> でカーソルの前の文字が消えない"] = function(p, key, s)
  if key ~= "<C-x><C-u>" or not insert_mode(p) or p.buf ~= s.buf or p.cursor[1] ~= s.cursor[1] then
    return
  end
  local before = cur_line(p):sub(1, p.cursor[2])
  if cur_line(s):sub(1, #before) ~= before then
    return ("<C-x><C-u> で、カーソルの前の %q が消えた（行 %q -> %q）"):format(
      before,
      cur_line(p),
      cur_line(s)
    )
  end
end

-- upstream #51（mode.ts の katakana）: カタカナ・半角カタカナモードで ▽ の読みがあるとき q を押すと、
-- 変換せずにひらがなの読みのまま確定する（ひらがなモードのときだけ、読みをカタカナにして確定する）。
-- 確定した文字に、カタカナ（全角も半角も）が入らない
M.action["mode: カタカナ系のモードの ▽ で q を押すと、ひらがなの読みで確定する"] = function(
  p,
  key,
  s
)
  if key ~= "q" or not insert_mode(p) or not insert_mode(s) or p.buf ~= s.buf or p.cursor[1] ~= s.cursor[1] then
    return
  end
  if p.skk_mode ~= "kata" and p.skk_mode ~= "hankata" then
    return
  end
  local st = p.state
  if st.type ~= "input" or st.mode ~= "okurinasi" or st.feed ~= "" or st.henkan_feed == "" then
    return
  end
  local pl, sl = cur_line(p), cur_line(s)
  local before, after = pl:sub(1, p.cursor[2]), pl:sub(p.cursor[2] + 1)
  if sl:sub(1, #before) ~= before or (#after > 0 and sl:sub(-#after) ~= after) or #sl < #before + #after then
    return
  end
  local inserted = sl:sub(#before + 1, #sl - #after)
  for _, c in ipairs(vim.fn.split(inserted, "\zs")) do
    local n = vim.fn.char2nr(c)
    if (n >= 0x30A1 and n <= 0x30FA) or (n >= 0xFF66 and n <= 0xFF9F) then
      return ("モード %q の ▽%q で q を押したら、ひらがなで確定するはずが %q になった"):format(
        p.skk_mode,
        st.henkan_feed,
        inserted
      )
    end
  end
end

-- 候補一覧（popup）で選択キーを押すと、そのページの i 番目の候補が、カーソルの位置にそのまま確定する
local SELECT = { a = 1, s = 2, d = 3, f = 4, j = 5, k = 6, l = 7 }
M.action["popup: 選択キーで選んだ候補が確定する"] = function(p, key, s)
  local i = SELECT[key]
  if not i or not p.want_popup or #p.popup ~= 1 or not insert_mode(p) or not insert_mode(s) then
    return
  end
  local cand = p.want_popup[i]
  if not cand then
    return
  end
  cand = cand:gsub(";.*$", "")
  local pl = cur_line(p)
  local before, after = pl:sub(1, p.cursor[2]), pl:sub(p.cursor[2] + 1)
  local want = before .. cand .. after
  -- 送り仮名つき（▼悪る など）のときは送り仮名も入るので、候補が入っていることだけを見る
  local sl = table.concat(s.lines, "\n")
  if not sl:find(before .. cand, 1, true) or s.ctx_text ~= "" then
    return ("%s で %q を選んだはずが、行 %q（pre-edit %q）、期待 %q"):format(
      key,
      cand,
      cur_line(s),
      s.ctx_text,
      want
    )
  end
end

-- upstream #41 の型: normal の u と <C-r> は、これまでに観測したバッファの状態のどれかに戻る
-- （入力の途中の、存在しなかった状態にはならない）
M.action["undo: u と <C-r> は観測したことのある状態に戻る"] = function(p, key, s, hist)
  if (key ~= "u" and key ~= "<C-r>") or p.vim_mode ~= "n" or not hist or not hist.texts or hist.unseen then
    return
  end
  local text = (s.buf or 0) .. ":" .. table.concat(s.lines, "\n")
  if not hist.texts[text] then
    return ("%s のあとのバッファ %s は、これまでに無かった状態"):format(key, short(s.lines))
  end
end

local function count(s, name)
  return (s.events or {})[name] or 0
end

-- upstream #130: 辞書登録から出るときに disable の autocmd が発火する。
-- disable-post は、有効から無効に変わったときだけ発火する
-- @a や . は記録したキーを 1 ステップでまとめて再生するので、途中で有効・無効が行き来してもよい
local function replays(key)
  return key == "." or (key or ""):match("^@") ~= nil
end

M.action["event: disable-post は無効になったときだけ"] = function(p, key, s)
  if not p.events or not s.events or registering(p) or registering(s) or replays(key) then
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
  if not p.events or not s.events or replays(key) then
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
  -- 登録の最中に :stopinsert が走ると（register プロファイルの <StopinsertLater>）、取り消したあとで insert を抜ける。
  -- カーソルは normal の位置（1 つ左）になり、skkeleton は無効になる。登録の前と比べない（normal に戻ったあとの
  -- 片付けは、ほかの性質が見る）
  if b.vim_mode:sub(1, 1) == "i" and s.vim_mode:sub(1, 1) ~= "i" then
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

-- 辞書登録のプロンプトが 1 つ閉じた直後（深さが 1 減った）の前後の観測を返す。
-- b は、そのプロンプトを開く直前の観測。typed は、閉じる直前のプロンプトの中身
local function closed_prompt(p, key, s, hist, allow_term)
  if not (p.input_depth and s.input_depth and p.input_depth == s.input_depth + 1) then
    return
  end
  local b = hist and hist.reg_stack and hist.reg_stack[p.input_depth]
  if not b or (not allow_term and (s.buftype == "terminal" or b.buftype == "terminal")) then
    return
  end
  local typed = p.cmdline
  local clean = typed and typed ~= "" and p.ctx_text == ""
  if clean then
    for _, m in ipairs(markers(p)) do
      if typed:find(m, 1, true) or typed:find("__skkeleton_return__", 1, true) then
        clean = false
      end
    end
  end
  -- 確定: <CR> で、プロンプトに pre-edit もマーカーも無い文字列があるとき。取り消し: <Esc>・<C-g>・<C-c>、
  -- 空のプロンプトの <CR>（空の確定は取り消しと同じ。upstream も同じ）
  local confirm = key == "<CR>" and clean
  local cancel = key == "<Esc>"
    or key == "<C-g>"
    or key == "<C-c>"
    or (key == "<CR>" and (typed or "") == "" and p.ctx_text == "")
  return b, (confirm and typed or nil), cancel
end

-- 登録のプロンプトが閉じたあと、バッファは登録した語（確定）か元の読みの ▽（取り消し）になり、
-- マーカーは入らない。入れ子の内側が閉じたときは、外側のプロンプトの cmdline も同じ規則で戻る
M.action["register: 閉じたあとのバッファは登録した語か元の ▽ の読み"] = function(
  p,
  key,
  s,
  hist
)
  local b, word, cancel = closed_prompt(p, key, s, hist)
  if not b or p.cmdwin ~= "" or not (word or cancel) or s.buf ~= b.buf then
    return
  end
  -- 閉じる操作と同じ 1 キーの中で、タイマーが行を書き換えることは無い（StealLine は alphabet に入れない）
  local inner_insert = b.vim_mode:sub(1, 1) == "i"
  if cancel then
    if table.concat(s.lines, "\n") ~= table.concat(b.lines, "\n") then
      return ("取り消し（%s）のあとに行が変わった: %q -> %q"):format(key, cur_line(b), cur_line(s))
    end
    -- <Space> は打ちかけのローマ字（かk の k）を捨てて変換するので、そのときは pre-edit が 1 文字短くなる
    if inner_insert and b.state.feed == "" and s.ctx_text ~= b.ctx_text then
      return ("取り消し（%s）のあとの pre-edit が %q（登録の前は %q）"):format(
        key,
        s.ctx_text,
        b.ctx_text
      )
    end
    if b.cmdtype == "@" and s.cmdtype == "@" and s.cmdline ~= b.cmdline then
      return ("取り消しのあとの外側のプロンプトが %q（内側を開く前は %q）"):format(
        s.cmdline,
        b.cmdline
      )
    end
    return
  end
  if inner_insert and b.cursor[1] == s.cursor[1] then
    local bl = b.lines[b.cursor[1]] or ""
    -- 送り仮名の登録では、語のあとに送り仮名が続く（"か" を登録した か*か は "かか"）
    local head, tail = bl:sub(1, b.cursor[2]) .. word, bl:sub(b.cursor[2] + 1)
    local l = cur_line(s)
    if
      s.vim_mode:sub(1, 1) == "i"
      and (l:sub(1, #head) ~= head or (#tail > 0 and l:sub(-#tail) ~= tail) or #l < #head + #tail)
    then
      return ("確定した語 %q が入っていない: %q（期待 %q + 送り仮名 + %q）"):format(
        word,
        l,
        head,
        tail
      )
    end
  elseif b.cmdtype == "@" and s.cmdtype == "@" then
    local pre = b.ctx_text or ""
    if pre ~= "" and b.cmdline:sub(-#pre) == pre then
      local want = b.cmdline:sub(1, #b.cmdline - #pre) .. word
      -- 送りありの登録は、語のあとに送り仮名が付く（insert のときと同じ。upstream も同じ）
      local okuri_ok = b.state.mode == "okuriari" and s.cmdline:sub(1, #want) == want
      if s.cmdline ~= want and not okuri_ok then
        return ("外側のプロンプトが %q（期待 %q）"):format(s.cmdline, want)
      end
    end
  end
  for _, m in ipairs(markers(s)) do
    if cur_line(s):find(m, 1, true) or (s.cmdline and s.cmdline:find(m, 1, true) and s.ctx_text == "") then
      return ("閉じたあとに %s が残っている（行 %q）"):format(m, cur_line(s))
    end
  end
end

-- cmdline（: と /）か terminal の中で始めた辞書登録のプロンプト（regcmd プロファイル）が閉じたあと。
-- 登録は外側の cmdline や terminal のジョブの上で開くので、外側の状態が壊れていないかを見る。
--   確定: 外側の行は「pre-edit の手前の文字列 + 登録した語」になり、マーカーは残らない
--   取り消し: 外側の行は「pre-edit の手前の文字列 + ▽ の読み」に戻る（upstream の cmdline・terminal と同じ。
--             tests/formal/upstream.lua の c ではなく、tmux で : の ▽か<Space><Esc> を見比べた）
--   どちらも外側の cmdline は閉じておらず、種類（: か /）と手前の文字列が同じ
-- terminal は pre-edit も本物の文字としてジョブに流すので、ジョブから見える行（バッファの今の行）で同じことを見る
M.action["regcmd: 登録のあと、外側の cmdline と terminal の行が戻る"] = function(p, key, s, hist)
  if (p.input_depth or 0) ~= 1 or (s.input_depth or 0) ~= 0 or p.cmdwin ~= "" then
    return
  end
  local b, word, cancel = closed_prompt(p, key, s, hist, true)
  if not b or not (word or cancel) then
    return
  end
  local term = b.buftype == "terminal"
  local outer = b.cmdtype
  if not term and outer ~= ":" and outer ~= "/" then
    return
  end
  -- 外側の行: cmdline は getcmdline()、terminal はカーソルの行
  local function text(o)
    if term then
      return o.lines[o.cursor[1]] or ""
    end
    return o.cmdline or ""
  end
  local before, after = text(b), text(s)
  -- 手前の文字列 = 登録を始める前の行から、pre-edit を除いたもの
  local pre = b.ctx_text or ""
  if pre == "" or before:sub(-#pre) ~= pre then
    return
  end
  local prefix = before:sub(1, #before - #pre)
  if term then
    if s.buf ~= b.buf or s.vim_mode:sub(1, 1) ~= "t" then
      return ("terminal に戻っていない（mode %s）"):format(s.vim_mode)
    end
  elseif s.vim_mode:sub(1, 1) ~= "c" or s.cmdtype ~= outer then
    return ("外側の cmdline が閉じた（mode %s、cmdtype %q、登録の前は %q）"):format(
      s.vim_mode,
      tostring(s.cmdtype),
      outer
    )
  end
  if after:sub(1, #prefix) ~= prefix then
    return ("pre-edit の手前の文字列が変わった: %q（期待 %q）"):format(after, prefix)
  end
  local rest = after:sub(#prefix + 1)
  if word then
    -- 確定: 語（と送り仮名）が入り、pre-edit は残らない
    if rest:sub(1, #word) ~= word then
      return ("確定した語 %q が外側に入っていない: %q（手前 %q）"):format(word, after, prefix)
    end
    if s.ctx_text ~= "" then
      return ("確定したのに pre-edit %q が残っている"):format(s.ctx_text)
    end
  else
    -- 取り消し: ▽ の読みに戻る。打ちかけのローマ字は <Space> で捨てられるので、その分だけ短くなってよい
    if rest ~= s.ctx_text then
      return ("取り消しのあとの外側が %q、pre-edit は %q"):format(rest, s.ctx_text)
    end
    if b.state.feed == "" and rest ~= pre then
      return ("取り消しのあとの読みが %q（登録の前は %q）"):format(rest, pre)
    end
  end
  for _, m in ipairs(markers(s)) do
    -- ▽ は取り消しで戻した pre-edit としては残る。それ以外（確定のあと、▼）にはマーカーが無い
    local allowed = cancel and m == s.opt.markerHenkan
    if after:find(m, 1, true) and not allowed then
      return ("閉じたあとの外側 %q に %s が残っている"):format(after, m)
    end
  end
  if not term and word and s.cmdpos and s.cmdpos < #prefix + #word + 1 then
    return ("外側の cmdline のカーソル位置 %d が語の手前（%d）"):format(s.cmdpos, #prefix + #word + 1)
  end
end

-- terminal のジョブが実行した行には、pre-edit のマーカーも登録の内部の語も入らない（確定した文字だけが渡る）
M.state["regcmd: terminal のジョブに渡った行にマーカーや内部の語が無い"] = function(s, _, hist)
  -- pre-edit のあいだの <C-r> はジョブ（bash）に渡り、行の本物の ▽ ごと実行されうる。upstream も同じ
  if not s.job_log or (hist and hist.term_ctrl_r) then
    return
  end
  if s.job_log:find("__skkeleton_return__", 1, true) then
    return ("ジョブが受けた行に登録の内部の語: %q"):format(s.job_log)
  end
  for _, m in ipairs(markers(s)) do
    if s.job_log:find(m, 1, true) then
      return ("ジョブが受けた行に %s: %q"):format(m, s.job_log)
    end
  end
end

-- ユーザー辞書に新しい見出しが増えるのは、空でない確定のときだけ。取り消しと空の確定では、中身が変わらない。
-- 確定したら、登録した語が先頭の候補としてどれかの見出しに入る
M.action["register: ユーザー辞書は空でない確定のときだけ増える"] = function(p, key, s, hist)
  if not p.user_dict or not s.user_dict then
    return
  end
  local b, word, cancel = closed_prompt(p, key, s, hist, true)
  local grown = {}
  for k in pairs(s.user_dict) do
    if not p.user_dict[k] then
      grown[#grown + 1] = k
    end
  end
  -- 普通の変換（▼ の確定）でも、辞書にある語の見出しは作られる。ここで見るのはプロンプトの取り消しや空の確定
  -- 打ちかけのローマ字（"えr" の r）が残ったままの <CR> も、cmdline の中身を登録する（upstream も同じ）
  local dirty_confirm = key == "<CR>" and (p.cmdline or "") ~= "" and (p.input_depth or 0) == (s.input_depth or 0) + 1
  -- 補完の候補を選んだとき（blink.cmp の <Tab> など）は確定としてユーザー辞書に覚える（main.complete_callback）
  local completed = (p.menu or p.pum)
    and (key == "<Tab>" or key == "<C-n>" or key == "<C-p>" or key == "<C-y>" or key == "<CR>")
  -- "KaN" のようなローマ字のまとまりは、1 つのキー列の中で変換と確定が起きる（upstream も同じ）
  -- 1 つのキーの表記（<Space> など）でなければ、まとめて流したキー列として扱う（Kanji<Space> など）
  local romaji_macro = #key > 1 and not key:match("^<[^<>]+>$")
  if
    #grown > 0
    and not word
    and not dirty_confirm
    and not completed
    and not romaji_macro
    and p.state.type ~= "henkan"
  then
    return ("プロンプトの確定でも変換の確定でもないのに辞書の見出し %s が増えた（%s）"):format(
      short(grown),
      key
    )
  end
  if b and cancel and not vim.deep_equal(p.user_dict, s.user_dict) then
    return ("取り消し（%s）でユーザー辞書が変わった"):format(key)
  end
  if b and word then
    for _, c in pairs(s.user_dict) do
      if c[1] == word then
        return
      end
    end
    return ("確定した語 %q がユーザー辞書の先頭の候補に無い"):format(word)
  end
end

-- 登録が終わったら、skkeleton の有効・モードは登録の前と同じ（登録の中の別の Context は捨てられている）。
-- 確定のあとは pre-edit が空になる
M.action["register: 閉じたあとのモードと状態が登録の前と同じ"] = function(p, key, s, hist)
  local b, word, cancel = closed_prompt(p, key, s, hist)
  if not b or p.cmdwin ~= "" or s.buf ~= b.buf or not (word or cancel) then
    return
  end
  -- 登録の最中の :stopinsert は、閉じたあとに insert を抜ける（Vim の動き）。そのときは skkeleton も無効になる
  if s.vim_mode:sub(1, 1) ~= b.vim_mode:sub(1, 1) then
    if s.enabled and b.vim_mode:sub(1, 1) == "i" and s.vim_mode:sub(1, 1) == "n" then
      return ("insert を抜けたのに skkeleton が有効のまま（mode %s）"):format(s.vim_mode)
    end
    return
  end
  -- abbrev・カタカナ・半角カタカナから始めた登録は、確定するとひらがなに戻る（upstream も同じ）
  local want_mode = b.skk_mode
  if (word or key == "<CR>") and (b.skk_mode == "abbrev" or b.skk_mode == "kata" or b.skk_mode == "hankata") then
    want_mode = "hira"
  end
  if s.enabled ~= b.enabled or s.skk_mode ~= want_mode then
    return ("閉じたあと enabled=%s mode=%s（登録の前は %s / %s）"):format(
      tostring(s.enabled),
      s.skk_mode,
      tostring(b.enabled),
      b.skk_mode
    )
  end
  if word and b.vim_mode:sub(1, 1) == "i" and s.ctx_text ~= "" then
    return ("確定したのに pre-edit %q が残っている"):format(s.ctx_text)
  end
  -- プロンプトの中でタイマーなどがウィンドウを移しても、終わったら登録を始めたウィンドウに戻る（#13）
  if s.win ~= b.win then
    return ("登録が終わったのにウィンドウ %d にいる（始めたのは %d）"):format(s.win, b.win)
  end
end

-- マーカーが空の設定（markerHenkan = ""）で起きる登録の不具合は、メッセージに印を付けて既知と見分ける（#55）
for _, name in ipairs({
  "register: 閉じたあとのバッファは登録した語か元の ▽ の読み",
  "register: ユーザー辞書は空でない確定のときだけ増える",
  "register: 閉じたあとのモードと状態が登録の前と同じ",
}) do
  local f = M.action[name]
  M.action[name] = function(p, key, s, hist)
    local msg = f(p, key, s, hist)
    if msg and (p.opt.markerHenkan == "" or p.opt.markerHenkanSelect == "") then
      return msg .. " [空のマーカー]"
    end
    return msg
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

-- 未マップの特殊キー（profiles.unmapped_keys。<C-.>・<S-CR>・<Left>・<F5> など。#56）。
-- skkeleton は英数字と記号、<BS>・<CR>・<Space>・<Esc> などしか奪わないので、これらは ▽/▼ の途中で Neovim の標準の動きが先に走る
-- （文字が入る、カーソルが動く、端末なら job にエスケープシーケンスが渡る）。
-- upstream（denops 版）は pre-edit が本物のバッファの文字なので、キーはそのまま通り、打った読みは文字として残る。
-- こちらは pre-edit が extmark（insert）か、書いて BS で消し直す文字（cmdline と terminal）なので、打った読みが消えやすい。
-- 守ること: キーのあと、(a) キーが捨てられて pre-edit がそのまま残る（読みが消えない）か、
--           (b) 打った読みがバッファ（cmdline、terminal の行）に文字として残る（確定、または upstream のようにそのまま残る）。
--           読みが黙って消えるのは違反（#56。M.known で既知にしている）。
local unmapped_set
local function is_unmapped(key)
  if not unmapped_set then
    unmapped_set = {}
    for _, k in ipairs(require("formal.profiles").unmapped_keys) do
      unmapped_set[k] = true
    end
  end
  -- 端末からの貼り付け（vim.paste）も、skkeleton を通らずに文字が入るので同じ決まりで見る（#56 の「打った読みは消さない」）
  return unmapped_set[key] == true or key == "<Paste>" or key == "<PasteLines>"
end

local function count_plain(text, sub)
  local n, init = 0, 1
  while true do
    local a, b = text:find(sub, init, true)
    if not a then
      return n
    end
    n = n + 1
    init = b + 1
  end
end

-- 画面に出ているバッファや cmdline の文字
local function body(s)
  if s.cmdline then
    return s.cmdline
  end
  return (table.concat(s.lines, "\n"):gsub("\n+$", ""))
end

-- ▽/▼ の途中にあった読み。マーカーと送り仮名の印（*）と、まだかなになっていないローマ字を除く。▼ なら候補も返す
local function typed_reading(p)
  local text = p.ctx_text
  for _, m in ipairs(markers(p)) do
    text = text:gsub(vim.pesc(m), "")
  end
  local cand = p.state.type == "henkan" and text or ""
  local reading = text:gsub("%*", ""):gsub("[%a%d%p]+$", "")
  if p.state.type == "henkan" and (p.state.henkan_feed or "") ~= "" then
    reading = p.state.henkan_feed
  end
  return reading, cand
end

local function at_preedit(p, key)
  return is_unmapped(key) and p.enabled and p.ctx_text ~= "" and p.vim_mode:sub(1, 1):match("[icte]") ~= nil
end

M.action["unmapped: 未マップの特殊キーのあと、打った読みが黙って消えない"] = function(
  p,
  key,
  s
)
  if not at_preedit(p, key) or s.ctx_text == p.ctx_text then
    return
  end
  -- cmdline を抜けた（<S-CR> などでコマンドを実行した）ときは、確定した読みはコマンドに渡っている
  if p.cmdline ~= nil and s.cmdline == nil then
    return
  end
  -- terminal でシェルが自分の行を書き換えている（<C-r> の履歴の検索など）ときは見ない
  if p.vim_mode:sub(1, 1) == "t" and table.concat(p.lines or {}, "\n"):find("reverse%-i%-search") then
    return
  end
  local reading, cand = typed_reading(p)
  if reading == "" then
    return
  end
  -- insert の pre-edit は extmark でバッファに無い。cmdline と terminal は文字として書いてあるので、前と同じ数だけ残っていればよい
  local real = p.cmdline ~= nil or p.vim_mode:sub(1, 1) == "t"
  local need = count_plain(body(p), reading) + (real and 0 or 1)
  local need_cand = cand ~= "" and (count_plain(body(p), cand) + (real and 0 or 1)) or math.huge
  if count_plain(body(s), reading) < need and count_plain(body(s), cand ~= "" and cand or reading) < need_cand then
    return ("%s のあと、打った読み %q（pre-edit %q）が消えた（行 %q）"):format(
      key,
      reading,
      p.ctx_text,
      body(s)
    )
  end
end

-- 捨てたなら pre-edit が元のまま（バッファとカーソルも動かない）、リセットしたなら跡が残らない。
-- 途中までの状態（読みの一部だけ消費した、マーカーや extmark や popup だけ残る、state だけ残る）は違反
M.action["unmapped: 未マップの特殊キーのあと、pre-edit は元のままか、きれいにリセットされる"] = function(
  p,
  key,
  s
)
  if not at_preedit(p, key) then
    return
  end
  if s.ctx_text ~= "" then
    if s.ctx_text ~= p.ctx_text then
      return ("%s のあと pre-edit が %q から %q に変わった"):format(key, p.ctx_text, s.ctx_text)
    end
    -- 捨てたなら、バッファ（cmdline、terminal の行）もカーソルも動かない。キーが通って文字が入る・カーソルが動くと、
    -- pre-edit の位置が実際の文字とずれる（cmdline と terminal は pre-edit を文字で書いて BS で消し直すので、ずれた分が残る）
    if s.cmdline ~= nil and p.cmdline ~= nil and (s.cmdline ~= p.cmdline or s.cmdpos ~= p.cmdpos) then
      return ("%s のあと pre-edit %q は残っているが、cmdline が %q（位置 %d）から %q（位置 %d）に動いた"):format(
        key,
        p.ctx_text,
        p.cmdline,
        p.cmdpos,
        s.cmdline,
        s.cmdpos
      )
    end
    if
      s.vim_mode:sub(1, 1) == "t"
      and p.buf == s.buf
      and (body(s) ~= body(p) or p.cursor[1] ~= s.cursor[1] or p.cursor[2] ~= s.cursor[2])
    then
      return ("%s のあと pre-edit %q は残っているが、terminal の行が %q から %q に動いた（カーソル %s -> %s）"):format(
        key,
        p.ctx_text,
        body(p),
        body(s),
        short(p.cursor),
        short(s.cursor)
      )
    end
    return
  end
  if #s.preedit_marks > 0 then
    return ("%s のあと ctx は空なのに extmark %q が残っている"):format(key, mark_text(s))
  end
  if s.state.feed ~= "" or s.state.henkan_feed ~= "" then
    return ("%s のあと ctx は空なのに state に読み（feed=%q、henkan_feed=%q）が残っている"):format(
      key,
      s.state.feed,
      s.state.henkan_feed
    )
  end
  if #s.popup > 0 then
    return ("%s のあと pre-edit が無いのに popup が残っている"):format(key)
  end
end

-- 見つかったが、今は直さないもの。反例の性質の名前と、キー列で見分ける。
-- 当てはまる違反は「既知」として出し、失敗にしない
M.known = {}

-- #56 の別の現れ方。キーが先に通るので、pre-edit が残ったまま cmdline や terminal の文字がずれる、
-- pre-edit が消えても cmdline にマーカーと読みが文字で残る
local function has_unmapped(keys)
  for _, k in ipairs(keys) do
    if is_unmapped(k) then
      return true
    end
  end
  return false
end

if not CHECK_INDICATOR then
  for _, kind in ipairs({ M.state, M.action }) do
    for name in pairs(kind) do
      if name:find("^indicator:") then
        kind[name] = function() end
      end
    end
  end
end

function M.is_known(name, keys, msg)
  for _, k in ipairs(M.known) do
    if k.property == name and k.match(keys, msg) then
      return k
    end
  end
end

return M

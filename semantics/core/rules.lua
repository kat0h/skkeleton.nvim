-- SKK の入力エンジン（core）の規則の表（#260、親は #179）
--
-- このファイルが元で、図（figures/）と CORE.md の表は figures.lua がここから作る。
-- 素の Lua のテーブルを返す。vim.* は使わない。
--
-- src の行番号は main の c2a78ff のもの。
--
-- 1 行は「実装の 1 つの分岐」で、図では from × to の辺の束になる（CORE.md の「プロンプトの前提から変えたこと」）。
--   id         R- で始まる
--   group      input / henkan / commit / mode / register / power
--   from       状態の id の配列
--   key        キーの種類の id の配列（"*" はどのキーでも）
--   guard      設定、辞書、読みの中身の条件
--   to         行き先の状態の id の配列（読みの長さなどで分かれるときは複数）
--   short      図の辺に添える短い出力
--   out        確定する文字列、消える読み、host への呼び出し
--   pending    打ちかけの片付け方（settle の id）
--   again      "same"（同じキーを打ち直す）/ "lower"（小文字にして打ち直す）/ "henkan"（続けて変換に入る）
--   src        ファイル:行
--   confidence read（読んで追えた）/ inferred（推測）/ open（分からない）
--   views      当たる視点と、守るか破るか（holds / breaks / open）
--   status     current（今の動き）/ undefined（今の動きが決まらない、または規則が無い）
--   recommend  recommends の id

local I = "lua/skkeleton/function/input.lua:"
local H = "lua/skkeleton/function/henkan.lua:"
local C = "lua/skkeleton/function/common.lua:"
local M = "lua/skkeleton/function/mode.lua:"
local D = "lua/skkeleton/function/disable.lua:"
local DI = "lua/skkeleton/function/dictionary.lua:"
local K = "lua/skkeleton/keymap.lua:"
local MD = "lua/skkeleton/mode.lua:"
local S = "lua/skkeleton/state.lua:"
local HO = "lua/skkeleton/host.lua:"
local MA = "lua/skkeleton/main.lua:"
local OK = "lua/skkeleton/okuri.lua:"

local T = {}

T.revision = "c2a78ff"

------------------------------------------------------------------------
-- 状態（使う人の言葉）。段 × 打ちかけの有無
------------------------------------------------------------------------
T.states = {
  {
    id = "off",
    name = "無効",
    desc = "skkeleton が切れている。キーは core に届かない。<Esc> で抜けた直後もここ",
    impl = "g:skkeleton#enabled が偽（core の中には持っていない。" .. HO .. "23-33）。<Esc> の直後は st.type == \"escape\"（" .. D .. "26）",
    reading = "none",
    phase = "input / escape",
  },
  {
    id = "direct",
    name = "読みなし",
    desc = "打った文字がそのまま確定される。変換する読みは無い",
    impl = 'st.type == "input" and st.mode == "direct" and st.feed == ""（' .. S .. "51-62）",
    reading = "none",
    phase = "input",
  },
  {
    id = "pending",
    name = "打ちかけ",
    desc = "ローマ字の途中（k、n など）。まだかなになっていない",
    impl = 'st.type == "input" and st.mode == "direct" and st.feed ~= ""（' .. I .. "107-109）",
    reading = "romaji",
    phase = "input",
  },
  {
    id = "pre0",
    name = "▽（空）",
    desc = "▽ を開いたところ。読みはまだ無い",
    impl = 'st.mode == "okurinasi" and st.henkan_feed == "" and st.feed == ""（' .. I .. "157-163）",
    reading = "point",
    phase = "input:okurinasi",
  },
  {
    id = "pre",
    name = "▽",
    desc = "読みを打っている（▽かき）",
    impl = 'st.mode == "okurinasi" and st.henkan_feed ~= "" and st.feed == ""（' .. I .. "35-36）",
    reading = "point",
    phase = "input:okurinasi",
  },
  {
    id = "prep",
    name = "▽ 打ちかけ",
    desc = "読みの途中でローマ字が残っている（▽かk、▽k）",
    impl = 'st.mode == "okurinasi" and st.feed ~= ""',
    reading = "point",
    phase = "input:okurinasi",
  },
  {
    id = "oku",
    name = "▽ 送り",
    desc = "送りを始めたところ（▽か*）。▼ から戻ったときは送りが残る（▽か*く）",
    impl = 'st.mode == "okuriari" and st.feed == ""。送りは st.okuri_feed（' .. I .. "164-173）",
    reading = "point",
    phase = "input:okuriari",
  },
  {
    id = "okup",
    name = "▽ 送り 打ちかけ",
    desc = "送りのローマ字の途中（▽か*k）。送りの前の打ちかけ（▽さs*）もここ",
    impl = 'st.mode == "okuriari" and st.feed ~= ""。送りの前の打ちかけは st.previous_feed（' .. I .. "171）",
    reading = "point",
    phase = "input:okuriari",
  },
  {
    id = "sel",
    name = "▼",
    desc = "候補を 1 つずつ見ている",
    impl = 'st.type == "henkan" and st.candidate_index < showCandidatesCount（' .. H .. "46-48）",
    reading = "henkan",
    phase = "henkan",
  },
  {
    id = "list",
    name = "▼ 一覧",
    desc = "候補を 7 つずつ並べて、選択キーで選ぶ",
    impl = 'st.type == "henkan" and st.candidate_index >= showCandidatesCount（' .. H .. "123-125）",
    reading = "henkan",
    phase = "henkan",
  },
  {
    id = "reg",
    name = "辞書登録",
    desc = "候補が尽きて、登録の欄が開いている。欄の中では同じ機械がもう 1 つ動く",
    impl = "host.input の呼び出しの中（" .. DI .. "20、" .. HO .. "181-231）。外の Context は host がスタックに退避する",
    reading = "henkan（結合の層では P_PROMPT。aspect は入る前の ▽ / ▼）",
    phase = "henkan",
  },
}

------------------------------------------------------------------------
-- かなモード。状態とは掛け合わせない
------------------------------------------------------------------------
T.modes = {
  { id = "hira", name = "ひらがな", impl = "converter == nil、テーブルは kanaTable", states = "すべて" },
  { id = "kata", name = "カタカナ", impl = "converter == hira_to_kata", states = "すべて" },
  { id = "hankata", name = "半角カナ", impl = "converter == hira_to_hankata", states = "すべて" },
  { id = "zenkaku", name = "全英", impl = 'テーブルが "zen"、converter == nil', states = "読みなしだけ（▽ は開かない）" },
  { id = "abbrev", name = "abbrev", impl = "テーブルが空、direct_input が真", states = "▽・▼・辞書登録だけ（終わると抜ける）" },
  { id = "none", name = "（無効）", impl = 'g:skkeleton#mode == ""', states = "無効だけ" },
}

T.mode_edges = {
  { from = "hira", key = "q", to = "kata", rule = "R-MD-01" },
  { from = "kata", key = "q", to = "hira", rule = "R-MD-01" },
  { from = "hankata", key = "q", to = "hira", rule = "R-MD-01" },
  { from = "hira", key = "<C-q>", to = "hankata", rule = "R-MD-02" },
  { from = "kata", key = "<C-q>", to = "hankata", rule = "R-MD-02" },
  { from = "hankata", key = "<C-q>", to = "hira", rule = "R-MD-02" },
  { from = "zenkaku", key = "<C-q>", to = "hankata", rule = "R-MD-02" },
  { from = "hira", key = "L", to = "zenkaku", rule = "R-MD-04" },
  { from = "kata", key = "L", to = "zenkaku", rule = "R-MD-04" },
  { from = "hankata", key = "L", to = "zenkaku", rule = "R-MD-04" },
  { from = "hira", key = "/", to = "abbrev", rule = "R-MD-06" },
  { from = "kata", key = "/", to = "abbrev", rule = "R-MD-06" },
  { from = "hankata", key = "/", to = "abbrev", rule = "R-MD-06" },
  { from = "abbrev", key = "確定・取り消し", to = "hira", rule = "R-MD-10", breaks = true },
  { from = "kata", key = "<C-j>（読みなし）", to = "hira", rule = "R-CK-05" },
  { from = "hankata", key = "<C-j>（読みなし）", to = "hira", rule = "R-CK-05" },
  { from = "zenkaku", key = "<C-j>", to = "hira", rule = "R-CK-05" },
  { from = "none", key = "enable", to = "hira", rule = "R-EN-03" },
  { from = "hira", key = "l・<Esc>・disable", to = "none", rule = "R-EN-01" },
  { from = "kata", key = "l・<Esc>・disable", to = "none", rule = "R-EN-01" },
  { from = "hankata", key = "l・<Esc>・disable", to = "none", rule = "R-EN-01" },
  { from = "zenkaku", key = "<Esc>・disable", to = "none", rule = "R-EN-02" },
  { from = "abbrev", key = "<Esc>・disable", to = "none", rule = "R-EN-02" },
}

------------------------------------------------------------------------
-- キーの種類。keymap.handle_key の決め方（K 64-87）で分ける
------------------------------------------------------------------------
T.key_classes = {
  { id = "kana", label = "文字", desc = "小文字と記号。打ちかけ＋キーがかなテーブルにあればかなテーブルが受ける。無ければ kana_input がそのまま確定する" },
  { id = "upper", label = "大文字", desc = "kana_input が受ける。テーブルに <s-x> の項目があれば文字、無ければ変換の点を打ってから小文字として打ち直す（" .. I .. "91-99）" },
  { id = "l", label = "l", desc = "disable。kana_function で包んである（既定のローマ字のテーブルでだけ効く）" },
  { id = "q", label = "q", desc = "katakana。kana_function で包んである" },
  { id = ";", label = ";", desc = "henkanPoint。kana_function で包んである" },
  { id = "/", label = "/", desc = "abbrev。kana_function で包んである" },
  { id = "L", label = "L", desc = "zenkaku。kana_function で包んである。大文字だが変換の点は打たない" },
  { id = "space", label = "<Space>", desc = "入力では henkanFirst、▼ では henkanForward" },
  { id = "gt", label = ">", desc = "入力では prefix、▼ では suffix" },
  { id = "cq", label = "<C-q>", desc = "hankatakana。包んでいないので、打ちかけを片付けずに呼ばれる" },
  { id = "bs", label = "<BS>", desc = "deleteChar（<C-h> も同じ）。▼ のキーマップには無い" },
  { id = "cg", label = "<C-g>", desc = "cancel" },
  { id = "cj", label = "<C-j>", desc = "kakutei" },
  { id = "cr", label = "<CR>", desc = "newline" },
  { id = "esc", label = "<Esc>", desc = "escape。▼ のキーマップには無い" },
  { id = "x", label = "x", desc = "▼ では henkanBackward", otherwise = "kana" },
  { id = "X", label = "X", desc = "▼ では purgeCandidate", otherwise = "upper" },
  { id = "select", label = "選択キー", desc = "selectCandidateKeys（既定 asdfjkl）。▼ 一覧でだけ候補を選ぶ。一覧では l もここに入る", otherwise = "kana" },
  -- キーではない入力
  { id = "ev:enable", label = "enable", desc = "<Plug>(skkeleton-enable)。toggle は無効のときこれになる", event = true },
  { id = "ev:disable", label = "disable", desc = "<Plug>(skkeleton-disable)。toggle は有効のときこれになる", event = true },
  { id = "ans:word", label = "答え：語", desc = "host.input が語を返した", event = true },
  { id = "ans:cancel", label = "答え：取り消し", desc = "host.input が nil か空を返した、またはエラーで中断した", event = true },
  { id = "open", label = "（欄が開く）", desc = "host.input が内側の機械を作る", event = true },
}

------------------------------------------------------------------------
-- 打ちかけの片付け方。キーごとに違う（CORE.md の §4.0）
------------------------------------------------------------------------
T.settle = {
  { id = "flush", name = "片付ける", complete = "かなにして段に入れる（送りがそろえば変換が走る）", incomplete = "捨てる（acceptIllegalResult が真なら生のまま入れる）", src = I .. "71-81" },
  { id = "fold", name = "かなだけ入れる", complete = "かなにして段に入れる（変換は走らない）", incomplete = "残す", src = I .. "14-23" },
  { id = "fold-drop", name = "かなだけ入れて残りは捨てる", complete = "かなにして段に入れる", incomplete = "捨てる", src = I .. "215-216、" .. M .. "51-62" },
  { id = "raw", name = "生のまま確定する", complete = "かなにして確定する", incomplete = "ローマ字のまま確定する", src = C .. "33-38" },
  { id = "keep", name = "触らない", complete = "残す", incomplete = "残す", src = "" },
  { id = "erase", name = "消す", complete = "消す", incomplete = "消す", src = C .. "77-82" },
}

------------------------------------------------------------------------
-- 推奨。同じ形の規則は 1 つの推奨を共有する
------------------------------------------------------------------------
T.recommends = {
  {
    id = "REC-DROP",
    action = "今のまま。かなにならない打ちかけは、次のキーで捨てる",
    why = "V5（どの段でも同じ扱い）。残したい人は acceptIllegalResult で選べる",
    upstream = "同じ（upstream とそろえた動き）",
    alternatives = { { action = "生のまま確定する（acceptIllegalResult を既定で真にする）", breaks = "視点は破らないが、upstream の既定と変わる" } },
  },
  {
    id = "REC-HIDDEN",
    action = "打ちかけがかなにならないときは変換しない（▽かk のまま残す）",
    why = "V1・V2。▼ に見えない打ちかけを持ち込まない。読みが空のとき（R-HK-03）と同じ形になる",
    upstream = "打ちかけを捨てて変換する（tests/diff/known.lua の pending-consonant-kept-on-space の説明から。▽かk の形は未確認）",
    alternatives = {
      { action = "打ちかけを捨てて変換する（upstream）", breaks = "V2" },
      { action = "今のまま（隠して持ったまま変換する）", breaks = "V1・V2" },
    },
    differs_from_upstream = true,
  },
  {
    id = "REC-EMPTY-OKURI",
    action = "送りが空のままなら、送りなしとして変換する",
    why = "V10（送りはかなの単位）・V9（送りの無い語を送りありに登録しない）",
    upstream = "unknown",
    alternatives = {
      { action = "何も起きない（▽か* のまま）", breaks = "視点は破らないが、<BS> を押さないと進めない" },
      { action = "今のまま（子音の付かない見出しを送りありで引く）", breaks = "V10・V9" },
    },
  },
  {
    id = "REC-GT-OKURI",
    action = "▽ 送りでは > は何も起きない",
    why = "V10（> は送りのかなではない）・P5（変換を 2 度呼ばない）",
    upstream = "unknown",
    alternatives = {
      { action = "送りを捨てて、接頭辞として変換する", breaks = "V2" },
      { action = "今のまま", breaks = "V10・P5" },
    },
  },
  {
    id = "REC-CANCEL",
    action = "既定は今のまま（immediatelyCancel = true。▼ の <C-g> で読みごと消える）",
    why = "upstream と同じ既定。1 段ずつ戻りたい人は immediatelyCancel = false を選べる（R-CK-04）",
    upstream = "同じ既定",
    alternatives = { { action = "既定を false にする（▼ の <C-g> は ▽ に戻る）", breaks = "視点は破らない（V3 を守る）が、upstream の既定と変わる" } },
    ask = true,
  },
  {
    id = "REC-BS",
    action = "今のまま（▼ の <BS> は候補を確定してから 1 文字消す）",
    why = "upstream に合わせる。x で前の候補に戻れるので、戻る手段はある",
    upstream = "同じと思われる（移植元 function/henkan.ts の henkanInput。未確認）",
    alternatives = { { action = "▼ の <BS> は 1 つ前の段（前の候補、1 つ目なら ▽）に戻る", breaks = "視点は破らない（V3 を守る）が、upstream と変わる" } },
    ask = true,
  },
  {
    id = "REC-CANDNIL",
    action = "候補が無いまま確定に入ったら、読みと送りをそのまま確定する",
    why = "V1・V2。error という文字を入れない",
    upstream = "unknown",
    alternatives = { { action = "何も確定しない", breaks = "V2" } },
  },
  {
    id = "REC-ABBREV",
    action = "abbrev が終わったら、abbrev に入る前のモードに戻る",
    why = "V6（モードは自分で切り替えるまで変わらない）。abbrev は 1 語だけの一時のモード",
    upstream = "ひらがなに戻ると思われる（移植元 mode.ts。未確認）",
    alternatives = { { action = "今のまま（いつも ひらがな に戻る）", breaks = "V6" } },
    differs_from_upstream = true,
  },
  {
    id = "REC-ST",
    action = "l q ; / L の前の打ちかけの n は、ん にするだけで変換は走らせない",
    why = "V4（q を押したら辞書登録の欄が開く、ということを起こさない）",
    upstream = "同じ流れと思われる（これらのキーがかなテーブルの関数だった。未確認）",
    alternatives = { { action = "今のまま", breaks = "V4" } },
    differs_from_upstream = true,
  },
  {
    id = "REC-INNER-MODE",
    action = "内側は ひらがな で始め、モードの表示（g:skkeleton#mode）も hira にする。戻ったら外のモードに戻す（戻すのは今もしている）",
    why = "V1・P11（表示と中をそろえる）",
    upstream = "unknown",
    alternatives = {
      { action = "外のモードを引き継ぐ", breaks = "視点は破らないが、abbrev は引き継げないので例外が要る" },
      { action = "今のまま", breaks = "V1・P11" },
    },
  },
  {
    id = "REC-INNER-CANCEL",
    action = "内側に読みか候補があるときの <C-g> は、内側の取り消し（R-CK-02〜04）にする。読みなしのときだけ登録を取り消す。<Esc> は今のまま登録を取り消す",
    why = "V3（1 段ずつ戻る）・V9（欄の中でも同じ操作ができる）",
    upstream = "unknown",
    alternatives = { { action = "今のまま（内側の <C-g> はいつも登録を取り消す）", breaks = "V3・V9" } },
  },
  {
    id = "REC-TABLE",
    action = "今のかなテーブルの名前を機械ごとに持つ（kana.current_name を Context に移す）",
    why = "V1・P11・P6。内側で替えたテーブルが外に漏れない",
    upstream = "unknown",
    alternatives = { { action = "登録から戻るときに kana.current_name を外の値に戻す", breaks = "P6（機械の外に状態が残る）" } },
  },
  {
    id = "REC-INNER-DISABLE",
    action = "内側の l は内側だけを無効にする（欄に半角の英数を打てる）。登録が終わったら外は有効のまま戻る",
    why = "V9（欄の中でも同じ操作）・V2（外の読みを消さない）",
    upstream = "unknown",
    alternatives = { { action = "登録を取り消して、外も無効にする", breaks = "V2" } },
  },
  {
    id = "REC-REG-EVENT",
    action = "登録の欄が開いている間は、外への enable / disable を受けない",
    why = "V9・P9（入れ子から必ず戻れる）",
    upstream = "unknown",
    alternatives = { { action = "登録を取り消してから受ける", breaks = "V3（取り消しのキーでないのに登録が消える）" } },
  },
  {
    id = "REC-PURGE",
    action = "候補を消したあとも、モード（converter とテーブル）は残す",
    why = "V1・V6・P11。#87 と同じ形（converter だけが落ちて、モードの表示は残る）",
    upstream = "unknown（同じなら upstream の不具合として直す）",
    alternatives = {
      { action = "ひらがなモードに戻し、表示も hira にする", breaks = "V6" },
      { action = "今のまま", breaks = "V1・V6・P11" },
    },
  },
  {
    id = "REC-ESCAPE",
    action = "何も起きない（キーは捨てる）",
    why = "V5・P5。エラーを使う人に見せない",
    upstream = "unknown",
    alternatives = { { action = "今のまま（Illegal State のエラー）", breaks = "V5" } },
  },
}

------------------------------------------------------------------------
-- 規則
------------------------------------------------------------------------
T.rules = {}
local function R(r)
  r.status = r.status or "current"
  r.confidence = r.confidence or "read"
  r.views = r.views or {}
  T.rules[#T.rules + 1] = r
end

local DIRECT = { "direct", "pending" }
local PRE = { "pre0", "pre", "prep", "oku", "okup" }
local INPUT = { "direct", "pending", "pre0", "pre", "prep", "oku", "okup" }
local HENKAN = { "sel", "list" }
local ON = { "direct", "pending", "pre0", "pre", "prep", "oku", "okup", "sel", "list" }

-- 入力：読みなし・打ちかけ ---------------------------------------------
R({ id = "R-IN-01", group = "input", from = DIRECT, key = { "kana" }, guard = "打ちかけ＋キーが 1 つのかなに決まる", to = { "direct" },
  short = "かなを確定", out = "かなを確定する（カタカナなどのモードでは変換して）", src = I .. "104-106、" .. I .. "30-34", views = { V4 = "holds" } })
R({ id = "R-IN-02", group = "input", from = DIRECT, key = { "kana" }, guard = "続きがありうる（k、n など）", to = { "pending" },
  short = "打ちかけに積む", out = "何も確定しない", src = I .. "107-109" })
R({ id = "R-IN-03", group = "input", from = { "pending" }, key = { "kana" }, guard = "かなに決まり、次の打ちかけが残る（tt → っ＋t）", to = { "pending" },
  short = "っ を確定", out = "かなを確定し、残りを打ちかけにする", src = I .. "104-106、" .. I .. "45" })
R({ id = "R-IN-04", group = "input", from = { "pending" }, key = { "kana" }, guard = "続かない（nk、kz など）", to = { "direct", "pending" }, pending = "flush", again = "same",
  short = "片付けて打ち直す", out = "打ちかけがかなになれば確定する（n → ん）。ならなければ捨てる。そのあと同じキーを打ち直す",
  src = I .. "110-114、" .. I .. "71-81", views = { V2 = "breaks", P1 = "breaks", V4 = "holds" }, recommend = "REC-DROP" })
R({ id = "R-IN-05", group = "input", from = { "direct" }, key = { "kana" }, guard = "かなテーブルに無い文字", to = { "direct" },
  short = "そのまま確定", out = "その文字をそのまま確定する", src = I .. "115-118" })
R({ id = "R-IN-06", group = "input", from = DIRECT, key = { "space", "gt" }, to = { "direct" }, pending = "fold", again = "same",
  short = "文字として打つ", out = "変換するものが無いので、文字として打つ（打ちかけの n は ん になり、そのあとは文字の規則）",
  src = H .. "33-37、" .. I .. "222" })
R({ id = "R-IN-07", group = "input", from = { "direct" }, key = { "bs" }, to = { "direct" },
  short = "host へ BS", out = "host へ BS を渡す（確定済みの 1 文字が消える）", src = I .. "201-203" })
R({ id = "R-IN-08", group = "input", from = { "pending" }, key = { "bs" }, to = { "pending", "direct" },
  short = "打ちかけを 1 文字消す", out = "打ちかけを 1 文字消す", src = I .. "183-187", views = { V3 = "holds" } })
R({ id = "R-IN-09", group = "input", from = DIRECT, key = { "upper" }, to = { "pre0", "prep" }, pending = "keep", again = "lower",
  short = "▽ を開く", out = "▽ を開き、同じキーを小文字で打ち直す。打ちかけは読みの先頭に入る（kA → ▽か）。undo の区切りを host に出す",
  src = I .. "91-99、" .. I .. "157-163", views = { V10 = "holds" } })
R({ id = "R-IN-10", group = "input", from = DIRECT, key = { ";" }, to = { "pre0" }, pending = "flush",
  short = "▽ を開く", out = "▽ を開く。undo の区切りを host に出す", src = K .. "39、" .. I .. "129-143、" .. I .. "157-163", views = { V10 = "holds" } })

-- 入力：▽ ---------------------------------------------------------------
R({ id = "R-PR-01", group = "input", from = { "pre0", "pre", "prep" }, key = { "kana" }, guard = "かなに決まる", to = { "pre" },
  short = "読みに足す", out = "かなを読みに足す", src = I .. "35-36" })
R({ id = "R-PR-02", group = "input", from = { "pre0", "pre", "prep" }, key = { "kana" }, guard = "続きがありうる", to = { "prep" },
  short = "打ちかけに積む", out = "何も確定しない", src = I .. "107-109" })
R({ id = "R-PR-03", group = "input", from = { "prep" }, key = { "kana" }, guard = "かなに決まり、次の打ちかけが残る（tt）", to = { "prep" },
  short = "っ を読みに足す", out = "かなを読みに足し、残りを打ちかけにする", src = I .. "104-106、" .. I .. "45" })
R({ id = "R-PR-04", group = "input", from = { "prep" }, key = { "kana" }, guard = "続かない", to = { "pre", "prep", "pre0" }, pending = "flush", again = "same",
  short = "片付けて打ち直す", out = "打ちかけがかなになれば読みに足す（n → ん）。ならなければ捨てる。そのあと同じキーを打ち直す",
  src = I .. "110-114、" .. I .. "71-81", views = { V2 = "breaks", P1 = "breaks" }, recommend = "REC-DROP" })
R({ id = "R-PR-05", group = "input", from = { "pre0", "pre" }, key = { "kana" }, guard = "かなテーブルに無い文字", to = { "pre" },
  short = "読みに足す", out = "その文字を読みにそのまま足す", src = I .. "115-118" })
R({ id = "R-PR-06", group = "input", from = { "pre0", "prep" }, key = { "gt" }, guard = "読みが空", to = { "pre" }, pending = "flush", again = "same",
  short = "読みに > を足す", out = "> を文字として読みに足す（接尾辞の読み ▽>てき を手で打つ形）", src = I .. "214、" .. I .. "222" })
R({ id = "R-PR-07", group = "input", from = { "pre0" }, key = { "bs" }, to = { "direct" },
  short = "▽ を閉じる", out = "▽ を閉じる。モードは変わらない（abbrev は ひらがな に戻る）", src = I .. "195-199", views = { V3 = "holds", V6 = "holds" } })
R({ id = "R-PR-08", group = "input", from = { "pre" }, key = { "bs" }, to = { "pre", "pre0" },
  short = "読みを 1 文字消す", out = "読みを 1 文字消す", src = I .. "196-197", views = { V3 = "holds" } })
R({ id = "R-PR-09", group = "input", from = { "prep" }, key = { "bs" }, to = { "prep", "pre", "pre0" },
  short = "打ちかけを 1 文字消す", out = "打ちかけを 1 文字消す", src = I .. "183-187", views = { V3 = "holds" } })
R({ id = "R-PR-10", group = "input", from = { "pre0", "prep" }, key = { "upper", ";" }, guard = "読みが空", to = { "pre0", "prep" }, again = "lower",
  short = "送りは始まらない", out = "送りは始まらない。大文字は小文字として打つ。; は何も起きない（打ちかけは片付ける）", src = I .. "153-156", views = { V10 = "holds" } })
R({ id = "R-PR-11", group = "input", from = { "pre" }, key = { "upper" }, to = { "oku" }, again = "lower",
  short = "送りを始める", out = "送りを始め、同じキーを小文字で打ち直す", src = I .. "91-99、" .. I .. "164-173", views = { V10 = "holds" } })
R({ id = "R-PR-12", group = "input", from = { "pre" }, key = { ";" }, to = { "oku" },
  short = "送りを始める", out = "送りを始める", src = I .. "164-173", views = { V10 = "holds" } })
R({ id = "R-PR-13", group = "input", from = { "prep" }, key = { "upper" }, guard = "読みが空でない", to = { "oku", "okup" }, again = "lower",
  short = "送りを始める", out = "打ちかけがかなになれば読みに入れる（かn＋S → かん*）。ならなければ、送りの前の打ちかけとして残す（さs＋S → ▽さs*、察し）。そのあと小文字で打ち直す",
  src = I .. "165-173", views = { V4 = "holds", V10 = "holds" } })
R({ id = "R-PR-14", group = "input", from = { "prep" }, key = { ";" }, guard = "読みが空でない", to = { "oku" }, pending = "flush",
  short = "片付けて送りを始める", out = "打ちかけを片付けてから、送りを始める", src = I .. "137-142、" .. I .. "164-173" })

-- 入力：▽ 送り ----------------------------------------------------------
R({ id = "R-OK-01", group = "input", from = { "oku", "okup" }, key = { "kana" }, guard = "送りのかなが決まる", to = { "sel", "reg" }, again = "henkan",
  short = "送りに足して変換", out = "かなを送りに足し、すぐ変換する（R-HK-01 / R-HK-02）。っ で終わるときは、immediatelyOkuriConvert が偽なら変換しない",
  src = I .. "37-45、" .. I .. "56-66", views = { V10 = "holds" } })
R({ id = "R-OK-02", group = "input", from = { "oku", "okup" }, key = { "kana" }, guard = "続きがありうる", to = { "okup" },
  short = "打ちかけに積む", out = "何も確定しない", src = I .. "107-109" })
R({ id = "R-OK-03", group = "input", from = { "okup" }, key = { "kana" }, guard = "かなに決まり、次の打ちかけが残る（tt）", to = { "okup" },
  short = "っ を送りに足す", out = "っ を送りに足す（送りの前の打ちかけなら読みに足す）。変換はまだしない", src = I .. "38-45、" .. I .. "56", views = { V10 = "holds" } })
R({ id = "R-OK-04", group = "input", from = { "okup" }, key = { "kana" }, guard = "続かない", to = { "okup", "oku" }, pending = "flush", again = "same",
  short = "片付けて打ち直す", out = "打ちかけが n なら ん を送りに足して変換が走る（候補が無ければ辞書登録の欄が開く）。そのあと ▽ 送りに戻して同じキーを打つ（噛んで = KaNde）。ほかの打ちかけは捨てる",
  src = I .. "110-114、" .. I .. "71-81、" .. I .. "87", confidence = "inferred", views = { V2 = "breaks", P1 = "breaks" }, recommend = "REC-DROP" })
R({ id = "R-OK-05", group = "input", from = { "oku" }, key = { "kana" }, guard = "かなテーブルに無い文字", to = { "oku" },
  short = "送りに足す", out = "その文字を送りにそのまま足す。変換は走らない", src = I .. "115-118", confidence = "inferred" })
R({ id = "R-OK-06", group = "input", from = { "oku", "okup" }, key = { "upper" }, to = { "oku", "okup" }, again = "lower",
  short = "小文字として打つ", out = "送りはもう始まっているので、小文字として打つ", src = I .. "91-99、" .. I .. "164" })
R({ id = "R-OK-07", group = "input", from = { "oku", "okup" }, key = { ";" }, to = { "oku" }, pending = "flush",
  short = "何も起きない", out = "何も起きない（打ちかけは片付ける。n のときは R-ST-01）", src = I .. "137-142、" .. I .. "164" })
R({ id = "R-OK-08", group = "input", from = { "oku" }, key = { "bs" }, to = { "oku", "pre" },
  short = "送りを 1 文字消す", out = "送りを 1 文字消す。送りが空なら ▽ に戻る", src = I .. "188-194", views = { V3 = "holds" } })
R({ id = "R-OK-09", group = "input", from = { "okup" }, key = { "bs" }, to = { "okup", "oku" },
  short = "打ちかけを 1 文字消す", out = "打ちかけを 1 文字消す", src = I .. "183-187", views = { V3 = "holds" } })
R({ id = "R-ST-01", group = "input", from = { "okup" }, key = { "l", "q", ";", "/", "L" }, guard = "打ちかけが n（かなになる）", to = { "sel", "reg" }, pending = "flush", again = "same",
  short = "ん で変換が走る", out = "ん が送りに入って変換が走り、候補が無ければ辞書登録の欄が開く。そのあと ▽ 送りに戻して、キーの本来の動き（R-EN-01、R-MD-03 など）をする",
  src = I .. "137-142、" .. I .. "56-66", confidence = "inferred", views = { V4 = "breaks" }, recommend = "REC-ST" })

-- 変換 -------------------------------------------------------------------
R({ id = "R-HK-01", group = "henkan", from = { "pre", "prep", "oku", "okup" }, key = { "space" }, guard = "辞書に候補がある", to = { "sel" }, pending = "fold",
  short = "1 つ目の候補", out = "読み（送りありは 読み＋送りの最初のかなの子音）で辞書を引き、1 つ目の候補を出す", src = H .. "22-67、" .. H .. "91-101、" .. OK .. "43-59", views = { V10 = "holds" } })
R({ id = "R-HK-02", group = "henkan", from = { "pre", "prep", "oku", "okup" }, key = { "space" }, guard = "辞書に候補が無い", to = { "reg" }, pending = "fold",
  short = "登録の欄を開く", out = "host.input で辞書登録の欄を開く", src = H .. "102、" .. H .. "115、" .. DI .. "16-20", views = { V9 = "holds" } })
R({ id = "R-HK-03", group = "henkan", from = { "pre0", "prep" }, key = { "space" }, guard = "読みが空（▽、▽k）", to = { "pre0", "prep" }, pending = "fold",
  short = "何も起きない", out = "何も起きない。打ちかけは残る", src = H .. "40-42", views = { V2 = "holds" } })
R({ id = "R-HK-04", group = "henkan", from = { "prep", "okup" }, key = { "space" }, guard = "読みがあり、打ちかけがかなにならない（▽かk）", to = { "sel", "reg" }, pending = "keep",
  short = "打ちかけを隠して変換", out = "打ちかけを持ったまま変換する。▼ では打ちかけは見えず、確定すると消える。▽ に戻ると現れる",
  src = H .. "33、" .. H .. "46、" .. S .. "132-139、" .. C .. "20-31", confidence = "inferred", views = { V1 = "breaks", V2 = "breaks", P1 = "breaks" }, recommend = "REC-HIDDEN" })
R({ id = "R-HK-05", group = "henkan", from = { "oku" }, key = { "space" }, guard = "送りが空（▽か*）", to = { "reg", "sel" },
  short = "空の送りで引く", out = "送りありの辞書を、子音の付かない見出し（か）で引く。たいてい候補が無く、辞書登録の欄が開く。登録すると、送りの無い語が送りありに入る",
  src = H .. "52-54、" .. OK .. "58", confidence = "inferred", views = { V10 = "breaks", V9 = "breaks" }, recommend = "REC-EMPTY-OKURI" })
R({ id = "R-HK-06", group = "henkan", from = { "pre", "prep" }, key = { "gt" }, guard = "読みが空でない", to = { "sel", "reg" }, pending = "fold-drop", again = "henkan",
  short = "接頭辞として変換", out = "読みの終わりに > を足し、接頭辞として変換する（ちょう> → 超）。候補の終わりの > は出さない", src = I .. "214-219、" .. H .. "56-64、lua/skkeleton/candidate.lua:11-22" })
R({ id = "R-HK-07", group = "henkan", from = { "oku", "okup" }, key = { "gt" }, to = { "sel", "reg" }, pending = "fold-drop", again = "henkan",
  short = "> が送りに入る", out = "> が送りに入り、変換が 2 度呼ばれる。候補が無いと、登録の欄が続けて 2 回開きうる",
  src = I .. "214-218、" .. I .. "56-66", confidence = "inferred", views = { V10 = "breaks", P5 = "breaks" }, recommend = "REC-GT-OKURI" })
R({ id = "R-HK-08", group = "henkan", from = { "sel" }, key = { "space" }, guard = "次の候補がある", to = { "sel", "list" },
  short = "次の候補", out = "次の候補を出す。showCandidatesCount 個目からは一覧（host.show_candidates）", src = H .. "96-101、" .. H .. "123-125" })
R({ id = "R-HK-09", group = "henkan", from = { "list" }, key = { "space" }, guard = "次のページがある", to = { "list" },
  short = "7 つ進む", out = "一覧を 7 つ進める（host.show_candidates）", src = H .. "97-98、" .. H .. "123-125" })
R({ id = "R-HK-10", group = "henkan", from = HENKAN, key = { "space" }, guard = "候補が尽きた", to = { "reg" },
  short = "登録の欄を開く", out = "host.input で辞書登録の欄を開く", src = H .. "102、" .. H .. "115", views = { V9 = "holds" } })
R({ id = "R-HK-11", group = "henkan", from = { "pre", "prep", "oku", "okup", "sel", "list" }, key = { "space" }, guard = "候補が尽きた、かつ <C-r>= の式の中", to = { "direct" },
  short = "読みを確定", out = "登録の欄は開かず、読み（送りも）を確定する。host に式の中かを聞く（host.is_in_expression）", src = H .. "103-114", views = { V2 = "holds" } })
R({ id = "R-HK-12", group = "henkan", from = { "sel" }, key = { "x" }, to = { "sel", "pre", "oku" },
  short = "前の候補", out = "前の候補に戻る。1 つ目からは ▽ に戻る（送りありなら ▽ 送りで、送りは残る）", src = H .. "129-142", views = { V3 = "holds" } })
R({ id = "R-HK-13", group = "henkan", from = { "list" }, key = { "x" }, to = { "list", "sel" },
  short = "7 つ戻る", out = "一覧を 7 つ戻す。一覧の手前の候補で止まる", src = H .. "134-135、" .. H .. "143-145", views = { V3 = "holds" } })
R({ id = "R-HK-14", group = "henkan", from = { "list" }, key = { "select" }, guard = "その位置に候補がある", to = { "direct" },
  short = "その候補を確定", out = "その候補＋送りを確定し、辞書に覚える", src = H .. "152-165", views = { V8 = "holds", P10 = "holds" } })
R({ id = "R-HK-15", group = "henkan", from = { "list" }, key = { "select" }, guard = "その位置に候補が無い", to = { "list" },
  short = "何も起きない", out = "何も起きない", src = H .. "166-169" })
R({ id = "R-HK-16", group = "henkan", from = HENKAN, key = { "gt" }, to = { "pre" },
  short = "確定して ▽>", out = "候補を確定し、読みが > の ▽ を開く（接尾辞）", src = H .. "178-187", views = { V8 = "holds" } })
R({ id = "R-PG-01", group = "henkan", from = HENKAN, key = { "X" }, guard = "host.confirm の答えが「はい」", to = { "direct" },
  short = "候補を辞書から消す", out = "候補を辞書から消す。読みも候補も消える。converter も消えるので、カタカナモードでも ひらがな が出る（モードの表示はカタカナのまま）",
  src = C .. "89-112（" .. C .. "110）", confidence = "inferred", views = { V1 = "breaks", V6 = "breaks", P11 = "breaks" }, recommend = "REC-PURGE" })
R({ id = "R-PG-02", group = "henkan", from = HENKAN, key = { "X" }, guard = "host.confirm の答えが「いいえ」", to = { "sel", "list" },
  short = "何も起きない", out = "何も起きない", src = C .. "108" })

-- 取り消しと確定 ---------------------------------------------------------
R({ id = "R-CK-01", group = "commit", from = DIRECT, key = { "cg" }, to = { "direct" }, pending = "erase",
  short = "打ちかけを消す", out = "打ちかけを消す。cmdline の読みなしでは、host へ <C-c> を渡す", src = C .. "71-82", views = { V3 = "holds", V7 = "holds" } })
R({ id = "R-CK-02", group = "commit", from = PRE, key = { "cg" }, to = { "direct" }, pending = "erase",
  short = "読みを消す", out = "読みを消す。モードは変わらない（abbrev は ひらがな に戻る）", src = C .. "77-83、" .. MD .. "25-34", views = { V3 = "holds", V6 = "holds", V7 = "holds" } })
R({ id = "R-CK-03", group = "commit", from = HENKAN, key = { "cg" }, guard = "immediatelyCancel = true（既定）", to = { "direct" }, pending = "erase",
  short = "読みごと消す", out = "候補も読みも消す", src = C .. "77-79", views = { V3 = "breaks" }, recommend = "REC-CANCEL" })
R({ id = "R-CK-04", group = "commit", from = HENKAN, key = { "cg" }, guard = "immediatelyCancel = false", to = { "pre", "oku" }, pending = "keep",
  short = "▽ に戻る", out = "▽ に戻る（送りも残る）", src = C .. "83-85", views = { V3 = "holds" } })
R({ id = "R-CK-05", group = "commit", from = { "direct" }, key = { "cj" }, to = { "direct" },
  short = "ひらがなに戻す", out = "確定するものが無いので、ひらがなモードに戻す（host.mode_changed）", src = C .. "47-54、" .. M .. "31-42", views = { V7 = "holds" } })
R({ id = "R-CK-06", group = "commit", from = { "pending" }, key = { "cj" }, to = { "direct" }, pending = "raw",
  short = "打ちかけを確定", out = "打ちかけを確定する（n → ん、k → k のまま）", src = C .. "55、" .. C .. "32-38", views = { V4 = "holds", V2 = "holds" } })
R({ id = "R-CK-07", group = "commit", from = PRE, key = { "cj" }, to = { "direct" }, pending = "raw",
  short = "読みを確定", out = "読み＋送り＋打ちかけをそのまま確定する。モードは変わらない", src = C .. "32-42", views = { V2 = "holds", V6 = "holds", V7 = "open" } })
R({ id = "R-CK-08", group = "commit", from = HENKAN, key = { "cj" }, to = { "direct" },
  short = "候補を確定", out = "候補＋送りを確定し、辞書に覚える", src = C .. "20-31、" .. C .. "42", views = { V8 = "holds", P10 = "holds", V1 = "holds" } })
R({ id = "R-CK-09", group = "commit", from = DIRECT, key = { "cr" }, to = { "direct" }, pending = "raw",
  short = "確定して改行", out = "打ちかけを確定してから、改行を確定する。モードは変わらない", src = C .. "59-68", views = { V2 = "holds", V6 = "holds" } })
R({ id = "R-CK-10", group = "commit", from = PRE, key = { "cr" }, to = { "direct" }, pending = "raw",
  short = "確定（＋改行）", out = "読みを確定する。eggLikeNewline が偽（既定）なら改行もする", src = C .. "61-67", views = { V2 = "holds", V6 = "holds" } })
R({ id = "R-CK-11", group = "commit", from = HENKAN, key = { "cr" }, to = { "direct" },
  short = "確定（＋改行）", out = "候補を確定し、辞書に覚える。eggLikeNewline が偽（既定）なら改行もする", src = C .. "61-67", views = { V8 = "holds", V2 = "holds" } })
R({ id = "R-CK-12", group = "commit", from = HENKAN, key = { "kana", "upper", "l", "q", ";", "/", "L", "cq", "esc" }, to = { "direct" }, again = "same",
  short = "確定して打ち直す", out = "候補を確定して辞書に覚え、同じキーを読みなしで打ち直す（暗黙の確定）。一覧では選択キーが先に効く", src = H .. "150-175", views = { V8 = "holds", V2 = "holds", P10 = "holds" } })
R({ id = "R-CK-13", group = "commit", from = HENKAN, key = { "bs" }, to = { "direct" }, again = "same",
  short = "確定して 1 文字消す", out = "候補を確定してから、確定した 1 文字を消す", src = H .. "173-174、" .. I .. "201-203", views = { V3 = "breaks" }, recommend = "REC-BS" })
R({ id = "R-CK-14", group = "commit", from = HENKAN, key = { "*" }, guard = "候補が無いまま確定に入った（起きないはず）", to = { "direct" },
  short = "error が入る", out = "今は error という文字が確定される", src = C .. "31、" .. S .. "134", confidence = "inferred", status = "undefined", views = { V1 = "breaks", V2 = "breaks" }, recommend = "REC-CANDNIL" })

-- モード -----------------------------------------------------------------
R({ id = "R-MD-01", group = "mode", from = DIRECT, key = { "q" }, to = { "direct" }, pending = "flush",
  short = "カタカナ ↔ ひらがな", out = "ひらがな なら カタカナ へ、カタカナ・半角カナなら ひらがな へ（host.mode_changed）", src = M .. "70-91", views = { V1 = "holds" } })
R({ id = "R-MD-02", group = "mode", from = DIRECT, key = { "cq" }, to = { "direct", "pending" }, pending = "keep",
  short = "半角カナ ↔ ひらがな", out = "半角カナなら ひらがな へ、ほか（カタカナ・全英も）は半角カナへ。全英からはテーブルもローマ字に戻す（#40）", src = M .. "70-91", views = { V1 = "holds" } })
R({ id = "R-MD-03", group = "mode", from = PRE, key = { "q", "cq" }, guard = "abbrev でない", to = { "direct" }, pending = "fold-drop",
  short = "逆のかなで確定", out = "読み＋送りを、今と逆のかなで確定する（ひらがな中の q はカタカナ、カタカナ・半角カナ中の q は ひらがな）。モードは変わらない。registerConvertResult が真なら辞書に覚える。打ちかけの子音は消える",
  src = M .. "49-63、" .. M .. "74-79", views = { V1 = "holds", V6 = "holds", V2 = "breaks", P1 = "breaks" }, recommend = "REC-DROP" })
R({ id = "R-MD-04", group = "mode", from = DIRECT, key = { "L" }, to = { "direct" }, pending = "flush",
  short = "全英へ", out = "全英モードにする（テーブルを全角英字に替える）", src = M .. "104-116", views = { V1 = "holds" } })
R({ id = "R-MD-05", group = "mode", from = PRE, key = { "L" }, guard = "abbrev でない", to = { "direct" }, pending = "flush",
  short = "確定して全英へ", out = "読みを確定してから、全英モードにする", src = M .. "109-115", views = { V2 = "holds" } })
R({ id = "R-MD-06", group = "mode", from = DIRECT, key = { "/" }, to = { "pre0" }, pending = "flush",
  short = "abbrev を始める", out = "▽ を開き、abbrev モードにする（かなテーブルは空。大文字で送りを切らない）", src = M .. "19-28" })
R({ id = "R-MD-07", group = "mode", from = PRE, key = { "/" }, guard = "abbrev でない", to = PRE, pending = "flush",
  short = "何も起きない", out = "何も起きない（打ちかけは片付ける）", src = M .. "20-22、" .. I .. "137-142" })
R({ id = "R-MD-08", group = "mode", from = { "pre0", "pre" }, key = { "kana", "upper", "l", "q", ";", "/", "L", "gt" }, guard = "abbrev", to = { "pre" },
  short = "読みにそのまま足す", out = "どの文字も読みにそのまま足す（関数のキーも大文字も文字になる）", src = I .. "91、" .. I .. "134、" .. I .. "214、" .. I .. "115-118" })
R({ id = "R-MD-09", group = "mode", from = PRE, key = { "cq" }, guard = "abbrev", to = PRE,
  short = "何も起きない", out = "何も起きない（tests/diff/known.lua の abbrev-ignores-kana-toggle）", src = M .. "71-73" })
R({ id = "R-MD-10", group = "mode", from = { "pre0", "pre", "sel", "list" }, key = { "cj", "cr", "cg", "bs", "kana" }, guard = "abbrev で、確定か取り消しになるキー", to = { "direct" },
  short = "ひらがなに戻る", out = "確定・取り消しのあと、ひらがなモードに戻る。abbrev に入る前がカタカナでも ひらがな になる", src = MD .. "25-34、" .. M .. "23-27", views = { V6 = "breaks" }, recommend = "REC-ABBREV" })
R({ id = "R-MD-11", group = "mode", from = { "direct" }, key = { "kana", "upper", "l", "q", ";", "/", "L", "gt", "space" }, guard = "全英", to = { "direct" },
  short = "全角で確定", out = "全角の英字・記号で確定する。▽ は開かない（大文字も l q L も文字）", src = I .. "92-94、" .. I .. "134、lua/skkeleton/kana/rom_zen.lua:39-90", confidence = "inferred", views = { V5 = "holds" } })

-- 辞書登録 ---------------------------------------------------------------
R({ id = "R-RG-01", group = "register", from = { "reg" }, key = { "open" }, to = { "reg" },
  short = "内側の機械を作る", out = "内側に新しい機械（読みなし、ctx.mode は hira）を作る。g:skkeleton#mode は外のモードのまま変えない",
  src = HO .. "196-199、lua/skkeleton/context.lua:18-26", confidence = "inferred", views = { V1 = "breaks", P11 = "breaks" }, recommend = "REC-INNER-MODE" })
R({ id = "R-RG-02", group = "register", from = { "reg" }, key = { "*" }, to = { "reg" },
  short = "内側の機械が受ける", out = "キーは内側の機械が、同じ規則で受ける（入れ子にもなる）", src = HO .. "200-211", views = { V9 = "holds" } })
R({ id = "R-RG-03", group = "register", from = { "reg" }, key = { "ans:word" }, to = { "direct" },
  short = "語＋送りを確定", out = "外で 語＋送り を確定し、その語を辞書に覚える", src = DI .. "28-34、" .. C .. "20-31", views = { V9 = "holds", V8 = "holds", P10 = "holds" } })
R({ id = "R-RG-04", group = "register", from = { "reg" }, key = { "ans:cancel" }, guard = "1 つ目の候補より前で開いた", to = { "pre", "prep", "oku", "okup" },
  short = "▽ に戻る", out = "入る前の ▽ に戻る（送りも残る）。エラーで中断したときも同じ", src = H .. "118-121、" .. DI .. "20-30", views = { V3 = "holds", V9 = "holds", P9 = "holds" } })
R({ id = "R-RG-05", group = "register", from = { "reg" }, key = { "ans:cancel" }, guard = "候補を見たあとで開いた", to = { "sel", "list" },
  short = "最後の候補に戻る", out = "入る前の候補に戻る", src = H .. "118、" .. H .. "123-125", views = { V3 = "holds", P9 = "holds" } })
R({ id = "R-RG-06", group = "register", from = { "reg" }, key = { "cg", "esc" }, guard = "内側に読みか候補がある", to = { "pre", "oku", "sel", "list" },
  short = "登録ごと取り消す", out = "内側の読みではなく、登録そのものが取り消される（host が欄の <Esc> <C-g> <C-c> を取り消しに割り当てている）",
  src = HO .. "204-208", confidence = "inferred", views = { V3 = "breaks", V9 = "breaks" }, recommend = "REC-INNER-CANCEL" })
R({ id = "R-RG-07", group = "register", from = { "reg" }, key = { "ans:word" }, guard = "内側でかなテーブルを替えたまま確定した（全英など）", to = { "direct" },
  short = "テーブルが外に漏れる", out = "今のテーブルの名前（kana.current_name）は機械の外にあるので、外の次の初期化（<C-g> など）で全英のテーブルが入る。モードの表示は外のまま",
  src = M .. "113、" .. S .. "56、" .. C .. "78、" .. HO .. "165-166", confidence = "inferred", views = { V1 = "breaks", P11 = "breaks", P6 = "breaks" }, recommend = "REC-TABLE" })
R({ id = "R-RG-08", group = "register", from = { "reg" }, key = { "l" }, guard = "内側が読みなし", to = { "reg" },
  short = "内側だけ無効", out = "内側で無効にしたあとの動きを、core は決めていない", src = D .. "14-18、" .. HO .. "22-37", confidence = "open", status = "undefined", recommend = "REC-INNER-DISABLE" })
R({ id = "R-RG-09", group = "register", from = { "reg" }, key = { "ev:enable", "ev:disable" }, to = { "reg" },
  short = "受けない", out = "欄が開いている間の enable / disable を、core は決めていない", src = MA .. "101-176", confidence = "open", status = "undefined", recommend = "REC-REG-EVENT" })

-- 有効と無効 -------------------------------------------------------------
R({ id = "R-EN-01", group = "power", from = INPUT, key = { "l" }, guard = "既定のローマ字のテーブル", to = { "off" }, pending = "flush",
  short = "確定して無効", out = "読みを確定してから、無効にする（host.disable）", src = K .. "37、" .. I .. "129-143、" .. D .. "14-18", views = { V2 = "holds" } })
R({ id = "R-EN-02", group = "power", from = INPUT, key = { "esc" }, to = { "off" }, pending = "raw",
  short = "確定して <Esc>", out = "読みを確定して無効にし、host に <Esc> を通させる。keepState が真なら、次の InsertEnter で有効に戻す（host.keep_state_on_insert_enter）", src = D .. "20-27、" .. S .. "148-149", views = { V2 = "holds", V7 = "holds" } })
R({ id = "R-EN-03", group = "power", from = { "off" }, key = { "ev:enable" }, to = { "direct" },
  short = "有効にする", out = "新しい機械を作る。モードは hira（keepMode が真なら、前に使っていたモード）", src = MA .. "149-161、" .. MD .. "17-19", views = { V6 = "holds", P8 = "holds" } })
R({ id = "R-EN-04", group = "power", from = { "direct" }, key = { "ev:enable" }, to = { "direct" },
  short = "作り直す", out = "機械を作り直す（モードは R-EN-03 と同じ決め方）", src = MA .. "149-161" })
R({ id = "R-EN-05", group = "power", from = { "pending", "pre0", "pre", "prep", "oku", "okup" }, key = { "ev:enable" }, to = { "pending", "pre0", "pre", "prep", "oku", "okup" }, pending = "keep",
  short = "何も起きない", out = "何も起きない。読みは残る（#210）", src = MA .. "137-146", views = { V2 = "holds" } })
R({ id = "R-EN-06", group = "power", from = HENKAN, key = { "ev:enable" }, to = { "direct" },
  short = "確定して作り直す", out = "候補を確定してから、機械を作り直す（#210、#241）", src = MA .. "115-135", views = { V2 = "holds", V8 = "holds" } })
R({ id = "R-EN-07", group = "power", from = ON, key = { "ev:disable" }, to = { "off" }, pending = "raw",
  short = "確定して無効", out = "読みか候補を確定してから、無効にする", src = MA .. "166-176、" .. D .. "14-18", views = { V2 = "holds", P8 = "holds" } })
R({ id = "R-EN-08", group = "power", from = { "off" }, key = { "*" }, to = { "off" },
  short = "届かない", out = "キーは core に届かない（マッピングが外れている）。disable も何もしない", src = HO .. "22-29" })
R({ id = "R-EN-09", group = "power", from = { "off" }, key = { "*" }, guard = "<Esc> の直後で、マッピングが残っていてキーが届いた", to = { "off" },
  short = "エラー", out = "今は Illegal State のエラーになる", src = K .. "65-68、" .. D .. "26", confidence = "inferred", status = "undefined", recommend = "REC-ESCAPE" })

------------------------------------------------------------------------
-- 視点と性質。結論は rules の views から figures.lua が出す。note は手で書く
------------------------------------------------------------------------
T.views = {
  { id = "V1", title = "見えているとおりに確定する", note = "確定の文字列と表示は、同じ converter と同じ候補から作っている（" .. S .. "104-139、" .. C .. "20-38）。破れは、表示に出ない状態を持つところ" },
  { id = "V2", title = "打った文字は、取り消しのキーを押さない限り消えない", note = "有効・無効、改行、モードの切り替えは、どれも先に確定する。破れは、かなにならない打ちかけを捨てるところ（upstream と同じ）と、▼ に隠れた打ちかけ" },
  { id = "V3", title = "取り消しは 1 段ずつ戻る", note = "<BS> と x は 1 段ずつ戻る。<C-g> は設定で分かれる" },
  { id = "V4", title = "前に打ったキーの意味が、あとのキーで変わらない", note = "n は確定のときに ん になる（upstream #6）。送りの前の n は読みに入る（upstream #18）" },
  { id = "V5", title = "同じ状態で同じキーを押せば、同じことが起きる", note = "かなテーブルとキーマップの順番は keymap.handle_key の 1 か所で決まる（" .. K .. "73-86）" },
  { id = "V6", title = "モードは、自分で切り替えるまで変わらない", note = "確定と取り消しは converter とテーブルを残す（" .. C .. "42、" .. C .. "78）" },
  { id = "V7", title = "どこからでも、決まったキーで決まった場所に戻れる", verdict = "open", note = "<C-g> と <Esc> はどこからでも同じ。<C-j> は読みがあれば確定、無ければ ひらがな に戻るので、カタカナの ▽ から ひらがな の読みなしまでは 2 打かかる。1 打で戻ることまで求めるかで結論が変わる" },
  { id = "V8", title = "確定は 1 度だけで、確定したものが辞書に覚えられる", note = "候補の確定は、どの道も common.kakutei の 1 か所を通る（" .. C .. "20-26）" },
  { id = "V9", title = "辞書登録は変換の続きとして動く", note = "登録した語は送りと一緒に確定される。欄の中は同じ機械が動く" },
  { id = "V10", title = "送り仮名はかなの単位で切れる", note = "送りの子音は、っ を除いた最初のかなから決める（" .. OK .. "43-59）" },
  { id = "P1", title = "読みが黙って消えない", note = "V2 を core の外の言葉で言ったもの。破れは V2 と同じ" },
  { id = "P5", title = "二重に処理しない", note = "1 打は handle_key を 1 度通る。打ち直し（again）は同じ打鍵の中で起きる" },
  { id = "P6", title = "決定的", note = "設定・辞書・host の答えを決めれば、行き先は 1 つに決まる。ただし今のテーブルの名前と last_mode が機械の外にある" },
  { id = "P8", title = "enable → disable で元に戻る", note = "disable は状態を初期化し、enable は機械を作り直す。core の範囲では守っている。無効の間 ctx.mode は古い値のまま残るが、次の enable で作り直される" },
  { id = "P9", title = "登録の入れ子から戻れる", note = "host.input は pcall で包んであり、答えが無ければ入る前の段に戻る（" .. DI .. "20-30）" },
  { id = "P10", title = "2 度確定しない", note = "確定のあとは必ず状態を初期化する（" .. C .. "42）" },
  { id = "P11", title = "g:skkeleton#mode が中と一致する", note = "mode.mode_change が ctx.mode と host を一緒に変える（" .. MD .. "14-20）。破れは、mode_change を通らずに converter やテーブルが変わるところ" },
}

T.groups = {
  { id = "input", title = "入力", states = { "direct", "pending", "pre0", "pre", "prep", "oku", "okup", "sel", "reg" } },
  { id = "henkan", title = "変換", states = { "direct", "pre0", "pre", "prep", "oku", "okup", "sel", "list", "reg" } },
  { id = "commit", title = "取り消しと確定", states = { "direct", "pending", "pre0", "pre", "prep", "oku", "okup", "sel", "list" } },
  { id = "mode", title = "モード", states = { "direct", "pending", "pre0", "pre", "prep", "oku", "okup", "sel", "list" } },
  { id = "register", title = "辞書登録", states = { "direct", "pre", "prep", "oku", "okup", "sel", "list", "reg" } },
  { id = "power", title = "有効と無効", states = { "off", "direct", "pending", "pre0", "pre", "prep", "oku", "okup", "sel", "list" } },
}

return T

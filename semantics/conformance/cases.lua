-- SKK の実装を横に並べて比べるためのキー列（#262）
--
-- 素の Lua のテーブルを返す。vim.* は使わない。形と決まりは DESIGN.md に書いてある。
--
-- cases の 1 件：
--   id        C で始まる通し番号
--   group     baseline（ドライバの確かめ）/ pending（打ちかけ）/ okuri（送り）/ cancel（取り消しと確定）/ mode（モード）
--   keys      キー列。skkeleton の既定の割り当てを、Vim の表記で書く（"Kanji<Space><C-j>"）。
--             実装ごとのキーへの読み替えは DESIGN.md の §4
--   ask       このキー列で何を知りたいか（使う人の言葉で）
--   rules     当たる規則の id（semantics/core/rules.lua）
--   views     関わる視点（#260 の V1〜V10）
--   decision  根拠を足したい項目の番号（semantics/core/DECISIONS.md）。無ければ書かない
--   expect    skkeleton.nvim の今の動きの予想。観測の形（DESIGN.md の §2）で、比べたい項目だけ書く。
--             semantics/core/CORE.md の読みから書いたもので、まだ動かして確かめていない
--   sure      expect の確かさ。read（読んで追えた）/ inferred（推測）
--
-- どのケースも、新しい入力の状態（有効、ひらがな、読みなし）と、空のユーザー辞書から始める。

local T = {}

-- 全部の実装で同じものを使う辞書。自分で書いたもので、配布されている辞書からは写していない。
-- 見出しは、送りありが「読み＋送りの子音」、送りなしが読み。候補は先頭が 1 つ目
T.dictionary = {
  okuri_ari = {
    { "かk", { "書", "欠" } },
    { "かんs", { "関" } },
    { "さっs", { "察" } },
    { "つかt", { "使" } },
  },
  okuri_nasi = {
    { "か", { "蚊" } },
    { "かんじ", { "漢字", "幹事" } },
  },
}

T.cases = {
  -- ドライバの確かめ。ここで割れたら、実装の違いではなくドライバを疑う ------------
  {
    id = "C01", group = "baseline", keys = "aiueo",
    ask = "母音がそのまま ひらがな で確定されるか",
    rules = { "R-IN-01" }, views = {},
    expect = { text = "あいうえお", stage = "none", mode = "hira" }, sure = "read",
  },
  {
    id = "C02", group = "baseline", keys = "Kanji<Space>",
    ask = "大文字で読みを始め、<Space> で 1 つ目の候補が出るか。読みの途中の n は ん になるか",
    rules = { "R-IN-09", "R-PR-01", "R-PR-04", "R-HK-01" }, views = { "V4" },
    expect = { text = "", stage = "select", reading = "かんじ", candidate = "漢字", mode = "hira" }, sure = "read",
  },
  {
    id = "C03", group = "baseline", keys = "Kanji<Space><C-j>",
    ask = "<C-j> で候補が確定されるか",
    rules = { "R-CK-08" }, views = { "V8" },
    expect = { text = "漢字", stage = "none", mode = "hira" }, sure = "read",
  },
  {
    id = "C04", group = "baseline", keys = "Kanji<Space><Space>",
    ask = "2 度目の <Space> で次の候補が出るか",
    rules = { "R-HK-08" }, views = {},
    expect = { text = "", stage = "select", candidate = "幹事" }, sure = "read",
  },
  {
    id = "C05", group = "baseline", keys = "KaKu",
    ask = "2 つ目の大文字で送りが始まり、送りのかなが決まったら変換されるか",
    rules = { "R-PR-11", "R-OK-01" }, views = { "V10" },
    expect = { text = "", stage = "select", reading = "か", okuri = "く", candidate = "書" }, sure = "read",
  },

  -- 打ちかけ（ローマ字の途中）をどう片付けるか ------------------------------------
  {
    id = "C06", group = "pending", keys = "kt",
    ask = "かなにならない打ちかけ k は、次の子音で消えるか、残るか",
    rules = { "R-IN-04" }, views = { "V2" }, decision = 2,
    expect = { text = "", stage = "none", pending = "t" }, sure = "read",
  },
  {
    id = "C07", group = "pending", keys = "k<C-j>",
    ask = "打ちかけ k だけのときの <C-j> は、k を確定するか、消すか",
    rules = { "R-CK-06" }, views = { "V2" }, decision = 2,
    expect = { text = "k", stage = "none", pending = "", mode = "hira" }, sure = "read",
  },
  {
    id = "C08", group = "pending", keys = "Kan<C-j>",
    ask = "読みの終わりの打ちかけ n は、確定のときに ん になるか",
    rules = { "R-CK-07" }, views = { "V4" },
    expect = { text = "かん", stage = "none" }, sure = "read",
  },
  {
    id = "C09", group = "pending", keys = "Kak<Space>",
    ask = "読みのあとにかなにならない打ちかけ k があるとき、<Space> で変換されるか",
    rules = { "R-HK-04" }, views = { "V1", "V2" }, decision = 1,
    expect = { text = "", stage = "select", reading = "か", candidate = "蚊" }, sure = "inferred",
  },
  {
    id = "C10", group = "pending", keys = "Kak<Space><C-j>",
    ask = "C09 のあと確定すると、打ちかけ k はどこへ行くか（消える、確定される、残る）",
    rules = { "R-HK-04", "R-CK-08" }, views = { "V2" }, decision = 1,
    expect = { text = "蚊", stage = "none", pending = "" }, sure = "inferred",
  },

  -- 送り ----------------------------------------------------------------------------
  {
    id = "C11", group = "okuri", keys = "KanSu",
    ask = "送りを始める大文字の前の打ちかけ n は、読みに入るか（かん＋す）",
    rules = { "R-PR-13", "R-OK-01" }, views = { "V4", "V10" },
    expect = { text = "", stage = "select", reading = "かん", okuri = "す", candidate = "関" }, sure = "read",
  },
  {
    id = "C12", group = "okuri", keys = "SasSi",
    ask = "送りを始める大文字の前の打ちかけ s は、促音として読みに入るか（さっ＋し）",
    rules = { "R-PR-13", "R-OK-03", "R-OK-01" }, views = { "V10" },
    expect = { text = "", stage = "select", reading = "さっ", okuri = "し", candidate = "察" }, sure = "read",
  },
  {
    id = "C13", group = "okuri", keys = "TukaTta",
    ask = "送りが促音で始まるとき、促音の次のかなまで待ってから変換されるか（つか＋った）",
    rules = { "R-OK-03", "R-OK-01" }, views = { "V10" },
    expect = { text = "", stage = "select", reading = "つか", okuri = "った", candidate = "使" }, sure = "read",
  },
  {
    id = "C14", group = "okuri", keys = "Ka;<Space>",
    ask = "送りを始めただけ（▽か*）で <Space> を押すと、何が起きるか（何も起きない、送りなしで変換、登録の欄）",
    rules = { "R-PR-12", "R-HK-05" }, views = { "V9", "V10" }, decision = 10,
    expect = { text = "", stage = "register", reading = "か", okuri = "" }, sure = "inferred",
  },

  -- 取り消しと確定 ------------------------------------------------------------------
  {
    id = "C15", group = "cancel", keys = "Kanji<Space><C-g>",
    ask = "候補を見ているときの <C-g> は、読みに戻るか、読みごと消えるか",
    rules = { "R-CK-03", "R-CK-04" }, views = { "V3" }, decision = 14,
    expect = { text = "", stage = "none", reading = "" }, sure = "read",
  },
  {
    id = "C16", group = "cancel", keys = "Kanji<Space><BS>",
    ask = "候補を見ているときの <BS> は、前の段に戻るか、確定して 1 文字消すか",
    rules = { "R-CK-13" }, views = { "V3" }, decision = 15,
    expect = { text = "漢", stage = "none" }, sure = "read",
  },
  {
    id = "C17", group = "cancel", keys = "Kanji<Space>x",
    ask = "1 つ目の候補から x で戻ると、読みに戻るか",
    rules = { "R-HK-12" }, views = { "V3" },
    expect = { text = "", stage = "reading", reading = "かんじ" }, sure = "read",
  },
  {
    id = "C18", group = "cancel", keys = "Kanji<Space>a",
    ask = "候補を見ているときに文字を打つと、候補が確定されてから文字が入るか",
    rules = { "R-CK-12" }, views = { "V2", "V8" },
    expect = { text = "漢字あ", stage = "none" }, sure = "read",
  },

  -- モード --------------------------------------------------------------------------
  {
    id = "C19", group = "mode", keys = "qKa<C-j>",
    ask = "カタカナモードの読みを <C-j> で確定したあと、モードはカタカナのままか、ひらがなに戻るか",
    rules = { "R-MD-01", "R-CK-07" }, views = { "V6", "V7" }, decision = 18,
    expect = { text = "カ", stage = "none", mode = "kata" }, sure = "read",
  },
  {
    id = "C20", group = "mode", keys = "q/a<C-j>",
    ask = "カタカナモードから abbrev に入って確定したあと、モードはカタカナに戻るか、ひらがなになるか",
    rules = { "R-MD-06", "R-MD-08", "R-MD-10" }, views = { "V6" }, decision = 9,
    expect = { text = "a", stage = "none", mode = "hira" }, sure = "read",
  },
}

return T

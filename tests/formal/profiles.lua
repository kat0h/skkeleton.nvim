-- 形式検証の PoC: 検査の組み合わせ（プロファイル）。
-- それぞれ、skkeleton の設定（config）、流すキーの集合（alphabet）、初期状態（inits）、辞書（dict）を持つ。
-- 初期状態の lines は上のウィンドウのバッファ、下のウィンドウには "xy" がある。keys は初期状態に入るキー
local M = {}

local dict = table.concat({
  ";; okuri-ari entries.",
  "わるk /悪/",
  "かえr /帰/返/",
  ";; okuri-nasi entries.",
  "かん /缶/感/漢/幹/管/館/観/",
  "かんじ /漢字/幹事/",
  "なか /中/",
  "#ばい /#1倍/#3倍/",
  "abc /ＡＢＣ/",
  "",
}, "\n")

-- insert モードの入力・変換、skkeleton が処理しない編集キー、モードとウィンドウの行き来
local base = {
  "<C-j>", -- toggle（利用者の設定と同じく i と c に割り当てる）
  "k",
  "a",
  "n",
  "K",
  "<Space>",
  "x",
  "q",
  "<CR>",
  "<BS>",
  "<C-g>",
  "<C-u>",
  "<C-w>",
  "<Left>",
  "<Right>",
  "<Esc>",
  "i",
  "A",
  ":",
  "<Cmd>wincmd w<CR>",
  -- マクロ遷移: 深いところ（▽かん、候補一覧）へ 1 手で行く
  "Kan",
  "<Space><Space><Space><Space>",
}

local function with(list, extra)
  return vim.list_extend(vim.list_slice(list), extra)
end

local line_inits = {
  ["#bol"] = { lines = { "ab cd" }, cursor = { 1, 0 }, keys = "i" },
  ["#mid"] = { lines = { "ab cd" }, cursor = { 1, 2 }, keys = "i" },
  ["#eol"] = { lines = { "ab cd" }, cursor = { 1, 4 }, keys = "a" },
}

M.default = {
  doc = "既定の設定で、入力・変換・編集キー・モードとウィンドウの行き来",
  config = {},
  alphabet = base,
  inits = line_inits,
  dict = dict,
}

-- 入力モードの切り替え（カタカナ、半角カナ、全英、abbrev、英字）と送り仮名・数値変換
M.modes = {
  doc = "入力モードの切り替え（q、<C-q>、L、l、/）と送り仮名・数値変換",
  config = {},
  alphabet = {
    "<C-j>",
    "q",
    "<C-q>",
    "L",
    "l",
    "/",
    "a",
    "K",
    "<Space>",
    "<CR>",
    "<BS>",
    "<C-g>",
    "<Esc>",
    "i",
    "<Left>",
    ":",
    "Kaer",
    "Q1",
    "#",
    "abc",
    "Wa",
    "u",
  },
  inits = line_inits,
  dict = dict,
}

-- 設定を変えたとき（eggLikeNewline、keepState、keepMode、マーカー、候補一覧を早く出す）
M.config = {
  doc = "eggLikeNewline・keepState・keepMode・別のマーカー・showCandidatesCount = 1",
  config = {
    eggLikeNewline = true,
    keepState = true,
    keepMode = true,
    markerHenkan = "<>",
    markerHenkanSelect = "[]",
    showCandidatesCount = 1,
    popupBorder = "rounded",
  },
  alphabet = with(base, { "q", "a", "x", "<Space>" }),
  inits = line_inits,
  dict = dict,
}

-- 画面の端。右端（長い行の行末）と、ウィンドウの最後の行で、popup とインジケータを出す
M.edge = {
  doc = "画面の右端と下端で、popup とインジケータが画面に収まり、カーソルを隠さない",
  config = { indicator = { style = "rounded" }, popupBorder = "single", showCandidatesCount = 1 },
  alphabet = {
    "<C-j>",
    "Kan",
    "<Space>",
    "<Space><Space><Space>",
    "x",
    "<CR>",
    "<BS>",
    "<C-g>",
    "<Esc>",
    "A",
    "a",
    "<Left>",
    "<Right>",
  },
  inits = {
    -- 80 桁の画面で、行末が右端のすぐ手前
    ["#right"] = { lines = { ("x"):rep(74) }, cursor = { 1, 73 }, keys = "a" },
    -- 上のウィンドウの最後の行（画面の下の方）
    ["#bottom"] = {
      lines = vim.split(("l\n"):rep(30), "\n", { trimempty = true }),
      cursor = { 30, 0 },
      keys = "A",
      cmd = "normal! zb",
    },
    ["#corner"] = {
      lines = vim.list_extend(vim.split(("l\n"):rep(29), "\n", { trimempty = true }), { ("y"):rep(74) }),
      cursor = { 30, 73 },
      keys = "a",
      cmd = "normal! zb",
    },
  },
  dict = dict,
}

-- コマンドラインでの入力
M.cmdline = {
  doc = "コマンドライン（:）の中での入力・変換・取り消し",
  config = {},
  alphabet = {
    "<C-j>",
    "k",
    "a",
    "n",
    "K",
    "<Space>",
    "x",
    "q",
    "<CR>",
    "<BS>",
    "<C-g>",
    "<C-w>",
    "<C-u>",
    "<Left>",
    "<Right>",
    "<Esc>",
    "Kan",
    "<Space><Space><Space><Space>",
    "l",
    "/",
  },
  inits = {
    ["#cmd"] = { lines = { "ab cd" }, cursor = { 1, 2 }, keys = ":" },
    ["#cmd-on"] = { lines = { "ab cd" }, cursor = { 1, 2 }, keys = ":<C-j>" },
  },
  dict = dict,
}

-- インジケータの見た目（#9）と popup の枠（#10）
M.styles = {
  doc = "インジケータの style（pill、minimal）と popup の枠",
  config = { indicator = { style = "pill" }, popupBorder = "rounded" },
  alphabet = with(base, { "q", "l", "L" }),
  inits = line_inits,
  dict = dict,
}

M.rounded = {
  doc = "インジケータの style = rounded（枠つき）",
  config = { indicator = { style = "rounded" } },
  alphabet = with(base, { "q", "l" }),
  inits = line_inits,
  dict = dict,
}

M.minimal = {
  doc = "インジケータの style = minimal、always_shown = false",
  config = { indicator = { style = "minimal", alwaysShown = false } },
  alphabet = with(base, { "q", "l" }),
  inits = line_inits,
  dict = dict,
}

-- insert の中から別のモードへ入るキー（<C-o>、<C-r>=、<C-v>）、補完のメニュー、行の追加、置換モード、候補の削除
M.misc = {
  doc = "<C-o>・<C-r>=・<C-v>・<C-n> の補完・o/O・R（置換）・X（候補の削除）",
  config = {},
  alphabet = {
    "<C-j>",
    "Kan",
    "a",
    "<Space>",
    "<CR>",
    "<C-g>",
    "<Esc>",
    "<C-o>l",
    "<C-o>:<Esc>",
    "<C-r>=1<CR>",
    "<C-v>",
    "<C-n>",
    "<C-p>",
    "<C-e>",
    "o",
    "O",
    "R",
    "X",
    "<Tab>",
    "<C-x><C-n>",
  },
  inits = line_inits,
  dict = dict,
}

-- terminal モード（:terminal で cat を動かす）
M.terminal = {
  doc = "terminal モードでの入力・変換・抜け方",
  config = {},
  alphabet = {
    "<C-j>",
    "k",
    "a",
    "n",
    "K",
    "<Space>",
    "<CR>",
    "<BS>",
    "<C-g>",
    "Kan",
    "<C-\\><C-n>",
    "i",
    "q",
  },
  inits = {
    ["#term"] = { lines = { "ab cd" }, cursor = { 1, 2 }, cmd = "terminal cat", keys = "i" },
  },
  dict = dict,
}

M.names = { "default", "modes", "config", "edge", "cmdline", "styles", "rounded", "minimal", "misc", "terminal" }

return M

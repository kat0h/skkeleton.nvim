-- 形式検証の PoC: これまで issue にした反例（再現のキー列）。main を取り込むたびに流し直して、
-- 直したバグが戻っていないかを確かめる（make verify ARGS=--regress）
return {
  { issue = 12, keys = { "#mid", "<C-j>", "A", "<Space>", "A", "<Left>", "<CR>" } },
  { issue = 13, keys = { "<C-j>", "Kan", "A", "A", "Kan", "<C-u>", "<CR>", "<Cmd>wincmd w<CR>", "k" } },
  { issue = 14, keys = { "#bol", "<C-j>", "Kan", "<Space>", "<Space><Space><Space><Space>", "k" } },
  { issue = 15, keys = { "#mid", "<C-j>", "K", "K", "<Cmd>wincmd w<CR>" } },
  { issue = 16, profile = "edge", keys = { "#right", "Kan" } },
  { issue = 17, profile = "misc", keys = { "#eol", "<C-r>=1<CR>" } },
  { issue = 18, profile = "misc", keys = { "#bol", "<C-x><C-n>" } },
  { issue = 19, profile = "misc", keys = { "#eol", "<C-j>", "Kan", "<C-n>", "R", "<C-e>" } },
  { issue = 20, profile = "misc", keys = { "#bol", "<C-j>", "O", "<C-r>=1<CR>" } },
  { issue = 21, profile = "wrap", keys = { "#wide", "<C-j>", "Kan" } },
  { issue = 23, profile = "blink", keys = { "#mid", "<Tab>", "<Esc>", "i" } },
  { issue = 24, profile = "blink", keys = { "Kanji", "<CR>", "Kan", "<C-j>" } },
  { issue = 26, profile = "edge", keys = { "#corner", "<Left>", "<C-j>", "Kan", "A", "<Esc>", "<Right>" } },
  { issue = 27, keys = { "#mid", "<C-c>" } },
  { issue = 27, keys = { "#mid", "<C-j>", "Kan", "<C-c>" } },
  { issue = 28, keys = { "#mid", "<Esc>", "v", "/", "<C-j>", "<Esc>", "c", "a", "K", "a", "n" } },
  { issue = 28, profile = "steal", keys = { "#mid", "<C-j>", "<ClickL2>", "/", "<ClickL2>" } },
  { issue = 29, profile = "steal", keys = { "#eol", "<C-j>", "Kan", "<Insert>", "a", "<Space>", "k" } },
  { issue = 30, profile = "steal", keys = { "#eol", "<C-x><C-e>" } },
  { issue = 32, profile = "steal", keys = { "#eol", "<C-j>", "<Esc>v", "<C-g>j", "a" } },
  { issue = 34, profile = "edge", keys = { "#corner", "<C-j>", "<BS>", "Kan", "A", "<Esc>", "<BS>" } },
  { issue = 35, profile = "options", keys = { "#list", "<C-j>", "n" } },
  {
    issue = 36,
    profile = "macro",
    keys = { "#mid", "qa", "A", "<C-j>", "K", "a", "n", "<Space>", "<CR>", "<Esc>", "q", "j", "@a" },
  },
  { issue = 38, profile = "steal", keys = { "#eol", "<C-j>", "<Insert>", "<Insert>", "a" } },
  { issue = 39, profile = "options", keys = { "#list", "<Right>" } },
  { issue = 44, keys = { "#mid", "<C-j>", "A", "A", "<Space>", "K", "a", "n", "<C-c>", "A", "A", "<Space>", "<Up>" } },
  { issue = 12, profile = "cmdline", keys = { "#cmd-on", "Kan", "<C-y>" } },
  { issue = 12, profile = "cmdline", keys = { "#cmd-on", "Kan", "<C-k>a:" } },
  { issue = 12, profile = "cmdline", keys = { "#cmd-on", "Kan", "<C-x>" } },
  { issue = 46, keys = { "#mid", "<Esc>", ":", "<C-j>", "K", "<Cmd>wincmd w<CR>", "<C-j>" } },
  { issue = 47, profile = "mouse", keys = { "#eol", "<ClickOtherWin>", "<DragRight>", "<ClickLine3>" } },
  { issue = 12, profile = "mouse", keys = { "#mid", "<Esc>", ":", "<C-j>", "Kan", "<RightClickMid>" } },
  { issue = 74, profile = "terminal", keys = { "#term", "<Plug>(skkeleton-toggle)", "K", "<C-\\><C-n>" } },
  { issue = 85, profile = "styles", keys = { "<Cmd>wincmd w<CR>", "<C-j>", "<Cmd>wincmd w<CR>" } },
  { issue = 86, profile = "misc", keys = { "<C-j>", "K", "<C-o>:<Esc>" } },
  { issue = 87, profile = "default", keys = { "<C-j>", "q", "<C-g>", "A", "q" } },
  { issue = 111, profile = "steal", keys = { "#eol", "<C-j>", "Kan", "<Insert>", "a", "<Space>", "k" } },
  {
    issue = 115,
    profile = "cmdline",
    keys = { "#cmd-on", "Kan", "<Space><Space><Space><Space>", "<Space>", "<Right>" },
  },
  { issue = 116, profile = "blink", keys = { "<C-j>", "Kan", "Kanji", "n", "<C-w>", "<C-g>" } },
  {
    issue = 117,
    profile = "misc",
    keys = { "<Esc>", "O", "<Esc>", "<C-n>", "<C-v>", "<C-g>", "<C-p>", "<C-j>", "a", "Kan", "<C-o>l" },
  },
  { issue = 121, profile = "unmapped", keys = { "#term", "Kan", "<C-S-a>" } },
  { issue = 125, profile = "paste", keys = { "#mid", "<C-j>", "Kan", "<Paste>" } },
  -- カーソルが確定した文字の後ろに来ない（#142）、辞書登録の間の外側の pre-edit（#144）、
  -- blink のメニューの位置（#143）
  { issue = 142, profile = "misc", keys = { "#mid", "<C-j>", "Kan", "<C-c>" } },
  { issue = 151, profile = "steal", keys = { "#eol", "<C-j>", "/", "<C-o>u" } },
  { issue = 154, profile = "default", keys = { "#mid", "<C-j>", "A", "Kan", "<C-c>", "<C-c>" } },
  {
    issue = 155,
    profile = "unmapped",
    config = {
      acceptIllegalResult = true,
      eggLikeNewline = false,
      immediatelyCancel = true,
      keepState = true,
      markerHenkanSelect = "▼",
    },
    keys = { "<M-a>" },
  },
  {
    issue = 152,
    profile = "steal",
    config = { keepState = true },
    keys = { "<C-j>", "<Esc>", ".", "<C-k>a:" },
  },
  { issue = 143, profile = "blink", keys = { "#eol", "<C-j>", "Kanji" } },
  { issue = 144, profile = "register", keys = { "#mid", "<C-j>", "A", "<Space>", "k" } },
  -- DB の置き場の .tmp（#138）。db_check は dict.lua の最後に 1 回だけ流す
  { issue = 138, checker = "dict", args = { "--random", "1", "--length", "2" } },
  -- 半角カタカナモードの ▽ で q: denops 版はひらがなで確定する（性質では見つからず、upstream.lua で見比べる）
  { issue = 51, keys = { "<C-j>", "<C-q>", "Te", "q" } },
  -- 辞書登録の欄の <C-f>（register プロファイル）
  { issue = 54, profile = "register", keys = { "#mid", "<C-j>", "A", "<Space>", "<C-f>" } },
  {
    issue = 55,
    profile = "register",
    config = { markerHenkan = "" },
    keys = { "#mid", "<C-j>", "Ka", "<Space>", "ka", "<CR>" },
  },
  -- 未マップの特殊キー（unmapped プロファイル）。▽ の途中で押すと、insert は打った読みが消え、cmdline は ▽ と読みが文字で残り、
  -- terminal は job に渡ったキーで pre-edit の位置がずれる。直ったら 3 つとも「△ 既知」が出なくなる
  { issue = 56, profile = "unmapped", keys = { "#mid", "<C-j>", "Kan", "<C-.>" } },
  { issue = 56, profile = "unmapped", keys = { "#cmd-on", "Kan", "<C-.>" } },
  { issue = 56, profile = "unmapped", keys = { "#term", "Kan", "<F5>" } },
  -- <M-a>（<Esc> と a が続いた入力）で insert に戻ると escape の状態が残る。#32 の残り
  { issue = 32, profile = "unmapped", keys = { "#mid", "<C-j>", "Kan", "<M-a>" } },
  -- core.lua・dict.lua の検査で見つかったもの。checker にスクリプトの名前、args に引数（シード固定）を書く。
  -- 開いている issue は「△ 既知 #N」が出れば未修正、閉じたあとにまた出たら失敗になる
  { issue = 49, checker = "core", args = { "--metamorphic", "300", "--seed", "1" } },
  { issue = 50, checker = "dict", args = { "--random", "2000", "--seed", "1" } },
  { issue = 53, checker = "dict", args = { "--random", "5000", "--seed", "2" } },
  -- jisyo.lua（辞書ファイルの読み込み）。#48 は同じ見出しが複数行ある辞書で、今は先の行だけが使われる
  { issue = 48, checker = "jisyo", args = { "--random", "4000", "--seed", "11" } },
}

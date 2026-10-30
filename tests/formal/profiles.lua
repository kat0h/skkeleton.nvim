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
  "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
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
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
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
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
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
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
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
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
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
    "<Plug>(skkeleton-toggle)",
    "k",
    "a",
    "n",
    "K",
    "<Space>",
    "<CR>",
    "<BS>",
    "<C-g>",
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
    "Kan",
    "<C-\\><C-n>",
    "i",
    "q",
  },
  inits = {
    -- cat だと端末の消去文字（^?）と skkeleton が流す BS（^H）が合わないので、^H を消去に使う bash にする
    ["#term"] = {
      lines = { "ab cd" },
      cursor = { 1, 2 },
      cmd = "terminal env PS1='$ ' bash --norc --noprofile",
      keys = "i",
    },
  },
  dict = dict,
}

-- blink.cmp の補完（利用者の設定と同じ: super-tab、preselect と auto_insert、fuzzy は lua）
local BLINK = vim.fn.expand("~/.local/share/nvim/lazy/blink.cmp")
M.blink = {
  doc = "blink.cmp の補完（super-tab、auto_insert）。blink.cmp が無ければ使えない",
  available = vim.uv.fs_stat(BLINK) ~= nil,
  config = {},
  setup = ([[
    vim.opt.rtp:append(%q)
    vim.cmd("runtime plugin/blink-cmp.lua")
    require("blink.cmp").setup({
      keymap = { preset = "super-tab", ["<Space>"] = {} },
      completion = { list = { selection = { preselect = true, auto_insert = true } } },
      sources = {
        default = function()
          if require("skkeleton").is_enabled() then
            return { "skkeleton" }
          end
          return { "buffer" }
        end,
        providers = { skkeleton = { name = "skkeleton", module = "skkeleton.completion.blink" } },
      },
      fuzzy = { implementation = "lua" },
    })
  ]]):format(BLINK),
  wait_ms = 60,
  alphabet = {
    "<C-j>",
    "Kan",
    "Kanj",
    "Kanji",
    "K",
    "a",
    "n",
    "j",
    "i",
    "<Tab>",
    "<S-Tab>",
    "<C-n>",
    "<C-p>",
    "<CR>",
    "<C-e>",
    "<Space>",
    "<BS>",
    "<C-g>",
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
    "<Esc>",
    "<Left>",
    "<C-w>",
  },
  inits = line_inits,
  dict = dict,
}

-- 折り返しのある長い行（'wrap'）。pre-edit が折り返しをまたぐところ
M.wrap = {
  doc = "折り返しのある長い行で、pre-edit・インジケータ・popup が折り返しをまたぐ",
  config = { showCandidatesCount = 1 },
  alphabet = {
    "<C-j>",
    "Kan",
    "Kanji",
    "<Space>",
    "x",
    "<CR>",
    "<BS>",
    "<C-g>",
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
    "<Esc>",
    "A",
    "a",
    "<Left>",
    "<Right>",
    "<C-u>",
    "<Up>",
    "<Down>",
  },
  inits = {
    -- 80 桁の画面で、1 行目が 2 行に折り返す。カーソルは 1 段目の右端の手前と、2 段目
    ["#wrap1"] = { lines = { ("w"):rep(100), "next" }, cursor = { 1, 76 }, keys = "i" },
    ["#wrap2"] = { lines = { ("w"):rep(100), "next" }, cursor = { 1, 99 }, keys = "a" },
    ["#wide"] = { lines = { ("全"):rep(39) .. "x", "next" }, cursor = { 1, 117 }, keys = "a" },
  },
  dict = dict,
}

-- 送り仮名・数値変換・接頭辞と接尾辞・abbrev の変換
M.okuri = {
  doc = "送り仮名（Kaer、WaruK）・数値変換（Q1ba）・abbrev 変換・確定の取り消しまわり",
  config = {},
  alphabet = {
    "<C-j>",
    "Kaer",
    "WaruK",
    "E",
    "u",
    "Q",
    "1",
    "bai",
    "#",
    "/abc",
    "<Space>",
    "x",
    "X",
    "<CR>",
    "<BS>",
    "<C-g>",
    "<C-c>", -- insert・cmdline・辞書登録を <C-c> で抜ける（InsertLeave が来ない）
    "<Esc>",
    ">",
    "<Left>",
  },
  inits = line_inits,
  dict = dict,
}

-- Vim の使い方で、モード・カーソル・ウィンドウがいつもと違う経路で変わるもの。
-- 特に、キーを押していないのに、タイマーやプラグインがカーソルを奪うもの（LSP の hover、:checktime など）
-- 別名: キー列に短い名前で書ける操作（--keys は "," で区切るので、"," を含む操作に名前を付ける）
M.aliases = {
  ["<ClickL2>"] = "<Cmd>lua vim.api.nvim_input_mouse('left', 'press', '', 0, 1, 0) vim.api.nvim_input_mouse('left', 'release', '', 0, 1, 0)<CR>",
  ["<WheelDown>"] = "<Cmd>lua vim.api.nvim_input_mouse('wheel', 'down', '', 0, 0, 0)<CR>",
  ["<StealCursor>"] = "<Cmd>lua vim.defer_fn(function() pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 }) end, 15)<CR>",
  ["<StealLine>"] = "<Cmd>lua vim.defer_fn(function() vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'ext' }) end, 15)<CR>",
  ["<StealWin>"] = "<Cmd>lua vim.defer_fn(function() vim.cmd('wincmd w') end, 15)<CR>",
  ["<StealFloat>"] = "<Cmd>lua vim.defer_fn(function() local b = vim.api.nvim_create_buf(false, true) "
    .. "vim.bo[b].bufhidden = 'wipe' vim.api.nvim_open_win(b, true, { relative = 'editor', row = 3, col = 3, width = 10, height = 2 }) end, 15)<CR>",
  ["<CloseFloats>"] = "<Cmd>lua for _, w in ipairs(vim.api.nvim_list_wins()) do local c = vim.api.nvim_win_get_config(w) "
    .. "if c.focusable and c.relative ~= '' then pcall(vim.api.nvim_win_close, w, true) end end<CR>",
  ["<Cols50>"] = "<Cmd>set columns=50<CR>",
  ["<Cols80>"] = "<Cmd>set columns=80<CR>",
}

-- 別名を実際のキーにする
function M.expand(key)
  return M.aliases[key] or key
end

local function later(code)
  -- 少し遅れて起きる（落ち着くのを待つあいだに起きるように、wait_ms より短くする）
  return ("<Cmd>lua vim.defer_fn(function() %s end, 15)<CR>"):format(code)
end
M.steal = {
  doc = "抜け方・insert の中の移動・タイマーでカーソルやウィンドウを奪う・マウス・画面の幅",
  config = {},
  wait_ms = 60,
  alphabet = {
    "<C-j>",
    "Kan",
    "k",
    "a",
    "<Space>",
    "<CR>",
    "<C-g>",
    "<Esc>",
    "i",
    -- insert の抜け方
    "<C-[>",
    "<C-\\><C-n>",
    "<C-o>u",
    "<C-o><C-^>",
    "<Insert>",
    -- insert の中での移動と編集
    "<C-g>j",
    "<C-x><C-e>",
    "<C-e>",
    "<C-y>",
    "<C-t>",
    "<C-d>",
    "<C-a>",
    "<C-k>a:",
    "<Home>",
    "<End>",
    "<S-Left>",
    "<Up>",
    "<Down>",
    "<PageDown>",
    -- normal から: 前回の入力を繰り返す、visual を通って cmdline や insert へ
    ".",
    "<C-c>",
    "<Esc>v",
    "/",
    ":",
    "c",
    "<FocusLost>",
    "<FocusGained>",
    -- タイマーで奪う・マウス・画面の幅（別名。M.aliases を参照）
    "<StealCursor>",
    "<StealLine>",
    "<StealWin>",
    "<StealFloat>",
    "<CloseFloats>",
    "<ClickL2>",
    "<WheelDown>",
    "<Cols50>",
    "<Cols80>",
  },
  inits = {
    ["#mid"] = { lines = { "ab cd", "ef gh", "ij" }, cursor = { 1, 2 }, keys = "i" },
    ["#eol"] = { lines = { "ab cd", "ef gh", "ij" }, cursor = { 2, 4 }, keys = "a" },
  },
  dict = dict,
}

-- 表示に関わる Neovim のオプションを変えたもの。初期状態ごとに違うオプションを入れる
local opt_line = { "ab cd" }
M.options = {
  doc = "number・signcolumn・cmdheight=0・nowrap・ambiwidth=double・list・virtualedit・laststatus=0",
  config = {},
  alphabet = base,
  inits = {
    ["#number"] = { lines = opt_line, cursor = { 1, 2 }, keys = "i", cmd = "set number signcolumn=yes:2 numberwidth=6" },
    ["#cmdh0"] = { lines = opt_line, cursor = { 1, 2 }, keys = "i", cmd = "set cmdheight=0 laststatus=0" },
    ["#nowrap"] = {
      lines = { ("n"):rep(90) },
      cursor = { 1, 85 },
      keys = "a",
      cmd = "set nowrap sidescroll=1 sidescrolloff=0",
    },
    ["#ambi"] = { lines = opt_line, cursor = { 1, 2 }, keys = "i", cmd = "set ambiwidth=double" },
    ["#list"] = {
      lines = { "a\tb  c " },
      cursor = { 1, 1 },
      keys = "i",
      cmd = "set list listchars=tab:>-,trail:~,eol:$ virtualedit=all",
    },
  },
  dict = dict,
}

-- マクロ（q で記録して @ で再生）と .（前回の入力を繰り返す）。記録したときと同じ結果になるか
M.macro = {
  doc = "マクロ（qa … q と @a）と . の繰り返しで、skkeleton の入力が同じ結果になるか",
  config = {},
  allow_q = true,
  alphabet = { "<C-j>", "Kan", "a", "k", "<Space>", "<CR>", "<Esc>", "qa", "q", "@a", ".", "j", "0", "A", "i", "<C-c>" },
  inits = {
    ["#mid"] = { lines = { "ab cd", "ef gh", "ij kl" }, cursor = { 1, 2 }, keys = "<Esc>" },
  },
  dict = dict,
}

-- undo と redo（upstream #41: 辞書登録で undo の区切りが切られていない）
M.undo = {
  doc = "undo（u）と redo（<C-r>）で、入力の途中の状態に戻らないか",
  config = {},
  alphabet = {
    "<C-j>",
    "Kan",
    "a",
    "k",
    "<Space>",
    "<CR>",
    "<BS>",
    "<C-g>",
    "<Esc>",
    "A",
    "i",
    "u",
    "<C-r>",
    "Kanji<Space>",
    "KaN",
    "<C-g>u",
  },
  inits = {
    ["#mid"] = { lines = { "ab cd", "ef" }, cursor = { 1, 2 }, keys = "i" },
  },
  dict = dict,
}

-- インジケータを切ったもの（ちらつきなどの原因がインジケータかを切り分けるため）
M.noindicator = {
  doc = "インジケータを切った既定の設定（原因の切り分け用）",
  config = { indicator = false },
  alphabet = base,
  inits = line_inits,
  dict = dict,
}

M.names = {
  "default",
  "modes",
  "config",
  "edge",
  "cmdline",
  "styles",
  "rounded",
  "minimal",
  "misc",
  "terminal",
  "blink",
  "wrap",
  "okuri",
}

return M

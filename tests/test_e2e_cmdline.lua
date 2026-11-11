-- cmdline と terminal では、BS で消して書き直す
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function enable_in_cmdline()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
end

T["hiragana"] = function()
  enable_in_cmdline()
  type("kana")
  eq(child.fn.getcmdline(), "かな")
  eq(helpers.mode(child), "hira")
end

-- <C-r>= で式を入れて戻ったとき、cmdline に marker と読みを残さない (#206)
T["<C-r>= leaves no marker in the cmdline"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<C-r>=1<CR>")
  -- marker と読みは消え、式の結果だけが残る
  eq(child.fn.getcmdline(), "1")
  eq((child.g["skkeleton#state"] or {}).preedit, "")
  -- 続けて打った文字が marker の後ろに残らない
  type("a")
  eq(child.fn.getcmdline(), "1あ")
  child.type_keys("<Esc>")
  child.lua([[vim.wait(100)]])
end

-- 式入力の中でもかな変換すると、外側の読みの末尾が cmdline に残っていた (#206)
T["<C-r>= with conversion inside the expression"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<C-r>=")
  type("'Ka<C-j>'")
  eq(child.fn.getcmdline(), "'か'")
  eq(child.fn.getcmdtype(), "=")
  type("<CR>")
  -- 外側の読み（▽かn）は残らず、式の結果だけが入る
  eq(child.fn.getcmdline(), "か")
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

-- 式入力の中で候補の無い読みで <Space> を押しても、式が壊れない (#244)
T["<Space> in the expression prompt without a candidate"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<C-r>=")
  type("Ka")
  eq(child.fn.getcmdline(), "▽か")
  type("<Space>")
  -- 辞書登録のプロンプト（@）に移らず、読みが式に入る
  eq(child.fn.getcmdtype(), "=")
  eq(child.fn.getcmdline(), "か")
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

-- 式入力の中で候補の無い読みを確定するとき、送り仮名も残す (#244)
T["<Space> in the expression prompt keeps the okurigana"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<C-r>=")
  type("KaKu")
  -- 送り仮名の自動変換で候補が尽きる。読み全体を式に残す
  eq(child.fn.getcmdtype(), "=")
  eq(child.fn.getcmdline(), "かく")
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

-- 式を取り消して外側に戻ったとき、外側の読みが生きている (#246)
T["cancelling the expression keeps the outer reading live"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<C-r>=")
  type("'Ka<C-j>'")
  eq(child.fn.getcmdline(), "'か'")
  -- 式を取り消すと外側に戻る。読みはただの文字ではなく、生きている
  type("<C-c>")
  eq(child.fn.getcmdtype(), ":")
  eq(child.fn.getcmdline(), "▽かn")
  -- 打ちかけのローマ字 n も状態に戻る
  eq((child.g["skkeleton#state"] or {}).preedit, "▽かn")
  -- 続けて打った a は n とつながる
  type("a")
  eq(child.fn.getcmdline(), "▽かな")
  eq((child.g["skkeleton#state"] or {}).preedit, "▽かな")
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

-- 式を取り消したあと、送り仮名・候補の状態も戻る (#246)
T["cancelling the expression restores the okuri state"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("KaeR")
  eq(child.fn.getcmdline(), "▽かえ*r")
  type("<C-r>=")
  type("'Ka<C-j>'")
  type("<C-c>")
  eq(child.fn.getcmdline(), "▽かえ*r")
  eq((child.g["skkeleton#state"] or {}).phase, "input:okuriari")
  -- 送り仮名の続きを打てる
  type("u")
  eq(child.fn.getcmdline(), "▼帰る")
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

-- 式を取り消したあと、候補選択の状態も戻る (#246)
T["cancelling the expression restores the henkan state"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("KaeRu<Space>")
  eq(child.fn.getcmdline(), "▼返る")
  type("<C-r>=")
  type("'Ka<C-j>'")
  type("<C-c>")
  eq(child.fn.getcmdline(), "▼返る")
  eq((child.g["skkeleton#state"] or {}).phase, "henkan")
  -- 候補を選んで確定できる
  type("<C-j>")
  eq(child.fn.getcmdline(), "返る")
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

-- 式を確定せずに取り消しても、外側の状態が式の中身で汚れない (#246)
T["cancelling the expression without converting keeps the outer state"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<C-r>=")
  -- 式の中で打つだけで、確定はしない
  type("'Ka'")
  eq(child.fn.getcmdline(), "'▽か'")
  type("<C-c>")
  eq(child.fn.getcmdline(), "▽かn")
  -- 式の中で打った「'」が外側の読みに混ざらない
  eq((child.g["skkeleton#state"] or {}).preedit, "▽かn")
  type("a")
  eq(child.fn.getcmdline(), "▽かな")
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

-- <C-f> で cmdwin を開くとき、cmdline に書いた pre-edit が cmdwin に引き継がれる (#205)
T["cmdwin keeps the pre-edit"] = function()
  child.type_keys(":")
  type("abc")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "abc▽かn")
  type("<C-f>")
  eq(child.fn.getcmdwintype(), ":")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "abc▽かn" })
  -- cmdwin を閉じて、cmdline に戻る
  child.type_keys("<C-c>")
  child.lua([[vim.wait(100)]])
end

T["pre-edit is written in the command line"] = function()
  enable_in_cmdline()
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<Space>")
  eq(child.fn.getcmdline(), "▼缶")
  type("<C-j>")
  eq(child.fn.getcmdline(), "缶")
end

T["okuri-ari"] = function()
  enable_in_cmdline()
  type("KaeRu")
  eq(child.fn.getcmdline(), "▼帰る")
  type("<C-j>")
  eq(child.fn.getcmdline(), "帰る")
end

T["the text in front of the cursor is kept"] = function()
  child.type_keys(":", "abc")
  type("<Plug>(skkeleton-enable)")
  type("Ka")
  eq(child.fn.getcmdline(), "abc▽か")
  type("<C-g>")
  eq(child.fn.getcmdline(), "abc")
end

T["candidate popup is shown above the command line"] = function()
  enable_in_cmdline()
  type("Kan<Space><Space><Space><Space><Space>")
  eq(child.fn.getcmdline(), "▼管")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
  type("a")
  eq(child.fn.getcmdline(), "管")
  eq(helpers.popup(child), vim.NIL)
end

T["an unmapped special key that commits closes the candidate popup (#115)"] = function()
  enable_in_cmdline()
  type("Kan<Space><Space><Space><Space><Space>")
  eq(helpers.popup(child) ~= nil, true)
  type("<Right>")
  eq(child.fn.getcmdline(), "管")
  eq(helpers.popup(child), vim.NIL)
end

T["a command typed with skkeleton runs"] = function()
  enable_in_cmdline()
  type("<Plug>(skkeleton-disable)")
  type("let g:x = '")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space><C-j>")
  type("<Plug>(skkeleton-disable)")
  type("'<CR>")
  eq(child.g.x, "缶")
end

T["<CR> confirms and runs the command line"] = function()
  child.type_keys(":")
  -- " 以降はコメントなので、確定した文字に改行が続いて実行される
  type([[let g:y = 1 "]])
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space>")
  eq(child.fn.getcmdline(), [[let g:y = 1 "▼缶]])
  type("<CR>")
  eq(child.fn.mode(), "n")
  eq(child.g.y, 1)
end

T["<Esc> leaves the command line"] = function()
  enable_in_cmdline()
  type("Ka")
  type("<Esc>")
  eq(child.fn.mode(), "n")
  eq(child.g["skkeleton#enabled"], false)
end

T["the pre-edit is dropped when the command line is edited behind skkeleton"] = function()
  enable_in_cmdline()
  type("Ka")
  eq(child.fn.getcmdline(), "▽か")
  -- skkeleton を通らない編集（<C-u>）
  child.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-u>", true, true, true), "nt", false)
  helpers.settle(child)
  eq(child.fn.getcmdline(), "")
  type("ka")
  eq(child.fn.getcmdline(), "か")
end

T["the pre-edit is dropped when <C-y> is typed behind skkeleton (#12)"] = function()
  enable_in_cmdline()
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  child.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, true, true), "nt", false)
  helpers.settle(child)
  local line = child.fn.getcmdline()
  eq(line:find("▽", 1, true), nil)
end

T["the pre-edit is dropped when digraph <C-k>a: is typed behind skkeleton (#12)"] = function()
  enable_in_cmdline()
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  child.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-k>a:", true, true, true), "nt", false)
  helpers.settle(child)
  eq(child.fn.getcmdline(), "ä")
end

T["terminal"] = function()
  child.cmd("terminal cat")
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  eq(child.g["skkeleton#enabled"], true)
  type("Kan<Space><C-j>")
  type("<CR>")
  -- cat が書き戻した行が端末のバッファに出る
  local found = child.lua_get([[(function()
    vim.wait(2000, function()
      return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("缶", 1, true) ~= nil
    end, 20)
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("缶", 1, true) ~= nil
  end)()]])
  eq(found, true)
end

T["terminal-normal に移っても状態を捨てず、戻ると続きから打てる (#74)"] = function()
  child.cmd("terminal cat")
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("K")
  child.type_keys([[<C-\><C-n>]])
  helpers.settle(child)
  eq(child.api.nvim_get_mode().mode, "nt")
  eq(child.g["skkeleton#enabled"], true)
  child.type_keys("i")
  type("a")
  -- 端末の行は、残っていた ▽k の続きとして ▽か に書き直される（BS で消して書き直す）
  local line = child.lua_get([[(function()
    local function last()
      local ls = vim.tbl_filter(function(l) return l ~= "" end, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      return ls[#ls] or ""
    end
    vim.wait(2000, function() return last():find("▽か", 1, true) ~= nil end, 20)
    return last()
  end)()]])
  -- cat は BS を ^H と表示するので、行の終わりと状態で確かめる
  eq(vim.endswith(line, "▽か"), true)
  eq(child.g["skkeleton#state"].henkanFeed, "か")
end

T["visual から入った cmdline で有効にして抜けると無効になる (#28)"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
  child.type_keys("v/")
  type("<Plug>(skkeleton-enable)")
  eq(child.g["skkeleton#enabled"], true)
  child.type_keys("<Esc>")
  helpers.settle(child)
  eq(child.fn.mode(), "v")
  eq(child.g["skkeleton#enabled"], false)
  eq(child.g["skkeleton#state"].phase, "input")
end

T["<C-c> does not leave markers in command line history (#44)"] = function()
  enable_in_cmdline()
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  child.type_keys("<C-c>")
  helpers.settle(child)
  local hist = child.fn.histget("cmd", -1)
  eq(hist:find("▽", 1, true), nil)
  eq(hist:find("▼", 1, true), nil)
end

T["pasting in front of the pre-edit keeps the pasted text and drops the marker (#12)"] = function()
  enable_in_cmdline()
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  -- 中クリックの貼り付けを模す（▽ の直後に文字が入り、読みはそのあとに残る）
  child.lua([[vim.fn.setcmdline("▽PASTEDかn", 14)]])
  helpers.settle(child)
  eq(child.fn.getcmdline(), "PASTED")
  -- 状態も初期化されている
  type("ka")
  eq(child.fn.getcmdline(), "PASTEDか")
end

T["pasting in front of a candidate keeps the pasted text and drops the marker (#12)"] = function()
  enable_in_cmdline()
  type("Kan<Space>")
  eq(child.fn.getcmdline(), "▼缶")
  child.lua([[vim.fn.setcmdline("▼PASTED缶", 13)]])
  helpers.settle(child)
  eq(child.fn.getcmdline(), "PASTED")
end

T["pasting inside the pre-edit keeps the text in front of it (#12)"] = function()
  child.type_keys(":", "abc")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "abc▽かn")
  child.lua([[vim.fn.setcmdline("abc▽PASTEDかn", 17)]])
  helpers.settle(child)
  eq(child.fn.getcmdline(), "abcPASTED")
end

T["switching window during cmdline removes pre-edit from cmdline (#46)"] = function()
  child.cmd("botright new")
  child.cmd("wincmd p")
  enable_in_cmdline()
  type("K")
  eq(child.fn.getcmdline(), "▽k")
  child.type_keys("<Cmd>wincmd w<CR>")
  helpers.settle(child)
  eq(child.fn.getcmdline(), "")
  eq(child.g["skkeleton#enabled"], false)
end

return T

-- 候補の popup、辞書登録、候補の削除
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function enable()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
end

T["popup"] = MiniTest.new_set()

T["popup"]["is not shown for the first candidates"] = function()
  enable()
  type("Kan<Space><Space><Space><Space>")
  eq(helpers.preedit(child), "▼幹")
  eq(helpers.popup(child), vim.NIL)
end

T["popup"]["is shown from the fifth candidate"] = function()
  enable()
  type("Kan<Space><Space><Space><Space><Space>")
  eq(helpers.preedit(child), "▼管")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
end

T["popup"]["is closed by the next key"] = function()
  enable()
  type("Kan<Space><Space><Space><Space><Space>")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
  type("x")
  eq(helpers.preedit(child), "▼幹")
  eq(helpers.popup(child), vim.NIL)
  type("<Space>")
  eq(helpers.preedit(child), "▼管")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
end

T["popup"]["the next page past the last candidate asks for a new word"] = function()
  enable()
  type("Kan<Space><Space><Space><Space><Space><Space>")
  eq(child.fn.mode(), "c")
  type("<Esc>")
  -- 取り消すと、最後の候補の表示に戻る
  eq(child.fn.mode(), "i")
  eq(helpers.preedit(child), "▼管")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
end

T["popup"]["a key selects a candidate"] = function()
  enable()
  type("Kan<Space><Space><Space><Space><Space>s")
  eq(helpers.buffer(child), { "館" })
  eq(helpers.preedit(child), "")
  eq(helpers.popup(child), vim.NIL)
end

T["popup"]["stays open when an out-of-range selection key is pressed"] = function()
  enable()
  type("Kan<Space><Space><Space><Space><Space>k")
  eq(helpers.preedit(child), "▼管")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
end

T["popup"]["is closed when disabled"] = function()
  enable()
  type("Kan<Space><Space><Space><Space><Space>")
  type("<Esc>")
  eq(helpers.buffer(child), { "管" })
  eq(helpers.popup(child), vim.NIL)
end

T["popup"]["stays inside the window near the bottom of the screen"] = function()
  child.o.lines = 8
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "", "", "", "", "" })
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  enable()
  type("Kan<Space><Space><Space><Space><Space>")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
end

T["popup"]["applies part-specific highlights, column alignment, and border footer"] = function()
  child.lua([[
    require("skkeleton.config").set({ popupBorder = "rounded" })
    local popup = require("skkeleton.popup")
    popup.set({ "a: 候補;短い注釈", "s: 長い候補語;注釈2" }, { index = 4, total = 12 })
    popup.open()
  ]])
  local info = child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[w].skkeleton_popup then
          local b = vim.api.nvim_win_get_buf(w)
          local ns = vim.api.nvim_get_namespaces()["skkeleton.popup"]
          local marks = vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })
          local cfg = vim.api.nvim_win_get_config(w)
          return { marks = marks, border = cfg.border, footer = cfg.footer }
        end
      end
    end)()
  ]])
  eq(info.border[1], "╭")
  eq(info.footer[1][1], " 5-6/12 ")
  eq(#info.marks, 6)
  eq(info.marks[1][4].hl_group, "SkkeletonPopupKey")
  eq(info.marks[2][4].hl_group, "SkkeletonPopupCandidate")
  eq(info.marks[3][4].hl_group, "SkkeletonPopupAnnotation")
  -- 1行目の「候補」は2行目の「長い候補語」より短いため、inline virt_text でパディングが入る
  eq(info.marks[3][4].virt_text_pos, "inline")
  child.lua([[require("skkeleton.popup").close()]])
end

local function user_dictionary()
  return child.lua_get(
    [[vim.fn.filereadable(_G.dir .. "/user") == 1 and table.concat(vim.fn.readfile(_G.dir .. "/user"), "\n") or ""]]
  )
end

T["register"] = MiniTest.new_set()

T["register"]["a new word is typed in the command line"] = function()
  enable()
  type("Yomi<Space>")
  eq(child.fn.mode(), "c")
  eq(child.fn.getcmdline(), "")
  eq(child.lua_get("vim.fn.getcmdprompt and 1 or 0"), 1)
  type("yomi")
  eq(child.fn.getcmdline(), "よみ")
  type("<CR>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "よみ" })
  eq(helpers.preedit(child), "")
  eq(child.g["skkeleton#enabled"], true)
  eq(helpers.mode(child), "hira")
  eq(user_dictionary():find("よみ /よみ/", 1, true) ~= nil, true)
  -- 登録した語は次から候補になる
  type("Yomi<Space>")
  eq(helpers.preedit(child), "▼よみ")
end

T["register"]["skkeleton works again after registering"] = function()
  enable()
  type("Yomi<Space>yomi<CR>")
  type("ka")
  eq(helpers.buffer(child), { "よみか" })
  type("Kan<Space><C-j>")
  eq(helpers.buffer(child), { "よみか缶" })
end

T["register"]["the okuri string is shown in the prompt"] = function()
  enable()
  type("YomiKu")
  eq(child.fn.mode(), "c")
  type("<Esc>")
end

T["register"]["the mode comes back"] = function()
  enable()
  type("q")
  eq(helpers.mode(child), "kata")
  type("Yomi<Space>yomi<CR>")
  -- 入力中は新しい Context なので、ひらがなで打つ
  eq(helpers.buffer(child), { "よみ" })
  eq(helpers.mode(child), "kata")
  type("ka")
  eq(helpers.buffer(child), { "よみカ" })
end

T["register"]["<Esc> cancels"] = function()
  enable()
  type("Yomi<Space><Esc>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "" })
  eq(child.g["skkeleton#enabled"], true)
  eq(user_dictionary():find("よみ", 1, true), nil)
end

T["register"]["<C-g> cancels"] = function()
  enable()
  type("Yomi<Space>y<C-g>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "" })
  eq(child.g["skkeleton#enabled"], true)
end

T["register"]["<C-c> cancels"] = function()
  enable()
  type("Yomi<Space>")
  type("y")
  child.type_keys("<C-c>")
  helpers.settle(child)
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "" })
  eq(child.g["skkeleton#enabled"], true)
  eq(user_dictionary():find("よみ", 1, true), nil)
end

T["register"]["<C-c> twice keeps the outer pre-edit (#154)"] = function()
  enable()
  type("A")
  type("Kan")
  eq(child.fn.mode(), "c")
  type("<C-c>")
  eq(child.fn.mode(), "i")
  eq(helpers.preedit(child), "▽あ*か")
  type("<C-c>")
  eq(child.fn.mode(), "n")
  eq(helpers.buffer(child), { "あか" })
  eq(helpers.preedit(child), "")
end

T["register"]["<C-g> after <C-w> cancels and keeps the outer reading (#116)"] = function()
  enable()
  -- 送り仮名の変換で候補が無いときの登録になる。欄で打った「んじ」と打ちかけの n が残る
  type("KanKanjin")
  eq(child.fn.mode(), "c")
  eq(child.fn.getcmdline(), "んじn")
  child.type_keys("<C-w>")
  helpers.settle(child)
  eq(child.fn.getcmdline(), "んじ")
  -- 取り消しの印をかな入力に通すと、n が食われて印が崩れ、語として登録される
  type("<C-g>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "" })
  eq(helpers.preedit(child), "▽かん*か")
  eq(child.g["skkeleton#enabled"], true)
  eq(user_dictionary(), "")
end

T["register"]["<Esc> after <C-w> cancels and keeps the outer reading (#116)"] = function()
  enable()
  type("KanKanjin")
  eq(child.fn.mode(), "c")
  eq(child.fn.getcmdline(), "んじn")
  child.type_keys("<C-w>")
  helpers.settle(child)
  eq(child.fn.getcmdline(), "んじ")
  type("<Esc>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "" })
  eq(helpers.preedit(child), "▽かん*か")
  eq(child.g["skkeleton#enabled"], true)
  eq(user_dictionary(), "")
end

T["register"]["an empty input cancels"] = function()
  enable()
  type("Yomi<Space><CR>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "" })
end

T["register"]["the internal mappings are not left behind"] = function()
  enable()
  type("Yomi<Space><Esc>")
  type("<Esc>")
  eq(child.lua_get([[vim.fn.maparg("<Esc>", "c", false, true).buffer ]]), vim.NIL)
  eq(child.lua_get([[vim.fn.maparg("<C-g>", "c", false, true).buffer ]]), vim.NIL)
  eq(child.lua_get([[#vim.api.nvim_buf_get_keymap(0, "c") ]]), 0)
end

T["register"]["the cursor stays at the end of a line"] = function()
  enable()
  type("Yomi<Space>yomi<CR>")
  eq(helpers.cursor(child), { 1, 6 })
end

T["register"]["the cursor stays at the end of a line when cancelled with <Esc> or <C-g>"] = function()
  enable()
  type("aiu")
  eq(helpers.buffer(child), { "あいう" })
  eq(helpers.cursor(child), { 1, 9 })
  type("Yomi<Space><Esc>")
  eq(helpers.cursor(child), { 1, 9 })
  eq(helpers.preedit(child), "▽よみ")
  type("<Space><C-g>")
  eq(helpers.cursor(child), { 1, 9 })
  eq(helpers.preedit(child), "▽よみ")
end

T["register"]["moving the cursor in the registration prompt commits the reading first (#56)"] = function()
  enable()
  type("A<Space>A")
  eq(child.fn.mode(), "c")
  eq(child.fn.getcmdline(), "▽あ")
  -- <Left> は pre-edit を確定してからカーソルを動かす (#56)
  child.type_keys("<Left>")
  helpers.settle(child)
  eq(child.fn.getcmdline(), "あ")
  type("<CR>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "あ" })
  eq(helpers.preedit(child), "")
  eq(user_dictionary():find("▽", 1, true), nil)
  eq(user_dictionary():find("あ /あ/", 1, true) ~= nil, true)
end

T["register"]["deleting with <C-w> in the registration prompt drops the pre-edit (#12)"] = function()
  enable()
  type("A<Space>Kan")
  eq(child.fn.getcmdline(), "▽かn")
  child.type_keys("<C-w>")
  helpers.settle(child)
  eq(child.fn.getcmdline(), "")
  type("<CR>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "" })
  eq(helpers.preedit(child), "▽あ")
end

T["register"]["digraph in the registration prompt drops the pre-edit (#12)"] = function()
  enable()
  type("A<Space>Kan")
  eq(child.fn.getcmdline(), "▽かn")
  child.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-k>a:", true, true, true), "nt", false)
  helpers.settle(child)
  eq(child.fn.getcmdline(), "ä")
  type("<CR>")
  eq(child.fn.mode(), "i")
  eq(user_dictionary():find("▽", 1, true), nil)
end

T["register"]["switching windows during input() does not break state or mappings"] = function()
  child.cmd("botright new")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "xy" })
  child.cmd("wincmd p")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  enable()
  type("AA")
  eq(child.fn.mode(), "c")
  child.type_keys("<Cmd>wincmd w<CR>")
  helpers.settle(child)
  type("<Esc>")
  eq(child.fn.mode(), "i")
  eq(helpers.buffer(child), { "ab cd" })
  eq(helpers.cursor(child), { 1, 2 })
  eq(helpers.preedit(child), "▽あ*あ")
end

T["register"]["switching windows after a cancelled nested registration keeps the window"] = function()
  child.cmd("botright new")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "xy" })
  child.cmd("wincmd p")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
  enable()
  -- 外側の登録の欄で、入れ子の登録に入って取り消す
  type("KanA")
  eq(child.fn.mode(), "c")
  type("AKan")
  child.type_keys("<C-u><CR>")
  helpers.settle(child)
  eq(child.fn.getcmdline(), "▽あ*か")
  child.type_keys("<Cmd>wincmd w<CR>")
  helpers.settle(child)
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "ab cd" })
  type("k")
  eq(child.fn.getcmdline(), "▽あ*かk")
  type("<Esc>")
  type("<Esc>")
end

T["register"]["cancelling input does not leave markers in input history (#44)"] = function()
  enable()
  type("Yomi<Space>")
  eq(child.fn.mode(), "c")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  child.type_keys("<C-c>")
  helpers.settle(child)
  eq(child.fn.mode(), "i")

  local hist = child.fn.histget("@", -1)
  eq(hist:find("▽", 1, true), nil)
  eq(hist:find("▼", 1, true), nil)
  eq(hist:find("__skkeleton_return__", 1, true), nil)

  type("<Space>")
  eq(child.fn.mode(), "c")
  child.type_keys("<Up>")
  helpers.settle(child)
  eq(child.fn.getcmdline():find("▽", 1, true), nil)
  eq(child.fn.getcmdline():find("▼", 1, true), nil)
  child.type_keys("<Esc>")
  helpers.settle(child)

  type("<Space>")
  eq(child.fn.mode(), "c")
  child.type_keys("<Esc>")
  helpers.settle(child)
  local hist_esc = child.fn.histget("@", -1)
  eq(hist_esc:find("__skkeleton_return__", 1, true), nil)

  type("<Space>")
  eq(child.fn.mode(), "c")
  child.type_keys("<C-g>")
  helpers.settle(child)
  local hist_cg = child.fn.histget("@", -1)
  eq(hist_cg:find("__skkeleton_return__", 1, true), nil)
end

T["register"]["changing markers keeps them out of cmdline and input history (#94)"] = function()
  child.lua([[require("skkeleton.config").set({ markerHenkan = "▲", markerHenkanSelect = "△" })]])
  -- cmdline の履歴の掃除も、固定の ▽ ▼ ではなく設定したマーカーを見る
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  child.lua([[vim.fn.histadd("cmd", "▲かn")]])
  child.type_keys("<C-c>")
  helpers.settle(child)
  eq(child.fn.histget("cmd", -1):find("▲", 1, true), nil)

  -- 辞書登録の欄で、マーカーの付いた行を受け取っても履歴に残さない
  enable()
  type("Yomi<Space>")
  eq(child.fn.mode(), "c")
  type("Kan")
  eq(child.fn.getcmdline(), "▲かn")
  child.type_keys("<CR>")
  helpers.settle(child)
  eq(child.fn.histget("@", -1):find("▲", 1, true), nil)
end

T["purge"] = MiniTest.new_set()

T["purge"]["X removes the candidate after confirming"] = function()
  child.lua([[require("skkeleton.host").confirm = function(msg)
    _G.confirm_msg = msg
    return true
  end]])
  enable()
  type("Yomi<Space>yomi<CR>")
  type("Yomi<Space>X")
  eq(child.lua_get("_G.confirm_msg"), "Really purge? よみ /よみ/")
  eq(helpers.preedit(child), "")
  type("Yomi<Space>")
  -- 辞書に候補が無くなり、辞書登録になる
  eq(child.fn.mode(), "c")
  type("<Esc>")
end

T["purge"]["answering no keeps the candidate"] = function()
  child.lua([[require("skkeleton.host").confirm = function() return false end]])
  enable()
  type("Nihon<Space>X")
  eq(helpers.preedit(child), "▼日本")
end

T["purge"]["host.confirm asks with vim.fn.confirm"] = function()
  child.lua([[
    vim.fn.confirm = function(msg, choices, default)
      _G.asked = { msg, choices, default }
      return 1
    end
  ]])
  eq(child.lua_get([[require("skkeleton.host").confirm("hello") ]]), true)
  eq(child.lua_get("_G.asked"), { "hello", "&Yes\n&No\n", 2 })
end

T["candidate with semicolon in concat expression does not split prematurely (#49)"] = function()
  child.lua([=[
    local store = require("skkeleton.store")
    local u = store.library().user_dict
    u.maps.okurinasi["てす"] = { "a\\073b;注釈" }
  ]=])
  enable()
  type("Tesu<Space>")
  eq(helpers.preedit(child), "▼a;b")
  type("<C-j>")
  eq(helpers.buffer(child), { "a;b" })
  child.lua([[require("skkeleton").save_user_dict()]])
  local content = user_dictionary()
  eq(content:find('(concat "a\\073b");注釈', 1, true) ~= nil, true)
end

local can_cmdwin_from_input
local function supports_cmdwin_from_input()
  if can_cmdwin_from_input ~= nil then
    return can_cmdwin_from_input
  end
  child.type_keys(":call input('x')<CR>")
  child.type_keys("<C-f>")
  helpers.settle(child)
  can_cmdwin_from_input = child.fn.getcmdwintype() == "@"
  if can_cmdwin_from_input then
    child.type_keys("<C-c>")
    helpers.settle(child)
  end
  child.type_keys("<C-c>")
  helpers.settle(child)
  return can_cmdwin_from_input
end

T["C-f in dictionary input opens cmdline window without cancelling (#54)"] = function()
  if not supports_cmdwin_from_input() then
    MiniTest.skip("this Neovim cannot open cmdwin from input()")
  end
  enable()
  type("A<Space>")
  eq(child.fn.mode(), "c")
  child.type_keys("<C-f>")
  helpers.settle(child)
  eq(child.fn.getcmdwintype(), "@")
  eq(child.fn.mode(), "n")
  type("ikouho<CR>")
  helpers.settle(child)
  eq(helpers.buffer(child), { "kouho" })
  eq(#child.api.nvim_tabpage_list_wins(0), 1)
end

T["dictionary input clears the state variable and keeps the outer pre-edit (#54, #144)"] = function()
  enable()
  type("A")
  eq(helpers.preedit(child), "▽あ")
  type("<Space>")
  eq(child.fn.mode(), "c")
  -- 登録の Context は新しく作られるので、参照用の変数もその状態に合わせる
  eq(child.g["skkeleton#state"].henkanFeed, "")
  -- 登録の間も、外側の pre-edit はそのまま見える (#144)
  eq(helpers.preedit(child), "▽あ")
  child.type_keys("<Esc>")
  helpers.settle(child)
  eq(helpers.preedit(child), "▽あ")
end

T["register"]["the last candidate stays visible while registering (#144)"] = function()
  enable()
  type("Kan" .. ("<Space>"):rep(6))
  eq(child.fn.mode(), "c")
  eq(helpers.preedit(child), "▼管")
  child.type_keys("<Esc>")
  helpers.settle(child)
  eq(helpers.preedit(child), "▼管")
end

T["C-f in dictionary input keeps cmdline mode when cmdwin cannot open (#54)"] = function()
  if supports_cmdwin_from_input() then
    MiniTest.skip("this Neovim can open cmdwin from input()")
  end
  enable()
  type("A<Space>")
  eq(child.fn.mode(), "c")
  child.type_keys("<C-f>")
  helpers.settle(child)
  eq(child.fn.mode(), "c")
  type("kouho<CR>")
  helpers.settle(child)
  eq(helpers.buffer(child), { "こうほ" })
end

T["registers word when markerHenkan is empty string (#55)"] = function()
  child.lua([[require("skkeleton.config").set({ markerHenkan = "", markerHenkanSelect = "" })]])
  enable()
  type("Ka<Space>")
  type("ka<CR>")
  helpers.settle(child)
  eq(helpers.buffer(child), { "か" })
  local content = user_dictionary()
  eq(content:find("か /か/", 1, true) ~= nil, true)
end

return T

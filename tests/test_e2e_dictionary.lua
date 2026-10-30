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

return T

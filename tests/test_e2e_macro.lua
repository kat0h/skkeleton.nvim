-- skkeleton のマクロ記録・再生（qa ... q, @a）およびドットリピート（.）のテスト (#36)
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

T["macro recording and replay with skkeleton"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "first line: ", "second line: " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("qa")
  type("A")
  type("<Plug>(skkeleton-enable)")
  type("kan<C-j><Esc>")
  type("q")

  -- 確定文字列や FINISH_CMD がレジスタに混入していないことを確認
  local reg_a = child.fn.getreg("a")
  eq(reg_a:find("かん", 1, true), nil)
  eq(reg_a:find("finish", 1, true), nil)
  eq(helpers.buffer(child), { "first line: かん", "second line: " })

  type("j0")
  type("@a")

  eq(helpers.buffer(child), { "first line: かん", "second line: かん" })
end

T["macro recording and replay with henkan"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "1: ", "2: " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("qa")
  type("A")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space><C-j><Esc>")
  type("q")

  local reg_a = child.fn.getreg("a")
  eq(reg_a:find("缶", 1, true), nil)
  eq(reg_a:find("finish", 1, true), nil)
  eq(helpers.buffer(child), { "1: 缶", "2: " })

  type("j0")
  type("@a")

  eq(helpers.buffer(child), { "1: 缶", "2: 缶" })
end

T["macro recording and replay with okuriari henkan"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "1: ", "2: " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("qa")
  type("A")
  type("<Plug>(skkeleton-enable)")
  type("KaeRu<C-j><Esc>")
  type("q")

  local reg_a = child.fn.getreg("a")
  eq(reg_a:find("帰る", 1, true), nil)
  eq(reg_a:find("finish", 1, true), nil)
  eq(helpers.buffer(child), { "1: 帰る", "2: " })

  type("j0")
  type("@a")

  eq(helpers.buffer(child), { "1: 帰る", "2: 帰る" })
end

T["macro recording and replay with complex input"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1: ", "line 2: " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("qa")
  type("A")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space><CR>nippon<C-j><Esc>")
  type("q")

  eq(helpers.buffer(child), { "line 1: 缶", "にっぽん", "line 2: " })

  type("3G0")
  type("@a")

  eq(helpers.buffer(child), { "line 1: 缶", "にっぽん", "line 2: 缶", "にっぽん" })
end

T["macro replay with count"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "line: ", "", "", "" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("qa")
  type("A")
  type("<Plug>(skkeleton-enable)")
  type("kan<C-j><Esc>")
  type("j0")
  type("q")

  eq(helpers.buffer(child), { "line: かん", "", "", "" })

  type("3@a")

  eq(helpers.buffer(child), { "line: かん", "かん", "かん", "かん" })
end

T["dot repeat with skkeleton"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "first line: ", "second line: " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("A")
  type("<Plug>(skkeleton-enable)")
  type("kan<C-j><Esc>")

  eq(helpers.buffer(child), { "first line: かん", "second line: " })

  type("j0")
  type(".")

  eq(helpers.buffer(child), { "first line: かん", "second line: かん" })
end

T["dot repeat with skkeleton henkan"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "first line: ", "second line: " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("A")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space><C-j><Esc>")

  eq(helpers.buffer(child), { "first line: 缶", "second line: " })

  type("j0")
  type(".")

  eq(helpers.buffer(child), { "first line: 缶", "second line: 缶" })
end

T["dot repeat with okuriari henkan"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "1: ", "2: ", "3: " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("A")
  type("<Plug>(skkeleton-enable)")
  type("KaeRu<C-j><Esc>")

  eq(helpers.buffer(child), { "1: 帰る", "2: ", "3: " })

  type("j0.")
  eq(helpers.buffer(child), { "1: 帰る", "2: 帰る", "3: " })

  type("j0.")
  eq(helpers.buffer(child), { "1: 帰る", "2: 帰る", "3: 帰る" })
end

T["undo point (<C-g>u) works with feedkeys ni"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  type("i")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space><C-j>")
  type("Kan<Space><Space><C-j>")
  type("<Esc>")

  eq(helpers.buffer(child), { "缶感" })

  -- undo すると 2 回目の確定分 "感" だけが消える（setUndoPoint = true のため）
  type("u")
  eq(helpers.buffer(child), { "缶" })

  type("u")
  eq(helpers.buffer(child), { "" })
end

return T

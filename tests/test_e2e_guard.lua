-- 未マップの特殊キーが来たら、pre-edit を <Esc> と同じ形で確定してからキーを動かす (#56)
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function start()
  type("i<Plug>(skkeleton-enable)")
end

T["unmapped special keys commit the pre-edit before acting (#56)"] = function()
  start()
  type("Kan")
  eq(helpers.preedit(child), "▽かn")

  -- <Left> で読みが確定し、そのあとカーソルが 1 文字左へ動く
  type("<Left>")
  eq(helpers.buffer(child), { "かん" })
  eq(helpers.preedit(child), "")
  eq(helpers.cursor(child), { 1, 3 })
end

T["<C-.> commits the pre-edit and then inserts the key (#56)"] = function()
  start()
  type("Kan")
  type("<C-.>")
  eq(helpers.buffer(child), { "かん." })
  eq(helpers.preedit(child), "")
end

T["<F5> commits the pre-edit and then inserts the key (#56)"] = function()
  start()
  type("Kan")
  type("<F5>")
  eq(helpers.buffer(child), { "かん<F5>" })
  eq(helpers.preedit(child), "")
end

T["<C-Left> commits the pre-edit and then moves the cursor (#56)"] = function()
  start()
  type("Kan")
  type("<C-Left>")
  eq(helpers.buffer(child), { "かん" })
  eq(helpers.cursor(child), { 1, 0 })
end

T["a candidate is committed before the key acts (#56)"] = function()
  start()
  type("Kan<Space>")
  eq(helpers.preedit(child), "▼缶")

  type("<Left>")
  eq(helpers.buffer(child), { "缶" })
  eq(helpers.preedit(child), "")
  eq(helpers.cursor(child), { 1, 0 })
end

T["one undo removes the committed text (#56)"] = function()
  start()
  type("Kan<Left>")
  eq(helpers.buffer(child), { "かん" })
  type("<Esc>u")
  eq(helpers.buffer(child), { "" })
end

T["mapped keys still work (#56)"] = function()
  start()
  type("Kan<Space>")
  eq(helpers.preedit(child), "▼缶")

  type("<C-g>")
  eq(helpers.preedit(child), "")

  type("Kan")
  type("<BS>")
  eq(helpers.preedit(child), "▽か")
end

T["<Insert> still enters replace mode (#29)"] = function()
  start()
  type("Kan")
  eq(helpers.preedit(child), "▽かn")
  child.type_keys("<Insert>")
  helpers.settle(child)
  eq(child.fn.mode(), "R")
end

T["unmapped special keys in cmdline commit the pre-edit first (#56)"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")

  type("<Left>")
  eq(child.fn.getcmdline(), "かん")
  eq(child.fn.getcmdpos(), 4)
end

return T

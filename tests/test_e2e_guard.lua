-- 未マップの特殊キーから pre-edit を守るゲート (#56)
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set({ config = { guardUnmappedKeys = true } })
local type = function(...)
  helpers.type(child, ...)
end

local function start()
  type("i<Plug>(skkeleton-enable)")
end

T["unmapped special keys keep the pre-edit (#56)"] = function()
  start()
  type("Kan")
  eq(helpers.preedit(child), "▽かn")

  for _, key in ipairs({ "<C-.>", "<S-CR>", "<Left>", "<F5>", "<C-Left>" }) do
    type(key)
    eq(helpers.preedit(child), "▽かn")
    eq(helpers.buffer(child), { "" })
  end

  -- 捨てたキーのあとも、打った読みの続きから入力できる
  type("ka")
  eq(helpers.preedit(child), "▽かんか")
end

T["mapped keys still work with the guard (#56)"] = function()
  start()
  type("Kan")
  type("<Space>")
  eq(helpers.preedit(child), "▼缶")

  type("<C-g>")
  eq(helpers.preedit(child), "")

  type("Kan")
  type("<BS>")
  eq(helpers.preedit(child), "▽か")
end

T["<Insert> still enters replace mode with the guard (#29)"] = function()
  start()
  type("Kan")
  eq(helpers.preedit(child), "▽かn")
  child.type_keys("<Insert>")
  helpers.settle(child)
  eq(child.fn.mode(), "R")
end

T["unmapped special keys in cmdline keep the pre-edit (#56)"] = function()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")

  type("<Left>")
  eq(child.fn.getcmdline(), "▽かn")

  type("ka")
  eq(child.fn.getcmdline(), "▽かんか")
end

return T

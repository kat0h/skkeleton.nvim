-- 変換中かを返す API (#163)
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function composing()
  return child.lua_get([[require("skkeleton").is_composing()]])
end

T["is_composing is false when skk is disabled"] = function()
  eq(composing(), false)
end

T["is_composing is false when there is no pre-edit"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  eq(composing(), false)
  -- かなを確定すると pre-edit が無くなる
  type("ka")
  eq(composing(), false)
end

T["is_composing is true while typing a reading"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("K")
  eq(composing(), true)
  type("an")
  eq(composing(), true)
end

T["is_composing is true while choosing a candidate"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space>")
  eq(helpers.preedit(child), "▼缶")
  eq(composing(), true)
  type("<C-j>")
  eq(composing(), false)
end

return T

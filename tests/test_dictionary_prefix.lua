-- 前方一致の読み引き (#162)
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.child_set()

local PRE = helpers.dict_pre(([[
local User = require("skkeleton.dictionary.user")
]]):format(helpers.testdata))

local function run(code, ...)
  return child.lua(PRE .. code, { ... })
end

T["get_prefix returns the same keys after the dictionary changes"] = function()
  eq(
    run([[
      local u = User.new()
      u:register_henkan_result("okurinasi", "とうきょう", "東京")
      u:register_henkan_result("okurinasi", "とう", "塔")
      local before = u:get_prefix("okurinasi", "とう", 10)
      -- 辞書が変わったら並べ直す
      u:register_henkan_result("okurinasi", "とうだい", "灯台")
      u:purge_candidate("okurinasi", "とう", "塔")
      local after = u:get_prefix("okurinasi", "とう", 10)
      local names = {}
      for i, e in ipairs(after) do
        names[i] = e[1]
      end
      return { #before, names }
    ]]),
    { 2, { "とうきょう", "とうだい" } }
  )
end

T["get_prefix honours the limit"] = function()
  eq(
    run([[
      local u = User.new()
      for i = 1, 20 do
        u:register_henkan_result("okurinasi", ("とう%d"):format(i), ("候補%d"):format(i))
      end
      return #u:get_prefix("okurinasi", "とう", 5)
    ]]),
    5
  )
end

return T

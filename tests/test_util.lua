local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["chars"] = function()
  eq(require("skkeleton.util").chars("aかｶﾞ"), { "a", "か", "ｶ", "ﾞ" })
end

T["drop_last_char / last_char"] = function()
  local U = require("skkeleton.util")
  eq(U.drop_last_char("かな"), "か")
  eq(U.drop_last_char("a"), "")
  eq(U.drop_last_char(""), "")
  eq(U.last_char("かな"), "な")
end

return T

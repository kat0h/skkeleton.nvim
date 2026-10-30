-- preedit_test.ts
local eq = MiniTest.expect.equality
local PreEdit = require("skkeleton.preedit")
local T = MiniTest.new_set()

T["preedit test"] = function()
  local pe = PreEdit.new()
  -- PreEdit は前回の文字列の長さを覚えていて、返り値は「今の文字列を消して新しい文字列を書く」もの
  eq(pe:output("foo"), "foo")
  eq(pe:output("hoge"), "\b\b\bhoge")
  eq(pe:output("piyo"), "\b\b\b\bpiyo")
  -- 確定した文字列は新しい文字列の前に出る
  pe:do_kakutei("bar")
  eq(pe:output("baz"), "\b\b\b\bbarbaz")
end

T["preedit with grapheme"] = function()
  local pe = PreEdit.new()
  eq(pe:output("💩"), "💩")
  eq(pe:output("🚽"), "\b🚽")
  eq(pe:output("☀️"), "\b☀️") -- U+2600 U+FE0F の合成文字
  eq(pe:output("🍦"), "\b🍦")
end

T["preedit with Japanese"] = function()
  local pe = PreEdit.new()
  eq(pe:output("▽かん"), "▽かん")
  -- 前回の続きなら差分だけ
  eq(pe:output("▽かんじ"), "じ")
  eq(pe:output(""), "\b\b\b\b")
end

T["take_kakutei"] = function()
  local pe = PreEdit.new()
  pe:do_kakutei("あ")
  pe:do_kakutei("い")
  eq(pe:take_kakutei(), "あい")
  eq(pe:take_kakutei(), "")
  eq(pe:output("x"), "x")
end

return T

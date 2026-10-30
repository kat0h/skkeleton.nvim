local eq = MiniTest.expect.equality
local N = require("skkeleton.dictionary.numeral")
local T = MiniTest.new_set()

-- 位取りありの漢数字。upstream（@geolonia/japanese-numeral）の結果に合わせる
T["to_kanji_classic"] = function()
  local cases = {
    { "0", "〇" },
    { "1", "一" },
    { "2", "二" },
    { "9", "九" },
    { "10", "十" },
    { "11", "十一" },
    { "19", "十九" },
    { "20", "二十" },
    { "100", "百" },
    { "101", "百一" },
    { "110", "百十" },
    { "111", "百十一" },
    { "1000", "千" },
    { "1001", "千一" },
    { "1010", "千十" },
    { "1100", "千百" },
    { "1111", "千百十一" },
    { "2000", "二千" },
    { "2020", "二千二十" },
    { "9999", "九千九百九十九" },
    { "10000", "一万" },
    { "10001", "一万一" },
    { "10010", "一万十" },
    { "11000", "一万千" },
    { "12345", "一万二千三百四十五" },
    { "100000", "十万" },
    { "110000", "十一万" },
    { "1000000", "百万" },
    { "10000000", "千万" },
    { "100000000", "一億" },
    { "100000001", "一億一" },
    { "123456789", "一億二千三百四十五万六千七百八十九" },
    { "1000000000000", "一兆" },
    { "1234567890123", "一兆二千三百四十五億六千七百八十九万百二十三" },
    { "0101", "百一" },
  }
  for _, c in ipairs(cases) do
    eq({ c[1], N.to_kanji_classic(c[1]) }, c)
  end
end

T["to_kanji_classic leaves a number that is too large as digits"] = function()
  local big = "1" .. ("0"):rep(60)
  eq(N.to_kanji_classic(big), big)
end

T["to_kanji_classic returns non-digits as-is"] = function()
  eq(N.to_kanji_classic("abc"), "abc")
  eq(N.to_kanji_classic("12a34"), "12a34")
end

T["to_kanji_modern, to_zenkaku"] = function()
  eq(N.to_kanji_modern("101"), "一〇一")
  eq(N.to_kanji_modern("0"), "〇")
  eq(N.to_zenkaku("101"), "１０１")
  eq(N.to_zenkaku("007"), "７") -- parseInt と同じく、先頭の 0 は落ちる
  eq(N.to_zenkaku("1234567890"), "１２３４５６７８９０")
end

T["to_daiji"] = function()
  eq(N.to_daiji("101"), "佰壱")
  eq(N.to_daiji("0"), "零")
  eq(N.to_daiji("12345"), "壱萬弐阡参佰肆拾伍")
  eq(N.to_daiji("100000000"), "壱億")
  eq(N.to_daiji("6789"), "陸阡漆佰捌拾玖")
end

T["to_roman"] = function()
  local cases = {
    { "1", "I" },
    { "4", "IV" },
    { "9", "IX" },
    { "14", "XIV" },
    { "19", "XIX" },
    { "40", "XL" },
    { "90", "XC" },
    { "101", "CI" },
    { "400", "CD" },
    { "900", "CM" },
    { "1111", "MCXI" },
    { "1994", "MCMXCIV" },
    { "2020", "MMXX" },
    { "3999", "MMMCMXCIX" },
    { "9999", "MMMMMMMMMCMXCIX" },
  }
  for _, c in ipairs(cases) do
    eq({ c[1], N.to_roman(c[1]) }, c)
  end
  -- 変換できない数はそのまま
  eq(N.to_roman("0"), "0")
  eq(N.to_roman("100000"), "100000")
end

T["to_kifu"] = function()
  eq(N.to_kifu("11"), "１一")
  eq(N.to_kifu("34"), "３四")
  eq(N.to_kifu("99"), "９九")
  eq(N.to_kifu("10"), "10")
  eq(N.to_kifu("1"), "1")
  eq(N.to_kifu("111"), "111")
  eq(N.to_kifu("05"), "5")
end

T["convert_number"] = function()
  local cases = {
    { "#0番", "101ばん", "101番" },
    { "#1番", "101ばん", "１０１番" },
    { "#2番", "101ばん", "一〇一番" },
    { "#3番", "101ばん", "百一番" },
    { "#4番", "101ばん", "101番" },
    { "#5番", "101ばん", "佰壱番" },
    { "#6番", "101ばん", "101番" },
    { "#7番", "101ばん", "101番" },
    { "#8番", "101ばん", "CI番" },
    { "#9王手", "11おうて", "１一王手" },
    { "#9王手", "111おうて", "111王手" },
    -- 数字が複数あるとき
    { "#0月#0日", "12がつ25にち", "12月25日" },
    { "#3月#1日", "12がつ25にち", "十二月２５日" },
    -- 数字を含まない候補はそのまま
    { "東京", "101ばん", "東京" },
    -- リテラル '#'（数字が続かないもの）は置換されない
    { "C#", "101", "C#" },
    { "#番", "101ばん", "101番" },
    -- 注釈つきテンプレート・残りのセグメントを切り詰めない
    { "#0;#3の注釈", "101", "101;#3の注釈" },
    { "#1番;#0", "101", "１０１番;#0" },
    { "#0と#0", "5と", "5と#0" },
  }
  for _, c in ipairs(cases) do
    eq({ c[1], c[2], N.convert_number(c[1], c[2]) }, c)
  end
end

T["wrap"] = MiniTest.new_set()

local function memory(maps)
  return require("skkeleton.dictionary.skk").Memory.new(maps)
end

T["wrap"]["converts numbers (upstream: get num candidates)"] = function()
  local d = N.wrap(memory({ okurinasi = { ["#ばん"] = "/#0番/#1番/#2番/#3番/#8番/#5番/" } }))
  eq(
    d:get_henkan_result("okurinasi", "101ばん"),
    { "101番", "１０１番", "一〇一番", "百一番", "CI番", "佰壱番" }
  )
  eq(d:get_henkan_result("okurinasi", "ばん"), {})
end

T["wrap"]["converts kifu"] = function()
  local d = N.wrap(memory({ okurinasi = { ["#おうて"] = "/#9王手/" } }))
  eq(d:get_henkan_result("okurinasi", "11おうて"), { "１一王手" })
  eq(d:get_henkan_result("okurinasi", "111おうて"), { "111王手" })
end

T["wrap"]["puts exact matches of words that include numbers first"] = function()
  local d = N.wrap(memory({ okurinasi = { cat2 = "/🐈/", ["1000001"] = "/東京都千代田区千代田/" } }))
  eq(d:get_henkan_result("okurinasi", "cat2"), { "🐈" })
  eq(d:get_henkan_result("okurinasi", "1000001"), { "東京都千代田区千代田" })
end

T["wrap"]["puts exact matches before the numeric pattern"] = function()
  local d = N.wrap(memory({ okurinasi = { ["#ばん"] = "/#0番/", ["1ばん"] = "/一番/" } }))
  eq(d:get_henkan_result("okurinasi", "1ばん"), { "一番", "1番" })
end

T["wrap"]["does not change the inner dictionary"] = function()
  local inner = memory({ okurinasi = { ["#ばん"] = { "#0番" } } })
  local d = N.wrap(inner)
  d:get_henkan_result("okurinasi", "5ばん")
  eq(inner.maps.okurinasi["#ばん"], { "#0番" })
end

return T

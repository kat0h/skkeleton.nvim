-- kana_test.ts と、trie のかなテーブル（register / load_file / node）のテスト
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    H = require("core_helpers")
    H.setup_library()
    kana = require("skkeleton.kana")
  ]])
end

T["customize kanatable"] = function()
  init()
  -- 関数の登録名、{ かな, feed }、{ かな } だけ（feed は ""）、false で削除
  child.lua([[
    kana.register("rom", { jj = "newline", ["z,"] = { "―", "" }, ["z."] = { "―" }, ["!"] = { "!!" } })
    kana.register("rom", { ["!"] = false })
    ctx = require("skkeleton.context").new()
  ]])
  local cases = { { "jj", "\n" }, { "z,", "―" }, { "z.", "―" }, { "!", "!" } }
  for _, c in ipairs(cases) do
    eq(child.lua_get([[(function(keys) H.dispatch(ctx, keys); return ctx.preedit:output("") end)(...)]], { c[1] }), c[2])
  end
end

T["create kanatable"] = function()
  init()
  child.lua([[
    kana.register("test", { a = { "hoge", "" } }, true)
    kana.set_current("test")
    require("skkeleton.config").set({ kanaTable = "test" })
  ]])
  eq(child.lua_get([[H.output("a")]]), "hoge")
  eq(child.lua_get([[kana.current_name]]), "test")
end

T["register errors"] = function()
  init()
  eq(child.lua_get([[select(2, pcall(kana.register, "nothing", { a = { "x" } }))]]), "table nothing is not found.")
  eq(child.lua_get([[select(2, pcall(kana.register, "rom", { a = "nofunc" }))]]), "function not found: nofunc")
  eq(child.lua_get([[pcall(kana.register, "rom", { a = 1 })]]), false)
  eq(child.lua_get([[select(2, pcall(kana.get_table, "nothing"))]]), "undefined table: nothing")
end

T["uppercase key becomes <s-x> and string result becomes a function"] = function()
  init()
  child.lua([[kana.register("rom", { X = "newline", Q = { "Q", "" } })]])
  eq(child.lua_get([[kana.get_table():find("<s-x>") == require("skkeleton.function").functions.newline]]), true)
  eq(child.lua_get([[kana.get_table():find("<s-q>")]]), { "Q", "" })
end

T["registered entries take precedence over existing ones"] = function()
  init()
  child.lua([[kana.register("rom", { ka = { "KA", "" } })]])
  eq(child.lua_get([[kana.get_table():find("ka")]]), { "KA", "" })
  eq(child.lua_get([[kana.get_table():find("ki")]]), { "き", "" })
  eq(child.lua_get([[H.output("kaki")]]), "KAき")
end

T["builtin tables"] = function()
  init()
  eq(child.lua_get([[kana.get_table("rom"):count()]]), 248)
  eq(child.lua_get([[kana.get_table("zen"):count()]]), 94)
  -- 関数の値は本物の関数（abbrev が == で絞り込む）
  eq(child.lua_get([[kana.get_table():find(" ") == require("skkeleton.function.henkan").henkan_first]]), true)
  eq(child.lua_get([[kana.get_table():find(";") == require("skkeleton.function.input").henkan_point]]), true)
  eq(child.lua_get([[kana.get_table():find("l") == require("skkeleton.function.disable").disable]]), true)
  eq(child.lua_get([[kana.get_table():find("/") == require("skkeleton.function.mode").abbrev]]), true)
  eq(child.lua_get([[kana.get_table():find("q") == require("skkeleton.function.mode").katakana]]), true)
  eq(child.lua_get([[kana.get_table():find("<s-l>") == require("skkeleton.function.mode").zenkaku]]), true)
  eq(child.lua_get([[kana.get_table():find("z ")]]), { "　", "" })
  eq(child.lua_get([[kana.get_table("zen"):find("<s-a>")]]), { "Ａ", "" })
  eq(child.lua_get([[kana.get_table("zen"):find("\\")]]), { "＼", "" })
end

T["trie node"] = function()
  init()
  -- 前方一致の件数と完全一致の結果
  eq(child.lua_get([[kana.get_table():node("ky").count]]), 5)
  eq(child.lua_get([[kana.get_table():node("ky").result]]), vim.NIL)
  eq(child.lua_get([[kana.get_table():node("ka").count]]), 1)
  eq(child.lua_get([[kana.get_table():node("ka").result]]), { "か", "" })
  -- n, n', na, ne, ni, nn, no, nu, nya, nye, nyi, nyo, nyu
  eq(child.lua_get([[kana.get_table():node("n").count]]), 13)
  eq(child.lua_get([[kana.get_table():node("n").result]]), { "ん", "" })
  eq(child.lua_get([[kana.get_table():node("kz") == nil]]), true)
  eq(child.lua_get([[kana.get_table():node("").count]]), 248)
  eq(child.lua_get([[kana.get_table():find("kya")]]), { "きゃ", "" })
  eq(child.lua_get([[kana.get_table():find("ky")]]), vim.NIL)
end

T["filter"] = function()
  init()
  eq(child.lua_get([[kana.get_table():filter(function(from) return from:sub(1, 1) == "k" end):count()]]), 11)
  eq(
    child.lua_get([[
      kana.get_table():filter(function(_, func) return type(func) == "function" end):node("").count
    ]]),
    6
  )
end

T["load_file"] = function()
  init()
  child.lua([[
    path = vim.fn.tempname()
    vim.fn.writefile({ "# comment", "", "xx,ほ", "yy,へ" }, path)
    kana.load_file("rom", path, "utf-8", false)
  ]])
  eq(child.lua_get([[H.output("xxyy")]]), "ほへ")
  -- 既存のキーは残る
  eq(child.lua_get([[H.output("ka")]]), "か")
end

T["load_file with euc-jp"] = function()
  init()
  child.lua([[
    path = vim.fn.tempname()
    local f = io.open(path, "wb")
    f:write(vim.iconv("ww1,漢字\nww2,かな\n", "utf-8", "euc-jp"))
    f:close()
    kana.load_file("custom", path, "euc-jp", true)
    kana.load_file("custom2", path, "", true)
  ]])
  eq(child.lua_get([[kana.get_table("custom"):find("ww1")]]), { "漢字", "" })
  -- 指定がなければ UTF-8 でないものを EUC-JP とみなす
  eq(child.lua_get([[kana.get_table("custom2"):find("ww2")]]), { "かな", "" })
  eq(child.lua_get([[select(2, pcall(kana.load_file, "nothing", path, "euc-jp", false))]]), "table nothing is not found.")
end

T["globalKanaTableFiles"] = function()
  init()
  child.lua([[
    path = vim.fn.tempname()
    vim.fn.writefile({ "xx,ほ" }, path)
    require("skkeleton.config").set({ globalKanaTableFiles = { path } })
  ]])
  eq(child.lua_get([[H.output("xx")]]), "ほ")
end

T["hira_to_kata / hira_to_hankata"] = function()
  init()
  local cases = {
    { "hira_kata", "hira_to_kata", "ひらがなゔぁ、abc", "ヒラガナヴァ、abc" },
    { "hira_hankata", "hira_to_hankata", "ほげぴょん", "ﾎｹﾞﾋﾟｮﾝ" },
    { "hira_hankata", "hira_to_hankata", "がっこうー", "ｶﾞｯｺｳｰ" },
  }
  for _, c in ipairs(cases) do
    eq(child.lua_get(('require("skkeleton.kana.%s").%s(...)'):format(c[1], c[2]), { c[3] }), c[4])
  end
end

return T

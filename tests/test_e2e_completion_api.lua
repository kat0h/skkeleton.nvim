-- 補完の Lua API（get_prefix、get_preedit、get_completion_result、complete）
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

local function api(code)
  return child.lua_get("(function() " .. code .. " end)()")
end

T["get_prefix and get_preedit"] = function()
  enable()
  eq(api("return require('skkeleton').get_prefix()"), "")
  type("Kan")
  eq(api("return require('skkeleton').get_prefix()"), "か")
  eq(api("return require('skkeleton').get_preedit()"), "▽かn")
  type("j")
  eq(api("return require('skkeleton').get_prefix()"), "かん")
  eq(api("return require('skkeleton').get_preedit()"), "▽かんj")
end

T["get_prefix is empty outside of the input state"] = function()
  enable()
  type("Kan<Space>")
  eq(api("return require('skkeleton').get_prefix()"), "")
  eq(api("return require('skkeleton').get_completion_result()"), {})
end

T["get_completion_result uses the feed"] = function()
  enable()
  type("Ka")
  -- 読みが 1 文字（か）で feed が空のときは完全一致だけ
  eq(api("return require('skkeleton').get_completion_result()"), {})
  type("n")
  -- 読みが 1 文字でも feed があれば feed から始まる読みを展開する
  eq(api("return require('skkeleton').get_completion_result()"), {
    { "かん", { "缶", "感", "漢", "幹", "管", "館", "観" } },
    { "かんじ", { "漢字", "幹事" } },
  })
  type("j")
  -- かん + feed "j": じゃ、じゅ... の「じ」
  eq(api("return require('skkeleton').get_completion_result()"), { { "かんじ", { "漢字", "幹事" } } })
end

T["get_completion_result lists the readings that start with the pre-edit"] = function()
  enable()
  type("Kann")
  eq(api("return require('skkeleton').get_prefix()"), "かん")
  eq(api("return require('skkeleton').get_completion_result()"), {
    { "かん", { "缶", "感", "漢", "幹", "管", "館", "観" } },
    { "かんじ", { "漢字", "幹事" } },
  })
end

T["complete discards the pre-edit and commits the word"] = function()
  enable()
  type("Kanj")
  child.lua("require('skkeleton').complete('かんじ', '漢字;annotation')")
  helpers.settle(child)
  eq(helpers.buffer(child), { "漢字" })
  eq(helpers.preedit(child), "")
  eq(api("return require('skkeleton').get_prefix()"), "")
  eq(api("return require('skkeleton').get_preedit()"), "")
  -- ユーザー辞書には注釈つきで登録される
  eq(
    api("return require('skkeleton.store').library():get_henkan_result('okurinasi', 'かんじ')[1]"),
    "漢字;annotation"
  )
  eq(
    api("return require('skkeleton.store').context().last_candidate"),
    { type = "okurinasi", word = "かんじ", candidate = "漢字;annotation" }
  )
  -- そのまま続けて打てる（モードは変わらない）
  eq(helpers.mode(child), "hira")
  type("a")
  eq(helpers.buffer(child), { "漢字あ" })
end

T["complete puts the chosen word at the head of the candidates"] = function()
  enable()
  type("Kanj")
  child.lua("require('skkeleton').complete('かんじ', '感じ')")
  eq(
    api("return require('skkeleton.store').library():get_henkan_result('okurinasi', 'かんじ')"),
    { "感じ", "漢字", "幹事" }
  )
end

T["complete is one undo unit"] = function()
  enable()
  -- 確定の前にも文字を打っておき、undo の区切りが無くなったら落ちるようにする
  type("aiu")
  type("Kanj")
  child.lua("require('skkeleton').complete('かんじ', '漢字')")
  helpers.settle(child)
  type("<Esc>u")
  eq(helpers.buffer(child), { "あいう" })
end

T["get_completion_result returns numeral converted candidates (#50)"] = function()
  child.lua([[
    local store = require("skkeleton.store")
    store.library():register_henkan_result("okurinasi", "#ばい", "#1倍")
  ]])
  enable()
  type(";1ba")
  eq(api("return require('skkeleton').get_completion_result()"), { { "1ばい", { "１倍" } } })
end

return T

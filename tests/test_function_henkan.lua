-- function/henkan_test.ts と、候補の popup（showCandidates）
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    H = require("core_helpers")
    lib = H.setup_library()
    lib:register_henkan_result("okurinasi", "へんかん", "返還")
    lib:register_henkan_result("okurinasi", "へんかん", "変換")
    lib:register_henkan_result("okuriari", "おくr", "送")
    lib:register_henkan_result("okuriari", "えらn", "選")
    lib:register_henkan_result("okuriari", "うたがt", "疑")
    lib:register_henkan_result("okuriari", "うたがc", "疑")
    Context = require("skkeleton.context")
    henkan = require("skkeleton.function.henkan")
    H.spy_host()
  ]])
end

local function shown(keys)
  return child.lua_get("H.shown(...)", { keys })
end

T["okurinasi henkan"] = function()
  init()
  child.lua([[ctx = Context.new()]])
  local steps = { { ";henkan ", "▼変換" }, { " ", "▼返還" }, { "x", "▼変換" } }
  for _, s in ipairs(steps) do
    eq(child.lua_get([[(function(k) H.dispatch(ctx, k); return ctx:to_string() end)(...)]], { s[1] }), s[2])
  end
end

T["okuriari henkan"] = function()
  init()
  eq(shown(";oku;ri"), "▼送り")
  eq(shown(";era;nde"), "▼選んで")
  eq(shown(";utaga;tte"), "▼疑って")
  eq(shown(";utaga;ccha"), "▼疑っちゃ")
end

T["henkan cancel"] = function()
  init()
  eq(shown(";henkan x"), "▽へんかん")
end

T["fallback to kana_input in henkan_first"] = function()
  init()
  local KanaTable = [[require("skkeleton.kana").KanaTable]]
  child.lua(([[
    ctx = Context.new()
    ctx.state.table = %s.new({ { " ", { "", "space" } } })
    H.dispatch(ctx, " ")
  ]]):format(KanaTable))
  eq(child.lua_get([[ctx:to_string()]]), "space")
  -- 無限再帰を避けて、直接入力にフォールバックする
  child.lua(([[
    ctx.state.table = %s.new({ { " ", henkan.henkan_first } })
    H.dispatch(ctx, " ")
  ]]):format(KanaTable))
  eq(child.lua_get([[ctx.preedit:output("")]]), " ")
  -- 再入の防止は例外のあとにも残らない
  eq(child.lua_get([[(function() H.dispatch(ctx, " "); return ctx.preedit:output("") end)()]]), " ")
end

T["no candidates: input state returns when nothing is registered"] = function()
  init()
  -- 辞書登録を取り消すと、変換前の状態に戻る
  eq(shown(";hoge "), "▽ほげ")
  eq(child.lua_get([[#H.called("input")]]), 1)
end

T["register word prompt"] = function()
  init()
  child.lua([[H.ret.input = "穂毛"]])
  eq(shown(";hoge "), "")
  eq(child.lua_get([[H.called("input")[1][2] ]]), "[辞書登録] ほげ: ")
  -- 登録した候補が確定して、辞書に入る
  eq(child.lua_get([[lib:get_henkan_result("okurinasi", "ほげ")]]), { "穂毛" })
  eq(shown(";hoge "), "▼穂毛")
  -- 送り仮名ありでは * と送り仮名がプロンプトに入る
  child.lua([[H.calls = {}; H.output(";ho;ge")]])
  eq(child.lua_get([[H.called("input")[1][2] ]]), "[辞書登録] ほ*げ: ")
end

T["candidates popup"] = function()
  init()
  child.lua([[
    for i = 10, 1, -1 do
      lib:register_henkan_result("okurinasi", "あ", "候補" .. i)
    end
    ctx = Context.new()
    H.dispatch(ctx, ";a")
  ]])
  -- 4 つ目まではインラインで、5 つ目から popup
  for i = 1, 4 do
    eq(child.lua_get([[(function() H.dispatch(ctx, " "); return ctx:to_string() end)()]]), "▼候補" .. i)
  end
  eq(child.lua_get([[#H.called("show_candidates")]]), 0)
  eq(child.lua_get([[(function() H.dispatch(ctx, " "); return ctx:to_string() end)()]]), "▼候補5")
  eq(child.lua_get([[H.called("show_candidates")[1][2] ]]), {
    "a: 候補5",
    "s: 候補6",
    "d: 候補7",
    "f: 候補8",
    "j: 候補9",
    "k: 候補10",
  })
  -- 戻る
  child.lua([[H.dispatch(ctx, "x")]])
  eq(child.lua_get([[ctx:to_string()]]), "▼候補4")
  eq(child.lua_get([[#H.called("show_candidates")]]), 1)
end

T["select candidate with keys on popup"] = function()
  init()
  child.lua([[
    for i = 10, 1, -1 do
      lib:register_henkan_result("okurinasi", "あ", "候補" .. i)
    end
    ctx = Context.new()
    H.dispatch(ctx, ";a     ")
  ]])
  eq(child.lua_get([[ctx:to_string()]]), "▼候補5")
  -- 候補の範囲外のキーは何もしない
  child.lua([[henkan.henkan_input(ctx, "l")]])
  eq(child.lua_get([[ctx:to_string()]]), "▼候補5")
  -- d は 3 つ目 -> 候補7
  child.lua([[henkan.henkan_input(ctx, "d")]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "候補7")
  eq(child.lua_get([[ctx.last_candidate.candidate]]), "候補7")
end

T["select candidate with multibyte selectCandidateKeys"] = function()
  init()
  child.lua([[
    config = require("skkeleton.config")
    config.set({ selectCandidateKeys = "１２３４５６７" })
    for i = 10, 1, -1 do
      lib:register_henkan_result("okurinasi", "あ", "候補" .. i)
    end
    ctx = Context.new()
    H.dispatch(ctx, ";a     ")
  ]])
  eq(child.lua_get([[ctx:to_string()]]), "▼候補5")
  eq(child.lua_get([[H.called("show_candidates")[1][2] ]]), {
    "１: 候補5",
    "２: 候補6",
    "３: 候補7",
    "４: 候補8",
    "５: 候補9",
    "６: 候補10",
  })
  child.lua([[henkan.henkan_input(ctx, "３")]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "候補7")
end

T["henkan_input confirms and handles the key"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, ";henkan ")
    henkan.henkan_input(ctx, "k")
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "変換")
  eq(child.lua_get([[ctx:to_string()]]), "k")
  -- 大文字は次の変換開始になる
  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, ";henkan ")
    henkan.henkan_input(ctx, "A")
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "変換")
  eq(child.lua_get([[ctx:to_string()]]), "▽あ")
end

T["suffix"] = function()
  init()
  child.lua([[
    lib:register_henkan_result("okurinasi", ">さん", ">サン")
    ctx = Context.new()
    H.dispatch(ctx, ";henkan ")
    henkan.suffix(ctx)
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "変換")
  eq(
    child.lua_get([[{ ctx.state.type, ctx.state.mode, ctx.state.affix, ctx.state.henkan_feed }]]),
    { "input", "okurinasi", "suffix", ">" }
  )
  child.lua([[H.dispatch(ctx, "san ")]])
  eq(child.lua_get([[ctx:to_string()]]), "▼サン")
end

return T

-- function/disable_test.ts と function/dictionary_test.ts のうち、UI が要らない部分
-- （enable/disable を通す部分と、cmdline のマッピングの確認は E2E で扱う）
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    H = require("core_helpers")
    lib = H.setup_library()
    config = require("skkeleton.config")
    Context = require("skkeleton.context")
    common = require("skkeleton.function.common")
    disable = require("skkeleton.function.disable")
    dictionary = require("skkeleton.function.dictionary")
    H.spy_host()
  ]])
end

T["kakutei at disable"] = function()
  init()
  -- 確定する文字列があれば出して、host.disable を呼ぶ
  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, " ")
    disable.disable(ctx)
  ]])
  eq(child.lua_get([[ctx.preedit:output(ctx:to_string())]]), " ")
  eq(child.lua_get([[#H.called("disable")]]), 1)

  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, "n")
    disable.disable(ctx)
  ]])
  eq(child.lua_get([[ctx.preedit:output(ctx:to_string())]]), "ん")
  eq(child.lua_get([[#H.called("disable")]]), 2)
end

T["disable just after henkan point"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, ";hoge")
    disable.disable(ctx)
  ]])
  eq(child.lua_get([[{ ctx.state.type, ctx.state.mode, ctx:to_string() }]]), { "input", "direct", "" })
  eq(child.lua_get([[ctx.preedit:output("")]]), "ほげ")
end

T["disable kakutei the candidate"] = function()
  init()
  child.lua([[
    lib:register_henkan_result("okurinasi", "あ", "亜")
    ctx = Context.new()
    H.dispatch(ctx, ";a ")
    disable.disable(ctx)
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "亜")
end

T["escape disables and moves to the escape state"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, ";ho")
    disable.escape(ctx)
  ]])
  eq(child.lua_get([[ctx.state.type]]), "escape")
  eq(child.lua_get([[ctx.preedit:output("")]]), "ほ")
  eq(child.lua_get([[#H.called("disable")]]), 1)
  eq(child.lua_get([[#H.called("keep_state_on_insert_enter")]]), 0)
end

T["escape with keepState"] = function()
  init()
  child.lua([[
    config.set({ keepState = true })
    ctx = Context.new()
    disable.escape(ctx)
  ]])
  eq(child.lua_get([[#H.called("keep_state_on_insert_enter")]]), 1)
  eq(child.lua_get([[ctx.state.type]]), "escape")
end

local function henkan_state()
  child.lua([[
    state = require("skkeleton.state").initialize({})
    state.type = "henkan"
    state.mode = "okuriari"
    state.okuri_feed = "hoge"
    state.word = ""
    state.candidates = {}
    state.candidate_index = -1
    ctx = Context.new()
    ctx.state = state
  ]])
end

T["Don't put string when register dictionary was cancelled"] = function()
  init()
  henkan_state()
  -- Esc などで取り消されると "" が返る
  child.lua([[H.ret.input = ""]])
  eq(child.lua_get([[dictionary.register_word(ctx)]]), false)
  eq(child.lua_get([[ctx.preedit:output("")]]), "")
  -- nil でも同じ
  child.lua([[H.ret.input = nil]])
  eq(child.lua_get([[dictionary.register_word(ctx)]]), false)
  eq(child.lua_get([[ctx.preedit:output("")]]), "")
  -- UI が内部のマーカーで返したときも取り消し
  child.lua([[H.ret.input = "__skkeleton_return__"]])
  eq(child.lua_get([[dictionary.register_word(ctx)]]), false)
  -- 入力中に例外が起きても取り消しとして扱う
  child.lua([[H.ret.input = function() error("interrupted") end]])
  eq(child.lua_get([[dictionary.register_word(ctx)]]), false)
  eq(child.lua_get([[ctx.preedit:output("")]]), "")
end

T["register_word confirms the input as the only candidate"] = function()
  init()
  henkan_state()
  child.lua([[
    state.henkan_feed = "ほげ"
    state.word = "ほげr"
    H.ret.input = "穂毛"
  ]])
  eq(child.lua_get([[dictionary.register_word(ctx)]]), true)
  eq(child.lua_get([[H.called("input")[1][2] ]]), "[辞書登録] ほげ*hoge: ")
  eq(child.lua_get([[ctx.preedit:output("")]]), "穂毛hoge")
  eq(child.lua_get([[lib:get_henkan_result("okuriari", "ほげr")]]), { "穂毛" })
  eq(child.lua_get([[ctx.state.type]]), "input")
end

return T

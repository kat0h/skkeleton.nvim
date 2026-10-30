-- function/common_test.ts と config_test.ts（eggLikeNewline、acceptIllegalResult、immediatelyOkuriConvert）
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    H = require("core_helpers")
    lib = H.setup_library()
    lib:register_henkan_result("okurinasi", "あ", "い")
    lib:register_henkan_result("okurinasi", "ちゅうしゃく", "注釈;これは注釈です")
    lib:register_henkan_result("okurinasi", "あ", "あ")
    lib:register_henkan_result("okuriari", "あt", "会")
    lib:register_henkan_result("okuriari", "すp", "酸")
    config = require("skkeleton.config")
    Context = require("skkeleton.context")
    common = require("skkeleton.function.common")
    mode = require("skkeleton.function.mode")
    H.spy_host()
  ]])
end

local function output(keys)
  return child.lua_get("H.output(...)", { keys })
end

local function shown(keys)
  return child.lua_get("H.shown(...)", { keys })
end

T["input cancel"] = function()
  init()
  child.lua([[ctx = Context.new()]])
  local function step(keys)
    local code = [[(function(k) H.dispatch(ctx, k); common.cancel(ctx); return ctx:to_string() end)(...)]]
    return child.lua_get(code, { keys })
  end
  eq(step("A"), "")
  eq(step("A "), "")

  -- immediatelyCancel = false では変換中の取り消しは変換前に戻る
  child.lua([[config.set({ immediatelyCancel = false }); H.dispatch(ctx, "A ")]])
  eq(child.lua_get([[ctx:to_string()]]), "▼あ")
  child.lua([[common.cancel(ctx)]])
  eq(child.lua_get([[ctx:to_string()]]), "▽あ")
  child.lua([[common.cancel(ctx)]])
  eq(child.lua_get([[ctx:to_string()]]), "")
end

T["cancel in cmdline sends <C-c> when nothing is being input"] = function()
  init()
  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        ctx.vim_mode = "c"
        common.cancel(ctx)
        return ctx.preedit:output("")
      end)()
    ]]),
    "\x03"
  )
end

T["annotation"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, ";tyuusyaku ")
    common.kakutei(ctx)
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "注釈")
  -- 辞書には注釈つきのまま登録される
  eq(child.lua_get([[lib:get_henkan_result("okurinasi", "ちゅうしゃく")]]), { "注釈;これは注釈です" })
end

T["turn off mode when kakutei with empty input"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    mode.katakana(ctx)
    H.dispatch(ctx, "k")
    common.kakutei_key(ctx)
  ]])
  eq(child.lua_get([[ctx.mode]]), "kata")
  child.lua([[common.kakutei_key(ctx)]])
  eq(child.lua_get([[ctx.mode]]), "hira")
end

T["kakutei registers the candidate and keeps last_candidate"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    H.dispatch(ctx, ";a ")
    common.kakutei(ctx)
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "あ")
  eq(child.lua_get([[ctx.last_candidate]]), { type = "okurinasi", word = "あ", candidate = "あ" })
end

T["kakutei of input state outputs the pre-edit string"] = function()
  init()
  eq(output(";kan\n"), "かん\n")
  eq(output("ab\n"), "あb\n")
end

T["egg like newline"] = function()
  init()
  -- normal
  eq(output("A \nA\n"), "あ\nあ\n")
  -- egg like
  child.lua([[config.set({ eggLikeNewline = true })]])
  eq(output("A \nA\n"), "ああ")
  -- 直接入力中の改行は egg like でも出る
  eq(output("a\n"), "あ\n")
end

T["acceptIllegalResult"] = function()
  init()
  eq(output("ksa"), "さ")
  child.lua([[config.set({ acceptIllegalResult = true })]])
  eq(output("ksa"), "kさ")
end

T["immediatelyOkuriConvert"] = function()
  init()
  -- true
  eq(shown(";a;xtu"), "▼会っ")
  -- false
  child.lua([[config.set({ immediatelyOkuriConvert = false })]])
  eq(shown(";su;xtupa"), "▼酸っぱ")
end

T["purge_candidate asks host.confirm"] = function()
  init()
  child.lua([[
    H.ret.confirm = true
    ctx = Context.new()
    H.dispatch(ctx, ";a ")
    common.purge_candidate(ctx)
  ]])
  eq(child.lua_get([[H.called("confirm")[1][2] ]]), "Really purge? あ /あ/")
  eq(child.lua_get([[lib.purged]]), { { "okurinasi", "あ", "あ" } })
  eq(child.lua_get([[ctx:to_string()]]), "")
  eq(child.lua_get([[ctx.last_candidate.word]]), "")
  eq(child.lua_get([[lib:get_henkan_result("okurinasi", "あ")]]), { "い" })
end

T["purge_candidate does nothing when not confirmed"] = function()
  init()
  child.lua([[
    H.ret.confirm = false
    ctx = Context.new()
    H.dispatch(ctx, ";a ")
    common.purge_candidate(ctx)
  ]])
  eq(child.lua_get([[#lib.purged]]), 0)
  eq(child.lua_get([[ctx:to_string()]]), "▼あ")
end

T["purge_candidate after kakutei uses last_candidate"] = function()
  init()
  child.lua([[
    H.ret.confirm = true
    ctx = Context.new()
    H.dispatch(ctx, ";a ")
    common.kakutei(ctx)
    common.purge_candidate(ctx)
    -- 履歴を消したので、もう一度呼んでも何もしない
    common.purge_candidate(ctx)
  ]])
  eq(child.lua_get([[#H.called("confirm")]]), 1)
  eq(child.lua_get([[lib.purged]]), { { "okurinasi", "あ", "あ" } })
end

T["purge_candidate with nothing to purge"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    common.purge_candidate(ctx)
  ]])
  eq(child.lua_get([[#H.called("confirm")]]), 0)
end

return T

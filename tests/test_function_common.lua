-- Ported from skkeleton (denops/skkeleton/function/common_test.ts, denops/skkeleton/config_test.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten for mini.test.
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    require("core_helpers").init_core({ spy_host = true })
    lib:register_henkan_result("okurinasi", "あ", "い")
    lib:register_henkan_result("okurinasi", "ちゅうしゃく", "注釈;これは注釈です")
    lib:register_henkan_result("okurinasi", "あ", "あ")
    lib:register_henkan_result("okuriari", "あt", "会")
    lib:register_henkan_result("okuriari", "すp", "酸")
    common = require("skkeleton.function.common")
    mode = require("skkeleton.function.mode")
  ]])
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
  eq(helpers.core_output(child, ";kan\n"), "かん\n")
  eq(helpers.core_output(child, "ab\n"), "あb\n")
end

T["egg like newline"] = function()
  init()
  -- normal
  eq(helpers.core_output(child, "A \nA\n"), "あ\nあ\n")
  -- egg like
  child.lua([[config.set({ eggLikeNewline = true })]])
  eq(helpers.core_output(child, "A \nA\n"), "ああ")
  -- 直接入力中の改行は egg like でも出る
  eq(helpers.core_output(child, "a\n"), "あ\n")
end

T["acceptIllegalResult"] = function()
  init()
  eq(helpers.core_output(child, "ksa"), "さ")
  child.lua([[config.set({ acceptIllegalResult = true })]])
  eq(helpers.core_output(child, "ksa"), "kさ")
end

T["immediatelyOkuriConvert"] = function()
  init()
  -- true
  eq(helpers.core_output(child, ";a;xtu", { shown = true }), "▼会っ")
  -- false
  child.lua([[config.set({ immediatelyOkuriConvert = false })]])
  eq(helpers.core_output(child, ";su;xtupa", { shown = true }), "▼酸っぱ")
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

T["purge_candidate with nil or empty candidate does not crash"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    ctx.last_candidate = { type = "okurinasi", word = "test", candidate = nil }
    common.purge_candidate(ctx)
  ]])
  eq(child.lua_get([[#H.called("confirm")]]), 0)

  child.lua([[
    ctx.state = {
      type = "henkan",
      mode = "okurinasi",
      word = "test",
      candidates = {},
      candidate_index = 0,
    }
    common.purge_candidate(ctx)
  ]])
  eq(child.lua_get([[#H.called("confirm")]]), 0)
end

return T

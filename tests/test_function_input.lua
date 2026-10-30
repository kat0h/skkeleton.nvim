-- function/input_test.ts（UI が要る "new line" は E2E で扱う）
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    H = require("core_helpers")
    H.setup_library()
    config = require("skkeleton.config")
    Context = require("skkeleton.context")
    input = require("skkeleton.function.input")
    mode = require("skkeleton.function.mode")
    common = require("skkeleton.function.common")
  ]])
end

-- 新しい Context に keys を流して、確定した文字列を返す
local function output(keys)
  return child.lua_get("H.output(...)", { keys })
end

local function shown(keys)
  return child.lua_get("H.shown(...)", { keys })
end

T["kana input"] = function()
  init()
  eq(output("nihongoutteiki"), "にほんごうっていき")
end

T["kana input with illegal key"] = function()
  init()
  eq(output("n n n n "), "ん ん ん ん ")
  eq(output("@a"), "@あ")
  eq(output(" na"), " な")
end

T["kana input: table of romaji"] = function()
  init()
  local cases = {
    { "ka", "か" },
    { "kya", "きゃ" },
    { "kka", "っか" },
    { "nn", "ん" },
    { "n'", "ん" },
    { "nk", "ん" }, -- k は feed に残る
    { "nka", "んか" },
    { "tsu", "つ" },
    { "shi", "し" },
    { "xtsu", "っ" },
    { "z.", "…" },
    { "z ", "　" },
    { "-", "ー" },
    { "[]", "「」" },
  }
  for _, c in ipairs(cases) do
    eq({ c[1], output(c[1]) }, c)
  end
end

T["henkan point"] = function()
  init()
  child.lua([[ctx = Context.new()]])
  local steps = {
    { ";", "▽" },
    { ";", "▽" },
    { "y", "▽y" },
    { "a", "▽や" },
    { ";", "▽や*" },
    { ";", "▽や*" },
    { "t", "▽や*t" },
    { "t", "▽や*っt" },
    { ";", "▽や*っt" },
  }
  for _, s in ipairs(steps) do
    eq(child.lua_get([[(function(k) H.dispatch(ctx, k); return ctx:to_string() end)(...)]], { s[1] }), s[2])
  end
end

T["upper case input"] = function()
  init()
  eq(shown("HogeP"), "▽ほげ*p")
  eq(shown("sAsS"), "▽さっ*s")
end

T["upper case input with lowercaseMap"] = function()
  init()
  child.lua([[config.set({ lowercaseMap = { ["+"] = "a" } })]])
  eq(shown("+"), "▽あ")
end

T["delete char"] = function()
  init()
  local r = child.lua_get([[
    (function()
      local ctx = Context.new()
      H.dispatch(ctx, ";ya;tt")
      local actual, expected = {}, {}
      local result = ctx:to_string()
      repeat
        input.delete_char(ctx)
        result = require("skkeleton.util").drop_last_char(result)
        actual[#actual + 1] = ctx:to_string()
        expected[#expected + 1] = result
      until result == ""
      return { actual, expected }
    end)()
  ]])
  eq(r[1], r[2])
  eq(#r[1], 5) -- ▽ や * っ t
end

T["delete char in direct mode sends BS"] = function()
  init()
  child.lua([[ctx = Context.new(); input.delete_char(ctx)]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "\b")
end

T["undo point"] = function()
  init()
  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        ctx.vim_mode = "i"
        H.dispatch(ctx, "a")
        input.henkan_point(ctx)
        return ctx.preedit:output(ctx:to_string())
      end)()
    ]]),
    "あ\x07u▽"
  )
  -- cmdline では出さない
  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        ctx.vim_mode = "c"
        H.dispatch(ctx, "a")
        input.henkan_point(ctx)
        return ctx.preedit:output(ctx:to_string())
      end)()
    ]]),
    "あ▽"
  )
end

T["katakana input"] = function()
  init()
  local r = child.lua_get([[
    (function()
      local ctx = Context.new()
      local out = {}
      local function o() out[#out + 1] = ctx.preedit:output("") end
      mode.katakana(ctx)
      H.dispatch(ctx, "a"); o()
      mode.katakana(ctx)
      H.dispatch(ctx, "a"); o()

      -- 変換前
      mode.katakana(ctx)
      H.dispatch(ctx, "N")
      out[#out + 1] = ctx:to_string()
      -- そして確定
      common.kakutei(ctx); o()

      mode.katakana(ctx)
      -- 変換前の文字列を変換
      H.dispatch(ctx, "Hoge")
      mode.katakana(ctx); o()
      -- 半角カタカナモードから
      mode.hankatakana(ctx)
      H.dispatch(ctx, "Hoge")
      mode.katakana(ctx); o()
      mode.hankatakana(ctx)
      -- converter があるときは変換しない
      mode.katakana(ctx)
      H.dispatch(ctx, "Hoge")
      mode.katakana(ctx); o()
      return out
    end)()
  ]])
  eq(r, { "ア", "あ", "▽n", "ン", "ホゲ", "ホゲ", "ほげ" })
end

T["hankatakana input"] = function()
  init()
  local r = child.lua_get([[
    (function()
      local ctx = Context.new()
      local out = {}
      local function o() out[#out + 1] = ctx.preedit:output("") end
      mode.hankatakana(ctx)
      H.dispatch(ctx, "a"); o()
      mode.hankatakana(ctx)
      H.dispatch(ctx, "a"); o()
      -- カタカナモードから
      mode.katakana(ctx)
      mode.hankatakana(ctx)
      H.dispatch(ctx, "a"); o()
      -- 半角カタカナモードで katakana() するとひらがなに戻る
      mode.katakana(ctx)
      H.dispatch(ctx, "a"); o()

      -- 変換前
      mode.hankatakana(ctx)
      H.dispatch(ctx, "N")
      out[#out + 1] = ctx:to_string()
      -- そして確定
      common.kakutei(ctx); o()

      mode.hankatakana(ctx)
      -- 変換前の文字列を変換
      H.dispatch(ctx, "Hoge")
      mode.hankatakana(ctx); o()
      -- カタカナモードから
      mode.katakana(ctx)
      H.dispatch(ctx, "Hoge")
      mode.hankatakana(ctx); o()
      mode.katakana(ctx)
      -- converter があるときは変換しない
      mode.hankatakana(ctx)
      H.dispatch(ctx, "Hoge")
      mode.hankatakana(ctx); o()
      return out
    end)()
  ]])
  eq(r, { "ｱ", "あ", "ｱ", "あ", "▽n", "ﾝ", "ﾎｹﾞ", "ﾎｹﾞ", "ほげ" })
end

T["prefix and suffix"] = function()
  init()
  child.lua([[
    H.setup_library():register_henkan_result("okurinasi", "ぷれ>", "プレ>")
  ]])
  -- ">" を henkan_feed に積んでから変換すると接頭辞になる
  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        H.dispatch(ctx, ";")
        H.dispatch(ctx, "pure")
        input.prefix(ctx, ">")
        return { ctx.state.type, ctx.state.affix, ctx:to_string() }
      end)()
    ]]),
    { "henkan", "prefix", "▼プレ" }
  )
  -- 変換中でなければ普通の入力
  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        input.prefix(ctx, ">")
        return ctx.preedit:output("")
      end)()
    ]]),
    ">"
  )
end

T["prefix flushes pending romaji feed"] = function()
  init()
  child.lua([[
    H.setup_library():register_henkan_result("okurinasi", "おん>", "音>")
  ]])
  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        H.dispatch(ctx, ";on")
        input.prefix(ctx, ">")
        return { ctx.state.type, ctx.state.affix, ctx:to_string() }
      end)()
    ]]),
    { "henkan", "prefix", "▼音" }
  )
end

T["delete_char clears previous_feed when feed or okuri_feed is emptied"] = function()
  init()
  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        H.dispatch(ctx, ";sas;")
        local before = { ctx.state.mode, ctx.state.feed, ctx.state.previous_feed }
        input.delete_char(ctx)
        local after_drop_feed = { ctx.state.mode, ctx.state.feed, ctx.state.previous_feed }
        return { before, after_drop_feed }
      end)()
    ]]),
    { { "okuriari", "s", true }, { "okuriari", "", false } }
  )

  eq(
    child.lua_get([[
      (function()
        local ctx = Context.new()
        H.dispatch(ctx, ";sas;")
        ctx.state.feed = ""
        ctx.state.previous_feed = true
        ctx.state.okuri_feed = ""
        input.delete_char(ctx)
        return { ctx.state.mode, ctx.state.previous_feed }
      end)()
    ]]),
    { "okurinasi", false }
  )
end

return T

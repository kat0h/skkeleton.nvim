-- function/mode_test.ts（enable/disable を通す部分は E2E で扱う）
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
    input = require("skkeleton.function.input")
    mode = require("skkeleton.function.mode")
    kana = require("skkeleton.kana")
    store = require("skkeleton.store")
    H.spy_host()
  ]])
end

T["Can get skkeleton mode"] = function()
  init()
  child.lua([[ctx = Context.new()]])
  local steps = {
    { "katakana", "kata" },
    { "katakana", "hira" },
    { "hankatakana", "hankata" },
    { "zenkaku", "zenkaku" },
    { "hirakana", "hira" },
  }
  for _, s in ipairs(steps) do
    child.lua(("mode.%s(ctx)"):format(s[1]))
    eq(child.lua_get([[vim.g["skkeleton#mode"] ]]), s[2])
    eq(child.lua_get([[ctx.mode]]), s[2])
  end
end

T["Fire autocmd for mode changed"] = function()
  init()
  child.lua([[
    vim.api.nvim_create_autocmd("User", {
      pattern = "skkeleton-mode-changed",
      command = "let g:skkeleton#mode_actual = g:skkeleton#mode",
    })
    ctx = Context.new()
  ]])
  local steps = {
    { "katakana", "kata" },
    { "katakana", "hira" },
    { "hankatakana", "hankata" },
    { "zenkaku", "zenkaku" },
  }
  for _, s in ipairs(steps) do
    child.lua(("mode.%s(ctx)"):format(s[1]))
    eq(child.lua_get([[vim.g["skkeleton#mode_actual"] ]]), s[2])
  end
end

T["abbrev"] = function()
  init()
  child.lua([[ctx = Context.new()]])
  -- 確定するとモードが戻る
  child.lua([[mode.abbrev(ctx)]])
  eq(child.lua_get([[ctx.mode]]), "abbrev")
  child.lua([[common.kakutei(ctx)]])
  eq(child.lua_get([[ctx.mode]]), "hira")

  -- 文字を消すとモードが戻る
  child.lua([[mode.abbrev(ctx); input.delete_char(ctx)]])
  eq(child.lua_get([[ctx.mode]]), "hira")

  -- 大文字をちゃんと打てる
  child.lua([[mode.abbrev(ctx); input.kana_input(ctx, "A")]])
  eq(child.lua_get([[ctx:to_string()]]), "▽A")
  -- 確定したら元の状態に戻る
  child.lua([[common.kakutei(ctx); input.kana_input(ctx, "A")]])
  eq(child.lua_get([[ctx:to_string()]]), "▽あ")
end

T["abbrev keeps only henkan_first in the table"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    mode.abbrev(ctx)
  ]])
  eq(child.lua_get([[ctx.state.table:count()]]), 1)
  eq(child.lua_get([[ctx.state.table:find(" ") == require("skkeleton.function.henkan").henkan_first]]), true)
  eq(child.lua_get([[ctx.state.direct_input]]), true)
  eq(child.lua_get([[ctx.state.mode]]), "okurinasi")
end

T["abbrev: space converts the typed word"] = function()
  init()
  child.lua([[
    lib:register_henkan_result("okurinasi", "abc", "ABC")
    ctx = Context.new()
    mode.abbrev(ctx)
    H.dispatch(ctx, "abc ")
  ]])
  eq(child.lua_get([[ctx:to_string()]]), "▼ABC")
end

T["can convert okuri string properly when mode changed"] = function()
  init()
  child.lua([[lib:register_henkan_result("okuriari", "はg", "剥")]])
  child.lua([[ctx = Context.new(); mode.katakana(ctx); H.dispatch(ctx, ";ha;ge")]])
  eq(child.lua_get([[ctx:to_string()]]), "▼剥ゲ")
  child.lua([[common.kakutei(ctx)]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "剥ゲ")

  child.lua([[mode.hankatakana(ctx); H.dispatch(ctx, ";ha;ge")]])
  eq(child.lua_get([[ctx:to_string()]]), "▼剥ｹﾞ")
  child.lua([[common.kakutei(ctx)]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "剥ｹﾞ")
end

T["keepMode remembers the last mode"] = function()
  init()
  child.lua([[
    config.set({ keepMode = true })
    ctx = Context.new()
    mode.katakana(ctx)
  ]])
  eq(child.lua_get([[store.variables.last_mode]]), "kata")
  -- last_mode からモードを戻す（enable の中でやること）
  child.lua([[
    ctx = store.init_context()
    require("skkeleton.function").mode_functions[store.variables.last_mode](ctx, "")
  ]])
  eq(child.lua_get([[store.context().mode]]), "kata")
  child.lua([[mode.hirakana(store.context())]])
  eq(child.lua_get([[store.variables.last_mode]]), "hira")
end

T["last_mode stays when keepMode is off"] = function()
  init()
  child.lua([[ctx = Context.new(); mode.katakana(ctx)]])
  eq(child.lua_get([[store.variables.last_mode]]), "hira")
end

T["registerConvertResult registers katakana conversion"] = function()
  init()
  child.lua([[
    config.set({ registerConvertResult = true })
    ctx = Context.new()
    H.dispatch(ctx, ";hoge")
    mode.katakana(ctx)
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "ホゲ")
  eq(child.lua_get([[lib:get_henkan_result("okurinasi", "ほげ")]]), { "ホゲ" })
  eq(child.lua_get([[ctx.last_candidate]]), { type = "okurinasi", word = "ほげ", candidate = "ホゲ" })
end

T["hirakana resets converter and table"] = function()
  init()
  child.lua([[
    ctx = Context.new()
    mode.zenkaku(ctx)
  ]])
  eq(child.lua_get([[H.output("a")]]), "ａ") -- 新しい Context は今のテーブル（全角）を使う
  child.lua([[mode.hirakana(ctx)]])
  eq(child.lua_get([[kana.current_name]]), "rom")
  eq(child.lua_get([[ctx.state.table == kana.get_table("rom")]]), true)
end

T["zenkaku input"] = function()
  init()
  child.lua([[ctx = Context.new(); mode.zenkaku(ctx); H.dispatch(ctx, "aB1")]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "ａＢ１")
  eq(child.lua_get([[kana.current_name]]), "zen")
end

T["hankatakana from zenkaku goes back to the configured table"] = function()
  init()
  child.lua([[ctx = Context.new(); mode.zenkaku(ctx); mode.hankatakana(ctx); H.dispatch(ctx, "a")]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "ｱ")
  eq(child.lua_get([[kana.current_name]]), "rom")
end

return T

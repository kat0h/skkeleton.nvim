-- keymap_test.ts（`skkeleton#handle` を通さず handle_key を直接呼ぶ）
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    H = require("core_helpers")
    lib = H.setup_library()
    lib:register_henkan_result("okurinasi", "あ", "亜")
    lib:register_henkan_result("okurinasi", "われ", "我")
    lib:register_henkan_result("okuriari", "おもu", "思")
    Context = require("skkeleton.context")
    keymap = require("skkeleton.keymap")
    notation = require("skkeleton.notation")
    -- 未加工のキーを、skkeleton#handle と同じように正規化して handle_key に渡す
    press = function(ctx, keys)
      for _, k in ipairs(keys) do
        keymap.handle_key(ctx, notation.normalize(k))
      end
    end
    shown = function(keys)
      local ctx = Context.new()
      press(ctx, keys)
      return ctx:to_string()
    end
    H.spy_host()
  ]])
end

T["registerKeyMap"] = function()
  init()
  child.lua([[
    keymap.register("henkan", "x", "")
    keymap.register("henkan", notation.normalize("<BS>"), "henkanBackward")
  ]])

  -- "x" のマップを外したので、既定の処理（henkan_input -> 確定して入力）に戻る
  eq(child.lua_get([[shown({ "A", " ", "x" })]]), "x")

  -- <BS> で戻る
  eq(child.lua_get([[shown({ "A", " ", "<BS>" })]]), "▽あ")

  -- 大文字 1 文字のキーを登録する
  child.lua([[keymap.register("henkan", "B", "henkanBackward")]])
  eq(child.lua_get([[shown({ "A", " ", "B" })]]), "▽あ")

  -- 登録したキーマップを外す
  child.lua([[keymap.register("henkan", "B", nil)]])
  eq(child.lua_get([[shown({ "A", " ", "B" })]]), "▽b")
end

T["register with a function"] = function()
  init()
  child.lua([[
    called = {}
    keymap.register("input", "<c-t>", function(ctx, key) called[#called + 1] = key end)
    press(Context.new(), { "<C-t>" })
  ]])
  eq(child.lua_get([[called]]), { "\20" })
end

T["register errors"] = function()
  init()
  eq(child.lua_get([[select(2, pcall(keymap.register, "nothing", "a", "cancel"))]]), "unknown state: nothing")
  eq(child.lua_get([[select(2, pcall(keymap.register, "input", "a", "nothing"))]]), "unknown function: nothing")
end

T["send multiple keys into handle_key"] = function()
  init()
  eq(child.lua_get([[shown({ "W", "a", "r", "e" })]]), "▽われ")
  eq(child.lua_get([[shown({ "O", "m", "o", "U" })]]), "▼思う")
end

T["default keymap of input state"] = function()
  init()
  local cases = {
    { { "a", "<BS>" }, "" },
    { { "A", "k", "<C-h>" }, "▽あ" }, -- 1 つ目は feed を消す
    { { "A", "<C-g>" }, "" },
    { { "A", "<C-j>" }, "" },
  }
  for _, c in ipairs(cases) do
    eq(child.lua_get("shown(...)", { c[1] }), c[2])
  end
  -- ">" は変換中でなければ普通の入力
  child.lua([[out = function(keys) local c = Context.new(); press(c, keys); return c.preedit:output("") end]])
  eq(child.lua_get([[out({ ">" })]]), ">")
  -- <CR> と <C-j> は確定して、<CR> は改行を出す
  eq(child.lua_get([[out({ "a", "k", "<CR>" })]]), "あk\n")
  eq(child.lua_get([[out({ "a", "k", "<C-j>" })]]), "あk")
  -- <C-q> は半角カタカナ
  eq(child.lua_get([[out({ "<C-q>", "a" })]]), "ｱ")
  -- <Esc> は無効化して escape 状態になる
  child.lua([[ctx = Context.new(); press(ctx, { "<Esc>" })]])
  eq(child.lua_get([[ctx.state.type]]), "escape")
  eq(child.lua_get([[#H.called("disable")]]), 1)
end

T["default keymap of henkan state"] = function()
  init()
  eq(child.lua_get([[shown({ "A", "<Space>", "<Space>" })]]), "▼亜") -- 候補が尽きても戻らない（登録は取り消し）
  eq(child.lua_get([[shown({ "A", "<C-g>" })]]), "")
  eq(child.lua_get([[shown({ "A", "<Space>", "x" })]]), "▽あ")
  child.lua([[ctx = Context.new(); press(ctx, { "A", "<Space>", "<C-j>" })]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "亜")
  child.lua([[ctx = Context.new(); press(ctx, { "A", "<Space>", "<CR>" })]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "亜\n")
  -- X で見出しを消す
  child.lua([[H.ret.confirm = true; ctx = Context.new(); press(ctx, { "A", "<Space>", "X" })]])
  eq(child.lua_get([[#lib.purged]]), 1)
  eq(child.lua_get([[ctx.state.type]]), "input")
end

T["handle_key rejects illegal state"] = function()
  init()
  child.lua([[ctx = Context.new(); ctx.state.type = "escape"]])
  eq(child.lua_get([[select(2, pcall(keymap.handle_key, ctx, "a"))]]), "Illegal State: escape")
end

return T

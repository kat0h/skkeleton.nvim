-- state、context、store、host、candidate、okuri
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local function init()
  child.lua([[
    H = require("core_helpers")
    H.setup_library()
  ]])
end

T["state.initialize resets fields"] = function()
  init()
  child.lua([[
    state = require("skkeleton.state")
    st = state.initialize({})
  ]])
  eq(
    child.lua_get([[{ st.type, st.mode, st.direct_input, st.feed, st.henkan_feed, st.okuri_feed, st.previous_feed }]]),
    { "input", "direct", false, "", "", "", false }
  )
  eq(child.lua_get([[st.table == require("skkeleton.kana").get_table()]]), true)
end

T["state.initialize keeps ignored keys"] = function()
  init()
  child.lua([[
    state = require("skkeleton.state")
    conv = function(s) return s end
    st = { type = "henkan", mode = "okurinasi", feed = "k", henkan_feed = "あ", converter = conv, affix = "prefix" }
    state.initialize(st, { "converter" })
  ]])
  eq(child.lua_get([[{ st.type, st.mode, st.feed, st.henkan_feed, st.affix }]]), { "input", "direct", "", "" })
  eq(child.lua_get([[st.converter == conv]]), true)
  child.lua([[state.initialize(st)]])
  eq(child.lua_get([[st.converter]]), vim.NIL)
end

T["state.to_string"] = function()
  init()
  child.lua([[
    state = require("skkeleton.state")
    s = function(fields)
      local st = state.initialize({})
      for k, v in pairs(fields) do st[k] = v end
      return state.to_string(st)
    end
  ]])
  local cases = {
    { [[{ feed = "k" }]], "k" },
    { [[{ mode = "okurinasi", henkan_feed = "かん", feed = "j" }]], "▽かんj" },
    { [[{ mode = "okuriari", henkan_feed = "か", okuri_feed = "ん", feed = "j" }]], "▽か*んj" },
    { [[{ mode = "okuriari", henkan_feed = "や", feed = "t", previous_feed = true }]], "▽やt*" },
    { [[{ mode = "okurinasi", henkan_feed = "ほげ", converter = require("skkeleton.kana.hira_kata").hira_to_kata }]], "▽ホゲ" },
    { [[{ type = "henkan", candidates = { "変換;注釈" }, candidate_index = 0, okuri_feed = "った" }]], "▼変換った" },
    {
      [[{ type = "henkan", candidates = { "変換" }, candidate_index = 0, okuri_feed = "った", converter = function(x) return x .. "X" end }]],
      "▼変換ったX",
    },
    { [[{ type = "henkan", candidates = {}, candidate_index = 0 }]], "▼error" },
    { [[{ type = "henkan", candidates = { ">接頭" }, candidate_index = 0, affix = "suffix" }]], "▼接頭" },
    { [[{ type = "henkan", candidates = { "接頭>" }, candidate_index = 0, affix = "prefix" }]], "▼接頭" },
    { [[{ type = "escape" }]], "\27" },
  }
  for _, c in ipairs(cases) do
    eq(child.lua_get("s(" .. c[1] .. ")"), c[2])
  end
end

T["state.to_string follows config markers"] = function()
  init()
  child.lua([[
    require("skkeleton.config").set({ markerHenkan = "[", markerHenkanSelect = "<" })
    state = require("skkeleton.state")
  ]])
  eq(child.lua_get([[state.to_string({ type = "henkan", candidates = { "a" }, candidate_index = 0, okuri_feed = "" })]]), "<a")
end

T["candidate.modify"] = function()
  local candidate = require("skkeleton.candidate")
  eq(candidate.modify("注釈;これは注釈です"), "注釈")
  eq(candidate.modify("a>", "prefix"), "a")
  eq(candidate.modify(">a", "prefix"), ">a")
  eq(candidate.modify(">a", "suffix"), "a")
  eq(candidate.modify("a>", "suffix"), "a>")
  eq(candidate.modify(">a;x>", "suffix"), "a")
  eq(candidate.modify(nil), nil)
end

T["okuri.get_okuri_str"] = function()
  local okuri = require("skkeleton.okuri")
  local cases = {
    { "おく", "り", "おくr" },
    { "えら", "ん", "えらn" },
    { "うたが", "っ", "うたがt" },
    { "うたが", "っち", "うたがt" },
    { "す", "ぱ", "すp" },
    { "あ", "あ", "あa" },
    { "あ", "ぁ", "あx" },
    { "あ", "が", "あg" },
    { "あ", "じ", "あj" },
    { "あ", "を", "あw" },
    { "あ", "ゆ", "あy" },
  }
  for _, c in ipairs(cases) do
    eq(okuri.get_okuri_str(c[1], c[2]), c[3])
  end
end

T["context"] = function()
  init()
  child.lua([[
    ctx = require("skkeleton.context").new()
  ]])
  eq(child.lua_get([[{ ctx.mode, ctx.vim_mode, ctx.state.type, ctx.last_candidate.word, ctx:to_string() }]]), { "hira", "", "input", "", "" })
  -- undo point は insert モードだけ
  eq(
    child.lua_get([[
      (function()
        ctx.vim_mode = "i"
        ctx:kakutei_with_undo_point("あ")
        ctx.vim_mode = "c"
        ctx:kakutei_with_undo_point("い")
        ctx:kakutei("う")
        return ctx.preedit:output("")
      end)()
    ]]),
    "あ\x07uいう"
  )
  child.lua([[
    require("skkeleton.config").set({ setUndoPoint = false })
    ctx.vim_mode = "i"
    ctx:kakutei_with_undo_point("え")
  ]])
  eq(child.lua_get([[ctx.preedit:output("")]]), "え")
end

T["store"] = function()
  init()
  child.lua([[
    store = require("skkeleton.store")
    c1 = store.context()
  ]])
  eq(child.lua_get([[store.context() == c1]]), true)
  eq(child.lua_get([[store.init_context() ~= c1]]), true)
  eq(child.lua_get([[store.context() == store.context()]]), true)
  eq(child.lua_get([[store.variables.last_mode]]), "hira")
  eq(child.lua_get([[getmetatable(store.library()) == H.FakeLibrary]]), true)
end

T["host.mode_changed sets variable and fires User event"] = function()
  init()
  child.lua([[
    vim.api.nvim_create_autocmd("User", {
      pattern = "skkeleton-mode-changed",
      callback = function()
        events = events or {}
        events[#events + 1] = vim.g["skkeleton#mode"]
      end,
    })
    host = require("skkeleton.host")
    host.mode_changed("kata")
    host.mode_changed("hira")
  ]])
  eq(child.lua_get([[vim.g["skkeleton#mode"] ]]), "hira")
  eq(child.lua_get([[events]]), { "kata", "hira" })
end

T["host defaults do nothing"] = function()
  init()
  eq(child.lua_get([[require("skkeleton.host").input("p")]]), vim.NIL)
  eq(child.lua_get([[require("skkeleton.host").confirm("m")]]), false)
  eq(child.lua_get([[pcall(require("skkeleton.host").disable)]]), true)
  eq(child.lua_get([[pcall(require("skkeleton.host").show_candidates, { "a: b" })]]), true)
  eq(child.lua_get([[pcall(require("skkeleton.host").keep_state_on_insert_enter)]]), true)
end

return T

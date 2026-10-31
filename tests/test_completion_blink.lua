-- blink.cmp との結合と source のテスト
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local dict_text = table.concat({
  ";; -*- coding: utf-8 -*-",
  ";; okuri-ari entries.",
  "わるk /悪/",
  "かえr /帰/返/",
  "ならd /並/",
  ";; okuri-nasi entries.",
  "かん /缶/感/漢/幹/管/館/観/",
  "かんじ /漢字;kanji annotation/幹事;kanji secretary/感じ/",
  "ほげ /補外/",
  "にほん /日本/",
  "とうきょう /東京/",
  "abc /ＡＢＣ/",
}, "\n") .. "\n"

local T, child = helpers.e2e_set({ dict = dict_text })
local type = function(...)
  helpers.type(child, ...)
end

local function enable()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
end

-- =========================================================================
-- 1. completion オプションの検証
-- =========================================================================
T["options"] = MiniTest.new_set()

T["options"]["defaults"] = function()
  local opts = child.lua_get([[require("skkeleton.completion").options]])
  eq(opts, { enabled = true, minLength = 2 })
end

T["options"]["setup applies valid options"] = function()
  child.lua([[require("skkeleton").setup({ completion = { enabled = false, minLength = 4 } })]])
  local opts = child.lua_get([[require("skkeleton.completion").options]])
  eq(opts, { enabled = false, minLength = 4 })
end

T["options"]["setup with partial options fills in defaults"] = function()
  child.lua([[require("skkeleton").setup({ completion = { minLength = 3 } })]])
  eq(child.lua_get([[require("skkeleton.completion").options]]), { enabled = true, minLength = 3 })
  child.lua([[require("skkeleton").setup({ completion = { enabled = false } })]])
  eq(child.lua_get([[require("skkeleton.completion").options]]), { enabled = false, minLength = 2 })
end

T["options"]["setup rejects non-table completion"] = function()
  local res = child.lua_get([[(function()
    local ok, err = pcall(require("skkeleton").setup, { completion = "invalid" })
    return { ok = ok, err = ok and "" or tostring(err) }
  end)()]])
  eq(res.ok, false)
  eq(res.err:find("completion must be a table", 1, true) ~= nil, true)
end

T["options"]["setup rejects unknown completion keys"] = function()
  local res = child.lua_get([[(function()
    local ok, err = pcall(require("skkeleton").setup, { completion = { unknownKey = 1 } })
    return { ok = ok, err = ok and "" or tostring(err) }
  end)()]])
  eq(res.ok, false)
  eq(res.err:find("unknown completion option: unknownKey", 1, true) ~= nil, true)
end

T["options"]["setup rejects invalid types and values"] = function()
  child.lua([[
    _G.test_opt = function(val)
      local ok, err = pcall(require("skkeleton").setup, { completion = val })
      return ok and "" or tostring(err)
    end
  ]])
  local cases = {
    { [[{ enabled = "yes" }]], 'invalid completion.enabled: "yes"' },
    { [[{ enabled = 1 }]], "invalid completion.enabled: 1" },
    { [[{ minLength = "2" }]], 'invalid completion.minLength: "2"' },
    { [[{ minLength = 0 }]], "invalid completion.minLength: 0" },
    { [[{ minLength = -1 }]], "invalid completion.minLength: -1" },
    { [[{ minLength = 1.5 }]], "invalid completion.minLength: 1.5" },
  }
  for _, c in ipairs(cases) do
    local err = child.lua_get("_G.test_opt(" .. c[1] .. ")")
    eq(err:find(c[2], 1, true) ~= nil, true)
  end
end

T["options"]["setup preserves existing options on failure"] = function()
  child.lua([[
    require("skkeleton").setup({ completion = { enabled = true, minLength = 5 } })
    pcall(require("skkeleton").setup, { completion = { minLength = -1 } })
  ]])
  eq(child.lua_get([[require("skkeleton.completion").options]]), { enabled = true, minLength = 5 })
end

-- =========================================================================
-- 2. skkeleton.completion.blink source
-- =========================================================================
T["source"] = MiniTest.new_set()

T["source"]["new creates source instance with opts"] = function()
  local src = child.lua_get([[(function()
    local s = require("skkeleton.completion.blink").new({ foo = "bar" })
    return { has_mt = getmetatable(s) ~= nil, opts = s.opts }
  end)()]])
  eq(src.has_mt, true)
  eq(src.opts, { foo = "bar" })

  local src_default = child.lua_get([[(function()
    local s = require("skkeleton.completion.blink").new()
    return s.opts
  end)()]])
  eq(src_default, {})
end

T["source"]["enabled reflects input state and options"] = function()
  -- Not in insert mode
  eq(child.lua_get([[require("skkeleton.completion.blink"):enabled()]]), false)

  -- In insert mode, but skkeleton not enabled
  child.type_keys("i")
  eq(child.lua_get([[require("skkeleton.completion.blink"):enabled()]]), false)

  -- Enable skkeleton in insert mode, but no henkan feed
  type("<Plug>(skkeleton-enable)")
  eq(child.lua_get([[require("skkeleton.completion.blink"):enabled()]]), false)

  -- Okurinasi input state with henkan_feed
  type("Kan")
  eq(child.lua_get([[require("skkeleton.completion.blink"):enabled()]]), true)

  -- Leaving okurinasi input state via Space (into henkan state)
  type("<Space>")
  eq(child.lua_get([[require("skkeleton.completion.blink"):enabled()]]), false)

  -- When completion option is disabled
  type("<C-g>")
  type("Kan")
  eq(child.lua_get([[require("skkeleton.completion.blink"):enabled()]]), true)
  child.lua([[require("skkeleton.completion").options.enabled = false]])
  eq(child.lua_get([[require("skkeleton.completion.blink"):enabled()]]), false)
end

T["source"]["get_completions returns properly formatted items and handles annotations"] = function()
  enable()
  type("Kanj")

  local res = child.lua_get([[(function()
    local ctx = {
      get_keyword = function() return "kw" end,
      cursor = { 1, 5 },
    }
    local cb_response = nil
    local cancel = require("skkeleton.completion.blink"):get_completions(ctx, function(resp)
      cb_response = resp
    end)
    return {
      response = cb_response,
      has_cancel = type(cancel) == "function",
    }
  end)()]])

  eq(res.has_cancel, true)
  eq(res.response.is_incomplete_forward, true)
  eq(res.response.is_incomplete_backward, true)

  local items = res.response.items
  eq(#items, 3)

  -- Item 1: "漢字;kanji annotation" -> label "漢字", documentation with annotation
  eq(items[1], {
    label = "漢字",
    labelDetails = { description = "かんじ" },
    kind = 1,
    filterText = "kw",
    sortText = "000001",
    textEdit = {
      newText = "",
      range = {
        start = { line = 0, character = 5 },
        ["end"] = { line = 0, character = 5 },
      },
    },
    data = { skkeleton = true, kana = "かんじ", word = "漢字;kanji annotation" },
    documentation = { kind = "plaintext", value = "kanji annotation" },
  })

  -- Item 2: "幹事;kanji secretary"
  eq(items[2], {
    label = "幹事",
    labelDetails = { description = "かんじ" },
    kind = 1,
    filterText = "kw",
    sortText = "000002",
    textEdit = {
      newText = "",
      range = {
        start = { line = 0, character = 5 },
        ["end"] = { line = 0, character = 5 },
      },
    },
    data = { skkeleton = true, kana = "かんじ", word = "幹事;kanji secretary" },
    documentation = { kind = "plaintext", value = "kanji secretary" },
  })

  -- Item 3: "感じ" (without annotation) -> no documentation field
  eq(items[3].label, "感じ")
  eq(items[3].labelDetails, { description = "かんじ" })
  eq(items[3].documentation, nil)
  eq(items[3].data, { skkeleton = true, kana = "かんじ", word = "感じ" })
end

T["source"]["get_completions returns empty items outside pending state"] = function()
  enable()
  -- Not in okurinasi input state
  local res = child.lua_get([[(function()
    local ctx = { get_keyword = function() return "" end, cursor = { 1, 0 } }
    local items = nil
    require("skkeleton.completion.blink"):get_completions(ctx, function(resp)
      items = resp.items
    end)
    return items
  end)()]])
  eq(res, {})
end

T["source"]["execute calls skkeleton.complete and invokes callback"] = function()
  enable()
  type("Kanj")
  local called = child.lua_get([[(function()
    local item = {
      data = { skkeleton = true, kana = "かんじ", word = "漢字;kanji annotation" },
    }
    local cb_called = false
    require("skkeleton.completion.blink"):execute(nil, item, function()
      cb_called = true
    end)
    return cb_called
  end)()]])
  eq(called, true)
  helpers.settle(child)
  eq(helpers.buffer(child), { "漢字" })
  eq(helpers.preedit(child), "")
  -- Registered in user dictionary with annotation
  eq(
    child.lua_get([[require("skkeleton.store").library():get_henkan_result("okurinasi", "かんじ")[1] ]]),
    "漢字;kanji annotation"
  )
end

T["source"]["execute handles nil callback safely"] = function()
  enable()
  type("Kanj")
  child.lua([[(function()
    local item = {
      data = { skkeleton = true, kana = "かんじ", word = "漢字" },
    }
    require("skkeleton.completion.blink"):execute(nil, item, nil)
  end)()]])
  helpers.settle(child)
  eq(helpers.buffer(child), { "漢字" })
end

-- =========================================================================
-- 3. User skkeleton-handled による blink.show / blink.hide の自動発火
-- =========================================================================
T["auto_trigger"] = MiniTest.new_set()

local function setup_blink_mock()
  child.lua([[
    _G.blink_calls = {}
    package.loaded["blink.cmp"] = {
      show = function(opts)
        table.insert(_G.blink_calls, { "show", opts })
        return true
      end,
      hide = function()
        table.insert(_G.blink_calls, { "hide" })
      end,
      is_visible = function() return false end,
    }
    package.loaded["blink.cmp.config"] = {
      sources = {
        providers = {
          skkeleton = {
            name = "skkeleton",
            module = "skkeleton.completion.blink",
          },
        },
      },
    }
  ]])
end

T["auto_trigger"]["triggers show when henkan_feed reaches minLength"] = function()
  setup_blink_mock()
  enable()
  child.lua("_G.blink_calls = {}")

  -- 'Kan' -> henkan_feed: "か" (length 1 < minLength 2)
  type("Kan")
  local shows1 = child.lua_get([[(function()
    local res = {}
    for _, c in ipairs(_G.blink_calls) do
      if c[1] == "show" then table.insert(res, c) end
    end
    return res
  end)()]])
  eq(#shows1, 0)

  -- 'j' -> henkan_feed: "かん" (length 2 >= minLength 2)
  type("j")
  local last_call = child.lua_get("_G.blink_calls[#_G.blink_calls]")
  eq(last_call, { "show", { providers = { "skkeleton" } } })
end

T["auto_trigger"]["re-triggers on feed change and ignores identical key"] = function()
  setup_blink_mock()
  enable()
  child.lua("_G.blink_calls = {}")
  type("Kanj")
  local count1 = child.lua_get([[(function()
    local n = 0
    for _, c in ipairs(_G.blink_calls) do
      if c[1] == "show" then n = n + 1 end
    end
    return n
  end)()]])
  eq(count1, 1)

  -- Firing skkeleton-handled with identical key does not re-invoke blink.show
  child.lua([[vim.api.nvim_exec_autocmds("User", { pattern = "skkeleton-handled" })]])
  local count2 = child.lua_get([[(function()
    local n = 0
    for _, c in ipairs(_G.blink_calls) do
      if c[1] == "show" then n = n + 1 end
    end
    return n
  end)()]])
  eq(count2, 1)

  -- Typing 'i' changes feed to 'かんじ' -> triggers blink.show again
  type("i")
  local count3 = child.lua_get([[(function()
    local n = 0
    for _, c in ipairs(_G.blink_calls) do
      if c[1] == "show" then n = n + 1 end
    end
    return n
  end)()]])
  eq(count3, 2)
end

T["auto_trigger"]["calls hide when leaving okurinasi input via Space"] = function()
  setup_blink_mock()
  enable()
  type("Kanj")
  child.lua("_G.blink_calls = {}")
  type("<Space>")
  local last = child.lua_get("_G.blink_calls[#_G.blink_calls]")
  eq(last, { "hide" })
end

T["auto_trigger"]["calls hide when cancelling via C-g"] = function()
  setup_blink_mock()
  enable()
  type("Kanj")
  child.lua("_G.blink_calls = {}")
  type("<C-g>")
  local last = child.lua_get("_G.blink_calls[#_G.blink_calls]")
  eq(last, { "hide" })
end

T["auto_trigger"]["calls hide when backspacing below minLength"] = function()
  setup_blink_mock()
  enable()
  type("Kanj")
  child.lua("_G.blink_calls = {}")
  -- 'Kanj' had henkan_feed 'かん', feed 'j'.
  -- <BS> removes 'j', leaving 'かん' (length 2)
  type("<BS>")
  -- Another <BS> removes 'ん', leaving 'か' (length 1 < 2)
  type("<BS>")
  local last = child.lua_get("_G.blink_calls[#_G.blink_calls]")
  eq(last, { "hide" })
end

T["auto_trigger"]["respects custom minLength"] = function()
  child.lua([[require("skkeleton").setup({ completion = { minLength = 1 } })]])
  setup_blink_mock()
  enable()
  child.lua("_G.blink_calls = {}")
  -- Typing 'Ka' results in henkan_feed: "か" (length 1 >= 1)
  type("Ka")
  local last = child.lua_get("_G.blink_calls[#_G.blink_calls]")
  eq(last, { "show", { providers = { "skkeleton" } } })
end

T["auto_trigger"]["does nothing when completion is disabled"] = function()
  child.lua([[require("skkeleton").setup({ completion = { enabled = false } })]])
  setup_blink_mock()
  enable()
  child.lua("_G.blink_calls = {}")
  type("Kanji")
  eq(child.lua_get("#_G.blink_calls"), 0)
end

T["auto_trigger"]["does nothing without error when blink is not loaded or configured"] = function()
  -- blink not loaded
  child.lua([[
    package.loaded["blink.cmp"] = nil
    package.loaded["blink.cmp.config"] = nil
  ]])
  enable()
  type("Kanji")
  eq(helpers.preedit(child), "▽かんじ")

  -- blink loaded but provider not in config
  child.lua([[
    package.loaded["blink.cmp"] = { show = function() error("should not be called") end, hide = function() end }
    package.loaded["blink.cmp.config"] = { sources = { providers = {} } }
  ]])
  type("<BS>ji")
  eq(helpers.preedit(child), "▽かんじ")
end

-- =========================================================================
-- 4. eggLikeNewline = true での <CR> による blink.accept
-- =========================================================================
T["egg_like_newline"] = MiniTest.new_set()

local function setup_blink_accept_mock(opts)
  opts = opts or {}
  child.lua(
    [[
    local opts = ...
    _G.accepted = false
    _G.is_visible_val = opts.visible ~= false
    _G.selected_item = opts.item
    if _G.selected_item == nil and opts.no_item ~= true then
      _G.selected_item = {
        source_id = "skkeleton",
        data = { skkeleton = true, kana = "かんじ", word = "漢字;kanji annotation" },
      }
    end
    package.loaded["blink.cmp"] = {
      is_visible = function() return _G.is_visible_val end,
      is_menu_visible = function() return _G.is_visible_val end,
      get_selected_item = function() return _G.selected_item end,
      accept = function()
        _G.accepted = true
        require("skkeleton.completion.blink"):execute(nil, _G.selected_item, function() end)
        return true
      end,
      hide = function() end,
      show = function() return true end,
    }
    package.loaded["blink.cmp.config"] = {
      sources = {
        providers = {
          skkeleton = {
            name = "skkeleton",
            module = "skkeleton.completion.blink",
          },
        },
      },
    }
    if opts.explicitly_selected ~= nil then
      package.loaded["blink.cmp.completion.list"] = {
        is_explicitly_selected = opts.explicitly_selected,
      }
    else
      package.loaded["blink.cmp.completion.list"] = nil
    end
  ]],
    { opts }
  )
end

T["egg_like_newline"]["accepts selected item on CR with eggLikeNewline = true"] = function()
  child.lua([[require("skkeleton.config").set({ eggLikeNewline = true })]])
  setup_blink_accept_mock()
  enable()
  type("Kanj")
  type("<CR>")
  eq(child.lua_get("_G.accepted"), true)
  eq(helpers.buffer(child), { "漢字" })
  eq(helpers.preedit(child), "")
end

T["egg_like_newline"]["does not call blink.accept when eggLikeNewline = false"] = function()
  child.lua([[require("skkeleton.config").set({ eggLikeNewline = false })]])
  setup_blink_accept_mock()
  enable()
  type("Kanj")
  type("<CR>")
  eq(child.lua_get("_G.accepted"), false)
  -- skkeleton standard <CR> commits pre-edit and inserts a newline
  eq(helpers.buffer(child), { "かんj", "" })
end

T["egg_like_newline"]["does not call blink.accept when blink is not visible"] = function()
  child.lua([[require("skkeleton.config").set({ eggLikeNewline = true })]])
  setup_blink_accept_mock({ visible = false })
  enable()
  type("Kanj")
  type("<CR>")
  eq(child.lua_get("_G.accepted"), false)
  eq(helpers.buffer(child), { "かんj" })
end

T["egg_like_newline"]["does not call blink.accept when no item is selected"] = function()
  child.lua([[require("skkeleton.config").set({ eggLikeNewline = true })]])
  setup_blink_accept_mock({ no_item = true })
  enable()
  type("Kanj")
  type("<CR>")
  eq(child.lua_get("_G.accepted"), false)
  eq(helpers.buffer(child), { "かんj" })
end

T["egg_like_newline"]["does not call blink.accept when selected item is not from skkeleton"] = function()
  child.lua([[require("skkeleton.config").set({ eggLikeNewline = true })]])
  setup_blink_accept_mock({
    item = { source_id = "lsp", data = { something_else = true } },
  })
  enable()
  type("Kanj")
  type("<CR>")
  eq(child.lua_get("_G.accepted"), false)
  eq(helpers.buffer(child), { "かんj" })
end

T["egg_like_newline"]["does not call blink.accept when item is only preselected"] = function()
  child.lua([[require("skkeleton.config").set({ eggLikeNewline = true })]])
  setup_blink_accept_mock({ explicitly_selected = false })
  enable()
  type("Kanj")
  type("<CR>")
  eq(child.lua_get("_G.accepted"), false)
  eq(helpers.buffer(child), { "かんj" })
end

-- =========================================================================
-- 5. 3 段階補完候補ソート (skkeleton.completion.sort)
-- =========================================================================
T["sort"] = MiniTest.new_set()

T["sort"]["sorts by reading length, user rank, and dictionary order"] = function()
  local res = child.lua_get([[(function()
    local sort = require("skkeleton.completion.sort")
    local input = {
      { "かんじ", { "漢字", "幹事", "感じ" } },
      { "かん", { "缶", "感", "漢" } },
      { "か", { "蚊", "課" } },
    }
    local ranks = {
      ["感じ"] = 10,
      ["漢字"] = 5,
      ["感"] = 2,
    }
    return sort.sort_completions(input, ranks)
  end)()]])

  -- 1st level: length of reading (shorter first) -> "か" (len 1), then "かん" (len 2), then "かんじ" (len 3)
  -- Within "か": dict order (蚊, then 課)
  eq(res[1], { kana = "か", word = "蚊", rank = 0, kana_len = 1, dict_order = 7 })
  eq(res[2], { kana = "か", word = "課", rank = 0, kana_len = 1, dict_order = 8 })

  -- Within "かん": user rank first ("感" has rank 2, others 0), then dict order ("缶", then "漢")
  eq(res[3].kana, "かん")
  eq(res[3].word, "感")
  eq(res[3].rank, 2)
  eq(res[4].kana, "かん")
  eq(res[4].word, "缶")
  eq(res[5].kana, "かん")
  eq(res[5].word, "漢")

  -- Within "かんじ": user rank ("感じ" rank 10 > "漢字" rank 5 > "幹事" rank 0)
  eq(res[6].kana, "かんじ")
  eq(res[6].word, "感じ")
  eq(res[6].rank, 10)
  eq(res[7].kana, "かんじ")
  eq(res[7].word, "漢字")
  eq(res[7].rank, 5)
  eq(res[8].kana, "かんじ")
  eq(res[8].word, "幹事")
  eq(res[8].rank, 0)
end

T["sort"]["deduplicates by kana and word while preserving first appearance"] = function()
  local res = child.lua_get([[(function()
    local sort = require("skkeleton.completion.sort")
    local input = {
      { "かん", { "缶", "感", "缶" } },
      { "かん", { "缶", "漢" } },
    }
    return sort.sort_completions(input, {})
  end)()]])

  eq(#res, 3)
  eq(res[1].word, "缶")
  eq(res[2].word, "感")
  eq(res[3].word, "漢")
end

-- =========================================================================
-- 6. nvim-cmp source (skkeleton.completion.cmp)
-- =========================================================================
T["cmp_source"] = MiniTest.new_set()

T["cmp_source"]["source methods and properties"] = function()
  local info = child.lua_get([[(function()
    local cmp_mod = require("skkeleton.completion.cmp")
    local s = cmp_mod.new({ test = 1 })
    return {
      encoding = s:get_PositionEncodingKind(),
      triggers = s:get_trigger_characters(),
      keyword_pattern = s:get_keyword_pattern(),
      is_available = s:is_available(),
      opts = s.opts,
    }
  end)()]])

  eq(info.encoding, "utf-8")
  eq(info.triggers, {})
  eq(_G.type(info.keyword_pattern), "string")
  eq(info.is_available, false)
  eq(info.opts, { test = 1 })
end

T["cmp_source"]["complete returns 3-level sorted items with annotations"] = function()
  enable()
  type("Kanj")

  local res = child.lua_get([[(function()
    local s = require("skkeleton.completion.cmp").new()
    local result = nil
    s:complete({}, function(resp)
      result = resp
    end)
    return result
  end)()]])

  eq(res.isIncomplete, true)
  local items = res.items
  eq(#items, 3)
  eq(items[1].label, "漢字")
  eq(items[1].detail, "かんじ")
  eq(items[1].sortText, "000001")
  eq(items[1].documentation, { kind = "plaintext", value = "kanji annotation" })
  eq(items[1].data, { skkeleton = true, kana = "かんじ", word = "漢字;kanji annotation" })

  eq(items[2].label, "幹事")
  eq(items[2].sortText, "000002")
  eq(items[2].documentation, { kind = "plaintext", value = "kanji secretary" })

  eq(items[3].label, "感じ")
  eq(items[3].sortText, "000003")
  eq(items[3].documentation, nil)
end

T["cmp_source"]["execute registers word in user dictionary"] = function()
  enable()
  type("Kanj")

  child.lua([[(function()
    local s = require("skkeleton.completion.cmp").new()
    local item = {
      data = { skkeleton = true, kana = "かんじ", word = "漢字;kanji annotation" },
    }
    s:execute(item, function() end)
  end)()]])

  eq(
    child.lua_get([[require("skkeleton.store").library():get_henkan_result("okurinasi", "かんじ")[1] ]]),
    "漢字;kanji annotation"
  )
end

T["cmp_source"]["register safely calls cmp.register_source"] = function()
  local registered = child.lua_get([[(function()
    local recorded = nil
    package.loaded["cmp"] = {
      register_source = function(name, src)
        recorded = { name = name, has_src = src ~= nil }
      end,
    }
    require("skkeleton.completion.cmp").register()
    return recorded
  end)()]])

  eq(registered, { name = "skkeleton", has_src = true })
end

-- =========================================================================
-- 7. completefunc support (skkeleton.completion.native)
-- =========================================================================
T["native_completefunc"] = MiniTest.new_set()

T["native_completefunc"]["findstart returns -3 when disabled or no prefix"] = function()
  local res1 = child.lua_get([[require("skkeleton.completion").completefunc(1, "")]])
  eq(res1, -3)

  enable()
  local res2 = child.lua_get([[require("skkeleton.completion").completefunc(1, "")]])
  eq(res2, -3)
end

T["native_completefunc"]["findstart returns byte col and findstart 0 returns candidates"] = function()
  enable()
  type("Kanj")

  local start_col = child.lua_get([[require("skkeleton.completion").completefunc(1, "")]])
  eq(_G.type(start_col), "number")
  eq(start_col >= 0, true)

  local items = child.lua_get([[require("skkeleton.completion").completefunc(0, "かん")]])
  eq(#items, 3)
  eq(items[1].word, "漢字")
  eq(items[1].abbr, "漢字")
  eq(items[1].menu, "かんじ")
  eq(items[1].info, "kanji annotation")
  eq(items[1].user_data, { skkeleton = { kana = "かんじ", word = "漢字;kanji annotation" } })

  eq(items[2].word, "幹事")
  eq(items[2].info, "kanji secretary")

  eq(items[3].word, "感じ")
  eq(items[3].info, "")
end

T["native_completefunc"]["CompleteDone cleans up state and registers in user dictionary"] = function()
  enable()
  type("Kanj")
  eq(helpers.preedit(child), "▽かんj")

  child.lua([[(function()
    vim.v.completed_item = {
      word = "漢字",
      user_data = {
        skkeleton = {
          kana = "かんじ",
          word = "漢字;kanji annotation",
        },
      },
    }
    vim.api.nvim_exec_autocmds("CompleteDone", {})
  end)()]])

  helpers.settle(child)
  eq(helpers.preedit(child), "")
  eq(
    child.lua_get([[require("skkeleton.store").library():get_henkan_result("okurinasi", "かんじ")[1] ]]),
    "漢字;kanji annotation"
  )
end

T["native_completefunc"]["preserves preceding and succeeding text when completing with completefunc"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("Kanj")
  eq(helpers.preedit(child), "▽かんj")

  -- findstart returns cursor column (2) without subtracting pre_edit
  local start_col = child.lua_get([[require("skkeleton.completion").completefunc(1, "")]])
  eq(start_col, 2)

  -- completefunc による実際の補完実行
  child.lua([[vim.bo.completefunc = "v:lua.require'skkeleton.completion'.completefunc"]])
  type("<C-x><C-u>")
  eq(child.lua_get("vim.fn.pumvisible()"), 1)
  type("<C-y>")
  helpers.settle(child)

  eq(helpers.buffer(child), { "ab漢字 cd" })
  eq(helpers.preedit(child), "")
end

-- =========================================================================
-- 8. Converter application on completion
-- =========================================================================
T["converter"] = MiniTest.new_set()

T["converter"]["complete applies converter when present on state"] = function()
  enable()
  type("Kanj")

  child.lua([[(function()
    local ctx = require("skkeleton.store").context()
    ctx.state.converter = function(s)
      return s == "" and "" or ("<<" .. s .. ">>")
    end
    require("skkeleton").complete("かんじ", "感じ")
  end)()]])

  helpers.settle(child)
  eq(helpers.buffer(child), { "<<感じ>>" })
  eq(helpers.preedit(child), "")
end

return T

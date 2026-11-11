-- 1 打鍵あたりにインジケータのウィンドウを作り直していないこと (#25)
-- 作り直すと、画面では一瞬消えて出る（フリッカー）ように見える
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set({ config = { indicator = {} } })
local type = function(...)
  helpers.type(child, ...)
end

-- インジケータの open / close を数える。子の nvim で包む
local function count_calls()
  child.lua([[
    _G.indicator_calls = {}
    local ind = require("skkeleton.indicator.indicator")
    for _, name in ipairs({ "open", "close" }) do
      if not ind["_orig_" .. name] then
        ind["_orig_" .. name] = ind[name]
        ind[name] = function(self, ...)
          table.insert(_G.indicator_calls, name)
          return ind["_orig_" .. name](self, ...)
        end
      end
    end
    _G.indicator_calls = {}
  ]])
end

local function calls()
  return child.lua_get([[_G.indicator_calls]])
end

T["typing a reading does not rebuild the indicator on every key"] = function()
  child.lua([[require("skkeleton").setup({ indicator = {} })]])
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("k")
  count_calls()
  type("a")
  type("n")
  eq(calls(), {})
end

T["choosing a candidate does not rebuild the indicator on every key"] = function()
  child.lua([[require("skkeleton").setup({ indicator = {} })]])
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space>")
  count_calls()
  type("<Space>")
  eq(calls(), {})
end

-- render.update / render.finish を数える。子の nvim で包む
local function count_render()
  child.lua([[
    _G.render_calls = {}
    local render = require("skkeleton.render")
    for _, name in ipairs({ "update", "finish" }) do
      if not render["_orig_" .. name] then
        render["_orig_" .. name] = render[name]
        render[name] = function(...)
          table.insert(_G.render_calls, name)
          return render["_orig_" .. name](...)
        end
      end
    end
    _G.render_calls = {}
  ]])
end

local function render_calls()
  return child.lua_get([[_G.render_calls]])
end

-- 1 打鍵で描き直すのは update と finish が 1 回ずつまで。
-- 同じ状態を 2 回描くと、画面では同じフレームが続けて出る（フリッカー）
local function expect_one_draw(keys)
  count_render()
  type(keys)
  eq(render_calls(), { "update", "finish" })
end

T["typing a reading draws once per key"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  for _, key in ipairs({ "k", "a", "n" }) do
    expect_one_draw(key)
  end
end

T["choosing a candidate draws once per key"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space>")
  expect_one_draw("<Space>")
  expect_one_draw("<C-j>")
end

-- 辞書登録の input() の中でも 1 打鍵 1 回。cmdline に pre-edit を書くので
-- BS での書き直しは出るが、描き直しは 1 回で足りる
T["typing in the dictionary prompt draws once per key"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  -- 辞書に無い読みで <Space> を押すと辞書登録の input() に入る
  type("Yomi<Space>")
  eq(child.fn.mode(), "c")
  eq(child.fn.getcmdline(), "")
  for _, key in ipairs({ "y", "o", "m", "i" }) do
    expect_one_draw(key)
  end
  -- <CR> で抜けるときは cmdline を片付ける描画と、元の insert に戻る描画で
  -- 2 回になる。どちらも別の状態なので冗長ではない
  count_render()
  type("<CR>")
  eq(render_calls(), { "update", "finish", "update", "finish" })
  eq(helpers.buffer(child), { "よみ" })
end

return T

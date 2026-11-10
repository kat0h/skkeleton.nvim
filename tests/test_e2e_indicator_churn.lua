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

return T

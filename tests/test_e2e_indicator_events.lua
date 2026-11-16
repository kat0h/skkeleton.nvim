-- 1 打鍵あたりの User イベントの回数 (#178)
-- インジケータは skkeleton-handled を受けて描き直すので、打鍵ごとに何度も出ると
-- 描き直しもその回数だけ走る
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set({ config = { indicator = {} } })
local type = function(...)
  helpers.type(child, ...)
end

-- User イベントを数える。1 打鍵ぶんだけ数えたいので、打つ前に空にする
local function count_events()
  child.lua([[
    _G.user_events = {}
    if not _G.user_events_attached then
      _G.user_events_attached = true
      vim.api.nvim_create_autocmd("User", {
        pattern = "*",
        callback = function(ev) table.insert(_G.user_events, ev.match) end,
      })
    end
    _G.user_events = {}
  ]])
end

local function events()
  return child.lua_get([[_G.user_events]])
end

T["one keystroke emits skkeleton-handled once"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  for _, key in ipairs({ "k", "a", "n" }) do
    count_events()
    type(key)
    eq(events(), { "skkeleton-handled" })
  end
end

T["choosing a candidate emits skkeleton-handled once"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space>")
  count_events()
  type("<Space>")
  eq(events(), { "skkeleton-handled" })
end

return T

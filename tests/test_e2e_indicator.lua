-- pre-edit が伸び縮みしても、インジケータが画面上のカーソルに付いてくることを確かめる
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set({ config = { indicator = {} } })
local type = function(...)
  helpers.type(child, ...)
end

local function start()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
end

-- インジケータのウィンドウの画面上の { 行, 列 }（0 起点）、カーソルの { 行, 列 }（0 起点）、幅
local function positions()
  return child.lua_get([[(function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= "" and not vim.w[w].skkeleton_popup then
        return {
          float = vim.api.nvim_win_get_position(w),
          cursor = { vim.fn.screenrow() - 1, vim.fn.screencol() - 1 },
          width = cfg.width,
          columns = vim.o.columns,
        }
      end
    end
  end)()]])
end

-- インジケータはカーソルの 1 行下、col オプション（既定 1）だけ右にある
local function expect_follows()
  local p = positions()
  eq(p.float, { p.cursor[1] + 1, p.cursor[2] + 1 })
end

T["follows the preedit while typing"] = function()
  start()
  expect_follows()
  for _, k in ipairs({ "K", "a", "n", "j", "i" }) do
    type(k)
    expect_follows()
  end
end

T["follows when the preedit shrinks by <BS>"] = function()
  start()
  type("Kanji")
  type("<BS>")
  eq(helpers.preedit(child), "▽かん")
  expect_follows()
  type("<BS><BS>")
  expect_follows()
  type("<BS>")
  eq(helpers.preedit(child), "")
  expect_follows()
end

T["follows when the preedit is confirmed"] = function()
  start()
  type("Kanji<C-j>")
  eq(helpers.buffer(child), { "かんじ" })
  expect_follows()
end

T["follows the conversion"] = function()
  start()
  type("Kanji<Space>")
  eq(helpers.preedit(child), "▼漢字")
  expect_follows()
  type("<Space>")
  eq(helpers.preedit(child), "▼幹事")
  expect_follows()
  type("<C-g>")
  expect_follows()
  type("<C-j>")
  expect_follows()
end

T["follows in the middle of a line"] = function()
  start()
  type("ab<Left>Kanji")
  eq(helpers.preedit(child), "▽かんじ")
  expect_follows()
end

T["stays on the screen when the preedit passes the right edge"] = function()
  child.o.columns = 30
  start()
  type(("a"):rep(26))
  type("Kanji")
  local p = positions()
  assert(p.float[2] >= 0 and p.float[2] + p.width <= p.columns, vim.inspect(p))
end

return T

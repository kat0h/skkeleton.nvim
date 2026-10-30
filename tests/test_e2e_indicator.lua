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

-- 枠も含めたインジケータの { 行, 列, 高さ, 幅 }（0 起点）と、カーソルの { 行, 列 }（0 起点）
local function rect(c)
  return c.lua_get([[(function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= "" and not vim.w[w].skkeleton_popup then
        local pos = vim.api.nvim_win_get_position(w)
        local b = (cfg.border and cfg.border ~= "none") and 1 or 0
        -- win_get_position は枠を含めた左上
        return {
          float = { pos[1], pos[2], cfg.height + 2 * b, cfg.width + 2 * b },
          cursor = { vim.fn.screenrow() - 1, vim.fn.screencol() - 1 },
        }
      end
    end
  end)()]])
end

local function hides_cursor(r)
  local f, c = r.float, r.cursor
  return c[1] >= f[1] and c[1] < f[1] + f[3] and c[2] >= f[2] and c[2] < f[2] + f[4]
end

-- #16: 枠つき（row の既定が 0）で右端のとき、押し戻されてカーソルを隠さない
local R, rchild = helpers.e2e_set({ config = { indicator = { style = "rounded" } } })
T["rounded"] = R
R["does not cover the cursor at the right edge"] = function()
  rchild.o.columns = 80
  rchild.api.nvim_buf_set_lines(0, 0, -1, false, { ("x"):rep(74) })
  rchild.type_keys("A")
  helpers.type(rchild, "<Plug>(skkeleton-enable)")
  for _, k in ipairs({ "K", "a", "n" }) do
    helpers.type(rchild, k)
    local r = rect(rchild)
    eq(hides_cursor(r), false, r)
    eq(r.float[2] >= 0 and r.float[2] + r.float[4] <= 80, true, r)
  end
  eq(helpers.preedit(rchild), "▽かn")
end

R["sits right after the preedit when it fits"] = function()
  rchild.o.columns = 80
  rchild.type_keys("i")
  helpers.type(rchild, "<Plug>(skkeleton-enable)")
  helpers.type(rchild, "Kan")
  local r = rect(rchild)
  -- 枠つきは row = 0、col = 1。左上がカーソルの 1 つ下ではなくカーソルの行に重なるので、下へ逃がす
  eq(hides_cursor(r), false, r)
  eq(r.float[2], r.cursor[2] + 1)
end

-- #21: pre-edit が次の画面の行へ折り返したら、インジケータもその行に付く
local W, wchild = helpers.e2e_set({ config = { indicator = {} } })
T["wrap"] = W
W["follows the preedit wrapped onto the next screen line"] = function()
  wchild.o.columns = 40
  wchild.api.nvim_buf_set_lines(0, 0, -1, false, { ("w"):rep(36) })
  wchild.type_keys("A")
  helpers.type(wchild, "<Plug>(skkeleton-enable)")
  helpers.type(wchild, "Kan")
  local r = rect(wchild)
  -- pre-edit ▽かn（6 桁）は 37 桁目から折り返して 2 行目に入る
  eq(r.cursor[1], 1)
  eq(r.float, { 2, r.cursor[2] + 1, 1, r.float[4] })
end

-- #23: カーソルの直後がタブでも、インジケータはカーソルの位置に付く
local B, bchild = helpers.e2e_set({ config = { indicator = {} } })
T["tab"] = B
B["is placed at the cursor, not after the tab"] = function()
  bchild.api.nvim_buf_set_lines(0, 0, -1, false, { "ab\t cd" })
  bchild.api.nvim_win_set_cursor(0, { 1, 2 })
  bchild.type_keys("i")
  helpers.settle(bchild)
  -- insert に入った直後（relative = "cursor" で開いていた位置）
  local r = rect(bchild)
  eq(r.float[2], 2 + 1)
  helpers.type(bchild, "<Plug>(skkeleton-enable)")
  r = rect(bchild)
  eq(r.float[2], 2 + 1)
  helpers.type(bchild, "Kan")
  r = rect(bchild)
  eq(r.cursor[2], 2 + 4)
  eq(r.float[2], 2 + 4 + 1)
end

T["is closed when insert is left with <C-c> (#27)"] = function()
  start()
  eq(positions() ~= nil, true)
  type("<C-c>")
  helpers.settle(child)
  eq(child.fn.mode(), "n")
  eq(positions(), vim.NIL)
end

T["is closed when insert is left with <C-c> without enabling skkeleton (#27)"] = function()
  child.type_keys("i")
  helpers.settle(child)
  eq(positions() ~= nil, true)
  type("<C-c>")
  helpers.settle(child)
  eq(child.fn.mode(), "n")
  eq(positions(), vim.NIL)
end

T["reopens when returning from replace to insert with <Insert> (#38)"] = function()
  start()
  eq(positions() ~= nil, true)
  type("<Insert>")
  eq(child.fn.mode(), "R")
  eq(positions(), vim.NIL)
  type("<Insert>")
  eq(child.fn.mode(), "i")
  eq(positions() ~= nil, true)
  expect_follows()
end

T["reopens when returning from replace to insert with <Insert> without enabling skkeleton (#38)"] = function()
  child.type_keys("i")
  helpers.settle(child)
  eq(positions() ~= nil, true)
  type("<Insert>")
  eq(child.fn.mode(), "R")
  eq(positions(), vim.NIL)
  type("<Insert>")
  eq(child.fn.mode(), "i")
  eq(positions() ~= nil, true)
end

T["follows cursor on window scroll (#30)"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3", "line 4", "line 5" })
  child.api.nvim_win_set_cursor(0, { 2, 6 })
  start()
  local before = positions()
  eq(before ~= nil, true)
  type("<C-x><C-e>")
  helpers.settle(child)
  local after = positions()
  eq(after ~= nil, true)
  eq(after.float[1], before.float[1] - 1)
end

T["follows cursor before tab with list and virtualedit (#35)"] = function()
  child.api.nvim_ui_attach(80, 24, {})
  child.cmd("set list listchars=tab:>-,trail:~,eol:$ virtualedit=all")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "a\tb  c " })
  child.api.nvim_win_set_cursor(0, { 1, 1 })
  start()
  type("n")
  helpers.settle(child)

  -- 画面上は pre-edit "n" が "a" とタブの間に表示される
  local sline = child.lua_get([[(function()
    local s = ""
    for c = 1, 10 do s = s .. vim.fn.screenstring(1, c) end
    return s
  end)()]])
  eq(sline:sub(1, 8), "an>-----")

  -- virtualedit 下で Neovim は端末カーソルを pre-edit 先頭セルに置くが、
  -- インジケータは実際の端末カーソル位置に追従する
  expect_follows()
end

return T

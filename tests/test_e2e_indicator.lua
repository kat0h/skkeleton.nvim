-- インジケータは出した位置を追いかけない。入力が始まったとき、出した位置からカーソルが
-- 動いたとき、cmdline で最初の変化があったときに消えることを確かめる
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

-- インジケータの画面上の { 行, 列 }（0 起点）、カーソルの { 行, 列 }（0 起点）、幅
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

local function is_shown()
  return positions() ~= vim.NIL
end

T["shows at the cursor's lower right when insert starts"] = function()
  start()
  local p = positions()
  eq(p.float, { p.cursor[1] + 1, p.cursor[2] + 1 })
end

T["closes when the pre-edit appears"] = function()
  start()
  eq(is_shown(), true)
  type("k")
  eq(helpers.preedit(child), "k")
  eq(is_shown(), false)
end

T["closes when the pre-edit appears with a conversion marker"] = function()
  start()
  type("Kan")
  eq(helpers.preedit(child), "▽かn")
  eq(is_shown(), false)
end

T["closes when a character is committed"] = function()
  start()
  type("a")
  eq(helpers.buffer(child), { "あ" })
  eq(is_shown(), false)
end

T["closes when a character is typed without skkeleton"] = function()
  type("i")
  eq(is_shown(), true)
  type("a")
  eq(is_shown(), false)
end

T["stays after entering insert with o and closes when a character is typed"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
  type("o")
  eq(is_shown(), true)
  type("x")
  eq(is_shown(), false)
end

T["closes when the cursor moves from the position it was shown at"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  type("i")
  eq(is_shown(), true)
  type("<Right>")
  eq(is_shown(), false)
end

T["shows after a mode change confirms the pre-edit"] = function()
  start()
  type("Kan")
  eq(is_shown(), false)
  type("L")
  eq(helpers.mode(child), "zenkaku")
  eq(is_shown(), true)
  local p = positions()
  eq(p.float, { p.cursor[1] + 1, p.cursor[2] + 1 })
end

T["is closed when insert is left with <C-c> (#27)"] = function()
  start()
  eq(is_shown(), true)
  type("<C-c>")
  eq(child.fn.mode(), "n")
  eq(is_shown(), false)
end

T["is closed when insert is left with <C-c> without enabling skkeleton (#27)"] = function()
  type("i")
  eq(is_shown(), true)
  type("<C-c>")
  eq(child.fn.mode(), "n")
  eq(is_shown(), false)
end

T["reopens when returning from replace to insert with <Insert> (#38)"] = function()
  start()
  eq(is_shown(), true)
  type("<Insert>")
  eq(child.fn.mode(), "R")
  eq(is_shown(), false)
  type("<Insert>")
  eq(child.fn.mode(), "i")
  eq(is_shown(), true)
end

T["reopens when returning from replace to insert with <Insert> without enabling skkeleton (#38)"] = function()
  type("i")
  eq(is_shown(), true)
  type("<Insert>")
  eq(child.fn.mode(), "R")
  eq(is_shown(), false)
  type("<Insert>")
  eq(child.fn.mode(), "i")
  eq(is_shown(), true)
end

T["closes on the first change in cmdline"] = function()
  child.type_keys(":")
  eq(is_shown(), true)
  type("a")
  eq(is_shown(), false)
  type("<Esc>")
end

return T

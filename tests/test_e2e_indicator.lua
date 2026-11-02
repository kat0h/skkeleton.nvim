-- インジケータは、出したあとに入力が始まるかカーソルが動くと消える (#63)
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

-- インジケータの画面上の位置と、カーソルの位置（すべて 0 起点）
local function positions()
  return child.lua_get([[(function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= "" and not vim.w[w].skkeleton_popup then
        return {
          float = vim.api.nvim_win_get_position(w),
          cursor = { vim.fn.screenrow() - 1, vim.fn.screencol() - 1 },
        }
      end
    end
  end)()]])
end

-- カーソルの右下（既定の row = 1、col = 1）に出ている
local function expect_at_cursor()
  local p = positions()
  eq(p.float, { p.cursor[1] + 1, p.cursor[2] + 1 })
end

T["shows the mode at the cursor when insert starts"] = function()
  child.type_keys("i")
  helpers.settle(child)
  eq(helpers.indicator(child).text, "Aa")
  expect_at_cursor()

  -- 文字が入ったら閉じる
  child.type_keys("x")
  helpers.settle(child)
  eq(positions(), vim.NIL)
end

T["stays after entering insert with A or o"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("A")
  helpers.settle(child)
  eq(positions() ~= nil, true)

  child.type_keys("<Esc>o")
  helpers.settle(child)
  eq(positions() ~= nil, true)
end

T["closes when the cursor moves from where it was shown"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("i")
  helpers.settle(child)
  eq(positions() ~= nil, true)

  type("<Right>")
  eq(positions(), vim.NIL)
end

T["closes when the preedit starts"] = function()
  start()
  eq(positions() ~= nil, true)

  type("K")
  eq(helpers.preedit(child) ~= "", true)
  eq(positions(), vim.NIL)
end

T["clears the preedit when leaving cmdline with <C-r>="] = function()
  start()
  type("<C-r>=")
  eq(positions() ~= nil, true)

  type("Kan")
  eq(positions(), vim.NIL)

  type("<Esc>")
  eq(child.g["skkeleton#state"].preedit, "")
  eq(positions() ~= nil, true)
end

T["clears the preedit when leaving cmdline with <C-c> from <C-r>="] = function()
  start()
  type("<C-r>=")
  type("Kan")
  eq(positions(), vim.NIL)

  -- <C-c> は skkeleton が奪わないので、handle を通らずに cmdline を抜ける
  child.type_keys("<C-c>")
  helpers.settle(child)
  eq(child.fn.mode(), "i")
  eq(child.g["skkeleton#state"].preedit, "")
  eq(positions() ~= nil, true)
end

T["does not show on a mode change while the preedit remains"] = function()
  start()
  type("Kan")
  eq(positions(), vim.NIL)
  eq(child.g["skkeleton#state"].preedit ~= "", true)

  child.g["skkeleton#mode"] = "kata"
  child.lua("vim.api.nvim_exec_autocmds('User', { pattern = 'skkeleton-mode-changed' })")
  helpers.settle(child)
  eq(positions(), vim.NIL)
end

T["shows on a mode change after the preedit is confirmed"] = function()
  start()
  type("Kan<C-j>")
  eq(helpers.buffer(child), { "かん" })
  eq(positions(), vim.NIL)

  type("q")
  eq(helpers.mode(child), "kata")
  eq(positions() ~= nil, true)
  eq(helpers.indicator(child).text, "ア")
end

T["closes on the first CmdlineChanged"] = function()
  child.type_keys(":")
  helpers.settle(child)
  eq(positions() ~= nil, true)

  child.type_keys("a")
  helpers.settle(child)
  eq(positions(), vim.NIL)

  child.type_keys("<Esc>")
end

T["updates the mode in the middle of cmdline"] = function()
  child.type_keys(":")
  helpers.settle(child)
  eq(helpers.indicator(child).text, "Aa")

  child.g["skkeleton#mode"] = "hira"
  child.lua("vim.api.nvim_exec_autocmds('User', { pattern = 'skkeleton-mode-changed' })")
  helpers.settle(child)
  eq(helpers.indicator(child).text, "あ")

  child.type_keys("<Esc>")
end

T["is closed when insert is left with <C-c> (#27)"] = function()
  start()
  eq(positions() ~= nil, true)
  type("<C-c>")
  eq(child.fn.mode(), "n")
  eq(positions(), vim.NIL)
end

T["is closed when insert is left with <C-c> without enabling skkeleton (#27)"] = function()
  child.type_keys("i")
  helpers.settle(child)
  eq(positions() ~= nil, true)
  type("<C-c>")
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
  expect_at_cursor()
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

T["opens at the cursor when returning from visual to insert (#47)"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3" })
  start()
  helpers.settle(child)

  -- visual モードに入る（選択）
  child.type_keys("<Esc>", "v")
  helpers.settle(child)
  eq(child.fn.mode(), "v")
  eq(positions(), vim.NIL)

  -- visual から c で insert に戻る際、ModeChanged の直後にカーソルが動く
  child.lua([[
    vim.api.nvim_create_autocmd("ModeChanged", {
      pattern = "v:i",
      once = true,
      callback = function()
        vim.api.nvim_win_set_cursor(0, { 3, 4 })
      end,
    })
  ]])
  child.type_keys("c")
  helpers.settle(child)
  eq(child.fn.mode(), "i")
  eq(positions() ~= nil, true)
  expect_at_cursor()
end

T["does not show after text is inserted right after insert starts"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("Afoo")
  helpers.settle(child)
  eq(helpers.buffer(child), { "hellofoo" })
  eq(positions(), vim.NIL)
end

return T

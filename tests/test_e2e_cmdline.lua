-- cmdline と terminal では、BS で消して書き直す
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function enable_in_cmdline()
  child.type_keys(":")
  type("<Plug>(skkeleton-enable)")
end

T["hiragana"] = function()
  enable_in_cmdline()
  type("kana")
  eq(child.fn.getcmdline(), "かな")
  eq(helpers.mode(child), "hira")
end

T["pre-edit is written in the command line"] = function()
  enable_in_cmdline()
  type("Kan")
  eq(child.fn.getcmdline(), "▽かn")
  type("<Space>")
  eq(child.fn.getcmdline(), "▼缶")
  type("<C-j>")
  eq(child.fn.getcmdline(), "缶")
end

T["okuri-ari"] = function()
  enable_in_cmdline()
  type("KaeRu")
  eq(child.fn.getcmdline(), "▼帰る")
  type("<C-j>")
  eq(child.fn.getcmdline(), "帰る")
end

T["the text in front of the cursor is kept"] = function()
  child.type_keys(":", "abc")
  type("<Plug>(skkeleton-enable)")
  type("Ka")
  eq(child.fn.getcmdline(), "abc▽か")
  type("<C-g>")
  eq(child.fn.getcmdline(), "abc")
end

T["candidate popup is shown above the command line"] = function()
  enable_in_cmdline()
  type("Kan<Space><Space><Space><Space><Space>")
  eq(child.fn.getcmdline(), "▼管")
  eq(helpers.popup(child), { "a: 管", "s: 館", "d: 観" })
  type("a")
  eq(child.fn.getcmdline(), "管")
  eq(helpers.popup(child), vim.NIL)
end

T["a command typed with skkeleton runs"] = function()
  enable_in_cmdline()
  type("<Plug>(skkeleton-disable)")
  type("let g:x = '")
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space><C-j>")
  type("<Plug>(skkeleton-disable)")
  type("'<CR>")
  eq(child.g.x, "缶")
end

T["<CR> confirms and runs the command line"] = function()
  child.type_keys(":")
  -- " 以降はコメントなので、確定した文字に改行が続いて実行される
  type([[let g:y = 1 "]])
  type("<Plug>(skkeleton-enable)")
  type("Kan<Space>")
  eq(child.fn.getcmdline(), [[let g:y = 1 "▼缶]])
  type("<CR>")
  eq(child.fn.mode(), "n")
  eq(child.g.y, 1)
end

T["<Esc> leaves the command line"] = function()
  enable_in_cmdline()
  type("Ka")
  type("<Esc>")
  eq(child.fn.mode(), "n")
  eq(child.g["skkeleton#enabled"], false)
end

T["the pre-edit is dropped when the command line is edited behind skkeleton"] = function()
  enable_in_cmdline()
  type("Ka")
  eq(child.fn.getcmdline(), "▽か")
  -- skkeleton を通らない編集（<C-u>）
  child.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-u>", true, true, true), "nt", false)
  helpers.settle(child)
  eq(child.fn.getcmdline(), "")
  type("ka")
  eq(child.fn.getcmdline(), "か")
end

T["terminal"] = function()
  child.cmd("terminal cat")
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  eq(child.g["skkeleton#enabled"], true)
  type("Kan<Space><C-j>")
  type("<CR>")
  -- cat が書き戻した行が端末のバッファに出る
  local found = child.lua_get([[(function()
    vim.wait(2000, function()
      return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("缶", 1, true) ~= nil
    end, 20)
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("缶", 1, true) ~= nil
  end)()]])
  eq(found, true)
end

return T

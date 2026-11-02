local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()

T["splits undo block on paste in active insert mode"] = function()
  child.type_keys("i")
  helpers.type(child, "<Plug>(skkeleton-enable)")
  helpers.type(child, "a")
  eq(helpers.buffer(child), { "あ" })

  child.lua([[vim.paste({ "貼り付け" }, -1)]])
  eq(helpers.buffer(child), { "あ貼り付け" })

  child.type_keys("<Esc>", "u")
  helpers.settle(child)
  -- 貼り付けた分だけが消え、前に打った文字は残る
  eq(helpers.buffer(child), { "あ" })

  child.type_keys("u")
  helpers.settle(child)
  eq(helpers.buffer(child), { "" })
end

T["does not split undo block when setUndoPointOnPaste is false"] = function()
  child.lua([[require("skkeleton.config").set({ setUndoPointOnPaste = false })]])
  child.type_keys("i")
  helpers.type(child, "<Plug>(skkeleton-enable)")
  helpers.type(child, "a")
  eq(helpers.buffer(child), { "あ" })

  child.lua([[vim.paste({ "貼り付け" }, -1)]])
  eq(helpers.buffer(child), { "あ貼り付け" })

  child.type_keys("<Esc>", "u")
  helpers.settle(child)
  -- 1 回の u で全部消える
  eq(helpers.buffer(child), { "" })
end

T["does not split undo block when skkeleton is disabled"] = function()
  child.type_keys("i")
  helpers.type(child, "hello")
  eq(helpers.buffer(child), { "hello" })

  child.lua([[vim.paste({ " world" }, -1)]])
  eq(helpers.buffer(child), { "hello world" })

  child.type_keys("<Esc>", "u")
  helpers.settle(child)
  eq(helpers.buffer(child), { "" })
end

T["does not split undo block in normal mode"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "first" })
  child.type_keys("o", "second")
  helpers.settle(child)
  child.type_keys("<Esc>")
  helpers.settle(child)

  -- normal モードで貼り付け（カーソル位置の直後に挿入される）
  child.lua([[vim.paste({ "third" }, -1)]])
  eq(helpers.buffer(child), { "first", "secondthird" })

  child.type_keys("u")
  helpers.settle(child)
  eq(helpers.buffer(child), { "first", "second" })
end

T["preserves buffer-local undolevels state (-123456 and explicit value)"] = function()
  child.type_keys("i")
  helpers.type(child, "<Plug>(skkeleton-enable)")

  -- 1. グローバル値を継承している状態 (-123456)
  local local_ul_before = child.lua_get([[vim.api.nvim_get_option_value("undolevels", { scope = "local", buf = 0 })]])
  eq(local_ul_before, -123456)

  child.lua([[vim.paste({ "test" }, -1)]])

  local local_ul_after = child.lua_get([[vim.api.nvim_get_option_value("undolevels", { scope = "local", buf = 0 })]])
  eq(local_ul_after, -123456)

  -- 2. バッファローカルに特定の値が設定されている状態
  child.lua([[vim.bo.undolevels = 50]])
  child.lua([[vim.paste({ "test2" }, -1)]])
  local local_ul_explicit = child.lua_get([[vim.api.nvim_get_option_value("undolevels", { scope = "local", buf = 0 })]])
  eq(local_ul_explicit, 50)
end

T["calls original vim.paste and preserves result and multi-line behavior"] = function()
  child.type_keys("i")
  helpers.type(child, "<Plug>(skkeleton-enable)")

  local res = child.lua_get([[vim.paste({ "line1", "line2" }, -1)]])
  eq(res, true)
  eq(helpers.buffer(child), { "line1", "line2" })

  child.type_keys("<Esc>", "u")
  helpers.settle(child)
  eq(helpers.buffer(child), { "" })
end

T["splits undo during pre-edit without changing existing behavior"] = function()
  child.type_keys("i")
  helpers.type(child, "<Plug>(skkeleton-enable)")
  helpers.type(child, "a") -- "あ" を入力
  eq(helpers.buffer(child), { "あ" })

  helpers.type(child, "Ka") -- 変換中 "▽か"
  eq(helpers.preedit(child), "▽か")

  child.lua([[vim.paste({ "abc" }, -1)]])
  helpers.settle(child)
  -- 貼り付けた文字列がバッファに入る
  eq(helpers.buffer(child), { "あabc" })

  -- u で貼った分 "abc" が消え、前に打った "あ" は残る
  child.type_keys("<Esc>", "u")
  helpers.settle(child)
  eq(helpers.buffer(child), { "あ" })

  child.type_keys("u")
  helpers.settle(child)
  eq(helpers.buffer(child), { "" })
end

T["splits undo before first chunk only in streaming paste (phase 1, 2, 3)"] = function()
  child.type_keys("i")
  helpers.type(child, "<Plug>(skkeleton-enable)")
  helpers.type(child, "a")
  eq(helpers.buffer(child), { "あ" })

  child.lua([[vim.paste({ "chunk1" }, 1)]])
  child.lua([[vim.paste({ "chunk2" }, 2)]])
  child.lua([[vim.paste({ "chunk3" }, 3)]])
  eq(helpers.buffer(child), { "あchunk1chunk2chunk3" })

  child.type_keys("<Esc>", "u")
  helpers.settle(child)
  -- 全チャンクが 1 回の u で消え、前の入力は残る
  eq(helpers.buffer(child), { "あ" })

  child.type_keys("u")
  helpers.settle(child)
  eq(helpers.buffer(child), { "" })
end

return T

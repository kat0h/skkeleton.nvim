-- マクロの再生中も、guard は pre-edit を確定してからキーを流す (#216)
--
-- 記録したマクロを @a で流すと、Vim がレジスタのキーを流すので vim.on_key の typed は
-- 空になる。guard がこれを feedkeys と同じ扱いにすると、<S-Tab> が読みを確定せず、
-- バッファが変わったあとに読みが捨てられる。
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()

-- レジスタ a に「有効化 → Kan → <S-Tab> → <Esc>」を入れる。
-- ヘッドレスでは q の記録が入力待ちで止まるので、レジスタを直接書いて再生だけを見る。
local function replay()
  child.lua([[
    local keys = vim.api.nvim_replace_termcodes("<Plug>(skkeleton-enable)Kan<S-Tab><Esc>", true, true, true)
    vim.fn.setreg("a", "A" .. keys, "v")
  ]])
  child.type_keys("@a")
  child.lua([[vim.wait(300)]])
end

T["replayed macro commits the pre-edit before a guard key (#216)"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd", "ef gh" })
  child.api.nvim_win_set_cursor(0, { 2, 4 })
  replay()
  -- 読みが確定して入る（<S-Tab> のタブは別の課題として #216 に残す）
  eq(helpers.buffer(child), { "ab cd", "ef ghかん" })
end

return T

-- Ported from skkeleton (plugin/skkeleton.vim)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
if vim.g.loaded_skkeleton then
  return
end
vim.g.loaded_skkeleton = true

-- 参照用の変数。ステータスラインやインジケータが読む
if vim.g["skkeleton#enabled"] == nil then
  vim.g["skkeleton#enabled"] = false
end
if vim.g["skkeleton#mode"] == nil then
  vim.g["skkeleton#mode"] = ""
end
if vim.g["skkeleton#state"] == nil then
  vim.g["skkeleton#state"] = { phase = "", henkanFeed = "" }
end

for _, name in ipairs({ "enable", "disable", "toggle" }) do
  vim.keymap.set({ "i", "c", "t" }, ("<Plug>(skkeleton-%s)"):format(name), function()
    require("skkeleton")[name]()
  end, { desc = "skkeleton " .. name })
end

-- 'iminsert' の lmap が空だと enable が失敗することがあるため、ダミーを置く
vim.cmd("lnoremap <Plug>(skkeleton-dummy) :")

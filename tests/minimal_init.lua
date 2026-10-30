-- テストのための最小の設定。親（ランナー）と子（MiniTest.new_child_neovim）の両方がこれを読む
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end

vim.opt.runtimepath = { vim.env.VIMRUNTIME, root, mini }
vim.opt.packpath = {}
-- テストから require("helpers") で tests/helpers.lua を読めるようにする
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile = false
vim.o.shada = ""
-- テストが書く辞書やキャッシュを手元の環境と分ける
vim.env.XDG_CACHE_HOME = root .. "/.tests/cache"
vim.env.XDG_STATE_HOME = root .. "/.tests/state"

-- plugin/ 以下を読む（--noplugin でも -u のあとに明示すれば読める）
vim.cmd("runtime! plugin/skkeleton.lua")

require("mini.test").setup({
  collect = {
    find_files = function()
      return vim.fn.globpath(root .. "/tests", "**/test_*.lua", true, true)
    end,
  },
})

-- テストの共通部分。キー入力のドライバ（type/buffer/preedit/...）は第 2 波で足す
local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
M.testdata = M.root .. "/tests/testdata"

-- 子の nvim を使うテストの set を作る。ケースごとに子を作り直すので状態が漏れない
---@return table set, table child
function M.child_set(opts)
  local child = MiniTest.new_child_neovim()
  local set = MiniTest.new_set(vim.tbl_deep_extend("force", {
    hooks = {
      pre_case = function()
        child.restart({ "-u", M.root .. "/tests/minimal_init.lua" })
      end,
      post_once = child.stop,
    },
  }, opts or {}))
  return set, child
end

return M

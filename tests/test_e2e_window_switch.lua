-- 変換中（▽読み・▼候補）に別ウィンドウ/タブへ移っても pre-edit を保持する (#169)
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function two_windows()
  child.cmd("botright new")
  child.cmd("wincmd p")
end

local function enable()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
end

-- バッファを指定して pre-edit（extmark の virt_text）の文字列を取る
local function preedit_in(buf)
  return child.lua_get(
    [[(function(buf)
      local ns = vim.api.nvim_get_namespaces()["skkeleton-preedit"]
      local text = ""
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        for _, chunk in ipairs(m[4].virt_text or {}) do
          text = text .. chunk[1]
        end
      end
      return text
    end)(...)]],
    { buf }
  )
end

local function state_preedit()
  return child.lua_get([[vim.g["skkeleton#state"] and vim.g["skkeleton#state"].preedit or ""]])
end

T["<C-o>:wincmd w keeps the reading (▽) (#169)"] = function()
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji")
  eq(helpers.preedit(child), "▽かんじ")
  type("<C-o>:wincmd w<CR>")
  eq(preedit_in(buf), "▽かんじ")
  eq(state_preedit(), "▽かんじ")
  eq(child.g["skkeleton#enabled"], true)
end

T["<C-o>:wincmd w keeps the candidate (▼) (#169)"] = function()
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji<Space>")
  eq(helpers.preedit(child), "▼漢字")
  type("<C-o>:wincmd w<CR>")
  eq(preedit_in(buf), "▼漢字")
  eq(state_preedit(), "▼漢字")
  eq(child.g["skkeleton#enabled"], true)
end

T["<C-o>:tabnext keeps the reading (▽) (#169)"] = function()
  child.cmd("tabnew")
  child.cmd("tabprevious")
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji")
  type("<C-o>:tabnext<CR>")
  eq(preedit_in(buf), "▽かんじ")
  eq(state_preedit(), "▽かんじ")
  eq(child.g["skkeleton#enabled"], true)
end

T["<C-o>:stopinsert keeps the candidate (▼) (#169)"] = function()
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji<Space>")
  type("<C-o>:stopinsert<CR>")
  eq(child.fn.mode(), "n")
  eq(preedit_in(buf), "▼漢字")
  eq(state_preedit(), "▼漢字")
  eq(child.g["skkeleton#enabled"], true)
end

T["<C-o><C-w>w without cmdline keeps the reading (#169)"] = function()
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji")
  type("<C-o><C-w>w")
  eq(preedit_in(buf), "▽かんじ")
  eq(state_preedit(), "▽かんじ")
  eq(child.g["skkeleton#enabled"], true)
end

T["mouse click to another window keeps the reading (#169)"] = function()
  child.cmd("set mouse=a")
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji")
  -- 別ウィンドウをクリックする（マウスでウィンドウを移る動き）
  child.api.nvim_input_mouse("left", "press", "", 0, 10, 1)
  child.api.nvim_input_mouse("left", "release", "", 0, 10, 1)
  helpers.settle(child)
  eq(preedit_in(buf), "▽かんじ")
  eq(state_preedit(), "▽かんじ")
  eq(child.g["skkeleton#enabled"], true)
end

T["<C-o>:enew drops the pre-edit because the buffer is left (#169)"] = function()
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji")
  type("<C-o>:enew<CR>")
  eq(preedit_in(buf), "")
  eq(state_preedit(), "")
end

T["<C-o>:edit <file> drops the pre-edit because the buffer is left (#169)"] = function()
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  local f = vim.fn.tempname()
  child.lua("vim.fn.writefile({ 'x' }, ...)", { f })
  enable()
  type("Kanji")
  type("<C-o>:edit " .. f .. "<CR>")
  eq(preedit_in(buf), "")
  eq(state_preedit(), "")
end

T["returning to the window continues the input (#169)"] = function()
  two_windows()
  local buf = child.api.nvim_get_current_buf()
  enable()
  type("Kanji")
  type("<C-o>:wincmd w<CR>")
  eq(preedit_in(buf), "▽かんじ")
  -- 元のウィンドウに戻って続きを打つ
  type("<C-o>:wincmd p<CR>")
  eq(helpers.preedit(child), "▽かんじ")
  type("<Space>")
  eq(helpers.preedit(child), "▼漢字")
end

return T

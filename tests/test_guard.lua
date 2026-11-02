-- 未マップの特殊キーの判定 (#56)
local guard = require("skkeleton.guard")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

---@param notation string
---@return string
local function tc(notation)
  return vim.api.nvim_replace_termcodes(notation, true, true, true)
end

T["physical special keys are detected"] = function()
  for _, notation in ipairs({ "<C-.>", "<S-CR>", "<Left>", "<F5>", "<C-Left>" }) do
    eq(guard._is_physical_special(tc(notation)), true)
  end
end

T["Ctrl with a letter is not a special key"] = function()
  for _, notation in ipairs({ "<C-r>", "<C-k>", "<C-n>", "<C-\\>", "<C-c>" }) do
    eq(guard._is_physical_special(tc(notation)), false)
  end
end

T["text and escaped bytes are not special keys"] = function()
  eq(guard._is_physical_special("a"), false)
  eq(guard._is_physical_special("あ"), false)
  -- KS_SPECIAL (0x80 0xfe) は本文中の 0x80 のエスケープ
  eq(guard._is_physical_special("\128\254X"), false)
end

return T

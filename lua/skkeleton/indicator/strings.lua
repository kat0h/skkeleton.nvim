-- Ported from skkeleton_indicator.nvim (lua/skkeleton_indicator/strings.lua)
-- Copyright (c) 2021 Yasushi Jinnouchi, zlib license (see LICENSES/skkeleton_indicator.nvim.txt)
-- Modified for skkeleton.nvim: モジュール名を変更し、vim.iter を使わない形に書き直した。

-- camelCase を snake_case にする（"fadeOutMs" -> "fade_out_ms"）
---@param str string
---@return string
local function snake_case(str)
  local s = str:gsub("(%u+)(%u%l)", "%1_%2")
  s = s:gsub("([%l%d])(%u)", "%1_%2")
  return s:lower()
end

-- キーをすべて snake_case にした新しいテーブルを返す
---@param orig table<string, any>
---@return table<string, any>
local function snake_case_dict(orig)
  local acc = {}
  for key, value in pairs(orig) do
    acc[snake_case(key)] = value
  end
  return acc
end

return { snake_case = snake_case, snake_case_dict = snake_case_dict }

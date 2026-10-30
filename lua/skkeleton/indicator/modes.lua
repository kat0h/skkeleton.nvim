-- Ported from skkeleton_indicator.nvim (lua/skkeleton_indicator/modes.lua)
-- Copyright (c) 2021 Yasushi Jinnouchi, zlib license (see LICENSES/skkeleton_indicator.nvim.txt)
-- Modified for skkeleton.nvim: モードを g:skkeleton#mode から読む。

local config = require("skkeleton.indicator.config")

---@alias skkeleton.IndicatorModeName "eiji"|"hira"|"kata"|"hankata"|"zenkaku"|"abbrev"

---@class skkeleton.IndicatorMode
---@field text string
---@field hl_name string
---@field name skkeleton.IndicatorModeName
---@field width integer
local Mode = {
  -- colorscheme が無いとき（または未定義のとき）に使う既定の色
  default_hl = {
    dark = {
      eiji = { fg = "NvimLightBlue", bg = "NvimDarkGrey2", ctermfg = "blue", ctermbg = "black", bold = true },
      hira = { fg = "NvimDarkGrey2", bg = "NvimLightGreen", ctermfg = "black", ctermbg = "green", bold = true },
      kata = { fg = "NvimDarkGrey2", bg = "NvimLightYellow", ctermfg = "black", ctermbg = "yellow", bold = true },
      hankata = { fg = "NvimDarkGrey2", bg = "NvimLightMagenta", ctermfg = "black", ctermbg = "magenta", bold = true },
      zenkaku = { fg = "NvimLightGrey2", bg = "NvimDarkCyan", ctermfg = "black", ctermbg = "cyan", bold = true },
      abbrev = { fg = "NvimLightGrey2", bg = "NvimDarkRed", ctermfg = "white", ctermbg = "red", bold = true },
    },
    light = {
      eiji = { fg = "NvimDarkBlue", bg = "NvimLightGrey2", ctermfg = "blue", ctermbg = "white", bold = true },
      hira = { fg = "NvimDarkGrey2", bg = "NvimLightGreen", ctermfg = "white", ctermbg = "green", bold = true },
      kata = { fg = "NvimDarkGrey2", bg = "NvimLightYellow", ctermfg = "white", ctermbg = "yellow", bold = true },
      hankata = { fg = "NvimDarkGrey2", bg = "NvimLightMagenta", ctermfg = "white", ctermbg = "magenta", bold = true },
      zenkaku = { fg = "NvimDarkGrey2", bg = "NvimLightBlue", ctermfg = "black", ctermbg = "blue", bold = true },
      abbrev = { fg = "NvimDarkGrey2", bg = "NvimLightRed", ctermfg = "black", ctermbg = "red", bold = true },
    },
  },
}
Mode.__index = Mode

-- 設定から 1 つのモードを作り、ハイライトグループを定義する
---@param name skkeleton.IndicatorModeName
---@return skkeleton.IndicatorMode
function Mode.new(name)
  local self = setmetatable({ name = name, hl_name = config[name .. "_hl_name"], text = config[name .. "_text"] }, Mode)
  self.width = vim.fn.strdisplaywidth(self.text)
  local hl = vim.api.nvim_get_hl(0, { name = self.hl_name })
  local is_default_colorscheme = not vim.g.colors_name
  if vim.tbl_isempty(hl) or (is_default_colorscheme and config.use_default_highlight) then
    hl = Mode.default_hl[vim.o.background][name]
  end
  vim.api.nvim_set_hl(0, self.hl_name, hl)
  return self
end

---@class skkeleton.IndicatorModes
---@field modes table<skkeleton.IndicatorModeName, skkeleton.IndicatorMode>
local Modes = {}
Modes.__index = Modes

---@return skkeleton.IndicatorModes
function Modes.new()
  local modes = {}
  for _, name in ipairs({ "eiji", "hira", "kata", "hankata", "zenkaku", "abbrev" }) do
    modes[name] = Mode.new(name)
  end
  return setmetatable({ modes = modes }, Modes)
end

---@return boolean
function Modes.is_insert()
  return vim.api.nvim_get_mode().mode:find("i") ~= nil
end

-- g:skkeleton#mode から今のモードを引く。空や未知の名前は英字にする
---@return skkeleton.IndicatorMode
function Modes:detect()
  return self.modes[vim.g["skkeleton#mode"]] or self.modes.eiji
end

return Modes

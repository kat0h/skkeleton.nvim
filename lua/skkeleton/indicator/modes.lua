-- Ported from skkeleton_indicator.nvim (lua/skkeleton_indicator/modes.lua)
-- Copyright (c) 2021 Yasushi Jinnouchi, zlib license (see LICENSES/skkeleton_indicator.nvim.txt)
-- Modified for skkeleton.nvim: モードを g:skkeleton#mode から読む。

local config = require("skkeleton.indicator.config")

---@alias skkeleton.IndicatorModeName "eiji"|"hira"|"kata"|"hankata"|"zenkaku"|"abbrev"

---@class skkeleton.IndicatorMode
---@field text string
---@field raw_text string
---@field left_cap? string
---@field right_cap? string
---@field hl_name string
---@field cap_hl_name? string
---@field name skkeleton.IndicatorModeName
---@field width integer
local Mode = {
  LEFT_CAP = "\238\130\182", -- \u{e0b6} 
  RIGHT_CAP = "\238\130\180", -- \u{e0b4} 
  -- colorscheme が無いとき（または未定義のとき）に使う既定の色
  default_hl = {
    dark = {
      eiji = { fg = "NvimDarkGrey2", bg = "NvimLightBlue", ctermfg = "black", ctermbg = "blue", bold = true },
      hira = { fg = "NvimDarkGrey2", bg = "NvimLightGreen", ctermfg = "black", ctermbg = "green", bold = true },
      kata = { fg = "NvimDarkGrey2", bg = "NvimLightYellow", ctermfg = "black", ctermbg = "yellow", bold = true },
      hankata = { fg = "NvimDarkGrey2", bg = "NvimLightMagenta", ctermfg = "black", ctermbg = "magenta", bold = true },
      zenkaku = { fg = "NvimDarkGrey2", bg = "NvimLightCyan", ctermfg = "black", ctermbg = "cyan", bold = true },
      abbrev = { fg = "NvimDarkGrey2", bg = "NvimLightRed", ctermfg = "black", ctermbg = "red", bold = true },
    },
    light = {
      eiji = { fg = "NvimDarkGrey2", bg = "NvimLightBlue", ctermfg = "black", ctermbg = "blue", bold = true },
      hira = { fg = "NvimDarkGrey2", bg = "NvimLightGreen", ctermfg = "white", ctermbg = "green", bold = true },
      kata = { fg = "NvimDarkGrey2", bg = "NvimLightYellow", ctermfg = "white", ctermbg = "yellow", bold = true },
      hankata = { fg = "NvimDarkGrey2", bg = "NvimLightMagenta", ctermfg = "white", ctermbg = "magenta", bold = true },
      zenkaku = { fg = "NvimDarkGrey2", bg = "NvimLightCyan", ctermfg = "black", ctermbg = "cyan", bold = true },
      abbrev = { fg = "NvimDarkGrey2", bg = "NvimLightRed", ctermfg = "black", ctermbg = "red", bold = true },
    },
  },
}
Mode.__index = Mode

-- 設定から 1 つのモードを作り、ハイライトグループを定義する
---@param name skkeleton.IndicatorModeName
---@return skkeleton.IndicatorMode
function Mode.new(name)
  local raw_text = config[name .. "_text"]
  local self = setmetatable({
    name = name,
    hl_name = config[name .. "_hl_name"],
    raw_text = raw_text,
    text = raw_text,
  }, Mode)
  local hl = vim.api.nvim_get_hl(0, { name = self.hl_name })
  local is_default_colorscheme = not vim.g.colors_name
  if vim.tbl_isempty(hl) or (is_default_colorscheme and config.use_default_highlight) then
    hl = Mode.default_hl[vim.o.background][name]
  end
  vim.api.nvim_set_hl(0, self.hl_name, hl)

  if config.style == "pill" then
    self.left_cap = Mode.LEFT_CAP
    self.right_cap = Mode.RIGHT_CAP
    self.text = Mode.LEFT_CAP .. " " .. raw_text .. " " .. Mode.RIGHT_CAP
    self.cap_hl_name = self.hl_name .. "Cap"
    local resolved = vim.api.nvim_get_hl(0, { name = self.hl_name, link = false })
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    vim.api.nvim_set_hl(0, self.cap_hl_name, {
      fg = resolved.bg or hl.bg,
      bg = normal.bg or "NONE",
      ctermfg = resolved.ctermbg or hl.ctermbg,
      ctermbg = normal.ctermbg or "NONE",
    })
  end

  self.width = vim.fn.strdisplaywidth(self.text)
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
  return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

---@return boolean
function Modes.is_cmdline()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == "c"
end

---@return boolean
function Modes.is_active()
  return Modes.is_insert() or (config.show_in_cmdline and Modes.is_cmdline())
end

-- g:skkeleton#mode から今のモードを引く。空や未知の名前は英字にする
---@return skkeleton.IndicatorMode
function Modes:detect()
  return self.modes[vim.g["skkeleton#mode"]] or self.modes.eiji
end

return Modes

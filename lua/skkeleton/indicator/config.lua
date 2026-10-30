-- Ported from skkeleton_indicator.nvim (lua/skkeleton_indicator/config.lua)
-- Copyright (c) 2021 Yasushi Jinnouchi, zlib license (see LICENSES/skkeleton_indicator.nvim.txt)
-- Modified for skkeleton.nvim: module_name を廃止し、setup は呼ぶたびに既定値から作り直す。

---@alias skkeleton.IndicatorBorder "none"|"single"|"double"|"rounded"|"solid"|"shadow"|string[]|string[][]
---@alias skkeleton.IndicatorBorderOpt skkeleton.IndicatorBorder|fun(args: { mode: string }): skkeleton.IndicatorBorder?

---@class skkeleton.IndicatorOpts
---@field eijiHlName? string
---@field hiraHlName? string
---@field kataHlName? string
---@field hankataHlName? string
---@field zenkakuHlName? string
---@field abbrevHlName? string
---@field eijiText? string
---@field hiraText? string
---@field kataText? string
---@field hankataText? string
---@field zenkakuText? string
---@field abbrevText? string
---@field border? skkeleton.IndicatorBorderOpt
---@field row? integer
---@field col? integer
---@field zindex? integer
---@field alwaysShown? boolean
---@field fadeOutMs? integer
---@field ignoreFt? string[]
---@field bufFilter? fun(buf: integer): boolean
---@field useDefaultHighlight? boolean

---@class skkeleton.IndicatorConfig
---@field eiji_hl_name string
---@field hira_hl_name string
---@field kata_hl_name string
---@field hankata_hl_name string
---@field zenkaku_hl_name string
---@field abbrev_hl_name string
---@field eiji_text string
---@field hira_text string
---@field kata_text string
---@field hankata_text string
---@field zenkaku_text string
---@field abbrev_text string
---@field border? skkeleton.IndicatorBorderOpt
---@field row integer
---@field col integer
---@field zindex? integer
---@field always_shown boolean
---@field fade_out_ms integer
---@field ignore_ft string[]
---@field buf_filter fun(buf: integer): boolean
---@field use_default_highlight boolean

local M = {}

---@type skkeleton.IndicatorConfig
M.defaults = {
  eiji_hl_name = "SkkeletonIndicatorEiji",
  hira_hl_name = "SkkeletonIndicatorHira",
  kata_hl_name = "SkkeletonIndicatorKata",
  hankata_hl_name = "SkkeletonIndicatorHankata",
  zenkaku_hl_name = "SkkeletonIndicatorZenkaku",
  abbrev_hl_name = "SkkeletonIndicatorAbbrev",
  eiji_text = "英字",
  hira_text = "ひら",
  kata_text = "カタ",
  hankata_text = "半ｶﾀ",
  zenkaku_text = "全英",
  abbrev_text = "abbr",
  row = 1,
  col = 1,
  always_shown = true,
  fade_out_ms = 3000,
  ignore_ft = {},
  buf_filter = function(_)
    return true
  end,
  use_default_highlight = true,
}

-- 設定のキーと型。border と zindex だけは省略できる
local types = {
  eiji_hl_name = "string",
  hira_hl_name = "string",
  kata_hl_name = "string",
  hankata_hl_name = "string",
  zenkaku_hl_name = "string",
  abbrev_hl_name = "string",
  eiji_text = "string",
  hira_text = "string",
  kata_text = "string",
  hankata_text = "string",
  zenkaku_text = "string",
  abbrev_text = "string",
  border = { "string", "table", "function" },
  row = "number",
  col = "number",
  zindex = "number",
  always_shown = "boolean",
  fade_out_ms = "number",
  ignore_ft = "table",
  buf_filter = "function",
  use_default_highlight = "boolean",
}
local optional = { border = true, zindex = true }

---@type skkeleton.IndicatorConfig
M.values = M.defaults

-- config.eiji_text のように今の設定を読めるようにする
setmetatable(M, {
  __index = function(_, key)
    return M.values[key]
  end,
})

-- opts（camelCase）から設定を作って M.values にする。知らないキーはエラー
---@param opts? skkeleton.IndicatorOpts
function M.setup(opts)
  local raw = require("skkeleton.indicator.strings").snake_case_dict(opts or {})
  for key in pairs(raw) do
    if types[key] == nil then
      error("skkeleton.indicator: unknown option: " .. key, 2)
    end
  end

  -- row の既定値は border があるかどうかで変わる
  if raw.row == nil then
    local border = raw.border
    raw.row = (not border or border == "none" or border == "shadow") and 1 or 0
  end

  local config = vim.tbl_extend("force", M.defaults, raw)
  for key, ty in pairs(types) do
    vim.validate(key, config[key], ty, optional[key])
  end
  M.values = config
end

return M

-- Ported from skkeleton_indicator.nvim (lua/skkeleton_indicator/init.lua)
-- Copyright (c) 2021 Yasushi Jinnouchi, zlib license (see LICENSES/skkeleton_indicator.nvim.txt)
-- Modified for skkeleton.nvim: setup(false) で無効化でき、setup は何度でも呼べる。

local M = {}

---@type skkeleton.Indicator?
local indicator

-- opts でインジケータを設定する。false なら無効にして片付ける
---@param opts? skkeleton.IndicatorOpts|false
function M.setup(opts)
  if opts == false then
    if indicator then
      indicator:destroy()
      indicator = nil
    end
    return
  end

  require("skkeleton.indicator.config").setup(opts)
  if not indicator then
    indicator = require("skkeleton.indicator.indicator").new()
  end
  -- 設定を反映する。insert モード中なら開く
  indicator:refresh()
end

-- 色や文言を作り直す
function M.refresh()
  if indicator then
    indicator:refresh()
  end
end

return M

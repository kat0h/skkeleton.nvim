-- Ported from skkeleton (denops/skkeleton/preedit.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.

-- 確定した文字列を貯めておく。cmdline と terminal では、前回の表示を BS で消して書き直す
---@class skkeleton.PreEdit
---@field current string
---@field kakutei string
local PreEdit = {}
PreEdit.__index = PreEdit

---@return skkeleton.PreEdit
function PreEdit.new()
  return setmetatable({ current = "", kakutei = "" }, PreEdit)
end

-- 確定した文字列を貯める
---@param str string
function PreEdit:do_kakutei(str)
  self.kakutei = self.kakutei .. str
end

-- 貯めた確定文字列を取り出して空にする（insert モードの表示用）
---@return string
function PreEdit:take_kakutei()
  local s = self.kakutei
  self.kakutei = ""
  return s
end

-- BS * (前回の文字数) .. 確定 .. next を返す
---@param next string
---@return string
function PreEdit:output(next)
  local ret
  -- 補完ウィンドウのちらつき防止のため必要のないバックスペースを送らない
  if self.kakutei == "" and next:sub(1, #self.current) == self.current then
    ret = next:sub(#self.current + 1)
  else
    -- strcharlen は合成文字を含めて 1 文字と数える
    ret = ("\b"):rep(vim.fn.strcharlen(self.current)) .. self.kakutei .. next
  end
  self.current = next
  self.kakutei = ""
  return ret
end

return PreEdit

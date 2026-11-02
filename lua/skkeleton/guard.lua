-- pre-edit を出している間に、skkeleton が奪っていない物理の特殊キーが来たら、
-- 打った読みを <Esc> と同じ形で確定してから、そのキーの本来の動きをさせる (#56)。
-- 特殊キーを全部マップして潰すのは修飾キーの組み合わせの分だけ増えるので、
-- vim.on_key で「マップに消費されずに素通りしてきた物理の特殊キー」だけを見る。
local M = {}

local ns = vim.api.nvim_create_namespace("skkeleton-guard")

---@param notation string
---@return string
local function termcode(notation)
  return vim.api.nvim_replace_termcodes(notation, true, true, true)
end

-- 置換モードへ移る <Insert> は、そのまま Neovim に任せる (#29)
local insert_key = termcode("<Insert>")

-- KS_EXTRA (0x80 0xfd) は <Cmd> や Lua コールバックマッピングの擬似キーと
-- 物理キーが混ざる。物理キーだと分かっているものだけを列挙する。
-- 修飾キー付きの特殊キーの多くは KS_MODIFIER (0x80 0xfc) で届くので列挙は要らない。
---@type table<string, boolean>?
local extra_physical
---@return table<string, boolean>
local function extra_physical_keys()
  if extra_physical then
    return extra_physical
  end
  extra_physical = {}
  local names = { "<s-up>", "<s-down>", "<s-left>", "<s-right>", "<c-left>", "<c-right>" }
  for i = 1, 12 do
    names[#names + 1] = ("<s-f%d>"):format(i)
  end
  for _, n in ipairs(names) do
    extra_physical[termcode(n)] = true
  end
  return extra_physical
end

-- Lua コールバックマッピングの擬似キー (KE_LUA)。skkeleton が奪ったキーは
-- この形で届くので、確定せずにマッピングへ渡す
---@param key string
---@return boolean
local function is_mapped_key(key)
  return key:byte(1) == 0x80 and key:byte(2) == 0xfd and key:byte(3) == 0x67
end

-- 物理キー由来の K_SPECIAL シーケンスか
---@param key string
---@return boolean
function M._is_physical_special(key)
  if key:byte(1) ~= 0x80 then
    return false
  end
  local b2 = key:byte(2)
  if b2 == 0xfe then
    -- KS_SPECIAL: 本文中の 0x80 バイトのエスケープ。キーではない
    return false
  end
  if b2 == 0xfd then
    return extra_physical_keys()[key] == true
  end
  if b2 ~= 0xfc then
    -- termcap 系 (<Left> / <F5> など)
    return true
  end
  -- KS_MODIFIER: <C-x> は修飾バイトのあとに base の文字が続く。
  -- 文字の Ctrl 組み合わせ (<C-r> や <C-n> など) は、skkeleton が使う
  -- 編集キーなので通す。Alt / Meta / Cmd 付きと、文字でない base
  -- (<C-.>、<C-Left>、<S-CR> など) は確定の対象にする。
  local mod = key:byte(3) or 0
  if bit.band(mod, 0x04) == 0 or bit.band(mod, 0x08 + 0x10 + 0x20) ~= 0 then
    return true
  end
  local base = key:byte(4)
  if base == nil or base == 0x80 then
    return true
  end
  if (base >= 0x30 and base <= 0x39) or (base >= 0x41 and base <= 0x5a) or (base >= 0x61 and base <= 0x7a) then
    return false
  end
  -- insert で使う Ctrl 付きの記号
  local pass =
    { [0x5b] = true, [0x5c] = true, [0x5d] = true, [0x5e] = true, [0x5f] = true, [0x40] = true, [0x3f] = true }
  return not pass[base]
end

-- skkeleton 自身が pre-edit の書き直しに流す制御バイト。terminal では feedkeys の
-- "t" で流すので on_key には打鍵と同じ形で見える。これらは確定の対象にしない。
local own_output = {
  [0x07] = true, -- <C-g>（undo の区切り）
  [0x08] = true, -- \b（pre-edit の削除）
  [0x09] = true, -- <Tab>
  [0x0a] = true, -- <NL>
  [0x0d] = true, -- <CR>
  [0x1b] = true, -- <Esc>
}

-- terminal でジョブに渡す前に確定すべきキーか。
-- Ctrl + 文字は KS_MODIFIER (0x80 0xfc) で届くので、単バイトの制御キーだけでなく
-- KS_MODIFIER も対象にする (#121)。
---@param key string
---@return boolean
function M._is_terminal_unmapped(key)
  if #key == 1 then
    local b = key:byte(1)
    if b >= 0x20 and b ~= 0x7f then
      return false
    end
    return not own_output[b]
  end
  return key:byte(1) == 0x80 and key:byte(2) == 0xfc
end

-- terminal で insert-normal に抜ける <C-\><C-n> は、pre-edit を確定せずに通す (#74)
local terminal_escape_pending = false

---@param key string
---@return boolean
local function is_ctrl_backslash(key)
  if key == "\28" then
    return true
  end
  return key:byte(1) == 0x80 and key:byte(2) == 0xfc and key:byte(4) == 0x5c
end

---@param key string
---@return boolean
local function is_ctrl_n(key)
  if key == "\14" then
    return true
  end
  return key:byte(1) == 0x80 and key:byte(2) == 0xfc and (key:byte(4) == 0x4e or key:byte(4) == 0x6e)
end

-- vim.on_key のコールバック。"" を返すとそのキーは捨てられる
---@param key string マッピング適用後のキー
---@param typed string マッピング適用前の打鍵。feedkeys などでは空
---@return string?
function M._on_key(key, typed)
  if is_mapped_key(key) then
    return
  end
  if key == insert_key then
    return
  end
  -- feedkeys で流した確定文字列や、補完 UI が流すキーは打鍵ではない
  if typed == "" then
    return
  end
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  if mode ~= "i" and mode ~= "c" and mode ~= "t" then
    return
  end
  if mode == "t" then
    if is_ctrl_backslash(key) then
      terminal_escape_pending = true
      return
    end
    if terminal_escape_pending and is_ctrl_n(key) then
      terminal_escape_pending = false
      return
    end
    terminal_escape_pending = false
  end
  local commit = M._is_physical_special(key)
  -- terminal ではジョブが行を書き換えたことをあとから知れないので、Ctrl + 文字も
  -- ジョブに渡す前に確定する (#121)。insert と cmdline は check_stale に任せる。
  if not commit and mode == "t" then
    commit = M._is_terminal_unmapped(key)
  end
  if not commit then
    return
  end
  local enabled = vim.g["skkeleton#enabled"]
  if not (enabled == true or enabled == 1) then
    return
  end
  -- 本体が公開している状態だけで、pre-edit が出ているかを知る
  local state = vim.g["skkeleton#state"]
  if type(state) ~= "table" or (state.preedit or "") == "" then
    return
  end

  -- 打った読みを <Esc> と同じ形で確定してから、キーをそのまま流し直す。
  -- いまのキーは捨てるので、確定した文字が先に入り、そのあとキーが動く。
  require("skkeleton.main").commit_preedit()
  vim.api.nvim_feedkeys(key, "n", false)
  return ""
end

-- ゲートを有効にする。同じ namespace への登録は上書きなので、何度呼んでもよい
function M.attach()
  vim.on_key(M._on_key, ns)
end

-- ゲートを外す
function M.detach()
  vim.on_key(nil, ns)
end

return M

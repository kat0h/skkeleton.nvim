-- Ported from skkeleton (autoload/skkeleton.vim, autoload/skkeleton/internal/map.vim,
-- autoload/skkeleton/internal/option.vim)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
-- 有効な間だけバッファローカルにキーを奪い、元のマッピングとオプションを退避・復元する。
local notation = require("skkeleton.notation")

local M = {}

local MAP_DESC = "skkeleton"

-- 既定で奪うキー
local function default_keys()
  local chars = "abcdefghijklmnopqrstuvwxyz"
    .. "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    .. "1234567890"
    .. "!\"#$%&'()"
    .. ",./;:]@[-^\\"
    .. ">?_+*}`{=~"
  local keys = vim.split(chars, "", { plain = true })
  vim.list_extend(keys, { "<lt>", "<Bar>", "<BS>", "<C-h>", "<CR>", "<Space>", "<C-q>", "<C-j>", "<C-g>", "<Esc>" })
  return keys
end

-- g:skkeleton#mapped_keys（利用者が足すキー）と既定のキー
---@return string[]
function M.mapped_keys()
  local keys = vim.deepcopy(vim.g["skkeleton#mapped_keys"] or {})
  return vim.list_extend(keys, default_keys())
end

-- バッファごと・モードごとに退避したマッピング
---@type table<integer, table<string, table[]>>
local vault = {}
-- 自分が置いたキーが呼ぶ関数名。再度 map したときに <Plug> の指定を引き継ぐ
---@type table<integer, table<string, table<string, string>>>
local funcs = {}

-- mode のバッファローカルのマッピングを退避する。退避済みなら何もしない
---@param mode string
function M.save(mode)
  local buf = vim.api.nvim_get_current_buf()
  vault[buf] = vault[buf] or {}
  if vault[buf][mode] then
    return
  end
  vault[buf][mode] = vim.api.nvim_buf_get_keymap(buf, mode)
end

local function set_saved(buf, m)
  local opts = {
    noremap = m.noremap == 1,
    nowait = m.nowait == 1,
    silent = m.silent == 1,
    expr = m.expr == 1,
    script = m.script == 1,
    desc = m.desc,
    callback = m.callback,
  }
  if m.expr == 1 and m.replace_keycodes == 1 then
    opts.replace_keycodes = true
  end
  pcall(vim.api.nvim_buf_set_keymap, buf, m.mode, m.lhs, m.rhs or "", opts)
end

-- 単一モードのマッピングを戻す（cmdline 終了時など）
---@param buf integer
---@param mode string
function M.restore_mode(buf, mode)
  if not vim.api.nvim_buf_is_valid(buf) then
    if vault[buf] then
      vault[buf][mode] = nil
      if vim.tbl_isempty(vault[buf]) then
        vault[buf] = nil
      end
    end
    if funcs[buf] then
      funcs[buf][mode] = nil
      if vim.tbl_isempty(funcs[buf]) then
        funcs[buf] = nil
      end
    end
    return
  end
  for lhs in pairs((funcs[buf] and funcs[buf][mode]) or {}) do
    pcall(vim.api.nvim_buf_del_keymap, buf, mode, lhs)
  end
  local maps = vault[buf] and vault[buf][mode]
  if maps then
    for _, m in ipairs(maps) do
      set_saved(buf, m)
    end
  end
  if vault[buf] then
    vault[buf][mode] = nil
    if vim.tbl_isempty(vault[buf]) then
      vault[buf] = nil
    end
  end
  if funcs[buf] then
    funcs[buf][mode] = nil
    if vim.tbl_isempty(funcs[buf]) then
      funcs[buf] = nil
    end
  end
end

-- 退避したマッピングを戻す。skkeleton が置いたキーのみ削除し、元のマッピングを復元する
function M.restore()
  for b, modes in pairs(vault) do
    if vim.api.nvim_buf_is_valid(b) then
      for mode, maps in pairs(modes) do
        for lhs in pairs((funcs[b] and funcs[b][mode]) or {}) do
          pcall(vim.api.nvim_buf_del_keymap, b, mode, lhs)
        end
        for _, m in ipairs(maps) do
          set_saved(b, m)
        end
      end
    end
  end
  vault = {}
  funcs = {}
end

-- 今のバッファの今のモードに、キーを奪うマッピングを置く
function M.map()
  local mode = vim.fn.mode():sub(1, 1)
  if mode == "n" then
    mode = "i"
  end
  M.save(mode)
  local buf = vim.api.nvim_get_current_buf()
  funcs[buf] = funcs[buf] or {}
  funcs[buf][mode] = funcs[buf][mode] or {}
  local mine = funcs[buf][mode]
  for _, c in ipairs(M.mapped_keys()) do
    local key = notation.normalize(c)
    -- <Plug>(skkeleton-xxx) に割り当てたキーは、その関数で呼ぶ
    local func = "handleKey"
    local info = vim.fn.maparg(c, mode, false, true)
    local plug = type(info) == "table" and info.rhs and info.rhs:match("<Plug>%(skkeleton%-(%a+)%)")
    if plug then
      func = plug
    elseif type(info) == "table" and info.desc == MAP_DESC and mine[c] then
      func = mine[c]
    end
    mine[c] = func
    vim.keymap.set(mode, c, function()
      require("skkeleton.main").handle(func, { key = { key } })
    end, { buffer = true, nowait = true, silent = true, desc = MAP_DESC })
  end
end

-- 'textwidth' と 'iminsert' の退避。
-- （確定した文字列を流すときに、'textwidth' で不意に改行されるのを防ぐ）
---@type table<integer, integer>
local textwidth = {}
---@type table<integer, integer>
local iminsert = {}

function M.save_options()
  -- cmdline に関係ないオプションだけなので cmdline では飛ばす
  if vim.fn.mode() == "c" then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if textwidth[buf] == nil then
    textwidth[buf] = vim.bo[buf].textwidth
  end
  vim.bo[buf].textwidth = 0
  if iminsert[buf] == nil then
    iminsert[buf] = vim.bo[buf].iminsert
  end
  vim.bo[buf].iminsert = 0
end

function M.restore_options()
  for buf, tw in pairs(textwidth) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].textwidth = tw
    end
  end
  textwidth = {}

  for buf, im in pairs(iminsert) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].iminsert = im
    end
  end
  iminsert = {}
end

return M

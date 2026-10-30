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

-- 退避したマッピングを戻す。有効な間に置かれたバッファローカルのマッピングは消える
function M.restore()
  local buf = vim.api.nvim_get_current_buf()
  local modes = vault[buf]
  vault[buf] = nil
  funcs[buf] = nil
  for mode, maps in pairs(modes or {}) do
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      pcall(vim.api.nvim_buf_del_keymap, buf, mode, m.lhs)
    end
    for _, m in ipairs(maps) do
      set_saved(buf, m)
    end
  end
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

-- 'textwidth' の退避。pre-edit はバッファに書かないので 'virtualedit' は変えない
-- （確定した文字列を流すときに、'textwidth' で不意に改行されるのを防ぐ）
---@type table<integer, integer>
local textwidth = {}

function M.save_options()
  -- cmdline に関係ないオプションだけなので cmdline では飛ばす
  if vim.fn.mode() == "c" then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if textwidth[buf] == nil then
    textwidth[buf] = vim.bo.textwidth
  end
  vim.bo.textwidth = 0
end

function M.restore_options()
  if vim.fn.mode() == "c" then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if textwidth[buf] ~= nil then
    vim.bo.textwidth = textwidth[buf]
    textwidth[buf] = nil
  end
end

return M

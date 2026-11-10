-- Ported from skkeleton (denops/skkeleton/main.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
-- enable / disable / toggle / handle / complete。
-- 使い終わった state を片付ける autocmd は cleanup.lua にある。
local config = require("skkeleton.config")
local cleanup = require("skkeleton.cleanup")
local kana = require("skkeleton.kana")
local keymap = require("skkeleton.keymap")
local map = require("skkeleton.map")
local candidate = require("skkeleton.candidate")
local mode_mod = require("skkeleton.mode")
local notation = require("skkeleton.notation")
local popup = require("skkeleton.popup")
local render = require("skkeleton.render")
local store = require("skkeleton.store")
local util = require("skkeleton.util")

local functions = util.lazy("skkeleton.function")
local common_func = util.lazy("skkeleton.function.common")
local disable_func = util.lazy("skkeleton.function.disable")

local options = config.options

local M = {}

local initialized = false

local function doautocmd(name)
  -- 利用者の autocmd のエラーで止まらないようにする
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = name, modeline = false })
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

-- handle / complete の実行中であることを cleanup に伝え、エラーをそのまま投げ直す
local function handling(fn, ...)
  cleanup.enter_handling()
  local ok, err = pcall(fn, ...)
  cleanup.leave_handling()
  if not ok then
    error(err, 0)
  end
end

-- 最初に使うときに一度だけ呼ぶ。autocmd を作り、skkeleton-initialize-pre/post を発火する
---@param force? boolean
function M.init(force)
  if force then
    initialized = false
  end
  if initialized then
    return
  end
  initialized = true
  if vim.g["skkeleton#debug"] then
    options.debug = true
  end
  doautocmd("skkeleton-initialize-pre")

  cleanup.setup()
  doautocmd("skkeleton-initialize-post")
end

---@param keys string[]
---@return string[]
local function normalize_keys(keys)
  local ret = {}
  for i, k in ipairs(keys or {}) do
    ret[i] = notation.normalize(k)
  end
  return ret
end

-- キーを state に流す。補完の確定など、先に流すキーがあれば返す
---@param opts table
---@param vim_mode string
local function handle_keys(opts, vim_mode)
  local ctx = store.context()
  ctx.vim_mode = vim_mode:sub(1, 1)
  local keys = normalize_keys(opts.key)

  -- blink.cmp のメニューで項目を選んでいるときの <CR>。選んだ項目で確定する（確定は completion の execute が行う）
  if table.concat(keys) == "<cr>" and options.eggLikeNewline and require("skkeleton.completion").accept_selected() then
    return
  end

  local func = opts["function"]
  for _, key in ipairs(keys) do
    if func then
      functions.functions[func](ctx, key)
    else
      keymap.handle_key(ctx, key)
    end
  end
end

---@param opts table
---@param vim_mode string
local function enable(opts, vim_mode)
  local old = store.context()
  if vim_mode:sub(1, 1) == "R" then
    vim.notify("skkeleton doesn't allowed in replace mode")
    return
  end
  if (old.state.type ~= "input" or old.state.mode ~= "direct") and opts.key then
    handle_keys(opts, vim_mode)
    return
  end
  -- <Plug>(skkeleton-enable) から変換中に呼ばれたときは、Context を作り直さず、
  -- 打った読みをそのまま残す (#210)。upstream の enable() と同じく、変換中の状態は
  -- そのまま有効にするだけにする
  -- ▼ の候補中は、upstream と同じく候補を確定してから有効にする (#210)
  if not opts.key and old.state.type == "henkan" then
    old.vim_mode = vim_mode:sub(1, 1)
    common_func.kakutei(old)
    local commit = old.preedit:take_kakutei():gsub("\x07u$", "")
    kana.set_current(options.kanaTable)
    local ctx = store.init_context()
    ctx.vim_mode = vim_mode:sub(1, 1)
    ctx.preedit:do_kakutei(commit)
    doautocmd("skkeleton-enable-pre")
    map.save_options()
    map.map()
    vim.g["skkeleton#enabled"] = true
    local mode_function = functions.mode_functions[store.variables.last_mode]
    if mode_function then
      mode_function(ctx, "")
    end
    doautocmd("skkeleton-enable-post")
    return
  end
  if not opts.key and old.state.type == "input" and old:to_string() ~= "" then
    old.vim_mode = vim_mode:sub(1, 1)
    if not vim.g["skkeleton#enabled"] then
      doautocmd("skkeleton-enable-pre")
      map.save_options()
      map.map()
      vim.g["skkeleton#enabled"] = true
      doautocmd("skkeleton-enable-post")
    end
    return
  end
  -- Context を作り直す前に設定する
  kana.set_current(options.kanaTable)
  local ctx = store.init_context()
  ctx.vim_mode = vim_mode:sub(1, 1)

  doautocmd("skkeleton-enable-pre")
  map.save_options()
  map.map()
  vim.g["skkeleton#enabled"] = true
  local mode_function = functions.mode_functions[store.variables.last_mode]
  if mode_function then
    mode_function(ctx, "")
  end
  doautocmd("skkeleton-enable-post")
end

---@param opts table
---@param vim_mode string
local function disable(opts, vim_mode)
  local ctx = store.context()
  local st = ctx.state
  -- <Plug>(skkeleton-disable) は key を持たないので、ここでは素通しにしない
  if (st.type ~= "input" or st.mode ~= "direct") and opts.key then
    handle_keys(opts, vim_mode)
    return
  end
  ctx.vim_mode = vim_mode:sub(1, 1)
  disable_func.disable(ctx)
end

-- func: "handleKey" | "enable" | "disable" | "toggle" | "setState"
---@param func string
---@param opts? table
local handle_inner

function M.handle(func, opts)
  handling(handle_inner, func, opts)
end

function handle_inner(func, opts)
  M.init()
  opts = opts or {}
  local vim_mode = vim.api.nvim_get_mode().mode
  local short = vim_mode:sub(1, 1)
  if short == "i" and render.is_pending() then
    render.clear()
  end
  popup.close()

  -- 補完の後など pre-edit とバッファが合わなくなったときはリセットする
  cleanup.reset_if_stale(short)

  if func == "handleKey" then
    handle_keys(opts, vim_mode)
  elseif func == "enable" or func == "setState" then
    enable(opts, vim_mode)
  elseif func == "disable" then
    disable(opts, vim_mode)
  elseif func == "toggle" then
    local disabled = vim.g["skkeleton#mode"] == "" or not vim.g["skkeleton#enabled"]
    if disabled then
      enable(opts, vim_mode)
    else
      disable(opts, vim_mode)
    end
  else
    error("Unsupported function: " .. tostring(func), 0)
  end
  ctx = store.context()
  ctx.vim_mode = ctx.vim_mode ~= "" and ctx.vim_mode or short
  local pre = ctx:to_string()
  cleanup.update_state_variable(pre)
  render.update(ctx, pre)
end

-- 未マップの特殊キーが来たときに、pre-edit を <Esc> と同じ形で確定する (#56)
function M.commit_preedit()
  handling(function()
    M.init()
    local ctx = store.context()
    ctx.vim_mode = vim.api.nvim_get_mode().mode:sub(1, 1)
    common_func.kakutei(ctx)
    -- 候補の一覧が出ていたら閉じる。確定したあとに残さない (#115)
    popup.close()
    local pre = ctx:to_string()
    cleanup.update_state_variable(pre)
    render.update(ctx, pre)
  end)
end

-- 補完で選んだ語をユーザー辞書に登録して、直前の候補にする
---@param kana string
---@param word string
---@param kind? skkeleton.HenkanType
local function register_completion(kana, word, kind)
  kind = kind or "okurinasi"
  store.library():register_henkan_result(kind, kana, word)
  store.context().last_candidate = { type = kind, word = kana, candidate = word }
end

-- 補完で語を選んだとき。pre-edit を捨てて語を確定し、ユーザー辞書に登録する。
-- kana は読み、word は辞書の候補（注釈つきでもよい）、kind は変換の種類（既定は "okurinasi"）
---@param kana string
---@param word string
---@param kind? skkeleton.HenkanType
function M.complete(kana, word, kind)
  handling(function()
    M.init()
    popup.close()
    local ctx = store.context()
    local vim_mode = vim.api.nvim_get_mode().mode
    ctx.vim_mode = vim_mode:sub(1, 1)
    local conv = ctx.state.converter
    -- 変換中の状態は捨てる。モード（ひらがななど）は変えない
    mode_mod.initialize_state_with_abbrev(ctx, { "converter", "table" })
    register_completion(kana, word, kind)
    local text = candidate.modify(word or kana or "") or ""
    if conv then
      text = conv(text)
    end
    ctx:kakutei_with_undo_point(text)
    local pre = ctx:to_string()
    cleanup.update_state_variable(pre)
    render.update(ctx, pre)
  end)
end

return M

-- Ported from skkeleton (denops/skkeleton/main.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
-- enable / disable / toggle / handle と、使い終わった state を片付ける autocmd。
local config = require("skkeleton.config")
local host = require("skkeleton.host")
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

-- g:skkeleton#state を更新する（補完ソースなどが読む）
local function update_state_variable()
  local st = store.context().state
  local phase
  if st.type == "input" then
    phase = st.mode == "okurinasi" and "input:okurinasi" or st.mode == "okuriari" and "input:okuriari" or "input"
  else
    phase = st.type
  end
  vim.g["skkeleton#state"] = { phase = phase, henkanFeed = st.henkan_feed or "" }
end

-- Context を作り直す（使い終わった state の片付け）
local function reset()
  store.init_context()
  update_state_variable()
end

-- handle の実行中か（辞書登録の input() などで誤って初期化しない）
local handling_depth = 0

-- pre-edit が出ているのにバッファやカーソルがずれたら、すぐ状態を初期化して表示を片付ける
local function check_stale()
  local vm = vim.api.nvim_get_mode().mode:sub(1, 1)
  if
    not vim.g["skkeleton#enabled"]
    or handling_depth > host.in_input_depth()
    or render.is_pending()
    or (vm ~= "i" and vm ~= "c")
  then
    return
  end
  local ctx = store.context()
  if not render.is_stale(ctx, vm) then
    return
  end
  render.clear()
  if vm == "c" then
    render.clean_stale_cmdline()
  end
  mode_mod.initialize_state_with_abbrev(ctx, { "converter" })
  ctx.preedit:output("")
  popup.close()
  update_state_variable()
  doautocmd("skkeleton-handled")
  require("skkeleton.indicator").move()
  -- 折り返した pre-edit でウィンドウに収まらず @ になっていた行は、extmark を消しても描き直されない
  if vm == "i" and vim.api.nvim__redraw then
    pcall(vim.api.nvim__redraw, { win = 0, valid = false })
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

  local group = vim.api.nvim_create_augroup("skkeleton-internal", { clear = true })
  -- 使い終わった state を片付ける。CmdlineEnter にすると辞書登録の呼び出しで壊れる。
  -- 挿入モードの <C-o>（niI）などで解除されないよう ModeChanged の :n にする。
  -- SafeState を挟むのは、プラグインによる ModeChanged の呼び出しで解除されるのを防ぐため。
  -- このイベントは利用者の操作を受け付けるときに呼ばれるので、そこで normal なら改めて処理する
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*:n",
    callback = function()
      vim.api.nvim_create_autocmd("SafeState", {
        group = group,
        once = true,
        callback = function()
          if vim.fn.mode() == "n" then
            reset()
            host.disable()
          end
        end,
      })
    end,
  })
  -- visual・select・operator-pending から入った cmdline を抜けて戻ったときも片付ける。
  -- insert・cmdline・terminal に移るときは使い続けるので触らない（insert の <C-o> は niI のまま）
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "c:*",
    callback = function()
      local new_mode = vim.v.event.new_mode:sub(1, 1)
      if new_mode == "i" or new_mode == "c" or new_mode == "t" or new_mode == "n" then
        return
      end
      vim.api.nvim_create_autocmd("SafeState", {
        group = group,
        once = true,
        callback = function()
          local m = vim.fn.mode():sub(1, 1)
          if m ~= "i" and m ~= "c" and m ~= "t" and not host.is_in_input() then
            reset()
            host.disable()
          end
        end,
      })
    end,
  })
  -- insert のままウィンドウやバッファを切り替えても残らないようにする
  -- （辞書登録の input() の最中は元の状態を壊さないようスキップする）
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = group,
    callback = function()
      if host.is_in_input() then
        return
      end
      reset()
      host.disable()
    end,
  })
  -- upstream ではバッファの文字だった pre-edit が <C-u> や矢印キーで消える動きに合わせる
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP", "CursorMovedI", "CmdlineChanged", "CompleteDone" }, {
    group = group,
    callback = check_stale,
  })
  -- 終了時にユーザー辞書と補完ランクを保存する
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      require("skkeleton").save_user_dict()
    end,
  })
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
---@return string?
local function handle_keys(opts, vim_mode)
  local ctx = store.context()
  ctx.vim_mode = vim_mode:sub(1, 1)
  local keys = normalize_keys(opts.key)

  -- 補完の pum が出ているときの <CR>。native の pum だけ対応する
  if vim.fn.pumvisible() == 1 and table.concat(keys) == "<cr>" and options.eggLikeNewline then
    local ok, info = pcall(vim.fn.complete_info, { "selected" })
    if ok and info.selected >= 0 then
      mode_mod.initialize_state_with_abbrev(ctx, { "converter" })
      ctx.preedit:output("")
      return "\25"
    end
  end

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
---@return string?
local function enable(opts, vim_mode)
  local old = store.context()
  if vim_mode:sub(1, 1) == "R" then
    vim.notify("skkeleton doesn't allowed in replace mode")
    return
  end
  if (old.state.type ~= "input" or old.state.mode ~= "direct") and opts.key then
    return handle_keys(opts, vim_mode)
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
---@return string?
local function disable(opts, vim_mode)
  local ctx = store.context()
  local st = ctx.state
  -- <Plug>(skkeleton-disable) は key を持たないので、ここでは素通しにしない
  if (st.type ~= "input" or st.mode ~= "direct") and opts.key then
    return handle_keys(opts, vim_mode)
  end
  ctx.vim_mode = vim_mode:sub(1, 1)
  disable_func.disable(ctx)
end

-- func: "handleKey" | "enable" | "disable" | "toggle" | "setState"
---@param func string
---@param opts? table
function M.handle(func, opts)
  handling_depth = handling_depth + 1
  local ok, err = pcall(M.handle_inner, func, opts)
  handling_depth = handling_depth - 1
  if not ok then
    error(err, 0)
  end
end

function M.handle_inner(func, opts)
  M.init()
  opts = opts or {}
  local vim_mode = vim.api.nvim_get_mode().mode
  local short = vim_mode:sub(1, 1)
  if short == "i" and render.is_pending() then
    render.clear()
  end
  popup.close()

  local ctx = store.context()
  -- 補完の後など pre-edit とバッファが合わなくなったときはリセットする
  if render.is_stale(ctx, short) then
    render.clear()
    if short == "c" then
      render.clean_stale_cmdline()
    end
    mode_mod.initialize_state_with_abbrev(ctx, { "converter" })
    ctx.preedit:output("")
  end

  local prefix
  if func == "handleKey" then
    prefix = handle_keys(opts, vim_mode)
  elseif func == "enable" or func == "setState" then
    prefix = enable(opts, vim_mode)
  elseif func == "disable" then
    prefix = disable(opts, vim_mode)
  elseif func == "toggle" then
    local disabled = vim.g["skkeleton#mode"] == "" or not vim.g["skkeleton#enabled"]
    if disabled then
      prefix = enable(opts, vim_mode)
    else
      prefix = disable(opts, vim_mode)
    end
  else
    error("Unsupported function: " .. tostring(func), 0)
  end
  ctx = store.context()
  ctx.vim_mode = ctx.vim_mode ~= "" and ctx.vim_mode or short
  update_state_variable()
  render.update(ctx, prefix)
end

-- 補完で語を選んだとき。pre-edit を捨てて語を確定し、ユーザー辞書に登録する。
-- kana は読み、word は辞書の候補（注釈つきでもよい）、kind は変換の種類（既定は "okurinasi"）
---@param kana string
---@param word string
---@param kind? skkeleton.HenkanType
function M.complete(kana, word, kind)
  handling_depth = handling_depth + 1
  local ok, err = pcall(function()
    M.init()
    popup.close()
    local ctx = store.context()
    local vim_mode = vim.api.nvim_get_mode().mode
    ctx.vim_mode = vim_mode:sub(1, 1)
    local conv = ctx.state.converter
    -- 変換中の状態は捨てる。モード（ひらがななど）は変えない
    mode_mod.initialize_state_with_abbrev(ctx, { "converter", "table" })
    M.complete_callback(kana, word, kind)
    local text = candidate.modify(word or kana or "") or ""
    if conv then
      text = conv(text)
    end
    ctx:kakutei_with_undo_point(text)
    update_state_variable()
    render.update(ctx)
  end)
  handling_depth = handling_depth - 1
  if not ok then
    error(err, 0)
  end
end

-- 補完で選んだ語をユーザー辞書に登録して、直前の候補にする
---@param kana string
---@param word string
---@param kind? skkeleton.HenkanType
function M.complete_callback(kana, word, kind)
  kind = kind or "okurinasi"
  store.library():register_henkan_result(kind, kana, word)
  store.context().last_candidate = { type = kind, word = kana, candidate = word }
end

return M

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

-- g:skkeleton#state を更新する（補完ソースやインジケータが読む）
---@param pre? string ctx:to_string() の結果（呼び出し側で作ったもの）
local function update_state_variable(pre)
  local ctx = store.context()
  local st = ctx.state
  local phase
  if st.type == "input" then
    phase = st.mode == "okurinasi" and "input:okurinasi" or st.mode == "okuriari" and "input:okuriari" or "input"
  else
    phase = st.type
  end
  pre = pre or ctx:to_string()
  vim.g["skkeleton#state"] = {
    phase = phase,
    henkanFeed = st.henkan_feed or "",
    preedit = st.type ~= "escape" and pre or "",
  }
end

-- pre-edit を消したときに g:skkeleton#state.preedit も消す。
-- 値は handle でしか更新しないので、cmdline の pre-edit を片付けたときに残ってしまう
local function clear_preedit_state()
  local state = vim.g["skkeleton#state"]
  -- vim.g の表はコピーなので、書き換えたら入れ直す
  if type(state) == "table" and state.preedit ~= "" then
    state.preedit = ""
    vim.g["skkeleton#state"] = state
  end
end

-- Context を作り直す（使い終わった state の片付け）
local function reset()
  store.init_context()
  update_state_variable()
end

-- insert から normal へ移ったとき、今の pre-edit を <Esc> と同じ文字列としてバッファに書く (#70)。
-- <Esc> はマップされた escape が確定してから抜けるが、<C-c> はマップされていないのでここで確定する
local function commit_preedit()
  local buf, row, col = render.preedit_position()
  if not buf then
    return
  end
  local ctx = store.context()
  -- kakutei の undo point を付けずに、確定する文字列だけ取り出す
  ctx.vim_mode = "n"
  common_func.kakutei(ctx)
  local text = ctx.preedit:take_kakutei()
  if text ~= "" then
    vim.api.nvim_buf_set_text(buf, row, col, row, col, { text })
  end
end

local function should_delete_hist(item)
  if type(item) ~= "string" or item == "" then
    return false
  end
  return item:find("▽", 1, true) ~= nil
    or item:find("▼", 1, true) ~= nil
    or item:find("__skkeleton_return__", 1, true) ~= nil
end

local function clean_history(hist_type)
  local types = { ":", "/", "@" }
  if hist_type and hist_type ~= "" then
    table.insert(types, 1, hist_type)
  end
  for _, ht in ipairs(types) do
    local ok, item = pcall(vim.fn.histget, ht, -1)
    if ok and should_delete_hist(item) then
      pcall(vim.fn.histdel, ht, -1)
    end
  end
end

-- handle の実行中か（辞書登録の input() などで誤って初期化しない）
local handling_depth = 0

-- pre-edit が出ているのにバッファやカーソルがずれたら、状態を初期化して表示を片付ける。
-- 戻り値: ずれていてリセットしたかどうか
local function reset_if_stale(vm)
  vm = vm or vim.api.nvim_get_mode().mode:sub(1, 1)
  if vm ~= "i" and vm ~= "c" then
    return false
  end
  local ctx = store.context()
  if not render.is_stale(ctx, vm) then
    return false
  end
  render.clean_stale(vm)
  mode_mod.initialize_state_with_abbrev(ctx, { "converter" })
  ctx.preedit:output("")
  popup.close()
  update_state_variable()
  doautocmd("skkeleton-handled")
  -- 折り返した pre-edit でウィンドウに収まらず @ になっていた行は、extmark を消しても描き直されない
  if vm == "i" and vim.api.nvim__redraw then
    pcall(vim.api.nvim__redraw, { win = 0, valid = false })
  end
  return true
end

-- autocmd などから非同期に呼ばれるチェック
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
  reset_if_stale(vm)
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
  -- モード遷移に伴う後片付けの遷移表 (#62)
  -- 移る前と後のモードに応じて、片付け方（"reset"、"safe_reset"、"none"）を引く
  local MODE_TRANSITIONS = {
    -- 1. insert / completion 中から visual / select モードへの直接遷移（マウス選択など）
    { from = "^i", to = "^[vV\022sS\019]", action = "reset" },
    -- 2. insert 中から <Insert> キーで置換モードへの遷移
    { from = "^i", to = "^R", action = "reset" },
    -- 3. normal モードへの遷移（プラグイン等による一瞬の遷移を SafeState で待つ）
    { from = ".*", to = "^n", action = "safe_reset" },
    -- 4. cmdline から visual / select / operator-pending などへ戻ったとき
    { from = "^c", to = "^[^ictn]", action = "safe_reset" },
  }

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      local old_mode = vim.v.event.old_mode
      local new_mode = vim.v.event.new_mode
      if old_mode:sub(1, 1) == "c" then
        clean_history()
      end
      local action = "none"
      for _, rule in ipairs(MODE_TRANSITIONS) do
        if old_mode:find(rule.from) and new_mode:find(rule.to) then
          action = rule.action
          break
        end
      end
      if action == "reset" then
        if not host.is_in_input() then
          reset()
          host.disable()
        end
      elseif action == "safe_reset" and store.context().state.type == "escape" and not host.is_in_input() then
        -- skkeleton の <Esc> はもう確定して無効にしてある。SafeState を待つと、すぐ次の a などで
        -- insert に戻ったときに escape の状態が残るので、ここで片付ける (#32)
        reset()
      elseif action == "safe_reset" then
        -- insert から normal へ抜けたときは、捨てずに <Esc> と同じく確定する
        local commit = old_mode:sub(1, 1) == "i"
        vim.api.nvim_create_autocmd("SafeState", {
          group = group,
          once = true,
          callback = function()
            -- vim.fn.mode() は terminal-normal（nt）を n と返すので、nvim_get_mode() で見る (#74)
            local m = vim.api.nvim_get_mode().mode
            local s = m:sub(1, 1)
            if
              s ~= "i"
              and s ~= "c"
              and s ~= "t"
              and not vim.startswith(m, "ni")
              and not vim.startswith(m, "nt")
              and not host.is_in_input()
            then
              if commit then
                commit_preedit()
              end
              reset()
              host.disable()
            end
          end,
        })
      end
    end,
  })

  -- cmdline を抜ける際（取り消しも含めて）に pre-edit を取り除き、履歴にマーカーを残さない
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      render.clean_stale_cmdline()
      clear_preedit_state()
      local cmdtype = vim.v.event.cmdtype
      clean_history(cmdtype)
      vim.schedule(function()
        clean_history(cmdtype)
      end)
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
      if vim.fn.mode():sub(1, 1) == "c" then
        render.clean_stale_cmdline()
        clear_preedit_state()
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
  render.on_stale = check_stale
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

  -- 補完の後など pre-edit とバッファが合わなくなったときはリセットする
  reset_if_stale(short)

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
  local pre = ctx:to_string()
  update_state_variable(pre)
  render.update(ctx, prefix, pre)
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
    register_completion(kana, word, kind)
    local text = candidate.modify(word or kana or "") or ""
    if conv then
      text = conv(text)
    end
    ctx:kakutei_with_undo_point(text)
    local pre = ctx:to_string()
    update_state_variable(pre)
    render.update(ctx, nil, pre)
  end)
  handling_depth = handling_depth - 1
  if not ok then
    error(err, 0)
  end
end

return M

-- Ported from skkeleton (denops/skkeleton/main.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
-- モード遷移やバッファの変更に伴う後片付けの autocmd。
-- 有効・無効と handle は main.lua に置き、ここは片付けだけを受け持つ。
local host = require("skkeleton.host")
local marker = require("skkeleton.marker")
local mode_mod = require("skkeleton.mode")
local popup = require("skkeleton.popup")
local render = require("skkeleton.render")
local cmdline = require("skkeleton.render.cmdline")
local store = require("skkeleton.store")
local util = require("skkeleton.util")

local common_func = util.lazy("skkeleton.function.common")

local M = {}

local function doautocmd(name)
  -- 利用者の autocmd のエラーで止まらないようにする
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = name, modeline = false })
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

-- g:skkeleton#state を更新する（補完ソースやインジケータが読む）
---@param pre? string ctx:to_string() の結果（呼び出し側で作ったもの）
function M.update_state_variable(pre)
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
  M.update_state_variable()
end

-- insert から normal へ移ったとき、今の pre-edit を <Esc> と同じ文字列としてバッファに書く (#70)。
-- <Esc> はマップされた escape が確定してから抜けるが、<C-c> はマップされていないのでここで確定する。
-- move_cursor を真にすると、確定した文字の末尾へカーソルを移す（<Esc> と同じ位置にする。#142）
---@param move_cursor? "normal"|"insert"
local function commit_preedit(move_cursor)
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
    if move_cursor == "insert" then
      -- 置換・insert モードのカーソルは、確定した文字の後ろに置く (#156)
      vim.api.nvim_win_set_cursor(0, { row + 1, col + #text })
    elseif move_cursor then
      -- 最後の文字の先頭バイトへ移す（normal モードのカーソルは文字の上に置く）
      local last = vim.fn.byteidx(text, vim.fn.strchars(text) - 1)
      vim.api.nvim_win_set_cursor(0, { row + 1, col + last })
    end
  end
  return text, buf, row, col
end

-- 貼り付けの直前に同期的に確定する (#125)。extmark と g:state は呼び出し側で片付ける
M.commit_preedit_now = commit_preedit

local function clean_history(hist_type)
  local types = { ":", "/", "@" }
  if hist_type and hist_type ~= "" then
    table.insert(types, 1, hist_type)
  end
  for _, ht in ipairs(types) do
    marker.drop_marker_history(ht)
  end
end

-- handle の実行中か（辞書登録の input() などで誤って初期化しない）
local handling_depth = 0

-- handle の実行中であることを数える。main.lua の handling() が使う
function M.enter_handling()
  handling_depth = handling_depth + 1
end

function M.leave_handling()
  handling_depth = handling_depth - 1
end

-- pre-edit が出ているのにバッファやカーソルがずれたら、状態を初期化して表示を片付ける。
-- 戻り値: ずれていてリセットしたかどうか
---@param vm? string
---@return boolean
function M.reset_if_stale(vm)
  vm = vm or vim.api.nvim_get_mode().mode:sub(1, 1)
  if vm ~= "i" and vm ~= "c" then
    return false
  end
  local ctx = store.context()
  if not render.is_stale(ctx, vm) then
    return false
  end
  -- カーソルだけが動いたときは捨てずに、元の位置に確定する (#111)
  if render.is_cursor_only_stale(ctx, vm) then
    commit_preedit()
  end
  render.clear()
  if vm == "c" then
    cmdline.clean()
  end
  mode_mod.initialize_state_with_abbrev(ctx, { "converter" })
  ctx.preedit:output("")
  popup.close()
  M.update_state_variable()
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
  local did_reset = M.reset_if_stale(vm)
  -- 前の CmdlineChanged で片付けきれなかった cmdline の pre-edit を、もう一度試す (#12)
  if vm == "c" and not did_reset and cmdline.has_stale() then
    cmdline.clean()
  end
end

-- cmdline の pre-edit の記録と g:skkeleton#state.preedit を片付ける
local function drop_cmdline_preedit()
  cmdline.clean()
  cmdline.reset()
  clear_preedit_state()
end

-- 後片付けの autocmd を作る。main.M.init から一度だけ呼ぶ
function M.setup()
  local group = vim.api.nvim_create_augroup("skkeleton-internal", { clear = true })
  -- モード遷移に伴う後片付けの遷移表 (#62)
  -- 移る前と後のモードに応じて、片付け方（"reset"、"safe_reset"、"stale"、"none"）を引く
  local MODE_TRANSITIONS = {
    -- 1. insert / completion 中から visual / select モードへの直接遷移（マウス選択など）
    { from = "^i", to = "^[vV\022sS\019]", action = "reset" },
    -- 2. insert 中から <Insert> キーで置換モードへの遷移
    { from = "^i", to = "^R", action = "reset" },
    -- 3. <C-o> で insert-normal に入って、そのまま insert に戻ったとき (#117)
    { from = "^ni", to = "^i", action = "stale" },
    -- 4. normal モードへの遷移（プラグイン等による一瞬の遷移を SafeState で待つ）
    { from = ".*", to = "^n", action = "safe_reset" },
    -- 5. cmdline から visual / select / operator-pending などへ戻ったとき
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
          -- insert から置換・visual・select へ移るときも、捨てずに <Esc> と同じく確定する (#111)。
          -- 置換モードでは、確定した文字の後ろへカーソルを移す (#156)
          commit_preedit(new_mode:sub(1, 1) == "R" and "insert" or nil)
          reset()
          host.disable()
        end
      elseif action == "stale" then
        -- <C-o> から戻ったとき、カーソルだけが動いていれば確定する (#117)
        M.reset_if_stale("i")
      elseif action == "safe_reset" and store.context().state.type == "escape" and not host.is_in_input() then
        -- skkeleton の <Esc> はもう確定して無効にしてある。SafeState を待つと、すぐ次の a などで
        -- insert に戻ったときに escape の状態が残るので、ここで片付ける (#32)
        reset()
      elseif action == "safe_reset" then
        -- insert から normal へ抜けたときは、捨てずに <Esc> と同じく確定する
        local commit = old_mode:sub(1, 1) == "i"
        -- niI / nt へ入っただけ（<C-o> など）では SafeState を登録しない。
        -- そこから先の遷移（niI→n など）が自分で片付けを登録する (#169)
        if vim.startswith(new_mode, "ni") or vim.startswith(new_mode, "nt") then
          return
        end
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
              local ctx = store.context()
              -- <C-o> から normal へ抜けるとき（:stopinsert など）は、insert の pre-edit を
              -- 確定も捨てもせず保持する (#169)
              if not commit and ctx.vim_mode == "i" and ctx:to_string() ~= "" and render.preedit_position() then
                return
              end
              if commit then
                -- <C-c> などで insert を抜けたとき、確定した文字の末尾へ移す (#142)
                commit_preedit("normal")
              end
              reset()
              host.disable()
            end
          end,
        })
      end
    end,
  })

  -- cmdwin を開いたら印を消す。開けなかったときも、次の CmdlineLeave で消える
  vim.api.nvim_create_autocmd({ "CmdwinEnter", "CmdlineEnter" }, {
    group = group,
    callback = function()
      require("skkeleton.guard").clear_cmdwin_pending()
    end,
  })
  -- cmdline を抜ける際（取り消しも含めて）に pre-edit を取り除き、履歴にマーカーを残さない
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      -- <C-f> で cmdwin を開くときは、cmdline の文字列を Neovim が cmdwin に写す。
      -- 写すまで pre-edit を消さない (#205)
      -- <C-r>= などの内側の cmdline を抜けるときは、外側の cmdline の記録を残す (#206)
      if require("skkeleton.guard").is_cmdwin_pending() then
        cmdline.reset()
        clear_preedit_state()
      elseif vim.v.event.cmdtype == ":" then
        drop_cmdline_preedit()
      end
      -- <C-o>: から戻ったときなど、insert の pre-edit が残っていればその値を保つ (#86)
      M.update_state_variable()
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
      -- <C-f> で cmdwin を開くときは、cmdline の文字列を Neovim が cmdwin に写す。
      -- 写すまで pre-edit を消さない (#205)
      if vim.fn.mode():sub(1, 1) == "c" and not require("skkeleton.guard").is_cmdwin_pending() then
        drop_cmdline_preedit()
      end
      local ctx = store.context()
      -- insert の pre-edit が出ている間にウィンドウやタブを移るとき（<C-o>:wincmd w など）は、
      -- 移動が済んでから元のバッファがまだ表示されているかで判断する。表示されていれば
      -- pre-edit を保持し、バッファを離れていれば従来通り捨てる (#169)
      if ctx.vim_mode == "i" and ctx:to_string() ~= "" then
        local pbuf = render.preedit_buffer()
        if pbuf then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(pbuf) and #vim.fn.win_findbuf(pbuf) > 0 then
              M.update_state_variable()
            else
              reset()
              host.disable()
            end
          end)
          return
        end
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
  require("skkeleton.guard").attach()
end

return M

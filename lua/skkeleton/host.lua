-- core から UI へ出るところ。UI の実装が関数を差し替える。
-- テストでも差し替えて、呼ばれたことを確かめる。
-- Ported from skkeleton (autoload/skkeleton.vim の skkeleton#disable、function/dictionary.ts の registerWord の UI 部分)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local M = {}

local function doautocmd(name)
  vim.api.nvim_exec_autocmds("User", { pattern = name, modeline = false })
end

-- モードが変わったことを g:skkeleton#mode と User skkeleton-mode-changed で知らせる
---@param mode string
function M.mode_changed(mode)
  vim.g["skkeleton#mode"] = mode
  doautocmd("skkeleton-mode-changed")
end

-- skkeleton を無効化する。変数を更新してから User イベントを発火する
function M.disable()
  if not vim.g["skkeleton#enabled"] then
    return
  end
  doautocmd("skkeleton-disable-pre")
  local map = require("skkeleton.map")
  map.restore()
  map.restore_options()
  vim.g["skkeleton#mode"] = ""
  doautocmd("skkeleton-mode-changed")
  doautocmd("skkeleton-disable-post")
  vim.g["skkeleton#enabled"] = false
  require("skkeleton.render").clear()
  require("skkeleton.popup").close()
  require("skkeleton.completion").hide()
end

-- 候補一覧の popup。lines は "a: 候補" の配列。描画のあとに開く
---@param lines string[]
---@param meta? { index: integer, total: integer }
function M.show_candidates(lines, meta)
  require("skkeleton.popup").set(lines, meta)
end

local in_input_depth = 0

---@return boolean
function M.is_in_input()
  return in_input_depth > 0
end

---@return integer
function M.in_input_depth()
  return in_input_depth
end

-- 辞書登録の入力。取り消しなら nil か ""
-- 入力中は新しい Context で skkeleton を有効にし、終わったら元の Context とモードに戻す
---@param prompt string
---@return string?
function M.input(prompt)
  local store = require("skkeleton.store")
  local map = require("skkeleton.map")
  local ctx = store.context()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local saved_cursor = vim.api.nvim_win_get_cursor(win)
  local saved_ve = vim.o.virtualedit

  -- 辞書登録に入る前に補完メニューや候補ポップアップを閉じる
  require("skkeleton.popup").close()
  require("skkeleton.completion").hide()

  -- 行末の挿入位置（col == #line）で input() に入ってもカーソルが1文字左へ戻らないよう virtualedit=all にする
  vim.o.virtualedit = "all"

  -- cmdline のマッピングを退避して、<Esc> と <C-g> では取り消す
  map.save("c")

  local input_group = vim.api.nvim_create_augroup("skkeleton-host-input", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = input_group,
    callback = function()
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() ~= win then
        pcall(vim.api.nvim_set_current_win, win)
      end
    end,
  })

  in_input_depth = in_input_depth + 1
  local ok, res = pcall(function()
    store.init_context()
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      once = true,
      callback = function()
        map.map()
        for _, k in ipairs({ "<Esc>", "<C-g>" }) do
          vim.api.nvim_buf_set_keymap(buf, "c", k, "__skkeleton_return__<CR>", { noremap = true, silent = true })
        end
      end,
    })
    return vim.fn.input(prompt)
  end)
  in_input_depth = in_input_depth - 1
  pcall(vim.api.nvim_del_augroup_by_id, input_group)

  if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() ~= win then
    pcall(vim.api.nvim_set_current_win, win)
  end
  vim.o.virtualedit = saved_ve
  if vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_cursor, win, saved_cursor)
  end

  pcall(vim.api.nvim_buf_del_keymap, buf, "c", "<Esc>")
  pcall(vim.api.nvim_buf_del_keymap, buf, "c", "<C-g>")
  map.restore_mode(buf, "c")

  doautocmd("skkeleton-enable-pre")
  -- skkeleton のモードに戻す
  map.map()
  vim.g["skkeleton#enabled"] = true
  vim.cmd("redrawstatus")
  -- 退避した Context とモードを戻す
  store.set_context(ctx)
  require("skkeleton.mode").mode_change(ctx, ctx.mode)
  doautocmd("skkeleton-enable-post")

  if not ok then
    error(res, 0)
  end
  return res
end

-- purgeCandidate の確認
---@param msg string
---@return boolean
function M.confirm(msg)
  return vim.fn.confirm(msg, "&Yes\n&No\n", 2) == 1
end

-- keepState の再有効化（次の InsertEnter で enable する）
function M.keep_state_on_insert_enter()
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = vim.api.nvim_create_augroup("skkeleton", { clear = false }),
    buffer = vim.api.nvim_get_current_buf(),
    once = true,
    callback = function()
      require("skkeleton.main").handle("enable", {})
    end,
  })
end

return M

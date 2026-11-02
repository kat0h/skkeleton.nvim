-- core から UI へ出るところ。UI の実装が関数を差し替える。
-- テストでも差し替えて、呼ばれたことを確かめる。
-- Ported from skkeleton (autoload/skkeleton.vim の skkeleton#disable、function/dictionary.ts の registerWord の UI 部分)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local marker = require("skkeleton.marker")

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

---@class skkeleton.InputFrame
---@field context skkeleton.Context 退避した Context
---@field buf integer 呼び出し時のバッファ
---@field win integer 呼び出し時のウィンドウ
---@field cursor integer[] 呼び出し時のカーソル位置
---@field virtualedit string 呼び出し時の virtualedit

---@type skkeleton.InputFrame[]
local input_stack = {}

---@return boolean
function M.is_in_input()
  return #input_stack > 0
end

---@return integer
function M.in_input_depth()
  return #input_stack
end

local input_guard_group = vim.api.nvim_create_augroup("skkeleton-host-input", { clear = true })

---スタックのトップにある文脈（ウィンドウ）を WinEnter で守る。スタックが空なら守りを解除する
---@param frame skkeleton.InputFrame?
local function setup_input_guard(frame)
  vim.api.nvim_clear_autocmds({ group = input_guard_group })
  if not frame then
    return
  end
  vim.api.nvim_create_autocmd("WinEnter", {
    group = input_guard_group,
    callback = function()
      vim.schedule(function()
        local top = input_stack[#input_stack]
        if top ~= frame then
          return
        end
        if vim.fn.getcmdwintype() ~= "" then
          return
        end
        local cur = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_is_valid(frame.win) and cur ~= frame.win then
          pcall(vim.api.nvim_set_current_win, frame.win)
        end
      end)
    end,
  })
end

---@param win integer
---@param buf integer
---@return skkeleton.InputFrame
local function push_input_frame(win, buf)
  local store = require("skkeleton.store")
  local map = require("skkeleton.map")

  local frame = {
    context = store.context(),
    buf = buf,
    win = win,
    cursor = vim.api.nvim_win_get_cursor(win),
    virtualedit = vim.o.virtualedit,
  }

  table.insert(input_stack, frame)

  -- 行末の挿入位置（col == #line）で input() に入ってもカーソルが1文字左へ戻らないよう virtualedit=all にする
  vim.o.virtualedit = "all"

  -- cmdline のマッピングを退避
  map.save("c")

  -- このフレームのウィンドウを守る WinEnter を設定
  setup_input_guard(frame)

  return frame
end

---@param frame skkeleton.InputFrame
local function pop_input_frame(frame)
  local store = require("skkeleton.store")
  local map = require("skkeleton.map")

  for i = #input_stack, 1, -1 do
    if input_stack[i] == frame then
      table.remove(input_stack, i)
      break
    end
  end

  -- 1 つ前のフレーム（あれば）の守りに戻す。スタックが空なら守りを解除する
  local prev = input_stack[#input_stack]
  setup_input_guard(prev)

  if vim.api.nvim_win_is_valid(frame.win) and vim.api.nvim_get_current_win() ~= frame.win then
    pcall(vim.api.nvim_set_current_win, frame.win)
  end
  vim.o.virtualedit = frame.virtualedit
  if vim.api.nvim_win_is_valid(frame.win) then
    pcall(vim.api.nvim_win_set_cursor, frame.win, frame.cursor)
  end

  pcall(vim.api.nvim_buf_del_keymap, frame.buf, "c", "<Esc>")
  pcall(vim.api.nvim_buf_del_keymap, frame.buf, "c", "<C-g>")
  map.restore_mode(frame.buf, "c")

  doautocmd("skkeleton-enable-pre")
  -- skkeleton のモードに戻す
  map.map()
  vim.g["skkeleton#enabled"] = true
  vim.cmd("redrawstatus")
  -- 退避した Context とモードを戻す
  store.set_context(frame.context)
  require("skkeleton.mode").mode_change(frame.context, frame.context.mode)
  doautocmd("skkeleton-enable-post")
end

-- 辞書登録の欄の取り消し。<Cmd> から呼び、取り消しの印を書いて <CR> で抜ける。
-- 印を文字として打ち込むと、かな入力が一部を食って崩れる (#116)
function M.cancel_input()
  require("skkeleton.render.cmdline").reset()
  vim.fn.setcmdline(marker.CANCEL)
end

-- 辞書登録の入力。取り消しなら nil か ""
-- 入力中は新しい Context で skkeleton を有効にし、終わったら元の Context とモードに戻す
---@param prompt string
---@return string?
function M.input(prompt)
  local store = require("skkeleton.store")
  local map = require("skkeleton.map")

  -- 辞書登録に入る前に補完メニューや候補ポップアップを閉じる
  require("skkeleton.popup").close()
  require("skkeleton.completion").hide()
  -- 外側の pre-edit は登録の読みに変わるので、extmark を残さない
  require("skkeleton.render").clear()

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local frame = push_input_frame(win, buf)

  local ok, res = pcall(function()
    store.init_context()
    -- 新しい Context に合わせて参照用の変数も更新する（#54 の残り）
    vim.g["skkeleton#state"] = { phase = "input", henkanFeed = "", preedit = "" }
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      once = true,
      callback = function()
        map.map()
        -- 印をかな入力に通さず、<Cmd> から書いて <CR> で抜ける (#116)
        local cancel = "<Cmd>lua require('skkeleton.host').cancel_input()<CR><CR>"
        for _, k in ipairs({ "<Esc>", "<C-g>" }) do
          vim.api.nvim_buf_set_keymap(frame.buf, "c", k, cancel, { noremap = true, silent = true })
        end
      end,
    })
    return vim.fn.input(prompt)
  end)
  marker.drop_marker_history("@")

  pop_input_frame(frame)

  if not ok then
    error(res, 0)
  end
  if marker.contains_marker(res) then
    return ""
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

-- テストの共通部分。E2E 用のキー入力のドライバ（type/buffer/preedit/...）もここにある
local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
M.testdata = M.root .. "/tests/testdata"

-- 子が input() などで止まっても 1 ケース 10 秒で落ちるようにする。
-- 子の中のタイマーで自分を kill すると、親の待ち中の呼び出しがエラーになり、ケースが失敗になる
local function restart(child)
  child.restart({ "-u", M.root .. "/tests/minimal_init.lua" })
  child.lua([[vim.fn.timer_start(10000, function() vim.uv.kill(vim.uv.os_getpid(), "sigkill") end)]])
end

-- 子の nvim を使うテストの set を作る。ケースごとに子を作り直すので状態が漏れない
---@return table set, table child
function M.child_set(opts)
  local child = MiniTest.new_child_neovim()
  local set = MiniTest.new_set(vim.tbl_deep_extend("force", {
    hooks = {
      pre_case = function()
        restart(child)
      end,
      post_once = child.stop,
    },
  }, opts or {}))
  return set, child
end

-- E2E 用の小さな辞書（UTF-8）
M.dict_text = table.concat({
  ";; -*- coding: utf-8 -*-",
  ";; okuri-ari entries.",
  "わるk /悪/",
  "かえr /帰/返/",
  "ならd /並/",
  ";; okuri-nasi entries.",
  "かん /缶/感/漢/幹/管/館/観/",
  "かんじ /漢字/幹事/",
  "ほげ /補外/",
  "にほん /日本/",
  "とうきょう /東京/",
  "abc /ＡＢＣ/",
}, "\n") .. "\n"

-- E2E の子を作る。ケースごとに作り直し、skkeleton を setup する。
-- 辞書とユーザー辞書とデータベースは一時ディレクトリに置く（手元の ~/.skkeleton には触らない）
---@param opts? { config?: table, dict?: string, init?: string }
---@return table set, table child
function M.e2e_set(opts)
  opts = opts or {}
  local child
  local set
  set, child = M.child_set({
    hooks = {
      pre_case = function()
        restart(child)
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        local dict = dir .. "/dict"
        local f = assert(io.open(dict, "w"))
        f:write(opts.dict or M.dict_text)
        f:close()
        local config = vim.tbl_extend("force", {
          globalDictionaries = { { dict, "utf-8" } },
          userDictionary = dir .. "/user",
          databasePath = dir .. "/db",
          indicator = false,
        }, opts.config or {})
        child.lua("require('skkeleton').setup(...)", { config })
        child.lua("_G.dir = ...", { dir })
        if opts.init then
          child.lua(opts.init)
        end
      end,
    },
  })
  return set, child
end

-- 流したキーが全部処理されて、遅れて走る描画（feedkeys のあとの redraw）も終わるまで待つ
---@param child table
function M.settle(child)
  local quiet = 0
  for _ = 1, 600 do
    if child.is_blocked() then
      return
    end
    local pending = child.lua_get("vim.fn.getchar(1)")
    if pending == 0 then
      quiet = quiet + 1
      if quiet >= 3 then
        return
      end
    else
      quiet = 0
    end
    vim.uv.sleep(2)
  end
  error("settle: the child still has pending input")
end

-- キーを打って、処理が終わるまで待つ
---@param child table
function M.type(child, ...)
  child.type_keys(...)
  M.settle(child)
end

-- 確定した行
---@param child table
---@return string[]
function M.buffer(child)
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

-- pre-edit（extmark の virt_text）。出ていなければ ""
---@param child table
---@return string
function M.preedit(child)
  return child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["skkeleton-preedit"]
    local text = ""
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      for _, chunk in ipairs(m[4].virt_text or {}) do
        text = text .. chunk[1]
      end
    end
    return text
  end)()]])
end

-- g:skkeleton#mode
---@param child table
---@return string
function M.mode(child)
  return child.lua_get([[vim.g["skkeleton#mode"] ]])
end

-- 候補の popup の中身。出ていなければ nil
---@param child table
---@return string[]?
function M.popup(child)
  return child.lua_get([[(function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.w[w].skkeleton_popup then
        return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
      end
    end
  end)()]])
end

-- インジケータの文字列とハイライト。出ていなければ nil
---@param child table
---@return { text: string, hl: string? }?
function M.indicator(child)
  return child.lua_get([[(function()
    local ns = vim.api.nvim_get_namespaces()["skkeleton-indicator"]
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" and not vim.w[w].skkeleton_popup then
        local buf = vim.api.nvim_win_get_buf(w)
        local marks = ns and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) or {}
        return {
          text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
          hl = marks[1] and marks[1][4].hl_group or nil,
        }
      end
    end
  end)()]])
end

-- カーソルの位置 { 行 (1 起点), 列 (バイト, 0 起点) }
---@param child table
---@return integer[]
function M.cursor(child)
  return child.api.nvim_win_get_cursor(0)
end

return M

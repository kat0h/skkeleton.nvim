-- core から UI へ出るところ。UI の実装が関数を差し替える。
-- テストでも差し替えて、呼ばれたことを確かめる。
local M = {}

-- モードが変わったことを g:skkeleton#mode と User skkeleton-mode-changed で知らせる
---@param mode string
function M.mode_changed(mode)
  vim.g["skkeleton#mode"] = mode
  vim.api.nvim_exec_autocmds("User", { pattern = "skkeleton-mode-changed", modeline = false })
end

-- skkeleton を無効化する
function M.disable() end

-- 候補一覧の popup。lines は "a: 候補" の配列
---@param lines string[]
function M.show_candidates(lines) end

-- 辞書登録の入力。取り消しなら nil か ""
---@param prompt string
---@return string?
function M.input(prompt)
  return nil
end

-- purgeCandidate の確認
---@param msg string
---@return boolean
function M.confirm(msg)
  return false
end

-- keepState の再有効化（次の InsertEnter で enable する）
function M.keep_state_on_insert_enter() end

return M

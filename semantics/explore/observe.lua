-- 黒箱探索の観測。子の nvim から外に見える値だけを取り、状態クラスに写す。
-- 実装の内部（store、render）は読まない。読むのは公開した変数と、画面・バッファ・
-- マッピング・cmdline・terminal・popup・辞書登録の深さだけ。
local M = {}

-- 子の nvim で動かすスナップショット。戻り値は JSON にできる表だけにする
M.snapshot_source = [[(function()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local mode = vim.api.nvim_get_mode().mode
  local g_state = vim.g["skkeleton#state"]
  local state = { phase = "", henkan_feed = "", preedit = "" }
  if type(g_state) == "table" then
    state.phase = tostring(g_state.phase or "")
    state.henkan_feed = tostring(g_state.henkanFeed or "")
    state.preedit = tostring(g_state.preedit or "")
  end

  -- pre-edit の extmark（どのバッファに置かれているかも見る）
  local namespace = vim.api.nvim_get_namespaces()["skkeleton-preedit"]
  local marks = {}
  if namespace then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, namespace, 0, -1, { details = true })) do
          local text = ""
          for _, chunk in ipairs(m[4].virt_text or {}) do
            text = text .. chunk[1]
          end
          marks[#marks + 1] = { buf = b, row = m[2], col = m[3], text = text }
        end
      end
    end
  end

  -- cmdline。cmdline の外では全部空
  local cmdline = { type = "", line = "", pos = 0 }
  local ok_type, cmdtype = pcall(vim.fn.getcmdtype)
  if ok_type then
    cmdline.type = cmdtype
  end
  if cmdline.type ~= "" then
    cmdline.line = vim.fn.getcmdline()
    cmdline.pos = vim.fn.getcmdpos()
  end

  -- terminal。ジョブの出力が届くまで、行の中身が 2 回続けて同じになるのを待つ
  local terminal = {
    active = vim.bo[buf].buftype == "terminal",
    line_count = 0,
    lines = {},
    tail = "",
    cursor = { 0, 0 },
  }
  if terminal.active then
    local last, stable = nil, 0
    vim.wait(1000, function()
      local now = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      if now == last then
        stable = stable + 1
      else
        stable = 0
      end
      last = now
      return stable >= 2
    end, 10)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    terminal.line_count = #lines
    terminal.lines = lines
    for i = #lines, 1, -1 do
      if lines[i] ~= "" then
        terminal.tail = lines[i]
        break
      end
    end
    terminal.cursor = vim.api.nvim_win_get_cursor(win)
  end

  -- skkeleton の候補一覧（popup）
  local popup = { shown = false, count = 0, lines = {} }
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[w].skkeleton_popup then
      popup.shown = true
      popup.lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
      popup.count = #popup.lines
      break
    end
  end

  -- バッファローカルのマッピング。skk のものは desc に skkeleton が入る
  local function maps(m)
    local total, skk = 0, 0
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, m)) do
      total = total + 1
      if map.desc and map.desc:find("skkeleton", 1, true) then
        skk = skk + 1
      end
    end
    return total, skk
  end
  local i_total, i_skk = maps("i")
  local c_total, c_skk = maps("c")
  local t_total, t_skk = maps("t")

  -- 辞書登録のプロンプトの深さ。host の公開した関数だけを使う
  local depth = 0
  local ok_depth, d = pcall(function()
    return require("skkeleton.host").in_input_depth()
  end)
  if ok_depth and type(d) == "number" then
    depth = d
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- マクロの記録と再生の状態（#192）。状態クラスには出ないが、探索の状態を分けるのに使う
  local recording, executing = "", ""
  pcall(function()
    recording = vim.fn.reg_recording()
  end)
  pcall(function()
    executing = vim.fn.reg_executing()
  end)
  local register_a, register_dot = "", ""
  pcall(function()
    register_a = vim.fn.getreg("a")
    register_dot = vim.fn.getreg(".")
  end)

  -- 補完のメニュー。blink.cmp は自分の浮動ウィンドウを出す（filetype は blink-cmp-menu）。
  -- 画面の位置も、外から見える値として取る（#143、#174）
  local completion = { menu = false, row = -1, col = -1 }
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "blink-cmp-menu" then
      local pos = vim.api.nvim_win_get_position(w)
      completion.menu = true
      completion.row = pos[1]
      completion.col = pos[2]
      break
    end
  end

  return {
    buf = buf,
    win = win,
    vim_mode = mode,
    enabled = vim.g["skkeleton#enabled"] == true,
    skk_mode = vim.g["skkeleton#mode"] or "",
    state = state,
    buftype = vim.bo[buf].buftype,
    buffer = {
      lines = lines,
      text = table.concat(lines, "\n"),
      cursor = vim.api.nvim_win_get_cursor(win),
      changedtick = vim.api.nvim_buf_get_changedtick(buf),
    },
    preedit_marks = marks,
    cmdline = cmdline,
    terminal = terminal,
    popup = popup,
    completion = completion,
    mappings = {
      i = i_total,
      c = c_total,
      t = t_total,
      skk = i_skk + c_skk + t_skk,
    },
    register_depth = depth,
    registers = {
      recording = recording,
      executing = executing,
      a = register_a,
      dot = register_dot,
    },
    windows = #vim.api.nvim_tabpage_list_wins(0),
    buffers = #vim.api.nvim_list_bufs(),
  }
end)()]]

-- 子の nvim の今の観測を取る
---@param child table
---@return table
function M.snapshot(child)
  return child.lua_get(M.snapshot_source)
end

-- 今のバッファの pre-edit の extmark の文字列（無ければ ""）
---@param obs table
---@return string
function M.mark_text(obs)
  local text = ""
  for _, mark in ipairs(obs.preedit_marks or {}) do
    if mark.buf == obs.buf then
      text = text .. mark.text
    end
  end
  return text
end

-- 観測を状態クラスに写す。状態クラスの名前は semantics/GLOSSARY.md に合わせる。
-- 04 の model.lua ができたら、ここの対応を model.lua の定義と突き合わせる。
-- 増やしたクラスは NOT ここでは作らず、まず GLOSSARY のどれかに寄せる。
---@param obs table
---@return string
function M.classify(obs)
  local mode = obs.vim_mode or ""
  local state = obs.state or {}
  local preedit = state.preedit or ""
  local enabled = obs.enabled == true
  local mark = M.mark_text(obs)

  -- 辞書登録のプロンプト。mode は c、cmdtype は @
  if (obs.register_depth or 0) > 0 or (obs.cmdline or {}).type == "@" then
    return "P_PROMPT"
  end

  -- 組み込みの補完は Vim のモードが ic。blink.cmp は Vim のモードを変えずに
  -- 自分のメニューを出すので、pre-edit が残ったままでも IC とする
  if mode == "ic" or mode == "ix" then
    return "IC"
  end
  if enabled and preedit ~= "" and (obs.completion or {}).menu then
    return "IC"
  end

  -- <C-o> で一時的に normal に移っている間
  if mode:sub(1, 2) == "ni" then
    return "NI"
  end

  -- cmdline と replace の cmdline
  if mode == "c" or mode == "cr" or mode == "cv" or mode == "ce" then
    if mode == "cr" then
      return "C_REPLACE"
    end
    return preedit ~= "" and "C_POINT" or "C_DIRECT"
  end

  -- terminal
  if mode == "t" then
    return preedit ~= "" and "T_POINT" or "T_DIRECT"
  end
  if mode == "nt" then
    return "T_NORMAL"
  end

  -- replace モード。skk が有効なままなら R_MID
  if mode:sub(1, 1) == "R" then
    return (enabled and preedit ~= "") and "R_MID" or "R_OFF"
  end

  -- visual / select。pre-edit が残っているときだけ V_PRE。残っていなければ N_OFF に寄せる
  if mode == "v" or mode == "V" or mode == "\22" or mode == "s" or mode == "S" or mode == "\19" then
    return preedit ~= "" and "V_PRE" or "N_OFF"
  end

  -- insert
  if mode == "i" then
    -- 無効な insert は I_DIRECT と結果が違うので分ける（作者の判断 1）
    if not enabled then
      return "I_OFF"
    end
    if state.phase == "escape" then
      return "I_ESCAPE"
    end
    if state.phase == "henkan" then
      return "I_SELECT"
    end
    if preedit ~= "" then
      if state.henkan_feed ~= "" then
        return "I_POINT"
      end
      -- ローマ字の打ちかけ（state.feed）だけの状態（作者の判断 6）
      return "I_ROMAJI"
    end
    return "I_DIRECT"
  end

  -- normal。skk が有効なままなら、pre-edit が見えているかで分ける
  if mode == "n" then
    if not enabled then
      return "N_OFF"
    end
    if preedit ~= "" and mark == "" then
      return "N_LOST"
    end
    return "N_WAIT"
  end

  return "UNKNOWN"
end

return M

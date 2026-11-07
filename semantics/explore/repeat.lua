-- マクロ（q 記録・@ 実行）と `.` の繰り返しの観測（#192、親は #179）
--
-- 子の nvim に実際の打鍵を流し、1 つのキー列の前後で外から見える状態クラスを
-- JSONL に書く。レジスタの中身と undo の単位は状態クラスに無いので、記録だけ残す。
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/explore/repeat.lua
--   nvim --headless -u NONE -i NONE -l semantics/explore/repeat.lua --out /tmp/repeat.jsonl
--   nvim --headless -u NONE -i NONE -l semantics/explore/repeat.lua --case dot.insert
--
-- 子の nvim は tests/helpers.lua の e2e_set（一時ディレクトリの辞書、HISTFILE=/dev/null）。
-- 手元の辞書・クリップボード・履歴には触らない。
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end

vim.opt.runtimepath = { vim.env.VIMRUNTIME, root, mini }
package.path = root .. "/?.lua;" .. root .. "/tests/?.lua;" .. package.path
vim.g.loaded_netrwPlugin = 1
vim.o.swapfile = false
vim.o.shada = ""
vim.env.HISTFILE = "/dev/null"
local work = root .. "/.tests/repeat"
vim.fn.mkdir(work, "p")
vim.env.XDG_CACHE_HOME = work .. "/cache"
vim.env.XDG_STATE_HOME = work .. "/state"
require("mini.test").setup({})

local observe = require("semantics.explore.observe")
local helpers = require("helpers")

-- 観測の 1 行。before / after は observe.classify の状態クラス
local cases = {
  {
    id = "macro.record.insert",
    purpose = "q で記録し、insert のあいだに打ったキーを q で止める",
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    keys = { "qa", "A", "<Plug>(skkeleton-enable)", "Kan<Space><C-j>", "<Esc>", "q" },
    expect = "N_OFF",
  },
  {
    id = "macro.replay.insert",
    purpose = "記録した insert のマクロを @a で別の行に再生する",
    lines = { "ab", "cd", "ef" },
    cursor = { 1, 2 },
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "Kan<Space><C-j>",
      "<Esc>",
      "q",
      "j",
      "@a",
    },
    expect = "N_OFF",
  },
  {
    id = "macro.replay.count",
    purpose = "3@a で 3 回再生する",
    lines = { "ab", "", "", "" },
    cursor = { 1, 2 },
    keys = { "qa", "A", "<Plug>(skkeleton-enable)", "kan<C-j>", "<Esc>", "j0", "q", "3@a" },
    expect = "N_OFF",
  },
  {
    id = "macro.replay.normal",
    purpose = "normal のコマンドだけを記録して再生する",
    lines = { "one", "two", "three" },
    cursor = { 1, 1 },
    keys = { "qa", "j", "q", "j", "@a" },
    expect = "N_OFF",
  },
  {
    id = "dot.insert",
    purpose = "insert で確定したあと . で繰り返す",
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    keys = { "A", "<Plug>(skkeleton-enable)", "kan<C-j>", "<Esc>", "j0", "." },
    expect = "N_OFF",
  },
  {
    id = "dot.henkan",
    purpose = "変換して確定した insert を . で繰り返す",
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    keys = { "A", "<Plug>(skkeleton-enable)", "Kan<Space><C-j>", "<Esc>", "j0", "." },
    expect = "N_OFF",
  },
  {
    id = "dot.twice",
    purpose = ". を 2 回続ける",
    lines = { "ab", "cd", "ef", "gh" },
    cursor = { 1, 2 },
    keys = { "A", "<Plug>(skkeleton-enable)", "kan<C-j>", "<Esc>", "j0", ".", "j0", "." },
    expect = "N_OFF",
  },
  {
    id = "undo.replay",
    purpose = "@a の再生を u で戻す。skk の確定ごとに undo の区切りがあるか",
    lines = { "", "x" },
    cursor = { 1, 0 },
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "Kan<Space><C-j>",
      "Kan<Space><C-j>",
      "<Esc>",
      "q",
      "j0",
      "@a",
    },
    undo = 3,
    expect = "N_OFF",
  },
  {
    id = "undo.dot",
    purpose = ". の繰り返しを u で戻す",
    lines = { "", "y" },
    cursor = { 1, 0 },
    keys = { "A", "<Plug>(skkeleton-enable)", "Kan<Space><C-j>", "Kan<Space><C-j>", "<Esc>", "j0", "." },
    undo = 3,
    expect = "N_OFF",
  },
  {
    id = "keepstate.dot",
    purpose = "keepState の one-shot を . が使い切る（#152）",
    config = { keepState = true },
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    keys = {
      "i",
      "<Plug>(skkeleton-enable)",
      "Kan<Space><C-j>",
      "<Esc>",
      ".",
      "a",
    },
    expect = "I_OFF",
  },
  {
    id = "keepstate.dot.empty",
    purpose = "最後の変更が空の insert でも、. が InsertEnter を起こして one-shot を使い切る",
    config = { keepState = true },
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>", ".", "a" },
    expect = "I_OFF",
  },
  {
    id = "keepstate.replay",
    purpose = "keepState の one-shot があるときの @a のあと、insert が有効になるか",
    config = { keepState = true },
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "Kan<Space><C-j>",
      "<Esc>",
      "q",
      "i",
      "<Plug>(skkeleton-enable)",
      "<Esc>",
      "j",
      "@a",
      "a",
    },
    expect = "I_DIRECT",
  },
  {
    id = "cmdline.record",
    purpose = "cmdline で記録したマクロのレジスタと再生（既知の不具合）",
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    cmdline_toggle = true,
    keys = { "qa", ":", "<C-j>", "Kan<C-j>", "<Esc>", "q" },
    expect = "N_OFF",
    known_issue = "#214",
  },
  {
    id = "cmdline.replay",
    purpose = "cmdline で記録したマクロを @a で再生する（既知の不具合）",
    lines = { "ab", "cd" },
    cursor = { 1, 2 },
    cmdline_toggle = true,
    keys = { "qa", ":", "<C-j>", "Kan<C-j>", "<Esc>", "q", "j", "@a" },
    expect = "N_OFF",
    known_issue = "#214",
  },
  {
    id = "terminal.record",
    purpose = "terminal で記録したマクロのレジスタ（既知の不具合）",
    terminal = true,
    keys = {
      "<C-\\><C-n>",
      "qa",
      "i",
      "<Plug>(skkeleton-enable)",
      "Kan",
      "<C-\\><C-n>",
      "q",
    },
    expect = "T_NORMAL",
    known_issue = "#214",
  },
  {
    id = "replay.guard",
    purpose = "再生中の guard は typed が空なので、typed の <S-Tab> と再生の <S-Tab> で読みの扱いが違う（既知の不具合）",
    lines = { "ab cd", "ef gh" },
    cursor = { 1, 2 },
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "Kan",
      "<S-Tab>",
      "<Esc>",
      "q",
      "j",
      "0",
      "@a",
    },
    expect = "N_OFF",
    known_issue = "#216",
    guard_compare = true,
  },
}

local function parse_args(argv)
  local opts = {
    out = root .. "/semantics/explore/observations/repeat.jsonl",
    only = nil,
  }
  local i = 1
  while i <= #argv do
    local arg = argv[i]
    if arg == "--out" then
      i = i + 1
      opts.out = argv[i]
    elseif arg == "--case" then
      i = i + 1
      opts.only = argv[i]
    elseif arg == "--help" or arg == "-h" then
      opts.help = true
    else
      error(("知らない引数です: %s"):format(arg))
    end
    i = i + 1
  end
  return opts
end

local function snapshot(child)
  local obs = observe.snapshot(child)
  obs.class = observe.classify(obs)
  return obs
end

local function compact(obs)
  return {
    vim_mode = obs.vim_mode,
    enabled = obs.enabled,
    skk_mode = obs.skk_mode,
    phase = obs.state.phase,
    preedit = obs.state.preedit,
    mark = observe.mark_text(obs),
    buffer = obs.buffer.lines,
    cursor = obs.buffer.cursor,
    cmdline = obs.cmdline,
    mappings = obs.mappings,
    register_depth = obs.register_depth,
  }
end

-- JSONL を UTF-8 のままにする。レジスタには K_SPECIAL の 0x80 などが入るので、
-- 正しい UTF-8 でないバイトは <0x80> の形に置き換える
local function clean_bytes(s)
  local out = {}
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then
      out[#out + 1] = string.char(b)
      i = i + 1
    else
      local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 0
      local ok = len > 0 and i + len - 1 <= #s
      if ok then
        for j = 1, len - 1 do
          local c = s:byte(i + j)
          if c < 0x80 or c >= 0xC0 then
            ok = false
          end
        end
      end
      if ok then
        out[#out + 1] = s:sub(i, i + len - 1)
        i = i + len
      else
        out[#out + 1] = ("<0x%02x>"):format(b)
        i = i + 1
      end
    end
  end
  return table.concat(out)
end

-- skk が流した文字列がレジスタに入っているか。finish() は render.finish の <Cmd>
local function register_info(child)
  local a = clean_bytes(child.fn.getreg("a"))
  local dot = clean_bytes(child.fn.getreg("."))
  return {
    a = a,
    dot = dot,
    a_len = #a,
    a_has_finish = a:find("finish", 1, true) ~= nil,
    a_has_marker = a:find("▽", 1, true) ~= nil or a:find("▼", 1, true) ~= nil,
    a_has_reading = a:find("かん", 1, true) ~= nil,
    dot_has_marker = dot:find("▽", 1, true) ~= nil or dot:find("▼", 1, true) ~= nil,
  }
end

-- 1 つのケースを流す。子はケースごとに作り直す
local function run_case(case)
  local set, child = helpers.e2e_set({ config = case.config or {} })
  local hooks = getmetatable(set).opts.hooks
  local ok_pre = pcall(hooks.pre_case)
  local row = { id = case.id, purpose = case.purpose, expect = case.expect, keys = case.keys }
  if not ok_pre then
    row.error = "子の準備に失敗した"
    return row
  end
  local ok_setup, setup_err = pcall(function()
    if case.lines then
      child.api.nvim_buf_set_lines(0, 0, -1, false, case.lines)
    end
    if case.cursor then
      child.api.nvim_win_set_cursor(0, case.cursor)
    end
    if case.cmdline_toggle then
      child.lua([[vim.keymap.set("c", "<C-j>", "<Plug>(skkeleton-toggle)")]])
    end
    if case.terminal then
      child.cmd("terminal cat")
      helpers.settle(child)
      helpers.type(child, "i")
    end
    helpers.settle(child)
  end)
  if not ok_setup then
    row.error = tostring(setup_err)
    pcall(hooks.post_once)
    return row
  end

  local before = snapshot(child)
  row.from = before.class
  local type_error
  for _, keys in ipairs(case.keys) do
    local ok, err = pcall(helpers.type, child, keys)
    if not ok then
      type_error = err
      break
    end
  end
  if type_error then
    -- 手元のパスを JSONL に残さない。Vim のエラー番号と本文だけにする
    local msg = tostring(type_error):match("E%d+:[^\n]*") or "キー入力を処理できなかった"
    row.error = "キー入力でエラー: " .. msg
  end
  helpers.settle(child)
  -- 再生が Ex のエラーで止まると子が入力待ちになる（cmdline のマクロの不具合）。
  -- 状態を読めるように、待ちをほどいてから観測する
  if child.is_blocked() then
    row.blocked = true
    pcall(function()
      child.type_keys("<CR>")
    end)
    pcall(helpers.settle, child)
  end
  local after = snapshot(child)
  row.to = after.class
  row.ok = after.class == case.expect and not row.blocked
  row.known_issue = case.known_issue
  row.registers = register_info(child)
  row.errmsg = child.lua_get("vim.v.errmsg")
  local reg = row.registers
  local polluted = reg.a_has_finish or reg.a_has_marker or reg.a_has_reading
  if polluted and case.known_issue then
    row.ok = false
    row.error = row.error or "skk が流したキーがレジスタに入っている"
  end
  row.before = compact(before)
  row.after = compact(after)

  -- typed のキーと再生のキーで、同じキー列の結果が違わないか（#216）。
  -- 状態クラスは N_OFF のままで、バッファに残る読みだけが違う
  if case.guard_compare then
    local typed_line = after.buffer.lines[1] or ""
    local replay_line = after.buffer.lines[2] or ""
    row.guard = {
      typed_line = typed_line,
      replay_line = replay_line,
      typed_has_reading = typed_line:find("かん", 1, true) ~= nil,
      replay_has_reading = replay_line:find("かん", 1, true) ~= nil,
    }
    if row.guard.typed_has_reading and not row.guard.replay_has_reading then
      row.ok = false
      row.error = row.error or "再生で読みが消えた（typed のときと結果が違う）"
    end
  end

  -- undo は状態クラスに無いので、u ごとのバッファを残す
  if case.undo then
    row.undo = { { step = 0, buffer = after.buffer.lines } }
    for i = 1, case.undo do
      local ok = pcall(helpers.type, child, "u")
      if not ok then
        row.undo[#row.undo + 1] = { step = i, error = "u が失敗した" }
        break
      end
      row.undo[#row.undo + 1] = { step = i, buffer = helpers.buffer(child) }
    end
  end
  pcall(hooks.post_once)
  return row
end

local function main(argv)
  local opts = parse_args(argv)
  if opts.help then
    print("使い方: nvim --headless -u NONE -i NONE -l semantics/explore/repeat.lua [--out path] [--case id]")
    return 0
  end

  vim.fn.mkdir(vim.fs.dirname(opts.out), "p")
  local file = assert(io.open(opts.out, "w"))
  local stamp = os.date("%Y%m%d-%H%M%S")
  local rows = {}
  local failures, knowns = 0, 0
  for _, case in ipairs(cases) do
    if not opts.only or opts.only == case.id then
      local row = run_case(case)
      row.run = "repeat-" .. stamp
      file:write(vim.json.encode(row), "\n")
      rows[#rows + 1] = row
      local mark = row.ok and "✓" or (row.known_issue and "△" or "✗")
      if not row.ok then
        if row.known_issue then
          knowns = knowns + 1
        else
          failures = failures + 1
        end
      end
      print(
        ("%s %-22s %s -> %s（期待 %s）%s"):format(
          mark,
          row.id,
          tostring(row.from),
          tostring(row.to),
          tostring(row.expect),
          row.error and (" " .. row.error) or ""
        )
      )
    end
  end
  file:close()
  print(
    ("観測 %d 件: 一致 %d / 既知 %d / 不一致 %d"):format(#rows, #rows - knowns - failures, knowns, failures)
  )
  print(("JSONL: %s"):format(opts.out))
  return failures == 0 and 0 or 1
end

local code = main(arg)
os.exit(code)

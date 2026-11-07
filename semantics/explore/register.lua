-- 辞書登録のプロンプト（@、入れ子）の観測（#189 / 07c、親は #179）
--
-- 子の nvim に実際の打鍵を流し、1 つの出来事の前後の状態クラスを JSONL に書く。
-- プロンプトは input() の中で止まるので、explore.lua の --replay のように 1 キーずつ
-- 観測すると、途中のキーで子が入力待ちになって観測できないことがある。ここでは
-- 準備（prefix）を流してから、確かめるキーを 1 回で流し、落ち着いてから 1 回だけ観測する。
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/explore/register.lua
--   nvim --headless -u NONE -i NONE -l semantics/explore/register.lua --out /tmp/register.jsonl
--
-- 子の nvim は tests/helpers.lua の e2e_set（一時ディレクトリの辞書、HISTFILE=/dev/null）。
-- 手元の辞書・履歴・クリップボードには触らない。
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
local work = root .. "/.tests/register"
vim.fn.mkdir(work, "p")
vim.env.XDG_CACHE_HOME = work .. "/cache"
vim.env.XDG_STATE_HOME = work .. "/state"
require("mini.test").setup({})

local observe = require("semantics.explore.observe")
local helpers = require("helpers")

local set, child = helpers.e2e_set()
local hooks = getmetatable(set).opts.hooks

local enable = "<Plug>(skkeleton-enable)"
local spaces = string.rep("<Space>", 6)

-- 準備。prefix はこのあとに流す
local profiles = {
  insert = function()
    helpers.type(child, "i" .. enable)
    return {}
  end,
  reg_a = function()
    child.fn.setreg("a", "XYZ")
    helpers.type(child, "i" .. enable)
    return {}
  end,
  history = function()
    child.fn.histadd("@", "あ")
    helpers.type(child, "i" .. enable)
    return {}
  end,
  two_windows = function()
    child.cmd("new")
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "other" })
    child.cmd("wincmd k")
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    helpers.type(child, "i" .. enable)
    return { win = child.api.nvim_get_current_win() }
  end,
}

-- 準備のあとに流すキー列。prefix の最後で、確かめたい状態まで進める
local prefix = {
  point = "Nuru<Space>",
  point_reading = "Nuru<Space>Kan",
  point_nested = "Nuru<Space>Nuru<Space>",
  point_depth3 = "Nuru<Space>Nuru<Space>Nuru<Space>",
  select = "Kan" .. spaces,
  select_last = "Kan" .. string.rep("<Space>", 5),
  select_reading = "Kan" .. spaces .. "Kan",
  select_nested = "Kan" .. spaces .. "Kan" .. spaces,
}

local actions = {
  key = function(_, key)
    pcall(helpers.type, child, key)
  end,
  wincmd = function()
    child.cmd("wincmd w")
  end,
  wincmd_esc = function()
    child.cmd("wincmd w")
    helpers.type(child, "<Esc>")
  end,
}

-- 1 つの観測。expect はモデルの状態クラス
local cases = {
  -- プロンプトを開く
  { id = "register.open.point", profile = "insert", prefix = "Nuru", action = "key", key = "<Space>", expect = "P_PROMPT" },
  {
    id = "register.open.select",
    profile = "insert",
    prefix = prefix.select_last,
    action = "key",
    key = "<Space>",
    expect = "P_PROMPT",
  },
  -- 欄の中の入力
  { id = "register.char.direct", profile = "insert", prefix = prefix.point, action = "key", key = "a", expect = "P_PROMPT" },
  { id = "register.char.shift", profile = "insert", prefix = prefix.point, action = "key", key = "K", expect = "P_PROMPT" },
  {
    id = "register.select.space",
    profile = "insert",
    prefix = prefix.point .. "K",
    action = "key",
    key = "<Space>",
    expect = "P_PROMPT",
  },
  {
    id = "register.space.direct",
    profile = "insert",
    prefix = prefix.point,
    action = "key",
    key = "<Space>",
    expect = "P_PROMPT",
  },
  -- 確定（<CR>）と空の <CR>
  {
    id = "register.commit.text",
    profile = "insert",
    prefix = prefix.point .. "a",
    action = "key",
    key = "<CR>",
    expect = "I_DIRECT",
  },
  {
    id = "register.commit.point",
    profile = "insert",
    prefix = prefix.point_reading,
    action = "key",
    key = "<CR>",
    expect = "I_DIRECT",
  },
  {
    id = "register.commit.select.text",
    profile = "insert",
    prefix = prefix.select .. "a",
    action = "key",
    key = "<CR>",
    expect = "I_DIRECT",
  },
  {
    id = "register.commit.select.reading",
    profile = "insert",
    prefix = prefix.select_reading,
    action = "key",
    key = "<CR>",
    expect = "I_DIRECT",
  },
  { id = "register.empty-cr.point", profile = "insert", prefix = prefix.point, action = "key", key = "<CR>", expect = "I_POINT" },
  { id = "register.empty-cr.select", profile = "insert", prefix = prefix.select, action = "key", key = "<CR>", expect = "I_SELECT" },
  -- 取り消し（<Esc> / <C-g> / <C-c>）
  { id = "register.cancel.point.esc", profile = "insert", prefix = prefix.point, action = "key", key = "<Esc>", expect = "I_POINT" },
  { id = "register.cancel.point.cg", profile = "insert", prefix = prefix.point, action = "key", key = "<C-g>", expect = "I_POINT" },
  { id = "register.cancel.point.cc", profile = "insert", prefix = prefix.point, action = "key", key = "<C-c>", expect = "I_POINT" },
  {
    id = "register.cancel.reading.esc",
    profile = "insert",
    prefix = prefix.point_reading,
    action = "key",
    key = "<Esc>",
    expect = "I_POINT",
  },
  { id = "register.cancel.select.esc", profile = "insert", prefix = prefix.select, action = "key", key = "<Esc>", expect = "I_SELECT" },
  {
    id = "register.cancel.select.reading",
    profile = "insert",
    prefix = prefix.select_reading,
    action = "key",
    key = "<Esc>",
    expect = "I_SELECT",
  },
  -- 入れ子
  {
    id = "register.nested.open",
    profile = "insert",
    prefix = prefix.point .. "Nuru",
    action = "key",
    key = "<Space>",
    expect = "P_PROMPT",
  },
  {
    id = "register.nested.empty-cr",
    profile = "insert",
    prefix = prefix.point_nested,
    action = "key",
    key = "<CR>",
    expect = "P_PROMPT",
  },
  {
    id = "register.nested.cancel",
    profile = "insert",
    prefix = prefix.point_nested,
    action = "key",
    key = "<Esc>",
    expect = "P_PROMPT",
  },
  {
    id = "register.nested.cancel-twice",
    profile = "insert",
    prefix = prefix.point_nested,
    action = "key",
    key = "<Esc><Esc>",
    expect = "I_POINT",
  },
  {
    id = "register.nested.commit",
    profile = "insert",
    prefix = prefix.point_nested,
    action = "key",
    key = "a<CR>",
    expect = "P_PROMPT",
  },
  {
    id = "register.nested.commit-then-commit",
    profile = "insert",
    prefix = prefix.point_nested,
    action = "key",
    key = "a<CR><CR>",
    expect = "I_DIRECT",
  },
  {
    id = "register.nested.reading.commit",
    profile = "insert",
    prefix = prefix.point_nested,
    action = "key",
    key = "Kan<CR>",
    expect = "P_PROMPT",
  },
  {
    id = "register.nested.reading.cancel",
    profile = "insert",
    prefix = prefix.point_nested,
    action = "key",
    key = "Kan<Esc>",
    expect = "P_PROMPT",
  },
  {
    id = "register.nested.select.open",
    profile = "insert",
    prefix = prefix.select_reading .. string.rep("<Space>", 5),
    action = "key",
    key = "<Space>",
    expect = "P_PROMPT",
  },
  {
    id = "register.nested.select.cancel",
    profile = "insert",
    prefix = prefix.select_nested,
    action = "key",
    key = "<Esc>",
    expect = "P_PROMPT",
  },
  -- 欄の文字が変わるとき（ずれの検出で読みが捨てられる）
  {
    id = "register.left",
    profile = "insert",
    prefix = prefix.point_reading,
    action = "key",
    key = "<Left>",
    expect = "P_PROMPT",
  },
  {
    id = "register.ctrl-w",
    profile = "insert",
    prefix = prefix.point_reading,
    action = "key",
    key = "<C-w>",
    expect = "P_PROMPT",
  },
  {
    id = "register.ctrl-u",
    profile = "insert",
    prefix = prefix.point_reading,
    action = "key",
    key = "<C-u>",
    expect = "P_PROMPT",
  },
  { id = "register.tab", profile = "insert", prefix = prefix.point_reading, action = "key", key = "<Tab>", expect = "P_PROMPT" },
  {
    id = "register.ctrl-r",
    profile = "reg_a",
    prefix = prefix.point_reading,
    action = "key",
    key = "<C-r>a",
    expect = "P_PROMPT",
  },
  {
    id = "register.ctrl-r.empty",
    profile = "insert",
    prefix = prefix.point_reading,
    action = "key",
    key = "<C-r>a",
    expect = "P_PROMPT",
  },
  -- 対象外にするもの（cmdline window、履歴、深さ 3）
  {
    id = "register.cmdwin",
    profile = "insert",
    prefix = prefix.point,
    action = "key",
    key = "<C-f>",
    expect = "P_PROMPT",
  },
  {
    id = "register.history",
    profile = "history",
    prefix = prefix.point,
    action = "key",
    key = "<Up>",
    expect = "P_PROMPT",
  },
  {
    id = "register.depth3.open",
    profile = "insert",
    prefix = prefix.point_nested .. "Nuru",
    action = "key",
    key = "<Space>",
    expect = "P_PROMPT",
  },
  {
    id = "register.depth3.cancel",
    profile = "insert",
    prefix = prefix.point_depth3,
    action = "key",
    key = "<Esc><Esc><Esc>",
    expect = "I_POINT",
  },
  -- 過去の issue の再現キー列
  {
    id = "issue12.left.cr",
    profile = "insert",
    prefix = "A",
    action = "key",
    key = "<Space>A<Left><CR>",
    expect = "I_DIRECT",
  },
  {
    id = "issue116.ctrl-w.cg",
    profile = "insert",
    prefix = prefix.point_reading,
    action = "key",
    key = "<C-w><C-g>",
    expect = "I_POINT",
  },
  {
    id = "issue154.cc.cc",
    profile = "insert",
    prefix = "A",
    action = "key",
    key = "Kan<C-c><C-c>",
    expect = "N_OFF",
  },
  {
    id = "issue13.wincmd",
    profile = "two_windows",
    prefix = prefix.point,
    action = "wincmd",
    expect = "P_PROMPT",
  },
  {
    id = "issue13.wincmd.esc",
    profile = "two_windows",
    prefix = prefix.point,
    action = "wincmd_esc",
    expect = "I_POINT",
  },
}

local function parse_args(argv)
  local opts = {
    out = root .. "/semantics/explore/observations/register.jsonl",
  }
  local i = 1
  while i <= #argv do
    local arg = argv[i]
    if arg == "--out" then
      i = i + 1
      opts.out = argv[i]
    elseif arg == "--help" or arg == "-h" then
      opts.help = true
    else
      error(("知らない引数です: %s"):format(arg))
    end
    i = i + 1
  end
  return opts
end

local function snapshot()
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
    henkan_feed = obs.state.henkan_feed,
    preedit = obs.state.preedit,
    mark = observe.mark_text(obs),
    mode_marks = obs.preedit_marks,
    buffer = obs.buffer.lines,
    cursor = obs.buffer.cursor,
    cmdline = obs.cmdline,
    win = child.api.nvim_get_current_win(),
    mappings = obs.mappings,
    windows = obs.windows,
    buffers = obs.buffers,
    register_depth = obs.register_depth,
  }
end

local function run_case(case)
  local ok_reset = pcall(hooks.pre_case)
  if not ok_reset then
    pcall(child.stop)
    hooks.pre_case()
  end
  local ctx = profiles[case.profile]()
  if case.prefix ~= "" then
    helpers.type(child, case.prefix)
  end
  local before = snapshot()
  local ok, err = pcall(actions[case.action], ctx, case.key)
  if not ok then
    io.stderr:write(("アクション %s がエラー: %s\n"):format(case.id, tostring(err)))
  end
  helpers.settle(child)
  local after = snapshot()
  return before, after, ctx
end

local function main(argv)
  local opts = parse_args(argv)
  if opts.help then
    print("使い方: nvim --headless -u NONE -i NONE -l semantics/explore/register.lua [--out path]")
    return 0
  end

  vim.fn.mkdir(vim.fs.dirname(opts.out), "p")
  local file = assert(io.open(opts.out, "w"))
  local failures = 0
  local rows = {}
  local stamp = os.date("%Y%m%d-%H%M%S")

  for _, case in ipairs(cases) do
    local before, after, ctx = run_case(case)
    local matched = after.class == case.expect
    if not matched then
      failures = failures + 1
    end
    local record = {
      run = "register-" .. stamp,
      scenario = case.id,
      profile = case.profile,
      prefix = case.prefix,
      action = case.action,
      key = case.key,
      frame_win = ctx and ctx.win or -1,
      from = before.class,
      to = after.class,
      expect = case.expect,
      ok = matched,
      before = compact(before),
      after = compact(after),
    }
    file:write(vim.json.encode(record), "\n")
    rows[#rows + 1] = record
    print(
      ("%s %-30s %s -> %s（期待 %s）depth=%d"):format(
        matched and "✓" or "✗",
        case.id,
        record.from,
        record.to,
        case.expect,
        after.register_depth or 0
      )
    )
  end

  file:close()
  print(("観測 %d 件: 一致 %d / 不一致 %d"):format(#rows, #rows - failures, failures))
  print(("JSONL: %s"):format(opts.out))
  return failures == 0 and 0 or 1
end

local code = main(arg)
hooks.post_once()
os.exit(code)

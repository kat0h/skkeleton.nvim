-- 貼り付け・マウス・ホイール・WinLeave / BufLeave の観測（#191、親は #179）
--
-- 子の nvim に実際の入力（vim.paste、nvim_input_mouse、autocmd）を起こし、
-- 1 つの出来事の前後の状態クラスを JSONL に書く。キーの観測は explore.lua の
-- --replay / --bfs で取れるが、これらの出来事はキーではないので、ここで起こす。
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/explore/misc.lua
--   nvim --headless -u NONE -i NONE -l semantics/explore/misc.lua --out /tmp/misc.jsonl
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
local work = root .. "/.tests/misc"
vim.fn.mkdir(work, "p")
vim.env.XDG_CACHE_HOME = work .. "/cache"
vim.env.XDG_STATE_HOME = work .. "/state"
require("mini.test").setup({})

local observe = require("semantics.explore.observe")
local helpers = require("helpers")

-- 子は 1 つだけ作り、ケースごとに pre_case で作り直す
local set, child = helpers.e2e_set()
local hooks = getmetatable(set).opts.hooks

local enable = "<Plug>(skkeleton-enable)"

-- 子の準備。prefix はこのあとに流す
local profiles = {
  insert = function()
    helpers.type(child, "i" .. enable)
    return {}
  end,
  off = function()
    helpers.type(child, "i")
    return {}
  end,
  mouse = function()
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    helpers.type(child, "i" .. enable)
    return {}
  end,
  two_windows = function()
    child.cmd("new")
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "bottom" })
    child.cmd("wincmd k")
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    helpers.type(child, "i" .. enable)
    return {}
  end,
  two_buffers = function()
    local first = child.api.nvim_get_current_buf()
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "one" })
    child.cmd("setlocal nomodified")
    child.cmd("enew")
    local second = child.api.nvim_get_current_buf()
    child.cmd("buffer " .. first)
    helpers.type(child, "i" .. enable)
    return { second = second }
  end,
}

-- 出来事
local actions = {
  paste = function()
    child.lua([[vim.paste({ "PASTED" }, -1)]])
  end,
  paste_chunks = function()
    child.lua([[vim.paste({ "ONE" }, 1)]])
    helpers.settle(child)
    child.lua([[vim.paste({ "TWO" }, 2)]])
    helpers.settle(child)
    child.lua([[vim.paste({}, 3)]])
  end,
  click_cursor = function()
    -- いまのカーソルと同じ列をクリックする（カーソルが動かない）
    local row, col = unpack(child.api.nvim_win_get_cursor(0))
    child.api.nvim_input_mouse("left", "press", "", 0, row - 1, col)
    child.api.nvim_input_mouse("left", "release", "", 0, row - 1, col)
  end,
  click_left = function()
    child.api.nvim_input_mouse("left", "press", "", 0, 0, 2)
    child.api.nvim_input_mouse("left", "release", "", 0, 0, 2)
  end,
  click_other = function()
    child.api.nvim_input_mouse("left", "press", "", 0, 20, 2)
    child.api.nvim_input_mouse("left", "release", "", 0, 20, 2)
  end,
  dclick_left = function()
    for _ = 1, 2 do
      child.api.nvim_input_mouse("left", "press", "", 0, 0, 2)
      child.api.nvim_input_mouse("left", "release", "", 0, 0, 2)
    end
  end,
  drag = function()
    child.api.nvim_input_mouse("left", "press", "", 0, 0, 2)
    vim.uv.sleep(20)
    child.api.nvim_input_mouse("left", "drag", "", 0, 0, 4)
    vim.uv.sleep(20)
    child.api.nvim_input_mouse("left", "release", "", 0, 0, 4)
  end,
  wheel_up = function()
    child.api.nvim_input_mouse("wheel", "up", "", 0, 0, 0)
  end,
  wheel_down = function()
    child.api.nvim_input_mouse("wheel", "down", "", 0, 0, 0)
  end,
  wincmd = function()
    child.cmd("wincmd w")
  end,
  new_window = function()
    child.cmd("new")
  end,
  next_buffer = function(ctx)
    child.cmd("buffer! " .. ctx.second)
  end,
  key = function(_, key)
    pcall(helpers.type, child, key)
  end,
}

-- 1 つの観測。expected はモデルの状態クラス
local cases = {
  { id = "paste.direct", profile = "insert", prefix = "", action = "paste", expect = "I_DIRECT" },
  { id = "paste.romaji", profile = "insert", prefix = "K", action = "paste", expect = "I_DIRECT" },
  { id = "paste.point", profile = "insert", prefix = "Kan", action = "paste", expect = "I_DIRECT" },
  { id = "paste.select", profile = "insert", prefix = "Kan<Space>", action = "paste", expect = "I_DIRECT" },
  { id = "paste.off", profile = "off", prefix = "", action = "paste", expect = "I_OFF" },
  { id = "paste.chunks", profile = "insert", prefix = "Kan", action = "paste_chunks", expect = "I_DIRECT" },

  { id = "mouse.click.end", profile = "mouse", prefix = "Kan", action = "click_cursor", expect = "I_POINT" },
  { id = "mouse.click.left", profile = "mouse", prefix = "Kan", action = "click_left", expect = "I_DIRECT" },
  { id = "mouse.click.romaji", profile = "mouse", prefix = "K", action = "click_left", expect = "I_DIRECT" },
  { id = "mouse.click.select", profile = "mouse", prefix = "Kan<Space>", action = "click_left", expect = "I_DIRECT" },
  { id = "mouse.click.direct", profile = "mouse", prefix = "", action = "click_left", expect = "I_DIRECT" },
  { id = "mouse.click.off", profile = "off", prefix = "", action = "click_left", expect = "I_OFF" },
  { id = "mouse.dclick.direct", profile = "mouse", prefix = "", action = "dclick_left", expect = "N_OFF" },
  { id = "mouse.dclick.point", profile = "mouse", prefix = "Kan", action = "dclick_left", expect = "N_OFF" },
  { id = "mouse.dclick.select", profile = "mouse", prefix = "Kan<Space>", action = "dclick_left", expect = "N_OFF" },
  { id = "mouse.dclick.off", profile = "off", prefix = "", action = "dclick_left", expect = "N_OFF" },
  { id = "mouse.drag.point", profile = "mouse", prefix = "Kan", action = "drag", expect = "N_OFF" },
  { id = "mouse.otherwin.point", profile = "two_windows", prefix = "Kan", action = "click_other", expect = "I_OFF" },
  { id = "mouse.otherwin.romaji", profile = "two_windows", prefix = "K", action = "click_other", expect = "I_OFF" },
  {
    id = "mouse.otherwin.select",
    profile = "two_windows",
    prefix = "Kan<Space>",
    action = "click_other",
    expect = "I_OFF",
  },
  { id = "mouse.otherwin.direct", profile = "two_windows", prefix = "", action = "click_other", expect = "I_OFF" },

  { id = "wheel.up.point", profile = "mouse", prefix = "Kan", action = "wheel_up", expect = "I_POINT" },
  { id = "wheel.down.point", profile = "mouse", prefix = "Kan", action = "wheel_down", expect = "I_POINT" },
  { id = "wheel.up.romaji", profile = "mouse", prefix = "K", action = "wheel_up", expect = "I_ROMAJI" },
  { id = "wheel.up.select", profile = "mouse", prefix = "Kan<Space>", action = "wheel_up", expect = "I_SELECT" },
  { id = "wheel.up.direct", profile = "mouse", prefix = "", action = "wheel_up", expect = "I_DIRECT" },
  { id = "wheel.up.off", profile = "off", prefix = "", action = "wheel_up", expect = "I_OFF" },

  { id = "winleave.point", profile = "two_windows", prefix = "Kan", action = "wincmd", expect = "I_OFF" },
  { id = "winleave.direct", profile = "two_windows", prefix = "", action = "wincmd", expect = "I_OFF" },
  { id = "winleave.new.point", profile = "insert", prefix = "Kan", action = "new_window", expect = "I_OFF" },
  {
    id = "winleave.visual.mouse",
    profile = "two_windows",
    prefix = "Kan<C-o>v",
    action = "click_other",
    expect = "I_OFF",
  },
  { id = "bufleave.point", profile = "two_buffers", prefix = "Kan", action = "next_buffer", expect = "I_OFF" },
  { id = "bufleave.direct", profile = "two_buffers", prefix = "", action = "next_buffer", expect = "I_OFF" },

  { id = "guard.point.cdot", profile = "insert", prefix = "Kan", action = "key", key = "<C-.>", expect = "I_DIRECT" },
  { id = "guard.point.f5", profile = "insert", prefix = "Kan", action = "key", key = "<F5>", expect = "I_DIRECT" },
  { id = "guard.point.s-cr", profile = "insert", prefix = "Kan", action = "key", key = "<S-CR>", expect = "I_DIRECT" },
  { id = "guard.point.left", profile = "insert", prefix = "Kan", action = "key", key = "<Left>", expect = "I_DIRECT" },
  {
    id = "guard.point.c-left",
    profile = "insert",
    prefix = "Kan",
    action = "key",
    key = "<C-Left>",
    expect = "I_DIRECT",
  },
  { id = "guard.point.s-up", profile = "insert", prefix = "Kan", action = "key", key = "<S-Up>", expect = "I_DIRECT" },
  { id = "guard.point.s-f1", profile = "insert", prefix = "Kan", action = "key", key = "<S-F1>", expect = "I_DIRECT" },
  {
    id = "guard.select.left",
    profile = "insert",
    prefix = "Kan<Space>",
    action = "key",
    key = "<Left>",
    expect = "I_DIRECT",
  },
  { id = "guard.romaji.cdot", profile = "insert", prefix = "K", action = "key", key = "<C-.>", expect = "I_DIRECT" },
  { id = "guard.direct.cdot", profile = "insert", prefix = "", action = "key", key = "<C-.>", expect = "I_DIRECT" },
  { id = "guard.off.cdot", profile = "off", prefix = "", action = "key", key = "<C-.>", expect = "I_OFF" },

  { id = "ctrl-at.point", profile = "insert", prefix = "Kan", action = "key", key = "<C-@>", expect = "N_OFF" },
  { id = "ctrl-at.select", profile = "insert", prefix = "Kan<Space>", action = "key", key = "<C-@>", expect = "N_OFF" },
  { id = "ctrl-at.direct", profile = "insert", prefix = "", action = "key", key = "<C-@>", expect = "N_OFF" },
  { id = "ctrl-at.off", profile = "off", prefix = "", action = "key", key = "<C-@>", expect = "N_OFF" },
  { id = "ctrl-a.empty", profile = "insert", prefix = "Kan", action = "key", key = "<C-a>", expect = "I_POINT" },
}

local function parse_args(argv)
  local opts = {
    out = root .. "/semantics/explore/observations/misc.jsonl",
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
  return before, after
end

local function main(argv)
  local opts = parse_args(argv)
  if opts.help then
    print("使い方: nvim --headless -u NONE -i NONE -l semantics/explore/misc.lua [--out path]")
    return 0
  end

  vim.fn.mkdir(vim.fs.dirname(opts.out), "p")
  local file = assert(io.open(opts.out, "w"))
  local failures = 0
  local rows = {}
  local stamp = os.date("%Y%m%d-%H%M%S")

  for _, case in ipairs(cases) do
    -- マウスのドラッグは、ヘッドレスでイベントが落ちることがあるので数回試す
    local attempts = case.id == "mouse.drag.point" and 3 or 1
    local before, after, matched
    for attempt = 1, attempts do
      before, after = run_case(case)
      matched = after.class == case.expect
      if matched or attempt == attempts then
        break
      end
      io.stderr:write(("%s: %s（%d 回目）\n"):format(case.id, after.class, attempt))
    end
    if not matched then
      failures = failures + 1
    end
    local record = {
      run = "misc-" .. stamp,
      scenario = case.id,
      profile = case.profile,
      prefix = case.prefix,
      action = case.action,
      key = case.key,
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
      ("%s %-24s %s -> %s（期待 %s）"):format(
        matched and "✓" or "✗",
        case.id,
        record.from,
        record.to,
        case.expect
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

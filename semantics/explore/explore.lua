-- 実際の打鍵で skkeleton の状態を探索する黒箱探索器。
--
-- 子の nvim に 1 キーずつ実際の打鍵として流し、1 キーごとの観測を JSONL に書く。
-- 探索の方法は、アルファベットを与えた幅優先（深さ 3〜5）と、ランダムなキー列を流す
-- ファジング。`Kan` のようなまとまったキーは、探索では 1 つのマクロとして扱う。
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --replay "i,<Plug>(skkeleton-enable),Kan"
--   nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --bfs --profile insert --depth 3
--   nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --fuzz 50 --length 20
--
-- テストと同じ子の nvim（tests/helpers.lua の e2e_set）を使う。辞書は一時ディレクトリに
-- 置き、シェルの履歴は HISTFILE=/dev/null にする。
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
-- 子が作るキャッシュと状態を、この作業ツリーの中に分ける
local work = root .. "/.tests/explore"
vim.fn.mkdir(work, "p")
vim.env.XDG_CACHE_HOME = work .. "/cache"
vim.env.XDG_STATE_HOME = work .. "/state"
require("mini.test").setup({})

local observe = require("semantics.explore.observe")
local helpers = require("helpers")

local M = {}

-- 1 文字ずつに分ける（UTF-8 の文字単位）
---@param s string
---@return string[]
local function chars(s)
  local out = {}
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    out[#out + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return out
end

-- キー列を、実際に送るキーに分ける。`<Plug>(...)` と `<...>` は 1 つのキーとして扱う
---@param s string
---@return string[]
function M.scan_keys(s)
  local keys = {}
  local i = 1
  while i <= #s do
    if s:sub(i, i + 5) == "<Plug>" then
      local close = s:find(")", i, true)
      if close then
        keys[#keys + 1] = s:sub(i, close)
        i = close + 1
      else
        keys[#keys + 1] = s:sub(i, i)
        i = i + 1
      end
    elseif s:sub(i, i) == "<" then
      local close = s:find(">", i, true)
      if close then
        keys[#keys + 1] = s:sub(i, close)
        i = close + 1
      else
        keys[#keys + 1] = s:sub(i, i)
        i = i + 1
      end
    else
      local j = s:find("<", i, true) or (#s + 1)
      for _, ch in ipairs(chars(s:sub(i, j - 1))) do
        keys[#keys + 1] = ch
      end
      i = j
    end
  end
  return keys
end

-- 探索のアルファベット。まとまったキーは 1 つの遷移（マクロ）として扱う
local MACROS = {
  ["Kan"] = "Kan",
  ["KaeRu"] = "KaeRu",
  ["Nihon"] = "Nihon",
  ["Kan<Space>"] = "Kan<Space>",
  ["<C-o>v"] = "<C-o>v",
  ["<C-o>R"] = "<C-o>R",
  ["<C-o>:"] = "<C-o>:",
  ["<Plug>(skkeleton-enable)"] = "<Plug>(skkeleton-enable)",
  ["<Plug>(skkeleton-disable)"] = "<Plug>(skkeleton-disable)",
}

-- 1 文字ずつ送ると成り立たないキー。q は次の文字（レジスタ名）を待つので、
-- `qa` をまとめて送る（#192）
local RAW = {
  qa = true,
  ["@a"] = true,
  ["3@a"] = true,
}

-- 文字のキーは、そのまま 1 つの遷移にする
---@param name string
---@return table
local function token(name)
  return { name = name, keys = name }
end

-- blink.cmp の置き場所。観測のためだけに使い、リポジトリには入れない。
-- BLINK_PATH を設定すれば、そこを使う（テストの .tests/mini.nvim と同じ扱い）
local BLINK_PATH = os.getenv("BLINK_PATH") or (root .. "/.tests/blink.cmp")

-- blink.cmp を子に読み込ませる。sources.default は README の静的な一覧ではなく、
-- #24 の再現用に有効・無効で切り替える関数にする
---@param child table
local function setup_blink(child)
  if not vim.uv.fs_stat(BLINK_PATH) then
    error(("blink.cmp がありません（%s）"):format(BLINK_PATH))
  end
  child.lua(
    [[
    vim.opt.rtp:append(...)
    vim.cmd("runtime plugin/blink-cmp.lua")
    require("blink.cmp").setup({
      keymap = { preset = "super-tab", ["<Space>"] = {} },
      completion = { list = { selection = { preselect = true, auto_insert = true } } },
      sources = {
        default = function()
          if require("skkeleton").is_enabled() then
            return { "skkeleton" }
          end
          return { "buffer" }
        end,
        providers = { skkeleton = { name = "skkeleton", module = "skkeleton.completion.blink" } },
      },
      fuzzy = { implementation = "lua" },
    })
  ]],
    { BLINK_PATH }
  )
end

-- プロファイルごとの、子を作ったあとに流す準備と、アルファベット
local PROFILES = {
  none = {
    setup = function() end,
    alphabet = { "a", "K", "<Space>", "<Esc>", "<Insert>", "<C-o>" },
  },
  insert = {
    setup = function(child)
      helpers.type(child, "i<Plug>(skkeleton-enable)")
    end,
    alphabet = {
      "a",
      "k",
      "K",
      "A",
      "<Space>",
      "<C-j>",
      "<C-g>",
      "<Esc>",
      "<C-c>",
      "<Insert>",
      "<C-o>",
      "<C-w>",
      "<C-u>",
      "<Tab>",
      "<S-Tab>",
      "<C-n>",
      "<Left>",
      "Kan",
      "KaeRu",
      "Kan<Space>",
      "<C-o>v",
      "<C-o>R",
      "<C-o>:",
    },
  },
  normal = {
    setup = function(child)
      helpers.type(child, "<Esc>")
    end,
    alphabet = { "i", "a", "v", "V", "R", "<C-o>", ":", "q", "<Esc>" },
  },
  -- マクロと `.`（#192）。記録と再生は normal のキーなので、行のあるバッファから始める
  macro = {
    setup = function(child)
      child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd", "ef gh", "ij kl" })
      child.api.nvim_win_set_cursor(0, { 1, 5 })
    end,
    alphabet = {
      "qa",
      "q",
      "A",
      "<Plug>(skkeleton-enable)",
      "Kan<Space><C-j>",
      "<Esc>",
      "j",
      "@a",
      ".",
    },
  },
  cmdline = {
    setup = function(child)
      helpers.type(child, ":<Plug>(skkeleton-enable)")
    end,
    alphabet = {
      "a",
      "K",
      "<Space>",
      "<C-j>",
      "<C-g>",
      "<Esc>",
      "<C-c>",
      "<Tab>",
      "<Left>",
      "<CR>",
      "Kan",
      "KaeRu",
    },
  },
  terminal = {
    setup = function(child)
      child.cmd("terminal cat")
      helpers.type(child, "i")
      helpers.type(child, "<Plug>(skkeleton-enable)")
    end,
    alphabet = {
      "a",
      "K",
      "<Space>",
      "<C-j>",
      "<C-g>",
      "<Esc>",
      "<C-c>",
      "<C-r>",
      "<Tab>",
      "<C-\\><C-n>",
      "Kan",
    },
  },
  register = {
    -- 候補を最後まで送って、登録のプロンプトが開く 1 つ手前から始める
    setup = function(child)
      helpers.type(child, "i<Plug>(skkeleton-enable)Kan<Space><Space><Space><Space><Space>")
    end,
    alphabet = {
      "a",
      "K",
      "<Space>",
      "<CR>",
      "<Esc>",
      "<C-c>",
      "<C-g>",
      "<Tab>",
      "<Left>",
    },
  },
  expr = {
    -- insert から <C-r>= で式の入力を開いたところ。そこから <CR> で insert に戻る
    setup = function(child)
      helpers.type(child, "i<Plug>(skkeleton-enable)<C-r>=")
    end,
    alphabet = { "1", "<CR>", "<Esc>", "<C-c>" },
  },
  mouse = {
    -- 同じウィンドウのクリックで pre-edit を確定させる。行に文字を置いておく
    setup = function(child)
      child.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
      child.api.nvim_win_set_cursor(0, { 1, 6 })
      helpers.type(child, "i<Plug>(skkeleton-enable)")
    end,
    alphabet = { "a", "K", "Kan" },
  },
  completion = {
    setup = function(child)
      child.api.nvim_buf_set_lines(0, 0, -1, false, { "あいうえお", "" })
      child.api.nvim_win_set_cursor(0, { 2, 0 })
      helpers.type(child, "i<Plug>(skkeleton-enable)")
    end,
    alphabet = {
      "a",
      "<C-n>",
      "<C-p>",
      "<C-x>",
      "<C-x><C-n>",
      "<C-y>",
      "<C-e>",
      "<CR>",
      "<Tab>",
      "<BS>",
      "<C-g>",
      "<Esc>",
      "<C-c>",
      "Kan",
    },
  },
  blink = {
    -- blink.cmp を子に読み込ませたうえで、送りなしの読みを打てる行から始める
    wait_ms = 100,
    setup = function(child)
      child.api.nvim_buf_set_lines(0, 0, -1, false, { "あいうえお", "" })
      child.api.nvim_win_set_cursor(0, { 2, 0 })
      setup_blink(child)
      helpers.type(child, "i<Plug>(skkeleton-enable)")
    end,
    alphabet = {
      "K",
      "a",
      "n",
      "j",
      "Kanj",
      "Kanji",
      "<Tab>",
      "<S-Tab>",
      "<C-n>",
      "<C-p>",
      "<CR>",
      "<C-e>",
      "<Space>",
      "<BS>",
      "<C-g>",
      "<C-w>",
      "<Esc>",
      "<C-c>",
    },
  },
  -- #143 / #174 の再現。文字のある行の行末で、pre-edit の近くにメニューが出るかを見る
  blink_line = {
    wait_ms = 100,
    setup = function(child)
      child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
      child.api.nvim_win_set_cursor(0, { 1, 5 })
      setup_blink(child)
      helpers.type(child, "i<Plug>(skkeleton-enable)")
    end,
    alphabet = { "Kanji", "Henkan", "q", "<Space>", "<C-j>", "<CR>", "<Tab>", "<C-e>" },
  },
  -- #24 の再現。無効のあいだは buffer の補完が出て、<C-j> で有効にする
  blink_buffer = {
    wait_ms = 100,
    setup = function(child)
      child.api.nvim_buf_set_lines(0, 0, -1, false, { "Kanji", "" })
      child.api.nvim_win_set_cursor(0, { 2, 0 })
      setup_blink(child)
      child.lua([[vim.keymap.set("i", "<C-j>", "<Plug>(skkeleton-enable)")]])
      helpers.type(child, "i")
    end,
    alphabet = {
      "Kanji",
      "<CR>",
      "Kan",
      "<C-j>",
      "<C-n>",
      "<C-p>",
      "<Esc>",
    },
  },
}

-- アルファベットの名前を、遷移の表にする
---@param names string[]
---@return table[]
function M.alphabet(names)
  local out = {}
  for _, name in ipairs(names) do
    if MACROS[name] then
      out[#out + 1] = { name = name, keys = MACROS[name], macro = true }
    elseif RAW[name] then
      out[#out + 1] = { name = name, keys = name, raw = true }
    else
      out[#out + 1] = token(name)
    end
  end
  return out
end

-- 観測の抽象化。幅優先で同じ状態を 2 度広げないための鍵
---@param obs table
---@return string
function M.state_key(obs)
  local lines = obs.buffer.lines or {}
  return table.concat({
    obs.class,
    obs.enabled and "1" or "0",
    obs.skk_mode,
    obs.state.phase,
    obs.state.preedit,
    obs.cmdline.type,
    obs.cmdline.line,
    obs.terminal.tail,
    obs.popup.shown and "1" or "0",
    obs.completion and obs.completion.menu and "1" or "0",
    tostring(obs.register_depth),
    obs.registers and obs.registers.recording or "",
    obs.registers and obs.registers.executing or "",
    tostring(obs.mappings.skk),
    tostring(#lines),
    tostring(obs.buffer.cursor[1]),
    tostring(obs.buffer.cursor[2]),
  }, "\0")
end

-- 子の nvim と、その子を作り直すためのフック
local Runner = {}
Runner.__index = Runner

---@param profile table
---@param run_id string
---@return table
local function new_runner(profile, run_id)
  local set, child = helpers.e2e_set()
  local self = setmetatable({
    set = set,
    child = child,
    hooks = getmetatable(set).opts.hooks,
    profile = profile,
    run_id = run_id,
    last_dir = nil,
    edges = {},
    token_edges = {},
    classes = {},
    records = 0,
  }, Runner)
  return self
end

-- 子の前の辞書の一時ディレクトリを消す。子を止めたあとに呼ぶ
function Runner:cleanup_dir()
  if self.last_dir then
    vim.fn.delete(self.last_dir, "rf")
    self.last_dir = nil
  end
end

-- 子を作り直して、プロファイルの準備を流す
function Runner:reset()
  local ok = pcall(self.hooks.pre_case)
  if not ok then
    -- 入力待ちのまま止まることがある。いったん止めてから作り直す
    pcall(self.child.stop)
    self.hooks.pre_case()
  end
  self:cleanup_dir()
  self.last_dir = self.child.lua_get("_G.dir")
  self.profile.setup(self.child)
end

function Runner:stop()
  local dir = self.last_dir
  self.last_dir = nil
  self.hooks.post_once()
  if dir then
    vim.fn.delete(dir, "rf")
  end
end

-- 今の観測。子が入力待ちで観測できないときは、<Esc> と <C-c> で戻してから
-- もう一度試す。それでもだめなら BLOCKED の観測を返す
---@return table
function Runner:observe()
  local ok, obs = pcall(observe.snapshot, self.child)
  if not ok then
    pcall(self.child.type_keys, "<Esc>")
    pcall(self.child.type_keys, "<C-c>")
    local ok2, observed = pcall(observe.snapshot, self.child)
    if not ok2 then
      local reason = tostring(obs)
      return {
        class = "BLOCKED",
        vim_mode = "",
        enabled = false,
        skk_mode = "",
        state = { phase = "", henkan_feed = "", preedit = "" },
        buftype = "",
        buffer = { lines = {}, text = "", cursor = { 0, 0 }, changedtick = 0 },
        preedit_marks = {},
        cmdline = { type = "", line = "", pos = 0 },
        terminal = { active = false, line_count = 0, lines = {}, tail = "", cursor = { 0, 0 } },
        popup = { shown = false, count = 0, lines = {} },
        mappings = { i = 0, c = 0, t = 0, skk = 0 },
        register_depth = 0,
        windows = 0,
        buffers = 0,
        error = reason,
      }
    end
    obs = observed
  end
  obs.class = observe.classify(obs)
  self.classes[obs.class] = (self.classes[obs.class] or 0) + 1
  return obs
end

-- 1 キーを実際の打鍵として流す
---@param key string
---@return boolean ok, string? err
function Runner:feed(key)
  local ok, err = pcall(helpers.type, self.child, key)
  -- blink.cmp のメニューはタイマーで開くので、少し待ってから観測する
  if ok and self.profile.wait_ms then
    vim.wait(self.profile.wait_ms, function()
      return false
    end)
  end
  return ok, ok and nil or tostring(err)
end

function Runner:record_edge(from, event, to)
  local key = from .. "\0" .. event .. "\0" .. to
  local edge = self.edges[key]
  if edge then
    edge.count = edge.count + 1
  else
    self.edges[key] = { from = from, event = event, to = to, count = 1 }
  end
end

function Runner:record_token_edge(from, event, to)
  local key = from .. "\0" .. event .. "\0" .. to
  local edge = self.token_edges[key]
  if edge then
    edge.count = edge.count + 1
  else
    self.token_edges[key] = { from = from, event = event, to = to, count = 1 }
  end
end

-- JSONL を書く。1 行に 1 つの観測
local function write_jsonl(file, record)
  if not file then
    return
  end
  file:write(vim.json.encode(record), "\n")
end

-- 1 つの遷移（マクロなら複数のキー）を流し、キーごとに観測を書く。
-- 戻り値は、流したあとの観測。途中で子が止まったら nil とエラーを返す
---@param runner table
---@param tok table
---@param seq string[]
---@param file file?
---@param write boolean
---@return table? obs, string? err
local function feed_token(runner, tok, seq, file, write, record)
  local before = runner:observe()
  local from = before.class
  -- raw のトークンは、キー列をまとめて 1 回で送る（`qa` など次の文字を待つもの）
  local keys = tok.raw and { tok.keys } or M.scan_keys(tok.keys)
  for _, key in ipairs(keys) do
    local ok, err = runner:feed(key)
    local after
    if ok then
      after = runner:observe()
    else
      -- コマンドの実行などで Neovim がエラーを返しても、子はまだ観測できることがある。
      -- そのときは観測を残して先へ進む。観測できないなら止める
      local ok_obs, observed = pcall(runner.observe, runner)
      if not ok_obs then
        return nil, err
      end
      after = observed
      after.error = err
    end
    if after.class == "BLOCKED" then
      return nil, after.error
    end
    if write then
      write_jsonl(file, {
        run = runner.run_id,
        profile = runner.profile.name,
        seq = vim.deepcopy(seq),
        token = tok.name,
        key = key,
        from = before.class,
        to = after.class,
        obs = after,
      })
      runner.records = runner.records + 1
    end
    if record ~= false then
      runner:record_edge(before.class, key, after.class)
    end
    before = after
  end
  if record ~= false then
    runner:record_token_edge(from, tok.name, before.class)
  end
  return before
end

-- キー列を流す。prefix の分は観測を書かない（幅優先で同じ前置きを何度も流すため）
---@param runner table
---@param tokens table[]
---@param file file?
---@param write_from integer 1 起点。この番号より後ろの遷移だけ書く
---@return table? obs, string? err
local function feed_tokens(runner, tokens, file, write_from)
  local obs = runner:observe()
  local seq = {}
  for i, tok in ipairs(tokens) do
    seq[#seq + 1] = tok.name
    local write = i >= (write_from or 1)
    local next_obs, err = feed_token(runner, tok, seq, file, write, write)
    if not next_obs then
      return nil, err
    end
    obs = next_obs
  end
  return obs
end

-- 観測を 1 行の要約にする（表示用）
---@param obs table
---@return string
local function line(obs)
  local parts = {
    ("%-9s"):format(obs.class),
    ("mode=%-5s"):format(obs.vim_mode),
    ("enabled=%-5s"):format(tostring(obs.enabled)),
    ("skk=%-7s"):format(obs.skk_mode),
    ("phase=%-15s"):format(obs.state.phase),
    ("preedit=%q"):format(obs.state.preedit),
    ("depth=%d"):format(obs.register_depth),
  }
  return table.concat(parts, " ")
end

-- エッジを並べる
---@param edges table
---@return table[]
local function sorted_edges(edges)
  local out = {}
  for _, edge in pairs(edges) do
    out[#out + 1] = edge
  end
  table.sort(out, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    if a.event ~= b.event then
      return a.event < b.event
    end
    return a.to < b.to
  end)
  return out
end

-- 結果を表示して、要約を Markdown で書く
---@param runner table
---@param out_path string
---@param summary_path string?
local function report(runner, out_path, summary_path)
  local classes = {}
  for class in pairs(runner.classes) do
    classes[#classes + 1] = class
  end
  table.sort(classes)

  local edges = sorted_edges(runner.edges)
  print(
    ("観測: %d 行, 状態クラス: %d 種類 (%s)"):format(runner.records, #classes, table.concat(classes, ", "))
  )
  print(("遷移: %d 種類"):format(#edges))

  local md = { "# 探索の結果", "", ("- プロファイル: `%s`"):format(runner.profile.name), "" }
  md[#md + 1] = "## 状態クラス"
  md[#md + 1] = ""
  for _, class in ipairs(classes) do
    md[#md + 1] = ("- `%s`: %d 回"):format(class, runner.classes[class])
  end
  md[#md + 1] = ""
  md[#md + 1] = "## キーごとの遷移"
  md[#md + 1] = ""
  md[#md + 1] = "| 前 | キー | 後 | 回数 |"
  md[#md + 1] = "|---|---|---|---|"
  for _, edge in ipairs(edges) do
    md[#md + 1] = ("| `%s` | `%s` | `%s` | %d |"):format(edge.from, edge.event, edge.to, edge.count)
  end
  md[#md + 1] = ""
  md[#md + 1] = "## マクロごとの遷移"
  md[#md + 1] = ""
  md[#md + 1] = "| 前 | マクロ | 後 | 回数 |"
  md[#md + 1] = "|---|---|---|---|"
  for _, edge in ipairs(sorted_edges(runner.token_edges)) do
    md[#md + 1] = ("| `%s` | `%s` | `%s` | %d |"):format(edge.from, edge.event, edge.to, edge.count)
  end
  md[#md + 1] = ""
  local text = table.concat(md, "\n")
  print(("JSONL: %s"):format(out_path))
  if summary_path then
    vim.fn.mkdir(vim.fs.dirname(summary_path), "p")
    vim.fn.writefile(vim.split(text, "\n", { plain = true }), summary_path)
    print(("要約: %s"):format(summary_path))
  end
end

-- 新しい JSONL を開く
---@param path string
---@return file
local function open_jsonl(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local file, err = io.open(path, "w")
  if not file then
    error(("JSONL を開けません: %s (%s)"):format(path, err))
  end
  return file
end

-- キー列をコンマで分ける。コンマが無ければ、そのまま 1 本のキー列として分ける
---@param s string
---@return table[]
function M.parse_replay(s)
  local tokens = {}
  if s:find(",", 1, true) then
    for part in s:gmatch("[^,]+") do
      part = vim.trim(part)
      if part ~= "" then
        if MACROS[part] then
          tokens[#tokens + 1] = { name = part, keys = MACROS[part], macro = true }
        elseif RAW[part] then
          tokens[#tokens + 1] = { name = part, keys = part, raw = true }
        else
          tokens[#tokens + 1] = { name = part, keys = part }
        end
      end
    end
    return tokens
  end

  -- コンマが無いときは、`<...>` と 1 文字ずつに分ける
  for _, key in ipairs(M.scan_keys(s)) do
    tokens[#tokens + 1] = { name = key, keys = key }
  end
  return tokens
end

-- 幅優先探索
---@param runner table
---@param alphabet table[]
---@param depth integer
---@param max_sequences integer
---@param file file
local function bfs(runner, alphabet, depth, max_sequences, file)
  local queue = { {} }
  local head = 1
  local seen = {}
  local root = runner:observe()
  seen[M.state_key(root)] = true
  write_jsonl(file, {
    run = runner.run_id,
    profile = runner.profile.name,
    seq = {},
    token = nil,
    key = nil,
    from = nil,
    to = root.class,
    obs = root,
  })
  runner.records = runner.records + 1

  local count = 0
  while head <= #queue and count < max_sequences do
    local path = queue[head]
    head = head + 1
    if #path < depth then
      for _, tok in ipairs(alphabet) do
        if count >= max_sequences then
          break
        end
        count = count + 1
        local seq = {}
        for _, p in ipairs(path) do
          seq[#seq + 1] = p.name
        end
        seq[#seq + 1] = tok.name
        local label = table.concat(seq, ",")

        local ok_reset = pcall(runner.reset, runner)
        if not ok_reset then
          print(("子を作り直せませんでした: %s"):format(label))
        else
          local before, err = feed_tokens(runner, path, file, 0)
          if not before then
            print(("前置きで止まりました: %s (%s)"):format(label, err))
          else
            local after, ferr = feed_token(runner, tok, seq, file, true)
            if not after then
              print(("止まりました: %s (%s)"):format(label, ferr))
            else
              local key = M.state_key(after)
              if not seen[key] then
                seen[key] = true
                queue[#queue + 1] = vim.list_extend(vim.deepcopy(path), { tok })
              end
            end
          end
        end
      end
    end
  end
  print(("幅優先: 広げた遷移 %d 個, 残った状態 %d 個"):format(count, #queue))
end

-- ファジング（ランダムなキー列）
---@param runner table
---@param alphabet table[]
---@param count integer
---@param length integer
---@param seed integer
---@param file file
local function fuzz(runner, alphabet, count, length, seed, file)
  math.randomseed(seed)
  for i = 1, count do
    local ok_reset = pcall(runner.reset, runner)
    if not ok_reset then
      print(("ファジング %d: 子を作り直せませんでした"):format(i))
    else
      local root = runner:observe()
      write_jsonl(file, {
        run = runner.run_id,
        profile = runner.profile.name,
        seq = {},
        token = nil,
        key = nil,
        from = nil,
        to = root.class,
        obs = root,
      })
      local tokens = {}
      for _ = 1, length do
        tokens[#tokens + 1] = alphabet[math.random(#alphabet)]
      end
      local obs, err = feed_tokens(runner, tokens, file, 1)
      if not obs then
        print(("ファジング %d で止まりました: %s"):format(i, err))
      else
        print(("ファジング %d: %s"):format(i, line(obs)))
      end
    end
  end
end

-- NOTES.md の表を読み、1 行ずつ観測で再現する。
-- 表の形: | # | id | プロファイル | 前置き | イベント | 方法 | 前ノード | 後ノード | 観測前 | 観測後 |
---@param path string
---@return table[]
local function parse_notes(path)
  local rows = {}
  local lines = vim.fn.readfile(path)
  for _, l in ipairs(lines) do
    if l:sub(1, 1) == "|" then
      local cells = vim.split(l, "|", { plain = true })
      table.remove(cells, 1)
      table.remove(cells, #cells)
      for i, cell in ipairs(cells) do
        cells[i] = vim.trim((cell:gsub("`", "")))
      end
      if cells[1] and cells[1]:match("^%d+$") and #cells >= 10 then
        rows[#rows + 1] = {
          number = tonumber(cells[1]),
          id = cells[2],
          profile = cells[3],
          prefix = cells[4],
          event = cells[5],
          method = cells[6],
          from_node = cells[7],
          to_node = cells[8],
          from_class = cells[9],
          to_class = cells[10],
        }
      end
    end
  end
  return rows
end

-- 前置きを流す。空ならそのまま
---@param runner table
---@param prefix string
---@param file file
---@return table? obs, string? err
local function run_prefix(runner, prefix, file)
  local tokens = {}
  if prefix ~= "" and prefix ~= "-" then
    tokens = M.parse_replay(prefix)
  end
  return feed_tokens(runner, tokens, file, 0)
end

-- マウスのクリック（同じウィンドウ）で pre-edit を確定させる
---@param runner table
---@return table? obs, string? err
local function action_mouse(runner)
  local ok, err = pcall(runner.child.api.nvim_input_mouse, "left", "press", "", 0, 0, 3)
  pcall(runner.child.api.nvim_input_mouse, "left", "release", "", 0, 0, 3)
  if not ok then
    return nil, tostring(err)
  end
  helpers.settle(runner.child)
  return runner:observe()
end

-- vim.paste を呼ぶ（貼り付けはキーではなく API の入力）
---@param runner table
---@return table? obs, string? err
local function action_paste(runner)
  local ok, err = pcall(runner.child.lua, [[vim.paste({ "PASTED" }, -1)]])
  if not ok then
    return nil, tostring(err)
  end
  helpers.settle(runner.child)
  return runner:observe()
end

-- skk の外からバッファを書き換える（TextChangedI のずれ検出を起こす）
---@param runner table
---@return table? obs, string? err
local function action_stale(runner)
  local ok, err = pcall(runner.child.api.nvim_buf_set_text, 0, 0, 0, 0, 0, { "x" })
  if not ok then
    return nil, tostring(err)
  end
  helpers.settle(runner.child)
  return runner:observe()
end

-- NOTES の 1 行を再現する
---@param runner table
---@param row table
---@param file file
---@return table result
local function run_note(runner, row, file)
  local profile = PROFILES[row.profile]
  if not profile then
    return { ok = false, err = ("知らないプロファイル: %s"):format(row.profile) }
  end
  profile.name = row.profile
  runner.profile = profile
  local ok_reset = pcall(runner.reset, runner)
  if not ok_reset then
    return { ok = false, err = "子を作り直せませんでした" }
  end
  local before, err = run_prefix(runner, row.prefix, file)
  if not before then
    return { ok = false, err = ("前置きで止まりました: %s"):format(err) }
  end

  local after
  local classes = { before.class }
  if row.method == "key" then
    local tok = MACROS[row.event] and { name = row.event, keys = MACROS[row.event], macro = true }
      or { name = row.event, keys = row.event }
    after, err = feed_token(runner, tok, { row.event }, file, true)
    if not after then
      return { ok = false, err = ("イベントで止まりました: %s"):format(err) }
    end
    classes[#classes + 1] = after.class
  elseif row.method == "mouse" then
    after, err = action_mouse(runner)
  elseif row.method == "paste" then
    after, err = action_paste(runner)
  elseif row.method == "stale" then
    after, err = action_stale(runner)
  elseif row.method == "event" then
    -- ModeChanged / SafeState を記録してから、イベントのキーを流す。
    -- オートコマンドの中では重い観測をしない。状態クラスに要る値だけを写す
    runner.child.lua([[(function()
      local group = vim.api.nvim_create_augroup("skkeleton-notes-events", { clear = true })
      _G.__notes_events = {}
      vim.api.nvim_create_autocmd({ "ModeChanged", "SafeState" }, {
        group = group,
        callback = function(ev)
          local st = vim.g["skkeleton#state"]
          local ns = vim.api.nvim_get_namespaces()["skkeleton-preedit"]
          local marks = {}
          if ns then
            for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
              local text = ""
              for _, chunk in ipairs(m[4].virt_text or {}) do
                text = text .. chunk[1]
              end
              marks[#marks + 1] = { buf = 0, row = m[2], col = m[3], text = text }
            end
          end
          table.insert(_G.__notes_events, {
            event = ev.event,
            buf = 0,
            vim_mode = vim.fn.mode(1),
            enabled = vim.g["skkeleton#enabled"] == true,
            skk_mode = vim.g["skkeleton#mode"] or "",
            state = {
              phase = type(st) == "table" and tostring(st.phase or "") or "",
              henkan_feed = type(st) == "table" and tostring(st.henkanFeed or "") or "",
              preedit = type(st) == "table" and tostring(st.preedit or "") or "",
            },
            preedit_marks = marks,
            cmdline = { type = "", line = "", pos = 0 },
            buffer = { lines = {}, text = "", cursor = { 0, 0 } },
            terminal = { active = false },
            popup = { shown = false },
            mappings = { skk = 0 },
            register_depth = 0,
          })
        end,
      })
    end)()]])
    local tok = { name = row.event, keys = row.event }
    local event_after, ferr = feed_token(runner, tok, { row.event }, file, true)
    local events = runner.child.lua_get("_G.__notes_events")
    pcall(runner.child.api.nvim_del_augroup_by_name, "skkeleton-notes-events")
    if not event_after then
      return { ok = false, err = ("イベントで止まりました: %s"):format(ferr) }
    end
    for _, e in ipairs(events) do
      e.class = observe.classify(e)
      classes[#classes + 1] = e.class
    end
    classes[#classes + 1] = event_after.class
    after = { class = row.to_class }
  else
    return { ok = false, skip = true, before = before, after = before, err = "この方法では再現しません" }
  end

  if not after then
    return { ok = false, before = before, err = ("観測できませんでした: %s"):format(err) }
  end
  if row.method ~= "event" then
    classes[#classes + 1] = after.class
    if row.method ~= "key" then
      write_jsonl(file, {
        run = runner.run_id,
        profile = row.profile,
        seq = { row.id },
        token = row.method,
        from = before.class,
        to = after.class,
        obs = after,
      })
    end
    if before.class ~= row.from_class or after.class ~= row.to_class then
      return { ok = false, before = before, after = after, err = "" }
    end
    return { ok = true, before = before, after = after }
  end

  -- イベントの列に、from が to より先に出るか
  local from_index
  for i, c in ipairs(classes) do
    if c == row.from_class then
      from_index = i
      break
    end
  end
  local in_order = false
  if from_index then
    for i = from_index + 1, #classes do
      if classes[i] == row.to_class then
        in_order = true
        break
      end
    end
  end
  return { ok = in_order, before = before, after = after, classes = classes }
end

-- NOTES の 49 遷移を再現する
---@param runner table
---@param path string
---@param file file
---@return boolean all_ok, integer total, integer failed, integer skipped
local function run_notes(runner, path, file)
  local rows = parse_notes(path)
  if #rows == 0 then
    error(("NOTES の表を読めません: %s"):format(path))
  end
  local failed, skipped = 0, 0
  for _, row in ipairs(rows) do
    local result = run_note(runner, row, file)
    if result.skip then
      skipped = skipped + 1
      print(("－ %2d %-18s %s（%s）"):format(row.number, row.id, row.event, row.method))
    elseif not result.ok then
      failed = failed + 1
      local got_from = result.before and result.before.class or "?"
      local got_to = result.after and result.after.class or "?"
      print(
        ("✗ %2d %-18s %s: %s -> %s (期待 %s -> %s) %s"):format(
          row.number,
          row.id,
          row.event,
          got_from,
          got_to,
          row.from_class,
          row.to_class,
          result.err or ""
        )
      )
    else
      print(("✓ %2d %-18s %-14s %s -> %s"):format(row.number, row.id, row.profile, row.from_class, row.to_class))
    end
  end
  return failed == 0, #rows, failed, skipped
end

-- 引数を読む
---@param argv string[]
---@return table
local function parse_args(argv)
  local opts = {
    mode = "bfs",
    depth = 3,
    fuzz = 0,
    length = 20,
    seed = 1,
    max_sequences = 1000,
    list = false,
  }
  local i = 1
  while i <= #argv do
    local arg = argv[i]
    local function value()
      i = i + 1
      return argv[i]
    end
    if arg == "--replay" then
      opts.mode = "replay"
      opts.replay = value()
    elseif arg == "--notes" then
      opts.mode = "notes"
      opts.notes = value()
    elseif arg == "--bfs" then
      opts.mode = "bfs"
    elseif arg == "--fuzz" then
      opts.mode = "fuzz"
      opts.fuzz = tonumber(value()) or 0
    elseif arg == "--depth" then
      opts.depth = tonumber(value()) or 3
    elseif arg == "--length" then
      opts.length = tonumber(value()) or 20
    elseif arg == "--seed" then
      opts.seed = tonumber(value()) or 1
    elseif arg == "--profile" then
      opts.profile = value()
    elseif arg == "--alphabet" then
      opts.alphabet = value()
    elseif arg == "--out" then
      opts.out = value()
    elseif arg == "--summary" then
      opts.summary = value()
    elseif arg == "--max-sequences" then
      opts.max_sequences = tonumber(value()) or 1000
    elseif arg == "--list" then
      opts.list = true
    elseif arg == "--help" or arg == "-h" then
      opts.help = true
    else
      error(("知らない引数です: %s"):format(arg))
    end
    i = i + 1
  end
  return opts
end

local function usage()
  print([[
使い方: nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua [オプション]

  --replay <キー列>       1 本のキー列を流す（コンマ区切り。例: "i,<Plug>(skkeleton-enable),Kan"）
  --notes <path>          NOTES.md の遷移の表を 1 行ずつ再現して確かめる
                         （key / mouse / paste / stale / event の方法に対応）
  --bfs                  幅優先で探索する（既定）
  --depth <n>             幅優先の深さ（既定 3）
  --fuzz <n>             ランダムなキー列の本数
  --length <n>           ファジングの 1 本の長さ（遷移の数。既定 20）
  --seed <n>             ファジングの種（既定 1）
  --profile <名前>         none / insert / normal / cmdline / terminal / register / expr / mouse /
                         completion / blink / blink_line / blink_buffer（blink は .tests/blink.cmp か BLINK_PATH が要る）
  --alphabet <名前,..>    使う遷移の名前をコンマで指定する（既定はプロファイルの表）
  --max-sequences <n>    幅優先で広げる遷移の上限（既定 1000）
  --out <path>           JSONL の出力先（既定は .tests/explore/ の下）
  --summary <path>       遷移の表を Markdown で書く
  --list                 プロファイルとアルファベットを表示する
]])
end

local function main(argv)
  local opts = parse_args(argv)
  if opts.help then
    usage()
    return
  end
  if opts.list then
    for name, profile in pairs(PROFILES) do
      print(("profile %s: %s"):format(name, table.concat(profile.alphabet, ", ")))
    end
    return
  end

  local profile_name = opts.profile or (opts.mode == "replay" and "none" or "insert")
  local profile = PROFILES[profile_name]
  if not profile then
    error(("知らないプロファイルです: %s"):format(profile_name))
  end
  profile.name = profile_name
  local alphabet = M.alphabet(opts.alphabet and vim.split(opts.alphabet, ",", { plain = true }) or profile.alphabet)

  local stamp = os.date("%Y%m%d-%H%M%S")
  local out_path = opts.out or ("%s/%s-%s-%s-%d.jsonl"):format(work, opts.mode, profile_name, stamp, vim.uv.os_getpid())
  local summary_path = opts.summary
  local file = open_jsonl(out_path)

  local runner = new_runner(profile, ("%s-%s-%s"):format(opts.mode, profile_name, stamp))
  local notes_failed = false
  local ok, err = pcall(function()
    runner:reset()
    if opts.mode == "replay" then
      if not opts.replay then
        error("--replay にはキー列が要ります")
      end
      local tokens = M.parse_replay(opts.replay)
      local start = runner:observe()
      write_jsonl(file, {
        run = runner.run_id,
        profile = profile_name,
        seq = {},
        token = nil,
        key = nil,
        from = nil,
        to = start.class,
        obs = start,
      })
      local obs, ferr = feed_tokens(runner, tokens, file, 1)
      if not obs then
        error(ferr)
      end
      print(("最後: %s"):format(line(obs)))
    elseif opts.mode == "fuzz" then
      fuzz(runner, alphabet, opts.fuzz, opts.length, opts.seed, file)
    elseif opts.mode == "notes" then
      if not opts.notes then
        error("--notes には NOTES.md のパスが要ります")
      end
      local all_ok, total, failed, skipped = run_notes(runner, opts.notes, file)
      print(("NOTES: %d 行中 %d 行を再現、%d 行は未実施"):format(total - failed - skipped, total, skipped))
      if not all_ok then
        notes_failed = true
      end
    else
      bfs(runner, alphabet, opts.depth, opts.max_sequences, file)
    end
  end)
  runner:stop()
  file:close()
  if not ok then
    error(err)
  end
  report(runner, out_path, summary_path)
  if notes_failed then
    os.exit(1)
  end
end

main(arg)

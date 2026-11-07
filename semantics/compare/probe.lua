-- モデルと観測を突き合わせるための観測（#186、親は #179）
--
-- semantics/model/model.lua の状態ごとに「その状態まで進む前置き」を流し、次に
-- イベントのキーを打って、前後の観測を JSONL に書く。観測の取り方は 05 の
-- semantics/explore/observe.lua と同じ（子の nvim、一時ディレクトリの辞書、
-- HISTFILE=/dev/null）。モデルの状態と、観測の状態クラスの対応だけをこのファイルで決める。
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/compare/probe.lua
--   nvim --headless -u NONE -i NONE -l semantics/compare/probe.lua --out <path>
--   nvim --headless -u NONE -i NONE -l semantics/compare/probe.lua --only <id>
--   nvim --headless -u NONE -i NONE -l semantics/compare/probe.lua --list
--
-- 出力の 1 行が 1 つの観測。compare.lua がこれを読み、モデルとの差を出す。
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
local work = root .. "/.tests/compare"
vim.fn.mkdir(work, "p")
vim.env.XDG_CACHE_HOME = work .. "/cache"
vim.env.XDG_STATE_HOME = work .. "/state"
require("mini.test").setup({})

local observe = require("semantics.explore.observe")
local helpers = require("helpers")
local model = dofile(root .. "/semantics/model/model.lua")

local M = {}

-- ---------------------------------------------------------------------------
-- 状態クラスの対応（モデルと観測）
--
-- 観測（observe.classify）の名前と、モデルの人が読むクラス（M.states[].class）は
-- 完全には同じではない。違うところだけ、ここで理由を書いて寄せる。

-- モデルのクラスの集合
local MODEL_CLASS = {}
for _, st in ipairs(model.states) do
  MODEL_CLASS[st.class] = true
end

-- 観測のクラスを、モデルの人が読むクラスに寄せる
---@param obs table
---@return string
function M.project(obs)
  local c = obs.class
  if c == "I_PENDING" then
    -- 05 の探索器は、ローマ字の打ちかけ（▽k）を I_PENDING と呼ぶ。
    -- 04 のモデルは同じ状態を I_ROMAJI と呼ぶ（作者の判断 6）。
    return "I_ROMAJI"
  end
  if c == "R_MID" then
    -- 観測では replace の途中を R_MID と呼ぶが、モデルでは遷移の途中（transient）で、
    -- 人が読むクラスは R_OFF に寄せる（作者の判断 8）。
    return "R_OFF"
  end
  if c == "I_DIRECT" and not obs.enabled then
    -- observe.classify は insert で enabled を見ない。モデルは無効な insert を
    -- I_OFF として分けた（作者の判断 1）。ここで enabled で分ける。
    return "I_OFF"
  end
  if c == "N_OFF" and obs.enabled and M.is_visual(obs.vim_mode) then
    -- observe.classify は visual で pre-edit が無いと N_OFF にする。
    -- モデルは「visual で有効のまま」を V_IDLE として分けた（作者の判断 2）。
    return "V_IDLE"
  end
  return c
end

---@param mode string
---@return boolean
function M.is_visual(mode)
  return mode == "v" or mode == "V" or mode == "\22" or mode == "s" or mode == "S" or mode == "\19"
end

-- snapshot に、05 の探索器と同じ状態クラスを付ける
---@param obs table
---@return table
local function classify(obs)
  obs.class = observe.classify(obs)
  return obs
end

-- 観測を、比較に使う形（JSON にできる表）に落とす
---@param obs table
---@return table
local function slim(obs)
  return {
    class = M.project(obs),
    raw_class = obs.class,
    mode = obs.vim_mode,
    enabled = obs.enabled,
    skk_mode = obs.skk_mode,
    phase = obs.state.phase,
    preedit = obs.state.preedit,
    henkan_feed = obs.state.henkan_feed,
    mark = observe.mark_text(obs),
    buffer = table.concat(obs.buffer.lines or {}, "\n"),
    cursor = obs.buffer.cursor,
    cmdline_type = obs.cmdline.type,
    cmdline_line = obs.cmdline.line,
    register_depth = obs.register_depth,
    popup_shown = obs.popup.shown,
    popup_lines = obs.popup.lines,
    mappings_skk = obs.mappings.skk,
  }
end

-- ---------------------------------------------------------------------------
-- キーの分け方
--
-- `Kan` のようなまとまりは 1 つのトークンとして扱い、中の `<...>` と 1 文字に分ける。
-- 書き方は semantics/explore/explore.lua に合わせる。

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

-- コンマ区切りのトークンを、実際に送るキーに開く。例: "i,Kan" -> {"i","K","a","n"}
---@param s string
---@return string[]
local function tokens_to_keys(s)
  local keys = {}
  if not s or s == "" then
    return keys
  end
  for token in s:gmatch("[^,]+") do
    token = vim.trim(token)
    if token ~= "" then
      for _, k in ipairs(M.scan_keys(token)) do
        keys[#keys + 1] = k
      end
    end
  end
  return keys
end

-- ---------------------------------------------------------------------------
-- 観測の世界（設定・バッファ・辞書）
--
-- 同じ状態クラスでも、設定とバッファと辞書で結果が分かれる。分かれる組は
-- ここに「前提」として書き、それぞれの前提で観測する。

local WORLDS = {
  -- 既定。空のバッファ、既定の辞書（tests/helpers.lua の dict_text）
  default = {
    init = [[vim.fn.setreg("a", "XYZ")]],
  },
  -- keepState = true（作者の判断 3 の guard）
  keepstate = {
    config = { keepState = true },
    init = [[vim.fn.setreg("a", "XYZ")]],
  },
  -- 確定済みの文字がバッファにある（<C-w> / <C-u> の分岐）
  text = {
    init = [[
      vim.fn.setreg("a", "XYZ")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
    ]],
  },
  -- 組み込みの補完の候補が出る行
  completion = {
    init = [[
      vim.fn.setreg("a", "XYZ")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "あいうえお", "" })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    ]],
  },
}

-- 前置き。モデルの状態（と、分岐を選ぶための別名）から、流すキーと世界を決める。
-- keys はコンマ区切りのトークン。世界の既定は default。
local PREFIX = {
  N_OFF = { keys = "" },
  I_OFF = { keys = "i,<Plug>(skkeleton-enable),<Esc>,i" },
  I_DIRECT = { keys = "i,<Plug>(skkeleton-enable)" },
  I_ROMAJI = { keys = "i,<Plug>(skkeleton-enable),K" },
  I_ROMAJI_EMPTY = { keys = "i,<Plug>(skkeleton-enable),K,<BS>" },
  I_ROMAJI_TEXT = { keys = "i,<Plug>(skkeleton-enable),a,K" },
  I_POINT = { keys = "i,<Plug>(skkeleton-enable),Kan" },
  I_POINT_1 = { keys = "i,<Plug>(skkeleton-enable),Ka" },
  I_POINT_ARI = { keys = "i,<Plug>(skkeleton-enable),KaeR" },
  I_POINT_NURU = { keys = "i,<Plug>(skkeleton-enable),Nuru" },
  I_POINT_TEXT = { keys = "i,<Plug>(skkeleton-enable),a,Kan" },
  I_SELECT = { keys = "i,<Plug>(skkeleton-enable),Kan,<Space>" },
  I_SELECT2 = { keys = "i,<Plug>(skkeleton-enable),Kan,<Space>,<Space>" },
  -- 候補の最後（次の <Space> で辞書登録のプロンプトが開く）
  I_SELECT_LAST = {
    keys = "i,<Plug>(skkeleton-enable),Kan,<Space>,<Space>,<Space>,<Space>,<Space>",
  },
  -- 候補が 1 つだけで popup が出ない読み
  I_SELECT_NIHON = { keys = "i,<Plug>(skkeleton-enable),Nihon,<Space>" },
  I_SELECT_TEXT = { keys = "i,<Plug>(skkeleton-enable),a,Kan,<Space>" },
  NI_DIRECT = { keys = "i,<Plug>(skkeleton-enable),<C-o>" },
  -- 確定済みの文字がある行で niI に入る（戻ったときのずれを見る）
  NI_DIRECT_TEXT = {
    world = "text",
    keys = "i,<Plug>(skkeleton-enable),<C-o>",
  },
  NI_POINT_TEXT = {
    world = "text",
    keys = "i,<Plug>(skkeleton-enable),Kan,<C-o>",
  },
  NI_SELECT_TEXT = {
    world = "text",
    keys = "i,<Plug>(skkeleton-enable),Kan,<Space>,<C-o>",
  },
  NI_POINT = { keys = "i,<Plug>(skkeleton-enable),Kan,<C-o>" },
  NI_SELECT = { keys = "i,<Plug>(skkeleton-enable),Kan,<Space>,<C-o>" },
  IC = {
    world = "completion",
    keys = "i,<Plug>(skkeleton-enable),Kan,<C-n>",
  },
  V_IDLE = { keys = "i,<Plug>(skkeleton-enable),<C-o>v" },
  V_PRE_POINT = { keys = "i,<Plug>(skkeleton-enable),Kan,<C-o>v" },
  V_PRE_SELECT = { keys = "i,<Plug>(skkeleton-enable),Kan,<Space>,<C-o>v" },
  R_OFF = { keys = "i,<Plug>(skkeleton-enable),<Insert>" },
  -- keepState = true。i の InsertEnter で有効になるので、enable は打たない
  I_DIRECT_KEEP = { world = "keepstate", keys = "i" },
  I_ROMAJI_KEEP = { world = "keepstate", keys = "i,K" },
  I_POINT_KEEP = { world = "keepstate", keys = "i,Kan" },
  I_SELECT_KEEP = { world = "keepstate", keys = "i,Kan,<Space>" },
  P_PROMPT_POINT = { keys = "i,<Plug>(skkeleton-enable),Nuru,<Space>" },
  P_PROMPT_SELECT = {
    keys = "i,<Plug>(skkeleton-enable),Kan,<Space>,<Space>,<Space>,<Space>,<Space>,<Space>",
  },
}

-- 前置きを流したあとの状態が、この名前の状態になることを確かめるために使う。
-- 別名の前置きは、同じ状態の別の入り方（おくりあり・バッファに文字がある、など）。
local PREFIX_STATE = {
  I_ROMAJI_EMPTY = "I_ROMAJI",
  I_ROMAJI_TEXT = "I_ROMAJI",
  I_POINT_1 = "I_POINT",
  I_POINT_ARI = "I_POINT",
  I_POINT_NURU = "I_POINT",
  I_POINT_TEXT = "I_POINT",
  I_SELECT2 = "I_SELECT",
  I_SELECT_LAST = "I_SELECT",
  I_SELECT_NIHON = "I_SELECT",
  I_SELECT_TEXT = "I_SELECT",
  I_DIRECT_KEEP = "I_DIRECT",
  I_ROMAJI_KEEP = "I_ROMAJI",
  I_POINT_KEEP = "I_POINT",
  I_SELECT_KEEP = "I_SELECT",
}

-- ---------------------------------------------------------------------------
-- イベントごとの、打つキー（分岐を選ぶための言い換え）

local EVENT_KEYS = {
  char = "a",
  char_shift = "K",
  key_x = "x",
  key_X = "X",
  key_l = "l",
  key_q = "q",
  key_semicolon = ";",
  key_slash = "/",
  key_gt = ">",
  key_cq = "<C-q>",
  bs = "<BS>",
  cr = "<CR>",
  space = "<Space>",
  nl = "<C-j>",
  cg = "<C-g>",
  esc = "<Esc>",
  insert_key = "<Insert>",
  ctrl_o = "<C-o>",
  ctrl_c = "<C-c>",
  ctrl_r = "<C-r>a",
  ctrl_v = "<C-v>065",
  ctrl_k = "<C-k>a:",
  ctrl_t = "<C-t>",
  tab = "<Tab>",
  ctrl_w = "<C-w>",
  ctrl_u = "<C-u>",
  ctrl_a = "<C-a>",
  ctrl_at = "<C-@>",
  completion_open = "<C-n>",
  completion_next = "<C-n>",
  completion_accept = "<C-y>",
  ctrl_o_colon = "<C-o>:<Esc>",
  ctrl_o_v = "<C-o>v",
  ctrl_o_R = "<C-o>R",
  guard_special = "<S-Tab>",
  enable = "<Plug>(skkeleton-enable)",
  disable = "<Plug>(skkeleton-disable)",
  toggle = "<Plug>(skkeleton-toggle)",
  ni_return_keep = "l",
  ni_return_commit = "0",
  ni_return_drop = "x",
  -- 辞書登録のプロンプト。cmdline の中は 07c なので、入口と出口のキーだけ打つ
  register_commit = "<CR>",
  register_cancel = "<Esc>",
}

-- 分岐を選ぶ言い換え。遷移の id ごとに前置きとキーを変える。
local OVERRIDE = {
  ["t.I_DIRECT.char.keep"] = { keys = "a" },
  ["t.I_DIRECT.char.romaji"] = { keys = "k" },
  ["t.I_DIRECT.char_shift"] = { keys = "K" },
  ["t.I_DIRECT.char_shift.point"] = { keys = "A" },

  ["t.I_ROMAJI.char.keep"] = { prefix = "I_ROMAJI_EMPTY", keys = "k" },
  ["t.I_ROMAJI.char.commit"] = { keys = "a" },
  ["t.I_ROMAJI.bs"] = { prefix = "I_ROMAJI", keys = "<BS>" },
  ["t.I_ROMAJI.bs.empty"] = { prefix = "I_ROMAJI_EMPTY", keys = "<BS>" },
  ["t.I_ROMAJI.ctrl_w"] = { prefix = "I_ROMAJI_TEXT", keys = "<C-w>" },
  ["t.I_ROMAJI.ctrl_w.keep"] = { keys = "<C-w>" },
  ["t.I_ROMAJI.ctrl_u"] = { prefix = "I_ROMAJI_TEXT", keys = "<C-u>" },
  ["t.I_ROMAJI.ctrl_u.keep"] = { keys = "<C-u>" },

  ["t.I_POINT.bs"] = { prefix = "I_POINT", keys = "<BS>" },
  ["t.I_POINT.bs.empty"] = { prefix = "I_POINT_1", keys = "<BS>" },
  ["t.I_POINT.ctrl_w"] = { prefix = "I_POINT_TEXT", keys = "<C-w>" },
  ["t.I_POINT.ctrl_w.keep"] = { keys = "<C-w>" },
  ["t.I_POINT.ctrl_u"] = { prefix = "I_POINT_TEXT", keys = "<C-u>" },
  ["t.I_POINT.ctrl_u.keep"] = { keys = "<C-u>" },
  ["t.I_POINT.space.select"] = { keys = "<Space>" },
  ["t.I_POINT.space.register"] = { prefix = "I_POINT_NURU", keys = "<Space>" },

  ["t.I_SELECT.char.commit"] = { prefix = "I_SELECT_NIHON", keys = "a" },
  ["t.I_SELECT.char.commit_romaji"] = { keys = "z" },
  ["t.I_SELECT.ctrl_w"] = { prefix = "I_SELECT_TEXT", keys = "<C-w>" },
  ["t.I_SELECT.ctrl_w.keep"] = { keys = "<C-w>" },
  ["t.I_SELECT.ctrl_u"] = { prefix = "I_SELECT_TEXT", keys = "<C-u>" },
  ["t.I_SELECT.ctrl_u.keep"] = { keys = "<C-u>" },
  ["t.I_SELECT.x.prev"] = { prefix = "I_SELECT2", keys = "x" },
  ["t.I_SELECT.x.back"] = { prefix = "I_SELECT", keys = "x" },
  ["t.I_SELECT.space.next"] = { keys = "<Space>" },
  ["t.I_SELECT.space.register"] = { prefix = "I_SELECT_LAST", keys = "<Space>" },
  ["t.I_SELECT.key_X.purge"] = { keys = "X" },
  ["t.I_SELECT.key_X.register"] = { skip = true },
  -- 登録の確定は、プロンプトに語を打ってから <CR>。キー 1 つでは確かめられない
  ["t.P_PROMPT_POINT.register_commit"] = { skip = true },
  ["t.P_PROMPT_SELECT.register_commit"] = { skip = true },

  ["t.I_DIRECT.esc.keepstate"] = { world = "keepstate" },
  ["t.I_ROMAJI.esc.keepstate"] = { world = "keepstate" },
  ["t.I_POINT.esc.keepstate"] = { world = "keepstate" },
  ["t.I_SELECT.esc.keepstate"] = { world = "keepstate" },
  ["t.N_OFF.insert_enter.keepstate"] = { world = "keepstate", keys = "i" },

  -- niI からの <C-o>R / <C-o>v は、R / v の 1 キーで打つ（<C-o> はもう済んでいる）
  ["t.NI_DIRECT.replace"] = { keys = "R" },
  ["t.NI_POINT.replace"] = { keys = "R" },
  ["t.NI_SELECT.replace"] = { keys = "R" },
  ["t.NI_DIRECT.visual"] = { keys = "v" },
  ["t.NI_POINT.visual"] = { keys = "v" },
  ["t.NI_SELECT.visual"] = { keys = "v" },
  -- 戻るときのずれは、確定済みの文字がある行で作る
  ["t.NI_DIRECT.return_commit"] = { prefix = "NI_DIRECT_TEXT", keys = "0" },
  ["t.NI_POINT.return_commit"] = { prefix = "NI_POINT_TEXT", keys = "0" },
  ["t.NI_SELECT.return_commit"] = { prefix = "NI_SELECT_TEXT", keys = "0" },
  ["t.NI_DIRECT.return_drop"] = { prefix = "NI_DIRECT_TEXT", keys = "x" },
  ["t.NI_POINT.return_drop"] = { prefix = "NI_POINT_TEXT", keys = "x" },
  ["t.NI_SELECT.return_drop"] = { prefix = "NI_SELECT_TEXT", keys = "x" },
  ["t.NI_DIRECT.return_keep"] = { prefix = "NI_DIRECT_TEXT", keys = "l" },
  ["t.NI_POINT.return_keep"] = { prefix = "NI_POINT_TEXT", keys = "l" },
  ["t.NI_SELECT.return_keep"] = { prefix = "NI_SELECT_TEXT", keys = "l" },
  ["t.N_OFF.insert_enter"] = { keys = "i" },
}

-- モデルに遷移が無い（状態, キー）を打ってみるためのキー。
-- モデルがその状態で扱っていないキーだけを打つ（扱っているキーは遷移の観測で打つ）。
local EXTRA_KEYS = {
  "a", "K", "<Space>", "<C-j>", "<C-g>", "<BS>", "<Esc>", "<C-c>", "<Insert>", "<C-o>",
  "<Tab>", "<S-Tab>", "<C-n>", "<C-y>", "<C-w>", "<C-u>", "<C-r>a", "<C-v>065", "<C-k>a:",
  "<C-o>v", "<C-o>R", "<C-o>:<Esc>", "<C-o>:<CR>", "<Left>", "l", "x", ".", "R",
}

-- 名前を id に使える形にする
---@param s string
---@return string
local function slug(s)
  return (s:gsub("[^%w_]", "_"))
end

-- ---------------------------------------------------------------------------
-- 遷移の途中（internal）を、なくなるまで進める

local by_from = {}
for _, t in ipairs(model.transitions) do
  by_from[t.from] = by_from[t.from] or {}
  table.insert(by_from[t.from], t)
end

---@param config table
---@param atom table
---@return boolean
local function eval_atom(atom, state_name, config)
  if atom[1] == "not" then
    return not eval_atom(atom[2], state_name, config)
  end
  local var, op, value = atom[1], atom[2], atom[3]
  local prefix, name = var:match("^([%w_]+)%.(.+)$")
  local actual
  if prefix == "config" then
    actual = config[name]
  else
    actual = model.states[state_name][var]
  end
  if op == "=" then
    return actual == value
  elseif op == "in" then
    for _, v in ipairs(value) do
      if actual == v then
        return true
      end
    end
    return false
  end
  error(("知らない guard の演算子: %s"):format(tostring(op)), 0)
end

---@param t table
---@param config table
---@return boolean
local function guard_ok(t, config)
  for _, atom in ipairs(t.guard or {}) do
    if not eval_atom(atom, t.from, config) then
      return false
    end
  end
  return true
end

-- 遷移のあと、internal の片付けを最後まで進めた状態の集合を返す
---@param state_name string
---@param config table
---@return string[]
function M.settle(state_name, config)
  local out = {}
  local queue = { state_name }
  local seen = {}
  local count = 0
  while #queue > 0 do
    count = count + 1
    if count > 200 then
      error("内部の片付けが止まりません（遷移が循環しています）", 0)
    end
    local next_queue = {}
    for _, s in ipairs(queue) do
      if seen[s] then
        goto continue
      end
      seen[s] = true
      local advanced = false
      for _, t in ipairs(by_from[s] or {}) do
        if model.events[t.event].kind == "internal" and guard_ok(t, config) then
          advanced = true
          table.insert(next_queue, t.to)
        end
      end
      if not advanced then
        table.insert(out, s)
      end
      ::continue::
    end
    queue = next_queue
  end
  return out
end

-- 遷移の終わり先が、観測で見えるクラスになるか
---@param t table
---@param config table
---@return string[]
function M.expected_classes(t, config)
  local out = {}
  for _, s in ipairs(M.settle(t.to, config)) do
    out[model.states[s].class] = true
  end
  local list = {}
  for c in pairs(out) do
    list[#list + 1] = c
  end
  table.sort(list)
  return list
end

-- ---------------------------------------------------------------------------
-- 観測を取る

local function config_for(world)
  local conf = { keepState = false }
  for k, v in pairs(WORLDS[world].config or {}) do
    conf[k] = v
  end
  return conf
end

-- 世界ごとの子。作るのは 1 回だけ
local children = {}

---@param world string
---@return table set, table child
local function child_for(world)
  if children[world] then
    return children[world].set, children[world].child
  end
  local w = WORLDS[world]
  local set, child = helpers.e2e_set({ config = w.config, init = w.init })
  children[world] = { set = set, child = child }
  return set, child
end

-- 観測を 1 つ取る。子を作り直し、前置きを流し、イベントのキーを 1 つずつ打つ
---@param case table
---@return table
local function run_case(case)
  local world = case.world or "default"
  local set, child = child_for(world)
  local hooks = getmetatable(set).opts.hooks
  hooks.pre_case()
  local dir = child.lua_get("_G.dir")

  local rec = {
    id = case.id,
    transition = case.transition,
    from = case.from,
    state = case.state,
    event = case.event,
    world = world,
    prefix = case.prefix,
    keys = case.keys,
    expect = case.expect,
    note = case.note,
  }

  local ok_before, before = pcall(function()
    return classify(observe.snapshot(child))
  end)
  if not ok_before then
    rec.blocked = tostring(before)
    vim.fn.delete(dir, "rf")
    return rec
  end
  rec.before = slim(before)

  -- 前置き
  for _, key in ipairs(tokens_to_keys(case.prefix)) do
    pcall(helpers.type, child, key)
  end
  local ok_prefix, prefix_obs = pcall(function()
    return classify(observe.snapshot(child))
  end)
  if not ok_prefix then
    rec.blocked = "前置きのあとに観測できない: " .. tostring(prefix_obs)
    vim.fn.delete(dir, "rf")
    return rec
  end
  rec.after_prefix = slim(prefix_obs)
  rec.prefix_class = M.project(prefix_obs)

  -- イベントのキーを 1 つずつ打つ
  rec.steps = {}
  for _, key in ipairs(tokens_to_keys(case.keys)) do
    local ok, err = pcall(helpers.type, child, key)
    local snap
    if ok then
      local ok_snap, observed = pcall(function()
        return classify(observe.snapshot(child))
      end)
      if ok_snap then
        snap = observed
      end
    end
    table.insert(rec.steps, {
      key = key,
      ok = ok,
      err = (not ok) and tostring(err) or nil,
      class = snap and M.project(snap) or "BLOCKED",
      obs = snap and slim(snap) or nil,
    })
  end
  local last = rec.steps[#rec.steps]
  rec.final_class = last and last.class or rec.prefix_class
  rec.after = last and last.obs or rec.after_prefix

  vim.fn.delete(dir, "rf")
  return rec
end

-- ---------------------------------------------------------------------------
-- ケースを組み立てる

---@return table[]
function M.cases()
  local out = {}
  local seen = {}
  local function add(case)
    if seen[case.id] then
      return
    end
    seen[case.id] = true
    out[#out + 1] = case
  end

  -- 1. モデルの遷移（キー・API・Vim のコマンドだけ）
  --
  -- :stopinsert はコマンドでキーではない。API は、<Plug> がマップされている
  -- 挿入の状態でだけ打てる（normal や visual では <Plug> が無く、文字が入る）。
  local SKIP_EVENT = { stopinsert = true }
  for _, t in ipairs(model.transitions) do
    local event = model.events[t.event]
    local probeable = event.kind == "key" or event.kind == "api" or event.kind == "vim"
    local api_ok = true
    if event.kind == "api" then
      local class = model.states[t.from].class
      api_ok = class:match("^I_") ~= nil and t.from ~= "I_OFF" and t.from ~= "I_ESCAPE"
      api_ok = api_ok or class == "NI" or class == "P_PROMPT"
    end
    local prefix = PREFIX[t.from] and t.from or nil
    if probeable and not SKIP_EVENT[t.event] and api_ok and prefix then
      local ov = OVERRIDE[t.id] or {}
      local pname = ov.prefix or t.from
      if ov.skip then
        pname = nil
      end
      local pdef = PREFIX[pname]
      if pdef then
        local world = ov.world or pdef.world or "default"
        local conf = config_for(world)
        add({
          id = "p." .. t.id,
          transition = t.id,
          from = t.from,
          event = t.event,
          prefix = pdef.keys,
          keys = ov.keys or EVENT_KEYS[t.event] or (event.keys[1] or ""),
          world = world,
          expect = M.expected_classes(t, conf),
          note = t.notes,
        })
      end
    end
  end

  -- 2. モデルに遷移が無い（状態, キー）。打ってみて、観測にだけある遷移を探す
  for _, state_name in ipairs(vim.tbl_keys(PREFIX)) do
    local pdef = PREFIX[state_name]
    local world = pdef.world or "default"
    local state = PREFIX_STATE[state_name] or state_name
    if model.states[state] then
      -- その状態から出ている遷移のイベントが持つキー
      local covered = {}
      for _, t in ipairs(by_from[state] or {}) do
        for _, k in ipairs(model.events[t.event].keys or {}) do
          covered[k] = true
        end
      end
      for _, key in ipairs(EXTRA_KEYS) do
        if not covered[key] then
          add({
            id = ("x.%s.%s"):format(state_name, slug(key)),
            from = state_name,
            event = nil,
            prefix = pdef.keys,
            keys = key,
            world = world,
            expect = nil,
            note = "モデルにこの状態からの遷移が無いキー",
          })
        end
      end
    end
  end

  -- 2b. 辞書登録の確定は、プロンプトに語を打ってから <CR>（キー 1 つでは確かめられない）
  add({
    id = "d.register.commit",
    from = "P_PROMPT_POINT",
    event = nil,
    prefix = PREFIX.P_PROMPT_POINT.keys,
    keys = "tesuto,<CR>",
    world = "default",
    expect = nil,
    note = "登録する語を打って <CR>。語が辞書に入り、insert に戻る",
  })
  add({
    id = "d.register.cancel",
    from = "P_PROMPT_POINT",
    event = nil,
    prefix = PREFIX.P_PROMPT_POINT.keys,
    keys = "<Esc>",
    world = "default",
    expect = nil,
    note = "登録を取り消すと、外側の ▽ に戻る",
  })

  -- 3. 状態クラスの分け方を確かめるための観測
  -- 3a. ▽ と ▽*（おくりなし / おくりあり）で結果が割れないか（作者の判断 7）。
  --     同じキーを、おくりなしの ▽（Kan）とおくりありの ▽*（KaeR）から打って比べる。
  for _, key in ipairs({
    "<Space>", "<C-j>", "<C-g>", "<BS>", "<Esc>", "<C-w>", "<C-u>", "x", "X", ">", "a", "K",
    "<C-o>", "<C-o>v", "<C-o>R", "<C-n>", "<Tab>", "<S-Tab>", "<C-r>a", "<Left>",
  }) do
    for _, pname in ipairs({ "I_POINT", "I_POINT_ARI" }) do
      local pdef = PREFIX[pname]
      add({
        id = ("c.okuri.%s.%s"):format(pname, slug(key)),
        from = pname,
        event = nil,
        prefix = pdef.keys,
        keys = key,
        world = "default",
        expect = nil,
        note = "▽ と ▽* の分岐の確認",
      })
    end
  end
  -- 3b. visual で有効・pre-edit 無し（V_IDLE）と、無効な normal（N_OFF）で結果が割れるか
  for _, key in ipairs({ "<Esc>", "i", "a", "v", "<C-o>", ":", "R", "<C-j>", "<C-g>" }) do
    for _, pname in ipairs({ "N_OFF", "V_IDLE" }) do
      add({
        id = ("c.idle.%s.%s"):format(pname, slug(key)),
        from = pname,
        event = nil,
        prefix = PREFIX[pname].keys,
        keys = key,
        world = "default",
        expect = nil,
        note = "V_IDLE と N_OFF の分岐の確認",
      })
    end
  end
  -- 3c. insert で無効（I_OFF）と有効（I_DIRECT）で結果が割れるか
  for _, key in ipairs({ "<Esc>", "a", "K", "<Space>", "<Insert>", "<C-o>" }) do
    for _, pname in ipairs({ "I_OFF", "I_DIRECT" }) do
      add({
        id = ("c.ioff.%s.%s"):format(pname, slug(key)),
        from = pname,
        event = nil,
        prefix = PREFIX[pname].keys,
        keys = key,
        world = "default",
        expect = nil,
        note = "I_OFF と I_DIRECT の分岐の確認",
      })
    end
  end
  -- 3c2. I_ROMAJI は「▽ だけ」と「▽k」を同じクラスにしている。打ちかけの中身で
  --      同じキーの結果が割れないかを確かめる（状態クラスに持っていない前提の確認）。
  for _, key in ipairs({ "K", "a", "<Space>", "<C-j>", "<BS>" }) do
    for _, pname in ipairs({ "I_ROMAJI_EMPTY", "I_ROMAJI" }) do
      add({
        id = ("c.feed.%s.%s"):format(pname, slug(key)),
        from = pname,
        event = nil,
        prefix = PREFIX[pname].keys,
        keys = key,
        world = "default",
        expect = nil,
        note = "▽ と ▽k の分岐の確認",
      })
    end
  end

  -- 3d. NI / V_PRE / P_PROMPT の相（direct / point / select）で結果が割れるか（作者の判断 4）
  for _, key in ipairs({ "<Esc>", "a", "<Space>", "<C-j>", "<C-g>", "<BS>", "x", "X", "<C-o>v", "<C-o>R" }) do
    for _, pname in ipairs({ "NI_DIRECT", "NI_POINT", "NI_SELECT" }) do
      add({
        id = ("c.ni.%s.%s"):format(pname, slug(key)),
        from = pname,
        event = nil,
        prefix = PREFIX[pname].keys,
        keys = key,
        world = "default",
        expect = nil,
        note = "NI の相の確認",
      })
    end
  end

  -- 4. 作者が「06 でもう一度確かめる」と言った 3 つ（観測を正とする）
  local disputed = {
    {
      id = "d.disputed.ctrl-o-R",
      from = "I_POINT",
      keys = "<C-o>R",
      note = "<C-o>R: data.js / NOTES は pre-edit が残るとする。観測では確定して無効になるか。",
    },
    {
      id = "d.disputed.ctrl-o-v-esc",
      from = "I_POINT",
      keys = "<C-o>v,<Esc>",
      note = "<C-o>v → <Esc>: data.js は「抜けると確定」とする。観測では pre-edit が残るか。",
    },
    {
      id = "d.disputed.ctrl-o-colon-cr",
      from = "I_POINT",
      keys = "<C-o>:<CR>",
      note = "<C-o>:<CR>: data.js は「確定する」とする。観測では pre-edit が残るか。",
    },
    {
      id = "d.disputed.ctrl-o-R-select",
      from = "I_SELECT",
      keys = "<C-o>R",
      note = "<C-o>R を ▼ から。",
    },
    {
      id = "d.disputed.ctrl-o-v-esc-select",
      from = "I_SELECT",
      keys = "<C-o>v,<Esc>",
      note = "<C-o>v → <Esc> を ▼ から。",
    },
    {
      id = "d.disputed.ctrl-o-colon-cr-select",
      from = "I_SELECT",
      keys = "<C-o>:<CR>",
      note = "<C-o>:<CR> を ▼ から。",
    },
    {
      id = "d.disputed.ctrl-o-colon-esc",
      from = "I_POINT",
      keys = "<C-o>:<Esc>",
      note = "<C-o>:<Esc>（04 の観測と同じ形）。",
    },
  }
  for _, d in ipairs(disputed) do
    local pdef = PREFIX[d.from]
    add({
      id = d.id,
      from = d.from,
      event = nil,
      prefix = pdef.keys,
      keys = d.keys,
      world = "default",
      expect = nil,
      note = d.note,
    })
  end

  -- 別名の前置きは、対応するモデルの状態を書いておく（比較で使う）
  for _, case in ipairs(out) do
    case.state = PREFIX_STATE[case.from] or case.from
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

-- ---------------------------------------------------------------------------
-- 実行

---@param argv string[]
local function main(argv)
  local out_path = ("%s/probe-%s.jsonl"):format(work, os.date("%Y%m%d-%H%M%S"))
  local only
  local list = false
  local from_index, limit
  local i = 1
  while i <= #argv do
    local arg = argv[i]
    if arg == "--out" then
      i = i + 1
      out_path = argv[i]
    elseif arg == "--only" then
      i = i + 1
      only = argv[i]
    elseif arg == "--from" then
      i = i + 1
      from_index = tonumber(argv[i])
    elseif arg == "--limit" then
      i = i + 1
      limit = tonumber(argv[i])
    elseif arg == "--list" then
      list = true
    elseif arg == "--help" or arg == "-h" then
      print([[
使い方: nvim --headless -u NONE -i NONE -l semantics/compare/probe.lua [オプション]

  --out <path>     JSONL の出力先（既定は .tests/compare/）
  --only <id>      1 つのケースだけ流す
  --list          ケースの一覧を出す
  --from <n>       n 番目から流す（1 起点。分割して流すとき用）
  --limit <n>      n 個だけ流す
]])
      return
    else
      error(("知らない引数です: %s"):format(arg))
    end
    i = i + 1
  end

  local cases = M.cases()
  if list then
    for _, case in ipairs(cases) do
      print(("%-52s %s"):format(case.id, case.prefix))
    end
    print(("ケース: %d"):format(#cases))
    return
  end
  if only then
    local picked = {}
    for _, case in ipairs(cases) do
      if case.id == only then
        picked[#picked + 1] = case
      end
    end
    if #picked == 0 then
      error(("知らないケースです: %s"):format(only))
    end
    cases = picked
  end

  if from_index or limit then
    local picked = {}
    local first = from_index or 1
    local last = limit and (first + limit - 1) or #cases
    for idx = first, math.min(last, #cases) do
      picked[#picked + 1] = cases[idx]
    end
    cases = picked
  end

  vim.fn.mkdir(vim.fs.dirname(out_path), "p")
  local file = assert(io.open(out_path, "w"))
  local done, blocked, prefix_mismatch = 0, 0, 0
  for _, case in ipairs(cases) do
    if os.getenv("PROBE_TRACE") then
      io.write("> ", case.id, "\n")
      io.stdout:flush()
    end
    local ok, rec = pcall(run_case, case)
    if not ok then
      rec = { id = case.id, transition = case.transition, from = case.from, event = case.event, error = tostring(rec) }
    end
    file:write(vim.json.encode(rec), "\n")
    file:flush()
    done = done + 1
    if rec.blocked or rec.error then
      blocked = blocked + 1
      print(("? %-52s %s"):format(case.id, rec.blocked or rec.error))
    elseif rec.expect then
      -- 前置きが狙った状態になっているか
      local want = PREFIX_STATE[case.from] or case.from
      if model.states[want] and rec.prefix_class ~= model.states[want].class then
        prefix_mismatch = prefix_mismatch + 1
        print(("! %-52s 前置きが %s（期待 %s）"):format(case.id, rec.prefix_class, model.states[want].class))
      end
    end
    if done % 100 == 0 then
      print(("... %d / %d"):format(done, #cases))
    end
  end
  file:close()
  for _, w in pairs(children) do
    pcall(function()
      getmetatable(w.set).opts.hooks.post_once()
    end)
    pcall(w.child.stop)
  end
  print(("観測したケース: %d（観測できない %d、前置きの違い %d）"):format(done, blocked, prefix_mismatch))
  print(("JSONL: %s"):format(out_path))
end

M.work = work

if arg and arg[0] and arg[0]:match("probe%.lua$") then
  local ok, err = pcall(main, arg)
  if not ok then
    print(("✗ 観測が落ちました: %s"):format(tostring(err)))
    os.exit(2)
  end
  os.exit(0)
end

return M

-- 差分テストのドライバ。Lua 版と denops 版の子の nvim を作り、同じキー列を流して状態を記録する
local M = {}

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
M.root = root

local lazy = vim.fn.expand("~/.local/share/nvim/lazy")
M.denops_path = os.getenv("DENOPS_PATH") or (lazy .. "/denops.vim")
M.upstream_path = os.getenv("SKKELETON_UPSTREAM_PATH") or (lazy .. "/skkeleton")

-- denops 版を動かせるか。動かせない理由（無ければ nil）を返す
function M.unavailable()
  if vim.fn.executable("deno") ~= 1 then
    return "deno not found"
  end
  if vim.fn.isdirectory(M.denops_path) ~= 1 then
    return "denops.vim not found: " .. M.denops_path
  end
  if vim.fn.isdirectory(M.upstream_path) ~= 1 then
    return "skkeleton (upstream) not found: " .. M.upstream_path
  end
end

-- キーの文字列を 1 キーずつに分ける（"Kan<Space>" -> K a n <Space>）
---@param keys string
---@return string[]
function M.tokenize(keys)
  local ret = {}
  local i = 1
  while i <= #keys do
    local s, e = keys:find("^<[%w%-_]+>", i)
    if s then
      ret[#ret + 1] = keys:sub(s, e)
      i = e + 1
    else
      local c = keys:sub(i, i)
      ret[#ret + 1] = c == "<" and "<LT>" or c
      i = i + 1
    end
  end
  return ret
end

-- 子の中で現在の状態を集める。pre-edit は Lua 版だけ extmark なので、バッファに足して denops 版と揃える
local snapshot_code = [[
  local vm = vim.api.nvim_get_mode()
  local r = { vim = vm.mode, mode = vim.g["skkeleton#mode"], enabled = vim.g["skkeleton#enabled"] }
  if vm.mode:sub(1, 1) == "c" then
    r.cmdline = vim.fn.getcmdline()
    r.cmdpos = vim.fn.getcmdpos()
    r.cmdtype = vim.fn.getcmdtype()
  end
  -- 普通のウィンドウ以外（popup）
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      r.popup = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
    end
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cur = vim.api.nvim_win_get_cursor(0)
  local ns = vim.api.nvim_get_namespaces()["skkeleton-preedit"]
  if ns then
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      local text = ""
      for _, chunk in ipairs(m[4].virt_text or {}) do
        text = text .. chunk[1]
      end
      local l = lines[m[2] + 1]
      lines[m[2] + 1] = l:sub(1, m[3]) .. text .. l:sub(m[3] + 1)
      if m[2] + 1 == cur[1] and m[3] <= cur[2] then
        cur[2] = cur[2] + #text
      end
    end
  end
  r.lines = lines
  r.cursor = cur
  r.hc = _G.hc
  return r
]]

local function snapshot(child)
  -- <C-g> の次のキー待ちなどで nvim が止まっているときは、RPC で中身を読めない
  if child.is_blocked() then
    local m = child.api.nvim_get_mode()
    return { vim = m.mode, blocked = true, hc = -1 }
  end
  return child.lua(snapshot_code)
end

local function same(a, b)
  return vim.deep_equal(a, b)
end

-- キーを流したあと、処理が終わって状態が落ち着くまで待つ
local function type_and_settle(child, key)
  local before = child.is_blocked() and -1 or child.lua_get("_G.hc")
  child.api.nvim_input(key)
  local t0 = vim.uv.hrtime()
  -- handle が終わった（skkeleton-handled が出た）か、辞書登録で cmdline に入ったら次へ
  while (vim.uv.hrtime() - t0) / 1e6 < 600 do
    local s = snapshot(child)
    if s.blocked or s.hc > before or s.vim:sub(1, 1) == "c" then
      break
    end
    vim.uv.sleep(2)
  end
  local last = snapshot(child)
  local stable = 0
  for _ = 1, 500 do
    vim.uv.sleep(4)
    local pending = (not child.is_blocked()) and child.lua_get("vim.fn.getchar(1)") ~= 0
    local cur = snapshot(child)
    if not pending and same(cur, last) then
      stable = stable + 1
      if stable >= 3 then
        return cur
      end
    else
      stable = 0
    end
    last = cur
  end
  last.unsettled = true
  return last
end

local function write_file(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

---@class DiffChild
---@field child table
---@field dir string

local function counter_code()
  return [[
    _G.hc = 0
    vim.api.nvim_create_autocmd("User", {
      pattern = "skkeleton-handled",
      callback = function() _G.hc = _G.hc + 1 end,
    })
  ]]
end

-- Lua 版の子
local function start_lua(child, config)
  child.restart({ "-u", root .. "/tests/minimal_init.lua", "-i", "NONE" })
  child.lua(counter_code())
  child.lua("require('skkeleton').setup(...)", { config })
end

-- denops 版の子。denops の起動を待つ
local function start_denops(child, config)
  child.restart({ "-u", "NONE", "-i", "NONE", "--noplugin" })
  child.lua(
    [[
    vim.opt.rtp:append((...)[1])
    vim.opt.rtp:append((...)[2])
    vim.g["denops#server#deno_args"] = { "--allow-all", "--unstable-kv" }
    vim.cmd("runtime! plugin/denops.vim plugin/skkeleton.vim")
    local ok = vim.fn["denops#plugin#wait"]("skkeleton", { timeout = 60000 })
    assert(ok == 0, "denops: skkeleton did not start")
    vim.fn["denops#request"]("skkeleton", "config", { (...)[3] })
  ]],
    { { M.denops_path, M.upstream_path, config } }
  )
  child.lua(counter_code())
end

-- 子の nvim に config の辞書とユーザー辞書を作って渡す。ディレクトリは一時のもの
local function make_config(dict_text, extra)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  write_file(dir .. "/dict", dict_text)
  local config = vim.tbl_extend("force", {
    globalDictionaries = { { dir .. "/dict", "utf-8" } },
    sources = { "skk_dictionary" },
    userDictionary = dir .. "/user",
    databasePath = dir .. "/db",
  }, extra or {})
  return config, dir
end

-- 1 つの実装で 1 つのキー列を流す
---@param impl "lua"|"denops"
---@param child table  MiniTest の子
---@param dict_text string
---@param keys string
---@param extra? table
---@param auto_cancel? boolean  辞書登録に入ったら <Esc> で取り消す
---@return table  { steps = snapshot[], error? }
function M.run(impl, child, dict_text, keys, extra, auto_cancel)
  local config, dir = make_config(dict_text, extra)
  local result = { steps = {} }
  local ok, err = pcall(function()
    if impl == "lua" then
      config.indicator = false
      start_lua(child, config)
    else
      -- 並列に動かすと起動が間に合わないことがあるので、数回やり直す
      local started, serr
      for _ = 1, 3 do
        started, serr = pcall(start_denops, child, config)
        if started then
          break
        end
      end
      assert(started, serr)
    end
    child.type_keys("i")
    local s = type_and_settle(child, "<Plug>(skkeleton-enable)")
    s.key = "<enable>"
    result.steps[1] = s
    for _, tok in ipairs(M.tokenize(keys)) do
      result.last = tok
      s = type_and_settle(child, tok)
      s.key = tok
      result.steps[#result.steps + 1] = s
      -- 辞書登録に入ったら、状態を記録したあとに取り消して先へ進む
      if auto_cancel and s.vim:sub(1, 1) == "c" then
        s = type_and_settle(child, "<Esc>")
        s.key = "<Esc>(cancel)"
        result.steps[#result.steps + 1] = s
      end
    end
    -- 辞書登録の入力が残っていたら取り消す（最後の状態は上で記録済み）
    for _ = 1, 4 do
      if child.api.nvim_get_mode().mode:sub(1, 1) ~= "c" then
        break
      end
      type_and_settle(child, "<Esc>")
    end
  end)
  if not ok then
    result.error = tostring(err) .. " (at " .. tostring(result.last) .. ", after " .. #result.steps .. " steps)"
  end
  pcall(child.stop)
  vim.fn.delete(dir, "rf")
  return result
end

return M

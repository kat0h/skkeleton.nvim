-- 行カバレッジ。検査の中で lua/skkeleton/ の通った行を記録し、coverage.lua で集計する。
--
-- 記録: debug.sethook(fn, "l") で、行ごとに source の名前を引いて覚える（source ごとの判定は表に覚える）。
--   子の nvim（check.lua）では、起こし直す前に harvest で中身を取り出して親にためる。
--   coroutine の中は別のスレッドで、フックが付かないので、coroutine.create / wrap を包んで付ける。
-- 分母: LuaJIT のバイトコードから取る（loadfile した関数と、入れ子の関数を全部たどり、
--   各命令の currentline を集める）。luacov のように「実行できそうな行」を字句から推すより、
--   フックが実際に報告する行と一致しやすい。
local M = {}

-- 子（または同じプロセス）に入れるコード。_G.__formal_cov = { [相対パス] = { [行] = true } }
M.hook_code = [[
  local root = ...
  local prefix = root .. "/lua/skkeleton/"
  local cov, known = {}, {}
  _G.__formal_cov = cov
  local getinfo = debug.getinfo
  -- 関数ごとに判定を覚える（getinfo "S" は文字列を作るので重い。"f" なら表引きで済む）
  local function hook(_, line)
    local fn = getinfo(2, "f").func
    local rel = known[fn]
    if rel == nil then
      rel = false
      local src = getinfo(fn, "S").source
      if src:sub(1, 1) == "@" and src:sub(2, #prefix + 1) == prefix then
        rel = src:sub(#root + 3)
      end
      known[fn] = rel
    end
    if rel then
      local t = cov[rel]
      if not t then
        t = {}
        cov[rel] = t
      end
      t[line] = true
    end
  end
  debug.sethook(hook, "l")
  local create = coroutine.create
  coroutine.create = function(f)
    local co = create(f)
    debug.sethook(co, hook, "l")
    return co
  end
  coroutine.wrap = function(f)
    local co = coroutine.create(f)
    return function(...)
      local r = { coroutine.resume(co, ...) }
      if not r[1] then error(r[2], 0) end
      return unpack(r, 2)
    end
  end
]]

-- 同じプロセスに入れる
function M.install(root)
  assert(loadstring(M.hook_code))(root)
end

-- 今のプロセスの記録を取り出す（取り出したあとは空にする）
function M.take_local()
  local c = _G.__formal_cov or {}
  local out = {}
  for f, t in pairs(c) do
    out[f] = vim.tbl_keys(t)
  end
  _G.__formal_cov = {}
  return out
end

-- 記録は { [相対パス] = { [行] = true } } の形でためる
function M.new()
  return {}
end

function M.add(acc, rec)
  for f, lines in pairs(rec) do
    local t = acc[f] or {}
    acc[f] = t
    for k, v in pairs(lines) do
      -- 配列（[行, ...]）でも { [行] = true } でも受ける
      t[type(k) == "number" and v == true and k or v] = true
    end
  end
end

-- 子の nvim から取り出して acc に足す。子が死んでいても進める
function M.harvest(child, acc)
  local ok, rec = pcall(
    child.lua_get,
    [[(function()
    local out = {}
    for f, t in pairs(_G.__formal_cov or {}) do
      out[f] = vim.tbl_keys(t)
    end
    return out
  end)()]]
  )
  if ok and type(rec) == "table" then
    M.add(acc, rec)
  end
end

function M.dir(root, name)
  return root .. "/.tests/formal-cov/" .. name
end

-- acc を <名前>/<pid>.json に書く（同じ pid なら足す）
function M.write(root, name, acc)
  local d = M.dir(root, name)
  vim.fn.mkdir(d, "p")
  local path = ("%s/%d.json"):format(d, vim.uv.os_getpid())
  local out = {}
  for f, set in pairs(acc) do
    out[f] = vim.tbl_keys(set)
    table.sort(out[f])
  end
  vim.fn.writefile({ vim.json.encode(out) }, path)
end

-- 同じプロセスの記録を、終了時に書く
function M.write_at_exit(root, name, acc)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.add(acc, M.take_local())
      M.write(root, name, acc)
    end,
  })
end

-- 分母: ファイルの実行できる行の集合
function M.executable_lines(path)
  local util = require("jit.util")
  local fn = assert(loadfile(path))
  local lines = {}
  local function walk(f)
    local pc = 1
    while util.funcbc(f, pc) do
      local l = util.funcinfo(f, pc).currentline
      if l and l > 0 then
        lines[l] = true
      end
      pc = pc + 1
    end
    local i = 1
    while true do
      local k = util.funck(f, -i)
      if k == nil then
        break
      end
      if type(k) == "proto" then
        walk(k)
      end
      i = i + 1
    end
  end
  walk(fn)
  return lines
end

return M

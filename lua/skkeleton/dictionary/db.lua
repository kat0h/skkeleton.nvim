-- SKK 辞書の永続キャッシュ（DB の形式 v1）。docs/PLAN.md の「DB の形式 v1」を実装する。
--
--   [0, 128)   ヘッダ: "SKKDB 1 <nari> <nnasi> <src_size> <src_mtime_sec> <src_mtime_nsec>\n" を空白で埋めたもの
--   [128, ...) 索引: リトルエンディアンの u32 で、各行の先頭のファイル内オフセット（0 起点）
--              okuri-ari の nari 個 + 終端 1 個、続けて okuri-nasi の nnasi 個 + 終端 1 個
--   その後     データ: "読み /候補/…/\n" を種類ごとにバイト順にソートして並べたもの（ari, nasi の順）
--
-- 行 i の長さは off[i + 1] - off[i] でわかるので、行を読むときは 1 回の read で済む。
-- 検索は索引を二分探索し、比較のたびに pread（vim.uv.fs_read）で 1 行だけ読む。
local skk = require("skkeleton.dictionary.skk")
local util = require("skkeleton.util")
local bit = require("bit")

local uv = vim.uv

local M = {}

M.HEADER_SIZE = 128
M.VERSION = 1

local function noop() end

local function u32(n)
  return string.char(bit.band(n, 0xff), bit.band(bit.rshift(n, 8), 0xff), bit.band(bit.rshift(n, 16), 0xff), bit.rshift(n, 24))
end

---@param s string
function M.parse_header(s)
  local v, nari, nnasi, size, sec, nsec = s:match("^SKKDB (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)\n")
  if not v or tonumber(v) ~= M.VERSION then
    return nil
  end
  return {
    nari = tonumber(nari),
    nnasi = tonumber(nnasi),
    src_size = tonumber(size),
    src_sec = tonumber(sec),
    src_nsec = tonumber(nsec),
  }
end

-- DB を置くディレクトリ。databasePath が無ければ stdpath("cache")/skkeleton。
-- databasePath がディレクトリでなければ（upstream ではファイルのパスだった）その親を使う。
-- まだ無いパスは、拡張子があれば（"skk.db" など）ファイル、なければディレクトリとみなす
---@param database_path? string
---@return string
function M.cache_dir(database_path)
  if database_path and database_path ~= "" then
    local p = util.expand_home(database_path)
    local st = uv.fs_stat(p)
    if st then
      return st.type == "directory" and p or vim.fs.dirname(vim.fs.normalize(p))
    end
    if p:sub(-1) == "/" or not vim.fs.basename(p):find(".", 2, true) then
      return vim.fs.normalize(p)
    end
    return vim.fs.dirname(vim.fs.normalize(p))
  end
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "skkeleton")
end

-- 元の辞書に対応する DB のパス。ファイル名は元の辞書の絶対パスの sha256 の先頭 16 文字。
-- エンコーディングを明示したときは、違う指定で古い DB を使わないようにハッシュに含める
---@param src string
---@param dir string
---@param encoding? string
function M.path_for(src, dir, encoding)
  local key = vim.fs.normalize(vim.fn.fnamemodify(src, ":p"))
  if encoding and encoding ~= "" then
    key = key .. "\0" .. encoding:lower()
  end
  return vim.fs.joinpath(dir, vim.fn.sha256(key):sub(1, 16) .. ".db")
end

-- DB が元の辞書と食い違っていないか（サイズと mtime で判定。途中で切れたファイルも弾く）
---@param src string
---@param dst string
function M.is_fresh(src, dst)
  local fd = uv.fs_open(dst, "r", 438)
  if not fd then
    return false
  end
  local ok, fresh = pcall(function()
    local h = M.parse_header(uv.fs_read(fd, M.HEADER_SIZE, 0) or "")
    local st = uv.fs_stat(src)
    if not (h and st and h.src_size == st.size and h.src_sec == st.mtime.sec and h.src_nsec == st.mtime.nsec) then
      return false
    end
    -- 索引の最後の u32 が、ファイルの大きさと一致するはず
    local last = uv.fs_read(fd, 4, M.HEADER_SIZE + (h.nari + h.nnasi + 1) * 4)
    local fst = uv.fs_fstat(fd)
    if not last or #last ~= 4 or not fst then
      return false
    end
    local a, b, c, d = last:byte(1, 4)
    return a + b * 0x100 + c * 0x10000 + d * 0x1000000 == fst.size
  end)
  uv.fs_close(fd)
  return ok and fresh or false
end

local tmp_counter = 0

-- DB を作る。tick は一定の間隔で呼ぶ（コルーチンで譲るため。無ければ一気に作る）。
-- `.tmp`（プロセスと回ごとに別の名前）に書いてから rename するので、複数の Neovim が同時に作っても壊れない
---@param src string
---@param dst string
---@param encoding? string
---@param tick? fun()
function M.build(src, dst, encoding, tick)
  tick = tick or noop
  local data, stat = skk.read_file(src)
  tick()
  local text = skk.decode(data, encoding)
  data = nil
  tick()
  local maps = skk.parse(text, tick)
  text = nil
  local keys = { okuriari = skk.sorted_keys(maps.okuriari, tick), okurinasi = skk.sorted_keys(maps.okurinasi, tick) }
  local nari, nnasi = #keys.okuriari, #keys.okurinasi
  local data_start = M.HEADER_SIZE + (nari + 1 + nnasi + 1) * 4
  local idx, lines = {}, {}
  local pos = data_start
  local n = 0
  for _, kind in ipairs(skk.KINDS) do
    local map = maps[kind]
    for _, k in ipairs(keys[kind]) do
      local line = k .. " " .. map[k] .. "\n"
      idx[#idx + 1] = u32(pos)
      lines[#lines + 1] = line
      pos = pos + #line
      n = n + 1
      if n % 8192 == 0 then
        tick()
      end
    end
    idx[#idx + 1] = u32(pos) -- 終端
  end
  maps = nil
  assert(pos < 2 ^ 32, "dictionary too large")
  local header = ("SKKDB %d %d %d %d %d %d\n"):format(M.VERSION, nari, nnasi, stat.size, stat.mtime.sec, stat.mtime.nsec)
  header = header .. (" "):rep(M.HEADER_SIZE - #header)
  local index = table.concat(idx)
  tick()
  local body = table.concat(lines)
  tick()

  vim.fn.mkdir(vim.fs.dirname(dst), "p")
  tmp_counter = tmp_counter + 1
  local tmp = ("%s.%d.%d.tmp"):format(dst, uv.os_getpid(), tmp_counter)
  local fd, err = uv.fs_open(tmp, "w", 420)
  if not fd then
    error(("cannot write %s (%s)"):format(tmp, err), 0)
  end
  local ok, werr = uv.fs_write(fd, { header, index, body }, 0)
  uv.fs_close(fd)
  if not ok then
    uv.fs_unlink(tmp)
    error(("cannot write %s (%s)"):format(tmp, werr), 0)
  end
  local renamed, rerr = uv.fs_rename(tmp, dst)
  if not renamed then
    uv.fs_unlink(tmp)
    error(("cannot rename %s (%s)"):format(tmp, rerr), 0)
  end
end

-- fn(tick) をコルーチンで少しずつ進める。fn は途中で tick() を呼ぶと譲る。終わったら cb(ok, 結果かエラー)
---@param fn fun(tick: fun())
---@param cb fun(ok: boolean, result: any)
function M.run_async(fn, cb)
  local last
  local function tick()
    if uv.hrtime() - last > 4e6 then
      coroutine.yield()
      last = uv.hrtime()
    end
  end
  local co = coroutine.create(function()
    return fn(tick)
  end)
  local function step()
    last = uv.hrtime()
    local ok, res = coroutine.resume(co)
    if not ok then
      cb(false, res)
    elseif coroutine.status(co) == "dead" then
      cb(true, res)
    else
      vim.defer_fn(step, 1)
    end
  end
  vim.schedule(step)
end

---@class skkeleton.DbOpts
---@field encoding? string
---@field dir? string DB を置くディレクトリ。無ければ cache_dir()
---@field force? boolean 新しくても作り直す

local function resolve(src, opts)
  opts = opts or {}
  src = vim.fs.normalize(vim.fn.fnamemodify(util.expand_home(src), ":p"))
  return src, M.path_for(src, opts.dir or M.cache_dir(), opts.encoding), opts
end

-- 新しい DB があればそのパスを返し、無ければその場で作る
---@param src string
---@param opts? skkeleton.DbOpts
---@return string dst
function M.ensure(src, opts)
  local dst
  src, dst, opts = resolve(src, opts)
  if opts.force or not M.is_fresh(src, dst) then
    M.build(src, dst, opts.encoding)
  end
  return dst
end

local building = {} ---@type table<string, fun(dst?: string, err?: string)[]>

-- ensure の非同期版。UI を止めないよう、作るのを小分けにして、間にイベントループを回しながら進める。
-- 終わったら cb(dst) か cb(nil, err)。同じ DB を作っている最中の呼び出しは、その完了を待つ
---@param src string
---@param opts? skkeleton.DbOpts
---@param cb fun(dst?: string, err?: string)
function M.ensure_async(src, opts, cb)
  local dst
  src, dst, opts = resolve(src, opts)
  if not opts.force and M.is_fresh(src, dst) then
    return cb(dst)
  end
  if building[dst] then
    table.insert(building[dst], cb)
    return
  end
  building[dst] = { cb }
  M.run_async(function(tick)
    M.build(src, dst, opts.encoding, tick)
  end, function(ok, err)
    local cbs = building[dst]
    building[dst] = nil
    for _, f in ipairs(cbs) do
      if ok then
        f(dst)
      else
        f(nil, tostring(err))
      end
    end
  end)
end

---@class skkeleton.DbDictionary
---@field fd integer
---@field idx string
---@field path string
local Dict = {}
Dict.__index = Dict

-- DB を開き、索引だけをメモリに読む
---@param path string
---@return skkeleton.DbDictionary
function M.open(path)
  local fd, err = uv.fs_open(path, "r", 438)
  if not fd then
    error(("cannot open %s (%s)"):format(path, err), 0)
  end
  local ok, res = pcall(function()
    local h = M.parse_header(uv.fs_read(fd, M.HEADER_SIZE, 0) or "")
    if not h then
      error("bad header", 0)
    end
    local idx = uv.fs_read(fd, (h.nari + 1 + h.nnasi + 1) * 4, M.HEADER_SIZE)
    if not idx or #idx ~= (h.nari + 1 + h.nnasi + 1) * 4 then
      error("truncated index", 0)
    end
    return setmetatable({
      fd = fd,
      idx = idx,
      path = path,
      -- 索引の中で、その種類の 1 件目が何番目か（0 起点）
      okuriari = { base = 0, n = h.nari },
      okurinasi = { base = h.nari + 1, n = h.nnasi },
    }, Dict)
  end)
  if not ok then
    uv.fs_close(fd)
    error(("%s: %s"):format(path, res), 0)
  end
  return res
end

-- 元の辞書から DB を（必要なら作って）開く
---@param src string
---@param opts? skkeleton.DbOpts
---@return skkeleton.DbDictionary
function M.open_dictionary(src, opts)
  local dst = M.ensure(src, opts)
  local ok, dict = pcall(M.open, dst)
  if ok then
    return dict
  end
  -- 壊れていたら一度だけ作り直す
  local _, _, o = resolve(src, opts)
  o = vim.tbl_extend("force", o, { force = true })
  return M.open(M.ensure(src, o))
end

function Dict:close()
  if self.fd then
    uv.fs_close(self.fd)
    self.fd = nil
  end
end

-- 索引の j 番目（0 起点）の u32
local function off_at(idx, j)
  local a, b, c, d = idx:byte(j * 4 + 1, j * 4 + 4)
  return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

-- t の i 番目（1 起点）の行を読む
function Dict:line(t, i)
  local j = t.base + i - 1
  local off = off_at(self.idx, j)
  return uv.fs_read(self.fd, off_at(self.idx, j + 1) - off, off)
end

local function key_of(line)
  return line:sub(1, line:find(" ", 1, true) - 1)
end

-- key 以上になる最初の行の番号
local function lower_bound(self, t, key)
  local lo, hi = 1, t.n + 1
  while lo < hi do
    local mid = bit.rshift(lo + hi, 1)
    if key_of(self:line(t, mid)) < key then
      lo = mid + 1
    else
      hi = mid
    end
  end
  return lo
end

-- "/候補/…/" のまま返す。無ければ nil
---@param kind "okuriari"|"okurinasi"
---@param key string
---@return string?
function Dict:get_raw(kind, key)
  local t = self[kind]
  local i = lower_bound(self, t, key)
  if i > t.n then
    return nil
  end
  local line = self:line(t, i)
  if key_of(line) ~= key then
    return nil
  end
  return line:sub(#key + 2, -2)
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@return string[]
function Dict:get_henkan_result(kind, word)
  local raw = self:get_raw(kind, word)
  return raw and skk.split_candidates(raw) or {}
end

-- 前方一致する読みを、バイト順に limit 件まで。{ { 読み, 候補の配列 }, ... }
---@param kind "okuriari"|"okurinasi"
---@param prefix string
---@param limit? integer
function Dict:get_prefix(kind, prefix, limit)
  limit = limit or math.huge
  local t = self[kind]
  local hits = {}
  local n = #prefix
  local i = lower_bound(self, t, prefix)
  while i <= t.n and #hits < limit do
    local line = self:line(t, i)
    local k = key_of(line)
    if k:sub(1, n) ~= prefix then
      break
    end
    hits[#hits + 1] = { k, skk.split_candidates(line:sub(#k + 2, -2)) }
    i = i + 1
  end
  return hits
end

return M

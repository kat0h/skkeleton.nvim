-- C: 永続キャッシュを開き、索引だけメモリに読む。検索のたびに pread（vim.uv.fs_read）でデータ部を読む
local cache = require("lib.cache")
local bit = require("bit")

local Dict = {}
Dict.__index = Dict

local M = {}

M.build = cache.build

function M.open(path)
  local fd = assert(vim.uv.fs_open(path, "r", 438))
  local h = assert(cache.parse_header(assert(vim.uv.fs_read(fd, cache.HEADER_SIZE, 0))), "bad header")
  local idx = assert(vim.uv.fs_read(fd, (h.nari + 1 + h.nnasi + 1) * 4, cache.HEADER_SIZE))
  return setmetatable({
    fd = fd,
    idx = idx,
    -- 索引の中で、その種類の 1 件目が何番目か（0 起点）
    okuriari = { base = 0, n = h.nari },
    okurinasi = { base = h.nari + 1, n = h.nnasi },
  }, Dict)
end

function Dict:close()
  vim.uv.fs_close(self.fd)
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
  return vim.uv.fs_read(self.fd, off_at(self.idx, j + 1) - off, off)
end

local function key_of(line)
  return line:sub(1, line:find(" ", 1, true) - 1)
end

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

function Dict:lookup(kind, key)
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

function Dict:prefix(kind, prefix, limit)
  local t = self[kind]
  local hits = {}
  local n = #prefix
  local i = lower_bound(self, t, prefix)
  while i <= t.n and #hits < limit do
    local k = key_of(self:line(t, i))
    if k:sub(1, n) ~= prefix then
      break
    end
    hits[#hits + 1] = k
    i = i + 1
  end
  return hits
end

return M

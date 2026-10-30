-- C': C と同じキャッシュを LuaJIT FFI で mmap して読む（Linux/macOS のみ）
local cache = require("lib.cache")
local ffi = require("ffi")
local bit = require("bit")

pcall(
  ffi.cdef,
  [[
  int open(const char *path, int flags, ...);
  int close(int fd);
  void *mmap(void *addr, size_t len, int prot, int flags, int fd, long off);
  int munmap(void *addr, size_t len);
  int memcmp(const void *a, const void *b, size_t n);
  void *memchr(const void *s, int c, size_t n);
]]
)
local C = ffi.C
local PROT_READ, MAP_PRIVATE = 1, 2

local Dict = {}
Dict.__index = Dict

local M = {}

M.build = cache.build

function M.open(path)
  local size = assert(vim.uv.fs_stat(path)).size
  local fd = C.open(path, 0)
  assert(fd >= 0, "open failed")
  local p = C.mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)
  C.close(fd)
  assert(ffi.cast("intptr_t", p) ~= -1, "mmap failed")
  local base = ffi.cast("const uint8_t *", p)
  local h = assert(cache.parse_header(ffi.string(base, cache.HEADER_SIZE)), "bad header")
  local idx = ffi.cast("const uint32_t *", base + cache.HEADER_SIZE) -- x86/ARM はリトルエンディアン
  return setmetatable({
    p = p,
    size = size,
    base = base,
    okuriari = { idx = idx, n = h.nari },
    okurinasi = { idx = idx + h.nari + 1, n = h.nnasi },
  }, Dict)
end

function Dict:close()
  C.munmap(self.p, self.size)
end

-- i 番目（0 起点）の行の、行頭ポインタと読みの長さ
local function entry(self, t, i)
  local off = t.idx[i]
  local s = self.base + off
  local sp = C.memchr(s, 32, t.idx[i + 1] - off)
  return s, ffi.cast("const uint8_t *", sp) - s
end

-- 読みと key を比べる（memcmp と同じ符号）
local function cmp(s, klen, key)
  local n = #key
  local r = C.memcmp(s, key, klen < n and klen or n)
  if r ~= 0 then
    return r
  end
  return klen - n
end

local function lower_bound(self, t, key)
  local lo, hi = 0, t.n
  while lo < hi do
    local mid = bit.rshift(lo + hi, 1)
    local s, klen = entry(self, t, mid)
    if cmp(s, klen, key) < 0 then
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
  if i >= t.n then
    return nil
  end
  local s, klen = entry(self, t, i)
  if cmp(s, klen, key) ~= 0 then
    return nil
  end
  -- 空白の次から改行の手前まで
  return ffi.string(s + klen + 1, t.idx[i + 1] - t.idx[i] - klen - 2)
end

function Dict:prefix(kind, prefix, limit)
  local t = self[kind]
  local hits = {}
  local n = #prefix
  local i = lower_bound(self, t, prefix)
  while i < t.n and #hits < limit do
    local s, klen = entry(self, t, i)
    if klen < n or C.memcmp(s, prefix, n) ~= 0 then
      break
    end
    hits[#hits + 1] = ffi.string(s, klen)
    i = i + 1
  end
  return hits
end

return M

-- B: UTF-8 の行をソートして 1 本の文字列に連結し、行頭オフセットで二分探索する
-- 永続キャッシュは使わない（起動のたびに作る）
local skk = require("lib.skk")

local Dict = {}
Dict.__index = Dict

local M = {}

local function build_kind(map)
  local keys = skk.sorted_keys(map)
  local lines, offs = {}, {}
  local pos = 1
  for i, k in ipairs(keys) do
    local line = k .. " " .. map[k] .. "\n"
    lines[i] = line
    offs[i] = pos
    pos = pos + #line
  end
  return { blob = table.concat(lines), offs = offs, n = #keys }
end

function M.open(path)
  local maps = skk.load(path)
  return setmetatable({
    okuriari = build_kind(maps.okuriari),
    okurinasi = build_kind(maps.okurinasi),
  }, Dict)
end

local function key_at(t, i)
  local off = t.offs[i]
  local sp = t.blob:find(" ", off, true)
  return t.blob:sub(off, sp - 1), sp
end

-- key 以上になる最初の位置
local function lower_bound(t, key)
  local lo, hi = 1, t.n + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if key_at(t, mid) < key then
      lo = mid + 1
    else
      hi = mid
    end
  end
  return lo
end

function Dict:lookup(kind, key)
  local t = self[kind]
  local i = lower_bound(t, key)
  if i > t.n then
    return nil
  end
  local k, sp = key_at(t, i)
  if k ~= key then
    return nil
  end
  local stop = (t.offs[i + 1] or #t.blob + 1) - 2 -- 改行の手前
  return t.blob:sub(sp + 1, stop)
end

function Dict:prefix(kind, prefix, limit)
  local t = self[kind]
  local hits = {}
  local n = #prefix
  local i = lower_bound(t, prefix)
  while i <= t.n and #hits < limit do
    local k = key_at(t, i)
    if k:sub(1, n) ~= prefix then
      break
    end
    hits[#hits + 1] = k
    i = i + 1
  end
  return hits
end

return M

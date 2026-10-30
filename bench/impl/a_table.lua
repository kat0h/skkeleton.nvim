-- A: 毎回パースして Lua の table に入れる（基準。denops 版 skk_dictionary と同じ方式）
local skk = require("lib.skk")

local Dict = {}
Dict.__index = Dict

local M = {}

function M.open(path)
  return setmetatable({ maps = skk.load(path) }, Dict)
end

function Dict:lookup(kind, key)
  return self.maps[kind][key]
end

-- 前方一致は全件を走査する（参照実装）
function Dict:prefix(kind, prefix, limit)
  local hits = {}
  local n = #prefix
  for k in pairs(self.maps[kind]) do
    if k:sub(1, n) == prefix then
      hits[#hits + 1] = k
    end
  end
  table.sort(hits)
  for i = #hits, limit + 1, -1 do
    hits[i] = nil
  end
  return hits
end

return M

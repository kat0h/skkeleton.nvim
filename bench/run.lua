-- 使い方: nvim --headless -u NONE -l bench/run.lua <A|B|C|Cp> <dict...>
-- 1 つの実装について、起動・検索・前方一致・メモリを測って JSON 1 行で出す
-- 複数の辞書を渡したときは、検索のたびに全部の辞書を引く（skkeleton の Library と同じ）
local boot = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/lib/boot.lua")
package.path = boot.root .. "/?.lua;" .. package.path

local name = table.remove(arg, 1)
local srcs = { unpack(arg) } -- arg[0] (スクリプト名) を除く
local LIMIT = 100

local queries = {}
for _, line in ipairs(vim.fn.readfile(vim.fs.joinpath(boot.out, "queries.tsv"))) do
  local what, kind, key = line:match("^(%S+)\t(%S+)\t(.*)$")
  queries[#queries + 1] = { what, kind, key }
end
-- モジュールの読み込みは起動時間に入れない
require(boot.IMPLS[name])
require("lib.skk")
require("lib.cache")

collectgarbage("collect")
local gc0, rss0 = collectgarbage("count"), boot.rss_kb()

local t0 = boot.now()
local dicts = {}
for i, src in ipairs(srcs) do
  dicts[i] = boot.open(name, src)
end
local t1 = boot.now()
local q = queries[1]
for _, d in ipairs(dicts) do
  d:lookup(q[2], q[3])
end
local t2 = boot.now()

collectgarbage("collect")
local gc1, rss1 = collectgarbage("count"), boot.rss_kb()

local function stats(xs)
  table.sort(xs)
  local sum = 0
  for _, x in ipairs(xs) do
    sum = sum + x
  end
  local function p(r)
    return xs[math.max(1, math.ceil(#xs * r))] / 1e6
  end
  return { n = #xs, mean = sum / #xs / 1e6, p50 = p(0.5), p90 = p(0.9), p99 = p(0.99), max = xs[#xs] / 1e6 }
end

local lookup_t, miss_t, prefix_t = {}, {}, {}
local found = 0
for _, qq in ipairs(queries) do
  local what, kind, key = qq[1], qq[2], qq[3]
  local s = boot.now()
  if what == "prefix" then
    local hits = {}
    for _, d in ipairs(dicts) do
      vim.list_extend(hits, d:prefix(kind, key, LIMIT))
    end
    prefix_t[#prefix_t + 1] = boot.now() - s
  else
    local cands = {}
    for _, d in ipairs(dicts) do
      local c = d:lookup(kind, key)
      if c then
        cands[#cands + 1] = c
      end
    end
    local e = boot.now() - s
    if what == "hit" then
      lookup_t[#lookup_t + 1] = e
      found = found + (#cands > 0 and 1 or 0)
    else
      miss_t[#miss_t + 1] = e
    end
  end
end

io.stdout:write(
  vim.json.encode({
    kind = "run",
    impl = name,
    dicts = vim.tbl_map(vim.fs.basename, srcs),
    open_ms = (t1 - t0) / 1e6,
    first_lookup_ms = (t2 - t1) / 1e6,
    ready_ms = (t2 - t0) / 1e6,
    lua_heap_mb = (gc1 - gc0) / 1024,
    rss_mb = (rss1 - rss0) / 1024,
    hit_found = found,
    lookup = stats(lookup_t),
    miss = stats(miss_t),
    prefix = stats(prefix_t),
  }),
  "\n"
)

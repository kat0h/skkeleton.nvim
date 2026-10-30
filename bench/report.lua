-- 使い方: nvim --headless -u NONE -l bench/report.lua bench/out/results.jsonl
-- run.lua / build.lua の結果を Markdown の表にする（同じ条件の複数回は中央値）
local rows, builds = {}, {}
for _, line in ipairs(vim.fn.readfile(arg[1])) do
  local r = vim.json.decode(line)
  if r.kind == "build" then
    builds[#builds + 1] = r
  else
    local key = r.impl .. "|" .. #r.dicts
    rows[key] = rows[key] or { impl = r.impl, ndict = #r.dicts, runs = {} }
    table.insert(rows[key].runs, r)
  end
end

local function median(runs, f)
  local xs = vim.tbl_map(f, runs)
  table.sort(xs)
  return xs[math.ceil(#xs / 2)]
end

local NAMES = { A = "A table", B = "B memory", C = "C pread", Cp = "C' mmap" }
local out = {}
local function w(s)
  out[#out + 1] = s
end

w("### キャッシュの生成（C / C' 共通）")
w("")
w("| 辞書 | 生成時間 | キャッシュのサイズ |")
w("|---|---:|---:|")
for _, b in ipairs(builds) do
  w(("| %s | %.0f ms | %.1f MB |"):format(b.dict, b.ms, b.bytes / 1e6))
end

for _, ndict in ipairs({ 1, 5 }) do
  w("")
  w(ndict == 1 and "### SKK-JISYO.L だけ" or "### 5 辞書（L + jinmei + geo + station + propernoun）")
  w("")
  w("| 実装 | 起動（open+初回検索） | 検索 p50 | 検索 p99 | 検索 max | 無い語 p50 | 前方一致 p50 | 前方一致 max | Lua ヒープ | RSS 増加 |")
  w("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
  for _, impl in ipairs({ "A", "B", "C", "Cp" }) do
    local row = rows[impl .. "|" .. ndict]
    if row then
      local rs = row.runs
      w(("| %s | %.2f ms | %.4f ms | %.4f ms | %.3f ms | %.4f ms | %.3f ms | %.3f ms | %.1f MB | %.1f MB |"):format(
        NAMES[impl],
        median(rs, function(r) return r.ready_ms end),
        median(rs, function(r) return r.lookup.p50 end),
        median(rs, function(r) return r.lookup.p99 end),
        median(rs, function(r) return r.lookup.max end),
        median(rs, function(r) return r.miss.p50 end),
        median(rs, function(r) return r.prefix.p50 end),
        median(rs, function(r) return r.prefix.max end),
        median(rs, function(r) return r.lua_heap_mb end),
        median(rs, function(r) return r.rss_mb end)
      ))
    end
  end
end
print(table.concat(out, "\n"))

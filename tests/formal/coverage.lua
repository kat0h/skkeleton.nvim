-- 行カバレッジの集計。--coverage <名前> で溜めた .tests/formal-cov/<名前>/*.json を足し合わせる。
-- 使い方: nvim --headless -u NONE -i NONE -l tests/formal/coverage.lua <名前>... [--json] [--min N] [--top N]
--   ファイルごとの「通った行／実行できる行」を割合の低い順に、通っていない行のまとまりを出す。
--   --top N は、ファイルごとに出す未通過の範囲の数（既定 12。0 で全部）。--json は機械が読める形。
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")
local cov = dofile(here .. "/cov.lua")

local names, json, top = {}, false, 12
do
  local i = 1
  while i <= #arg do
    if arg[i] == "--json" then
      json = true
    elseif arg[i] == "--top" then
      top, i = tonumber(arg[i + 1]), i + 1
    else
      names[#names + 1] = arg[i]
    end
    i = i + 1
  end
end
if #names == 0 then
  io.stderr:write("usage: coverage.lua <name>... [--json] [--top N]\n")
  os.exit(2)
end

local acc = cov.new()
local nfiles = 0
for _, name in ipairs(names) do
  for _, f in ipairs(vim.fn.glob(cov.dir(root, name) .. "/*.json", true, true)) do
    local ok, rec = pcall(vim.json.decode, table.concat(vim.fn.readfile(f), "\n"))
    if ok then
      cov.add(acc, rec)
      nfiles = nfiles + 1
    end
  end
end

local rows, total_hit, total_all = {}, 0, 0
for _, path in ipairs(vim.fn.globpath(root, "lua/skkeleton/**/*.lua", true, true)) do
  local rel = path:sub(#root + 2)
  local exe = cov.executable_lines(path)
  local src = vim.fn.readfile(path)
  local hit, all, missed = 0, 0, {}
  for l in pairs(exe) do
    all = all + 1
    if acc[rel] and acc[rel][l] then
      hit = hit + 1
    else
      missed[#missed + 1] = l
    end
  end
  table.sort(missed)
  -- 連続（間の空行・コメントだけの行は続きとみなす）する未通過の行をまとまりにする
  local ranges = {}
  for _, l in ipairs(missed) do
    local last = ranges[#ranges]
    local contiguous = false
    if last then
      contiguous = true
      for m = last[2] + 1, l - 1 do
        local t = vim.trim(src[m] or "")
        if exe[m] or not (t == "" or t:sub(1, 2) == "--" or t == "end" or t == "else" or t == "}" or t == ")") then
          contiguous = false
          break
        end
      end
    end
    if contiguous then
      last[2], last[3] = l, last[3] + 1
    else
      ranges[#ranges + 1] = { l, l, 1 }
    end
  end
  for _, r in ipairs(ranges) do
    r.text = vim.trim(src[r[1]] or "")
  end
  total_hit, total_all = total_hit + hit, total_all + all
  rows[#rows + 1] = { file = rel, hit = hit, all = all, pct = all > 0 and hit / all * 100 or 100, ranges = ranges }
end
table.sort(rows, function(a, b)
  if a.pct ~= b.pct then
    return a.pct < b.pct
  end
  return a.file < b.file
end)

local total_pct = total_all > 0 and total_hit / total_all * 100 or 100
if json then
  local out = { names = names, runs = nfiles, hit = total_hit, all = total_all, pct = total_pct, files = {} }
  for _, r in ipairs(rows) do
    local ranges = {}
    for _, g in ipairs(r.ranges) do
      ranges[#ranges + 1] = { from = g[1], to = g[2], lines = g[3], text = g.text }
    end
    out.files[#out.files + 1] = { file = r.file, hit = r.hit, all = r.all, pct = r.pct, missed = ranges }
  end
  io.stdout:write(vim.json.encode(out), "\n")
  os.exit(0)
end

print(
  ("行カバレッジ（%s、記録 %d 個）: %d / %d 行 = %.1f%%\n"):format(
    table.concat(names, "+"),
    nfiles,
    total_hit,
    total_all,
    total_pct
  )
)
print(("%-42s %6s %6s %7s"):format("ファイル", "通った", "全行", "割合"))
for _, r in ipairs(rows) do
  print(("%-42s %6d %6d %6.1f%%"):format(r.file:gsub("^lua/skkeleton/", ""), r.hit, r.all, r.pct))
end
print("\n通っていない行のまとまり（範囲、行数、先頭の行）")
for _, r in ipairs(rows) do
  if #r.ranges > 0 then
    print(("\n%s（%d / %d）"):format(r.file, r.hit, r.all))
    for n, g in ipairs(r.ranges) do
      if top > 0 and n > top then
        print(("  ... ほか %d 個のまとまり"):format(#r.ranges - top))
        break
      end
      print(("  %d-%d (%d行)  %s"):format(g[1], g[2], g[3], g.text:sub(1, 80)))
    end
  end
end

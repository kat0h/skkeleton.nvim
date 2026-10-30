-- 使い方: nvim --headless -u NONE -l bench/gen_queries.lua <dict>
-- 検索に使う語を bench/out/queries.tsv に書く（seed 固定）
--   hit: 辞書にある語 10000 個、miss: 無い語 1000 個、prefix: 前方一致 100 個（okuri-nasi）
local boot = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/lib/boot.lua")
package.path = boot.root .. "/?.lua;" .. package.path
local skk = require("lib.skk")

local maps = skk.load(arg[1])
local all = {}
for _, kind in ipairs(skk.KINDS) do
  for _, k in ipairs(skk.sorted_keys(maps[kind])) do
    all[#all + 1] = { kind, k }
  end
end
local nasi = skk.sorted_keys(maps.okurinasi)

math.randomseed(42)
local lines = {}
for _ = 1, 10000 do
  local e = all[math.random(#all)]
  lines[#lines + 1] = ("hit\t%s\t%s"):format(e[1], e[2])
end
for _ = 1, 1000 do
  local e = all[math.random(#all)]
  lines[#lines + 1] = ("miss\t%s\t%s"):format(e[1], e[2] .. "ゔ")
end
for _ = 1, 100 do
  local p = boot.utf8_head(nasi[math.random(#nasi)], math.random(2))
  lines[#lines + 1] = ("prefix\tokurinasi\t%s"):format(p)
end
vim.fn.mkdir(boot.out, "p")
vim.fn.writefile(lines, vim.fs.joinpath(boot.out, "queries.tsv"))
print(("wrote %d queries"):format(#lines))

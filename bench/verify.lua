-- 使い方: nvim --headless -u NONE -l bench/verify.lua <dict...>
-- B/C/C' の検索結果が A（参照実装）と同じかを確かめる。食い違いがあれば終了コード 1
local boot = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/lib/boot.lua")
package.path = boot.root .. "/?.lua;" .. package.path
local skk = require("lib.skk")

local LIMIT = 100
local failed = 0

for _, src in ipairs(arg) do
  local ref = boot.open("A", src)
  local others = { B = boot.open("B", src), C = boot.open("C", src), Cp = boot.open("Cp", src) }
  math.randomseed(1)
  local checked, prefixes = 0, 0
  for _, kind in ipairs(skk.KINDS) do
    local keys = skk.sorted_keys(ref.maps[kind])
    local probes = {}
    for _, k in ipairs(keys) do
      probes[#probes + 1] = k
    end
    -- 無い語: 実在する読みの前後に文字を足したもの、空文字、範囲外
    for _ = 1, #keys > 0 and 2000 or 0 do
      local k = keys[math.random(#keys)]
      probes[#probes + 1] = k .. "ゔ"
      probes[#probes + 1] = "!" .. k
    end
    vim.list_extend(probes, { "", "\1", "\244\143\191\191" })
    for _, k in ipairs(probes) do
      local want = ref:lookup(kind, k)
      for name, d in pairs(others) do
        local got = d:lookup(kind, k)
        if got ~= want then
          failed = failed + 1
          if failed <= 20 then
            print(("MISMATCH %s %s %s %q: want %q got %q"):format(vim.fs.basename(src), name, kind, k, tostring(want), tostring(got)))
          end
        end
      end
      checked = checked + 1
    end
    -- 前方一致: 1〜3 文字の接頭辞
    for _ = 1, #keys > 0 and 300 or 0 do
      local k = keys[math.random(#keys)]
      local p = boot.utf8_head(k, math.random(3))
      local want = ref:prefix(kind, p, LIMIT)
      for name, d in pairs(others) do
        if not vim.deep_equal(want, d:prefix(kind, p, LIMIT)) then
          failed = failed + 1
          if failed <= 20 then
            print(("MISMATCH prefix %s %s %s %q"):format(vim.fs.basename(src), name, kind, p))
          end
        end
      end
      prefixes = prefixes + 1
    end
  end
  print(("%s: %d lookups, %d prefixes x %d impls checked"):format(vim.fs.basename(src), checked, prefixes, 3))
end

print(failed == 0 and "OK: no mismatch" or ("FAILED: %d mismatches"):format(failed))
os.exit(failed == 0 and 0 or 1)

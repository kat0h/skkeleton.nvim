-- SKK-JISYO.L を使う重いテスト。`make test` には入れず、`make jisyotest` で流す。
-- SKK-JISYO.L が無い環境では skip する。
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local PRE = helpers.dict_pre(([[
local dictionary = require("skkeleton.dictionary")
local Library = dictionary.Library
local User = require("skkeleton.dictionary.user")
local skk = require("skkeleton.dictionary.skk")
local db = require("skkeleton.dictionary.db")
local config = require("skkeleton.config")
local TD = %q
]]):format(helpers.testdata))

local function run(code, ...)
  return child.lua(PRE .. code, { ... })
end

local path = "/usr/share/skk/SKK-JISYO.L"

local function skip_if_missing()
  if vim.uv.fs_stat(path) == nil then
    MiniTest.skip(path .. " is not installed")
  end
end

-- DB の結果がメモリ上のパース結果と一致することを、辞書の全見出し語で確かめる
local COMPARE = [[
  local function compare(src, enc)
    local mem = skk.load_memory(src, enc)
    local d = db.open_dictionary(src, { encoding = enc, dir = TMP .. "/db" })
    local n = 0
    for _, kind in ipairs(skk.KINDS) do
      for k in pairs(mem.maps[kind]) do
        assert(vim.deep_equal(d:get_henkan_result(kind, k), mem:get_henkan_result(kind, k)), k)
        n = n + 1
      end
      local all = d:get_prefix(kind, "", math.huge)
      local cnt = 0
      for _ in pairs(mem.maps[kind]) do
        cnt = cnt + 1
      end
      assert(#all == cnt, ("%s: %d ~= %d"):format(kind, #all, cnt))
    end
    assert(vim.deep_equal(d:get_henkan_result("okurinasi", "ありえない読み"), {}))
    d:close()
    return n
  end
]]

T["db matches the memory dictionary for SKK-JISYO.L"] = function()
  skip_if_missing()
  local n = run(COMPARE .. [[ return compare(...) ]], path)
  eq(n > 100000, true)
end

T["db prefix search matches a scan of the memory dictionary for SKK-JISYO.L"] = function()
  skip_if_missing()
  eq(
    run(
      [[
      local src = ...
      local mem = skk.load_memory(src)
      local d = db.open_dictionary(src, { dir = TMP .. "/db" })
      local bad = 0
      for _, p in ipairs({ "あ", "か", "かん", "かんじ", "さ", "ん", "ア", "a", "1", "#" }) do
        for _, kind in ipairs(skk.KINDS) do
          local a, b = d:get_prefix(kind, p, 100), mem:get_prefix(kind, p, 100)
          if not vim.deep_equal(a, b) then
            bad = bad + 1
          end
        end
      end
      return bad
    ]],
      path
    ),
    0
  )
end

T["SKK-JISYO.L through Library"] = function()
  skip_if_missing()
  eq(
    run(
      [[
      config.set({
        globalDictionaries = { ... },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
      })
      local lib = dictionary.load()
      return { lib:get_henkan_result("okurinasi", "かんじ")[1], lib:get_henkan_result("okuriari", "わるs")[1] }
    ]],
      path
    ),
    { "漢字", "悪" }
  )
end

T["completion SKK-JISYO.L returns quickly"] = function()
  skip_if_missing()
  local r = run(
    [[
    config.set({
      globalDictionaries = { ... },
      userDictionary = TMP .. "/user",
      databasePath = TMP .. "/db",
    })
    local lib = dictionary.load()
    lib:get_completion_result("かん", "") -- 辞書を開く分の暖機
    local t = vim.uv.hrtime()
    local n = 20
    local a, b, c
    for _ = 1, n do
      a = lib:get_completion_result("か", "")
      b = lib:get_completion_result("かん", "")
      c = lib:get_completion_result("かん", "k")
    end
    return { (vim.uv.hrtime() - t) / 1e6 / n / 3, #a, #b, #c }
  ]],
    path
  )
  eq(r[2], 1)
  eq(r[3], 100)
  eq(r[4] > 0, true)
  eq(r[1] < 20, true) -- 1 回あたりの ms
end

return T

local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

-- 子の nvim でコードを動かす。共通の準備を前に付け、`...` に args が入る。return した値を返す
local PRE = ([[
local skk = require("skkeleton.dictionary.skk")
local db = require("skkeleton.dictionary.db")
local TD = %q
_G.TMP = _G.TMP or vim.fn.tempname()
vim.fn.mkdir(_G.TMP, "p")
local TMP = _G.TMP
local function write(name, s)
  local path = TMP .. "/" .. name
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
  return path
end
]]):format(helpers.testdata)

local function run(code, ...)
  return child.lua(PRE .. code, { ... })
end

T["skk.parse"] = MiniTest.new_set()

T["skk.parse"]["splits the okuri-ari and okuri-nasi sections"] = function()
  eq(
    run([[
      local m = skk.parse(table.concat({
        ";; -*- coding: utf-8 -*-",
        ";; okuri-ari entries.",
        "わるs /悪/",
        ";; okuri-nasi entries.",
        "あかね /茜/",
        "てすと /テスト/test/",
      }, "\n"))
      return m
    ]]),
    {
      okuriari = { ["わるs"] = "/悪/" },
      okurinasi = { ["あかね"] = "/茜/", ["てすと"] = "/テスト/test/" },
    }
  )
end

T["skk.parse"]["handles CRLF"] = function()
  eq(
    run([[
      local m = skk.parse(";; okuri-ari entries.\r\n;; okuri-nasi entries.\r\nあ /亜/\r\nい /伊/")
      return { m.okurinasi["あ"], m.okurinasi["い"], skk.split_candidates(m.okurinasi["あ"]) }
    ]]),
    { "/亜/", "/伊/", { "亜" } }
  )
end

T["skk.parse"]["uses the first one for the same reading"] = function()
  eq(
    run([[
      local m = skk.parse(";; okuri-nasi entries.\nあ /先/\nあ /後/\n")
      return m.okurinasi["あ"]
    ]]),
    "/先/"
  )
end

T["skk.parse"]["ignores comments and lines before the first marker"] = function()
  eq(
    run([[
      local m = skk.parse("あ /前/\n;; okuri-nasi entries.\n;; comment x\nい /伊/\n")
      return m
    ]]),
    { okuriari = {}, okurinasi = { ["い"] = "/伊/" } }
  )
end

T["encoding"] = MiniTest.new_set()

T["encoding"]["defaults to EUC-JP"] = function()
  eq(
    run([[
      local m = skk.load_memory(TD .. "/globalJisyo")
      return m:get_henkan_result("okurinasi", "てすと")
    ]]),
    { "テスト", "test" }
  )
end

T["encoding"]["follows the coding: comment"] = function()
  eq(
    run([[
      local utf8 = ";; -*- mode: fundamental; coding: utf-8 -*-\n;; okuri-nasi entries.\nあ /亜/\n"
      local euc = vim.iconv(";; -*- coding: euc-jp -*-\n;; okuri-nasi entries.\nあ /亜/\n", "utf-8", "euc-jp")
      return {
        skk.load_memory(write("a", utf8)):get_henkan_result("okurinasi", "あ"),
        skk.load_memory(write("b", euc)):get_henkan_result("okurinasi", "あ"),
      }
    ]]),
    { { "亜" }, { "亜" } }
  )
end

T["encoding"]["treats an untagged file that is clearly UTF-8 as UTF-8"] = function()
  eq(
    run([[
      return {
        skk.load_memory(TD .. "/globalJisyo2"):get_henkan_result("okurinasi", "てすと"),
        skk.detect_encoding(";; okuri-nasi entries.\nabc /def/\n"),
        skk.detect_encoding("\164\162 /\164\162/"),
      }
    ]]),
    { { "ﾃｽﾄ" }, "euc-jp", "euc-jp" }
  )
end

T["encoding"]["an explicit encoding wins"] = function()
  eq(
    run([[
      -- 先頭に coding: utf-8 とあっても、明示された EUC-JP を使う
      local euc = vim.iconv(";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n", "utf-8", "euc-jp")
      return skk.load_memory(write("a", euc), "euc-jp"):get_henkan_result("okurinasi", "あ")
    ]]),
    { "亜" }
  )
end

T["encoding"]["reports unsupported encodings"] = function()
  local ok = pcall(
    run,
    [[
      return skk.load_memory(write("a", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n"), "no-such-encoding")
    ]]
  )
  eq(ok, false)
end

T["memory dictionary"] = MiniTest.new_set()

T["memory dictionary"]["loads the JSON dictionary"] = function()
  eq(
    run([[
      local m = skk.load_memory(TD .. "/newJisyo.json")
      return {
        m:get_henkan_result("okuriari", "わるs"),
        m:get_henkan_result("okurinasi", "あかね"),
        m:get_henkan_result("okurinasi", "ない"),
        m:get_prefix("okurinasi", "あか"),
      }
    ]]),
    { { "悪" }, { "茜" }, {}, { { "あかね", { "茜" } } } }
  )
end

T["memory dictionary"]["rejects invalid JSON and unsupported formats"] = function()
  eq(
    run([[
      local out = {}
      out[1] = select(2, pcall(skk.load_memory, write("bad.json", '{"okuri_ari": {}}')))
      out[2] = select(2, pcall(skk.load_memory, TD .. "/newJisyo.yaml"))
      out[3] = select(2, pcall(skk.load_memory, TMP .. "/x.mpk"))
      return vim.tbl_map(function(s) return s:match("invalid JSON") or s:match("unsupported") end, out)
    ]]),
    { "invalid JSON", "unsupported", "unsupported" }
  )
end

T["db"] = MiniTest.new_set()

-- DB の結果がメモリ上のパース結果と一致することを、テストデータの全見出し語で確かめる
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
      for _ in pairs(mem.maps[kind]) do cnt = cnt + 1 end
      assert(#all == cnt, ("%s: %d ~= %d"):format(kind, #all, cnt))
    end
    assert(vim.deep_equal(d:get_henkan_result("okurinasi", "ありえない読み"), {}))
    d:close()
    return n
  end
]]

T["db"]["matches the memory dictionary for the test data"] = function()
  eq(
    run(COMPARE .. [[
      return {
        compare(TD .. "/globalJisyo", "euc-jp"),
        compare(TD .. "/globalJisyo2"),
        compare(TD .. "/numJisyo", "euc-jp"),
        compare(TD .. "/numIncludingJisyo", "utf-8"),
        compare(TD .. "/userJisyo", "utf-8"),
      }
    ]]),
    { 3, 2, 2, 2, 1 }
  )
end

T["db"]["looks up exact entries and prefixes"] = function()
  eq(
    run([[
      local src = write("d", table.concat({
        ";; coding: utf-8",
        ";; okuri-ari entries.",
        "わるs /悪/",
        "うごk /動/",
        ";; okuri-nasi entries.",
        "か /蚊/",
        "かん /缶/",
        "かんじ /漢字/幹事;manager/",
        "かんたん /簡単/",
        "き /木/",
      }, "\n") .. "\n")
      local d = db.open_dictionary(src, { dir = TMP .. "/db" })
      return {
        d:get_henkan_result("okuriari", "わるs"),
        d:get_henkan_result("okuriari", "か"),
        d:get_henkan_result("okurinasi", "かんじ"),
        d:get_henkan_result("okurinasi", "かん"),
        d:get_henkan_result("okurinasi", ""),
        d:get_henkan_result("okurinasi", "く"),
        vim.tbl_map(function(e) return e[1] end, d:get_prefix("okurinasi", "かん", 10)),
        vim.tbl_map(function(e) return e[1] end, d:get_prefix("okurinasi", "かん", 2)),
        d:get_prefix("okurinasi", "かんじ", 10),
        d:get_prefix("okurinasi", "ほ", 10),
        d:get_prefix("okuriari", "う", 10),
      }
    ]]),
    {
      { "悪" },
      {},
      { "漢字", "幹事;manager" },
      { "缶" },
      {},
      {},
      { "かん", "かんじ", "かんたん" },
      { "かん", "かんじ" },
      { { "かんじ", { "漢字", "幹事;manager" } } },
      {},
      { { "うごk", { "動" } } },
    }
  )
end

T["db"]["handles an empty dictionary"] = function()
  eq(
    run([[
      local src = write("e", ";; coding: utf-8\n;; okuri-ari entries.\n;; okuri-nasi entries.\n")
      local d = db.open_dictionary(src, { dir = TMP .. "/db" })
      return { d:get_henkan_result("okurinasi", "あ"), d:get_prefix("okuriari", "", 5) }
    ]]),
    { {}, {} }
  )
end

T["db"]["writes the header and a sorted index"] = function()
  eq(
    run([[
      local src = write("h", ";; coding: utf-8\n;; okuri-ari entries.\nあs /亜/\n;; okuri-nasi entries.\nい /伊/\nあ /阿/\n")
      local dst = db.ensure(src, { dir = TMP .. "/db" })
      local f = assert(io.open(dst, "rb"))
      local head = f:read(db.HEADER_SIZE)
      local st = vim.uv.fs_stat(src)
      f:close()
      return {
        head:sub(1, 8),
        #head,
        db.parse_header(head).nari,
        db.parse_header(head).nnasi,
        db.parse_header(head).src_size == st.size,
        dst:match("/(%x+)%.db$"):len(),
      }
    ]]),
    { "SKKDB 1 ", 128, 1, 2, true, 16 }
  )
end

T["db"]["rebuilds when the source changes"] = function()
  eq(
    run([[
      local src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n")
      local opts = { dir = TMP .. "/db" }
      local dst = db.ensure(src, opts)
      local fresh1 = db.is_fresh(vim.fs.normalize(src), dst)
      local d1 = db.open_dictionary(src, opts)
      src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/阿/\nい /伊/\n")
      local fresh2 = db.is_fresh(vim.fs.normalize(src), dst)
      local d2 = db.open_dictionary(src, opts)
      return {
        fresh1, fresh2,
        d1:get_henkan_result("okurinasi", "あ"),
        d2:get_henkan_result("okurinasi", "あ"),
        d2:get_henkan_result("okurinasi", "い"),
      }
    ]]),
    { true, false, { "亜" }, { "亜", "阿" }, { "伊" } }
  )
end

T["db"]["does not rebuild a fresh DB, and force rebuilds it"] = function()
  eq(
    run([[
      local src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n")
      local opts = { dir = TMP .. "/db" }
      local dst = db.ensure(src, opts)
      local t1 = vim.uv.fs_stat(dst).ino
      db.ensure(src, opts)
      local t2 = vim.uv.fs_stat(dst).ino
      db.ensure(src, { dir = opts.dir, force = true })
      local t3 = vim.uv.fs_stat(dst).ino
      return { t1 == t2, t1 ~= t3 }
    ]]),
    { true, true }
  )
end

T["db"]["rebuilds a truncated DB"] = function()
  eq(
    run([[
      local src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\nい /伊/\n")
      local opts = { dir = TMP .. "/db" }
      local dst = db.ensure(src, opts)
      local f = assert(io.open(dst, "rb")); local all = f:read("*a"); f:close()
      f = assert(io.open(dst, "wb")); f:write(all:sub(1, #all - 3)); f:close()
      local stale = not db.is_fresh(vim.fs.normalize(src), dst)
      local d = db.open_dictionary(src, opts)
      return { stale, d:get_henkan_result("okurinasi", "い") }
    ]]),
    { true, { "伊" } }
  )
end

T["db"]["uses separate DBs for different encodings of the same file"] = function()
  eq(
    run([[
      local src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n")
      local a = db.path_for(src, TMP, "utf-8")
      local b = db.path_for(src, TMP, "euc-jp")
      local c = db.path_for(src, TMP)
      return { a ~= b, a ~= c, c == db.path_for(src, TMP, "") }
    ]]),
    { true, true, true }
  )
end

T["db"]["leaves no .tmp files, and concurrent writers use different names"] = function()
  eq(
    run([[
      local src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n")
      local dir = TMP .. "/db"
      -- 作っている最中に別の作成が割り込む状況を、同じ DB への 2 回の build で再現する
      local dst = db.path_for(vim.fs.normalize(src), dir)
      db.build(src, dst)
      db.build(src, dst)
      local names = {}
      for name in vim.fs.dir(dir) do names[#names + 1] = name:match("%.tmp$") and "tmp" or "db" end
      -- 他のプロセスの .tmp が残っていても影響されない
      write("db/" .. vim.fs.basename(dst) .. ".99999.1.tmp", "garbage")
      local d = db.open(dst)
      return { names, d:get_henkan_result("okurinasi", "あ") }
    ]]),
    { { "db" }, { "亜" } }
  )
end

T["db"]["cache_dir"] = function()
  eq(
    run([[
      local dir = TMP .. "/cachedir"
      vim.fn.mkdir(dir, "p")
      local file = TMP .. "/old/skk.db"
      return {
        db.cache_dir(dir) == dir,
        db.cache_dir(file) == TMP .. "/old",
        db.cache_dir(TMP .. "/not/yet") == TMP .. "/not/yet",
        db.cache_dir(TMP .. "/not/yet/") == TMP .. "/not/yet",
        db.cache_dir(nil) == vim.fs.joinpath(vim.fn.stdpath("cache"), "skkeleton"),
        db.cache_dir("") == vim.fs.joinpath(vim.fn.stdpath("cache"), "skkeleton"),
      }
    ]]),
    { true, true, true, true, true, true }
  )
end

T["db"]["reports a missing source"] = function()
  local ok, err = pcall(run, [[ db.ensure(TMP .. "/nothing", { dir = TMP .. "/db" }) ]])
  eq(ok, false)
  eq(tostring(err):find("cannot open", 1, true) ~= nil, true)
end

T["db"]["ensure_async builds without blocking, and shares an in-flight build"] = function()
  eq(
    run([[
      local src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\nい /伊/\n")
      local opts = { dir = TMP .. "/db" }
      local results = {}
      db.ensure_async(src, opts, function(dst, err) results[#results + 1] = { dst, err } end)
      db.ensure_async(src, opts, function(dst, err) results[#results + 1] = { dst, err } end)
      local sync_done = #results > 0
      vim.wait(5000, function() return #results == 2 end)
      local d = db.open(results[1][1])
      return {
        sync_done, #results, results[1][1] == results[2][1], results[1][2],
        d:get_henkan_result("okurinasi", "い"),
        -- 新しくなったあとは、すぐ呼ばれる
        (function() local called; db.ensure_async(src, opts, function() called = true end); return called end)(),
      }
    ]]),
    { false, 2, true, vim.NIL, { "伊" }, true }
  )
end

T["db"]["ensure_async reports an error"] = function()
  eq(
    run([[
      local res
      db.ensure_async(TMP .. "/nothing", { dir = TMP .. "/db" }, function(dst, err) res = { dst, err } end)
      vim.wait(5000, function() return res ~= nil end)
      return { res[1], res[2]:find("cannot open", 1, true) ~= nil }
    ]]),
    { vim.NIL, true }
  )
end

T["db"]["matches the memory dictionary for SKK-JISYO.L"] = function()
  local path = "/usr/share/skk/SKK-JISYO.L"
  if vim.uv.fs_stat(path) == nil then
    MiniTest.skip(path .. " is not installed")
  end
  local n = run(COMPARE .. [[ return compare(...) ]], path)
  eq(n > 100000, true)
end

T["db"]["prefix search matches a scan of the memory dictionary for SKK-JISYO.L"] = function()
  local path = "/usr/share/skk/SKK-JISYO.L"
  if vim.uv.fs_stat(path) == nil then
    MiniTest.skip(path .. " is not installed")
  end
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
          if not vim.deep_equal(a, b) then bad = bad + 1 end
        end
      end
      return bad
    ]],
      path
    ),
    0
  )
end

return T

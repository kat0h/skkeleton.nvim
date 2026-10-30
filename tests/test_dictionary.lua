-- upstream の dictionary_test.ts の移植と、Library / load(cfg) のテスト
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local PRE = ([[
local dictionary = require("skkeleton.dictionary")
local Library = dictionary.Library
local User = require("skkeleton.dictionary.user")
local numeral = require("skkeleton.dictionary.numeral")
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
local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
-- 同じ辞書をメモリと DB の両方で開く（upstream の test() が SkkDictionary と DenoKvDictionary で回すのに当たる）
local function backends(path, enc)
  return {
    memory = skk.load_memory(path, enc),
    db = db.open_dictionary(path, { encoding = enc, dir = TMP .. "/db" }),
  }
end
]]):format(helpers.testdata)

local function run(code, ...)
  return child.lua(PRE .. code, { ... })
end

local function for_each_backend(path, enc, body, expected)
  for _, name in ipairs({ "memory", "db" }) do
    local got = run(
      ([[
        local d = backends(%q, %s)[%q]
        %s
      ]]):format(path, enc and ("%q"):format(enc) or "nil", name, body)
    )
    eq({ name, got }, { name, expected })
  end
end

local TD = helpers.testdata

T["load new JisyoJson"] = function()
  local m = run([[
    local lib = Library.new({ skk.load_memory(TD .. "/newJisyo.json") }, User.new())
    return { lib:get_henkan_result("okuriari", "わるs"), lib:get_henkan_result("okurinasi", "あかね") }
  ]])
  eq(m, { { "悪" }, { "茜" } })
end

T["load new JisyoYaml is not supported"] = function()
  local msg = run([[ return select(2, pcall(skk.load_memory, TD .. "/newJisyo.yaml")) ]])
  eq(msg:find("unsupported", 1, true) ~= nil, true)
end

T["get candidates"] = function()
  for_each_backend(
    TD .. "/globalJisyo",
    "euc-jp",
    [[
      local lib = Library.new({ d }, User.new())
      return { lib:get_henkan_result("okuriari", "てすt"), lib:get_henkan_result("okurinasi", "てすと") }
    ]],
    { { "テスト" }, { "テスト", "test" } }
  )
end

T["get num candidates"] = function()
  for_each_backend(
    TD .. "/numJisyo",
    "euc-jp",
    [[
      local lib = Library.new({ numeral.wrap(d) }, User.new())
      return lib:get_henkan_result("okurinasi", "101ばん")
    ]],
    { "101番", "１０１番", "一〇一番", "百一番", "CI番", "佰壱番" }
  )
end

T["get num candidates (Kifu)"] = function()
  for_each_backend(
    TD .. "/numJisyo",
    "euc-jp",
    [[
      local lib = Library.new({ numeral.wrap(d) }, User.new())
      return { lib:get_henkan_result("okurinasi", "11おうて"), lib:get_henkan_result("okurinasi", "111おうて") }
    ]],
    { { "１一王手" }, { "111王手" } }
  )
end

T["get candidates from words that include numbers"] = function()
  for_each_backend(
    TD .. "/numIncludingJisyo",
    "utf-8",
    [[
      local lib = Library.new({ numeral.wrap(d) }, User.new())
      return { lib:get_henkan_result("okurinasi", "cat2"), lib:get_henkan_result("okurinasi", "1000001") }
    ]],
    { { "🐈" }, { "東京都千代田区千代田" } }
  )
end

T["user dictionary converts numbers too"] = function()
  eq(
    run([[
      local user = User.new()
      user:register_henkan_result("okurinasi", "#ばん", "#3番")
      local lib = Library.new({}, user)
      return lib:get_henkan_result("okurinasi", "12ばん")
    ]]),
    { "十二番" }
  )
end

T["register candidate"] = function()
  eq(
    run([[
      local lib = Library.new({}, User.new())
      -- most recently registered
      lib:register_henkan_result("okurinasi", "test", "a")
      lib:register_henkan_result("okurinasi", "test", "b")
      local first = lib:get_henkan_result("okurinasi", "test")
      -- and remove duplicate
      lib:register_henkan_result("okurinasi", "test", "a")
      return { first, lib:get_henkan_result("okurinasi", "test") }
    ]]),
    { { "b", "a" }, { "a", "b" } }
  )
end

T["global/local jisyo interop"] = function()
  for_each_backend(
    TD .. "/globalJisyo",
    "euc-jp",
    [[
      local lib = Library.new({ d }, User.new())
      lib:register_henkan_result("okurinasi", "てすと", "test")
      -- remove dup
      local nasi = lib:get_henkan_result("okurinasi", "てすと")
      -- new candidate
      -- user candidates priority is higher than global
      lib:register_henkan_result("okurinasi", "てすと", "てすと")
      return { nasi, lib:get_henkan_result("okurinasi", "てすと") }
    ]],
    { { "test", "テスト" }, { "てすと", "test", "テスト" } }
  )
end

T["purge candidate"] = function()
  eq(
    run([[
      local lib = Library.new({ skk.load_memory(TD .. "/globalJisyo", "euc-jp") }, User.new())
      lib:register_henkan_result("okurinasi", "あ", "亜")
      lib:register_henkan_result("okurinasi", "あ", "阿")
      lib:purge_candidate("okurinasi", "あ", "亜")
      return lib:get_henkan_result("okurinasi", "あ")
    ]]),
    { "阿", "a" }
  )
end

T["works without a user dictionary"] = function()
  eq(
    run([[
      local lib = Library.new({ skk.load_memory(TD .. "/globalJisyo", "euc-jp") })
      lib:register_henkan_result("okurinasi", "あ", "亜")
      lib:purge_candidate("okurinasi", "あ", "a")
      lib:load()
      lib:save()
      return lib:get_henkan_result("okurinasi", "あ")
    ]]),
    { "a" }
  )
end

T["merges dictionaries in order without duplicates"] = function()
  eq(
    run([[
      local a = skk.Memory.new({ okurinasi = { ["あ"] = { "1", "2" } } })
      local b = skk.Memory.new({ okurinasi = { ["あ"] = { "2", "3" } } })
      local lib = Library.new({ a, b }, User.new())
      return lib:get_henkan_result("okurinasi", "あ")
    ]]),
    { "1", "2", "3" }
  )
end

T["immediatelyDictionaryRW saves after register/purge and loads before lookup"] = function()
  eq(
    run([[
      local path = TMP .. "/user"
      local user = User.new()
      user:load({ path = path })
      local lib = Library.new({}, user, { immediatelyDictionaryRW = true })
      lib:register_henkan_result("okurinasi", "あ", "亜")
      lib:register_henkan_result("okurinasi", "あ", "阿")
      local saved = read(path)
      lib:purge_candidate("okurinasi", "あ", "亜")
      local purged = read(path)
      -- 別の Neovim が書き換えた内容を、検索の前に読む
      vim.uv.sleep(20)
      write("user", ";; okuri-nasi entries.\nあ /別/\n")
      return { saved, purged, lib:get_henkan_result("okurinasi", "あ") }
    ]]),
    {
      ";; okuri-ari entries.\n;; okuri-nasi entries.\nあ /阿/亜/\n",
      ";; okuri-ari entries.\n;; okuri-nasi entries.\nあ /阿/\n",
      { "別" },
    }
  )
end

T["without immediatelyDictionaryRW nothing is written until save"] = function()
  eq(
    run([[
      local path = TMP .. "/user"
      local user = User.new()
      user:load({ path = path })
      local lib = Library.new({}, user, { immediatelyDictionaryRW = false })
      lib:register_henkan_result("okurinasi", "あ", "亜")
      local before = vim.uv.fs_stat(path) ~= nil
      lib:save()
      return { before, read(path) }
    ]]),
    { false, ";; okuri-ari entries.\n;; okuri-nasi entries.\nあ /亜/\n" }
  )
end

T["load(cfg)"] = MiniTest.new_set()

T["load(cfg)"]["builds a Library from the config"] = function()
  eq(
    run([[
      local lib = dictionary.load({
        globalDictionaries = {
          { TD .. "/globalJisyo", "euc-jp" },
          { path = TD .. "/numJisyo", encoding = "euc-jp" },
          TD .. "/globalJisyo2",
          TD .. "/newJisyo.json",
        },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
        immediatelyDictionaryRW = false,
        sources = { "skk_dictionary" },
      })
      lib:register_henkan_result("okurinasi", "てすと", "test")
      local files = {}
      for name in vim.fs.dir(TMP .. "/db") do files[#files + 1] = name:match("%.db$") and "db" or name end
      return {
        lib:get_henkan_result("okurinasi", "てすと"),
        lib:get_henkan_result("okurinasi", "5ばん"),
        lib:get_henkan_result("okuriari", "わるs"),
        files,
      }
    ]]),
    { { "test", "テスト", "ﾃｽﾄ" }, { "5番", "５番", "五番", "V番", "伍番" }, { "悪" }, { "db", "db", "db" } }
  )
end

T["load(cfg)"]["accepts deno_kv for compatibility and does not load twice"] = function()
  eq(
    run([[
      local lib = dictionary.load({
        globalDictionaries = { { TD .. "/globalJisyo", "euc-jp" } },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
        sources = { "deno_kv", "skk_dictionary" },
      })
      return { #lib.dicts, lib:get_henkan_result("okurinasi", "てすと") }
    ]]),
    { 2, { "テスト", "test" } }
  )
end

T["load(cfg)"]["warns about unknown sources and skips them"] = function()
  eq(
    run([[
      local msgs = {}
      vim.notify = function(m) msgs[#msgs + 1] = m end
      local lib = dictionary.load({
        globalDictionaries = { { TD .. "/globalJisyo", "euc-jp" } },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
        sources = { "skk_server", "skk_dictionary" },
      })
      return { #msgs, msgs[1]:find("skk_server", 1, true) ~= nil, lib:get_henkan_result("okurinasi", "てすと") }
    ]]),
    { 1, true, { "テスト", "test" } }
  )
end

T["load(cfg)"]["warns about a dictionary that cannot be loaded and keeps the others"] = function()
  eq(
    run([[
      local msgs = {}
      vim.notify = function(m) msgs[#msgs + 1] = m end
      local lib = dictionary.load({
        globalDictionaries = { TMP .. "/missing", TD .. "/newJisyo.yaml", { TD .. "/globalJisyo", "euc-jp" } },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
      })
      return {
        #msgs,
        msgs[1]:find("missing", 1, true) ~= nil,
        msgs[2]:find("newJisyo.yaml", 1, true) ~= nil,
        lib:get_henkan_result("okurinasi", "てすと"),
      }
    ]]),
    { 2, true, true, { "テスト", "test" } }
  )
end

T["load(cfg)"]["databasePath may be the old file path (its parent is used)"] = function()
  eq(
    run([[
      local lib = dictionary.load({
        globalDictionaries = { { TD .. "/globalJisyo", "euc-jp" } },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/dbdir/skk.db",
      })
      local n = 0
      for name in vim.fs.dir(TMP .. "/dbdir") do n = n + (name:match("%.db$") and 1 or 0) end
      return { n, vim.uv.fs_stat(TMP .. "/dbdir/skk.db") == nil or vim.uv.fs_stat(TMP .. "/dbdir/skk.db").type }
    ]]),
    { 1, true }
  )
end

T["load(cfg)"]["falls back to memory when the DB cannot be written"] = function()
  eq(
    run([[
      -- databasePath の親がファイルなので、ディレクトリを作れない
      write("blocker", "x")
      local lib = dictionary.load({
        globalDictionaries = { { TD .. "/globalJisyo", "euc-jp" } },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/blocker/db/x",
      })
      return lib:get_henkan_result("okurinasi", "てすと")
    ]]),
    { "テスト", "test" }
  )
end

T["load(cfg)"]["expands ~ in paths"] = function()
  eq(
    run([[
      vim.env.HOME = TMP
      write("g", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n")
      local lib = dictionary.load({
        globalDictionaries = { { "~/g", "utf-8" } },
        userDictionary = "~/user",
        databasePath = "~/db",
      })
      lib:register_henkan_result("okurinasi", "い", "伊")
      lib:save()
      return { lib:get_henkan_result("okurinasi", "あ"), vim.uv.fs_stat(TMP .. "/user") ~= nil }
    ]]),
    { { "亜" }, true }
  )
end

T["prepare"] = function()
  eq(
    run([[
      local cfg = {
        globalDictionaries = { { TD .. "/globalJisyo", "euc-jp" }, { TD .. "/numIncludingJisyo", "utf-8" }, TD .. "/newJisyo.json" },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
      }
      local lib
      dictionary.prepare(cfg, function(l) lib = l end)
      local sync = lib ~= nil
      vim.wait(5000, function() return lib ~= nil end)
      local n = 0
      for name in vim.fs.dir(TMP .. "/db") do n = n + (name:match("%.db$") and 1 or 0) end
      return { sync, n, lib:get_henkan_result("okurinasi", "てすと"), lib:get_henkan_result("okurinasi", "cat2"), lib:get_henkan_result("okurinasi", "あかね") }
    ]]),
    { false, 2, { "テスト", "test" }, { "🐈" }, { "茜" } }
  )
end


T["update_database"] = function()
  eq(
    run([[
      local cfg = { databasePath = TMP .. "/db" }
      local src = write("s", ";; coding: utf-8\n;; okuri-nasi entries.\nあ /亜/\n")
      dictionary.update_database(cfg, src, "utf-8")
      local dst = db.path_for(src, TMP .. "/db", "utf-8")
      local ino1 = vim.uv.fs_stat(dst).ino
      dictionary.update_database(cfg, src, "utf-8")
      local ino2 = vim.uv.fs_stat(dst).ino
      dictionary.update_database(cfg, src, "utf-8", true)
      local ino3 = vim.uv.fs_stat(dst).ino
      return { ino1 == ino2, ino1 ~= ino3 }
    ]]),
    { true, true }
  )
end

T["SKK-JISYO.L through Library"] = function()
  local path = "/usr/share/skk/SKK-JISYO.L"
  if vim.uv.fs_stat(path) == nil then
    MiniTest.skip(path .. " is not installed")
  end
  eq(
    run(
      [[
      local lib = dictionary.load({
        globalDictionaries = { ... },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
      })
      return { lib:get_henkan_result("okurinasi", "かんじ")[1], lib:get_henkan_result("okuriari", "わるs")[1] }
    ]],
      path
    ),
    { "漢字", "悪" }
  )
end

return T

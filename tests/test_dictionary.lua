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
    local got = run(([[
        local d = backends(%q, %s)[%q]
        %s
      ]]):format(path, enc and ("%q"):format(enc) or "nil", name, body))
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
    {
      { "test", "テスト", "ﾃｽﾄ" },
      { "5番", "５番", "五番", "V番", "伍番" },
      { "悪" },
      { "db", "db", "db" },
    }
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
        globalDictionaries = {
          { TD .. "/globalJisyo", "euc-jp" },
          { TD .. "/numIncludingJisyo", "utf-8" },
          TD .. "/newJisyo.json",
        },
        userDictionary = TMP .. "/user",
        databasePath = TMP .. "/db",
      }
      local lib
      dictionary.prepare(cfg, function(l) lib = l end)
      local sync = lib ~= nil
      vim.wait(5000, function() return lib ~= nil end)
      local n = 0
      for name in vim.fs.dir(TMP .. "/db") do n = n + (name:match("%.db$") and 1 or 0) end
      local function get(w) return lib:get_henkan_result("okurinasi", w) end
      return { sync, n, get("てすと"), get("cat2"), get("あかね") }
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

-- 補完（Library:get_completion_result）。upstream には専用のテストが無いので、仕様を表にして書く
-- 1 文字は完全一致だけ（feed は見ない）、2 文字以上は前方一致
local COMPLETION_DICT = table.concat({
  ";; -*- coding: utf-8 -*-",
  ";; okuri-ari entries.",
  "かえr /帰/",
  ";; okuri-nasi entries.",
  "か /蚊/可/",
  "かん /缶/感/",
  "かんじ /漢字/幹事/",
  "かんたん /簡単/",
  "かんき /換気/寒気/",
  "かんな /鉋/",
  "くう /食う/",
  "ほげ /補外/",
}, "\n") .. "\n"

local COMPLETION_PRE = [[
  local path = write("completion-dict", ]] .. ("%q"):format(COMPLETION_DICT) .. [[)
  local user = User.new()
  user:register_henkan_result("okurinasi", "かんぱい", "乾杯")
  user:register_henkan_result("okurinasi", "かんじ", "感じ")
]]

T["completion"] = MiniTest.new_set()

T["completion"]["a single character returns the exact okurinasi entry only"] = function()
  for _, name in ipairs({ "memory", "db" }) do
    eq(
      run(COMPLETION_PRE .. ([[
        local lib = Library.new({ backends(path, "utf-8")[%q] }, user)
        return lib:get_completion_result("か", "")
      ]]):format(name)),
      { { "か", { "蚊", "可" } } }
    )
  end
end

T["completion"]["a single character with non-empty feed matches by expanded prefixes"] = function()
  for _, name in ipairs({ "memory", "db" }) do
    eq(
      run(COMPLETION_PRE .. ([[
        local lib = Library.new({ backends(path, "utf-8")[%q] }, user)
        -- か + "n" の続き: かんじ、かんぱい、かん、...
        return lib:get_completion_result("か", "n")
      ]]):format(name)),
      {
        { "かんじ", { "感じ", "漢字", "幹事" } },
        { "かんぱい", { "乾杯" } },
        { "かん", { "缶", "感" } },
        { "かんき", { "換気", "寒気" } },
        { "かんたん", { "簡単" } },
        { "かんな", { "鉋" } },
      }
    )
  end
end

T["completion"]["two or more characters match by prefix, user dictionary first, without duplicates"] = function()
  for _, name in ipairs({ "memory", "db" }) do
    eq(
      run(COMPLETION_PRE .. ([[
        local lib = Library.new({ backends(path, "utf-8")[%q] }, user)
        return lib:get_completion_result("かん", "")
      ]]):format(name)),
      {
        { "かんじ", { "感じ", "漢字", "幹事" } },
        { "かんぱい", { "乾杯" } },
        { "かん", { "缶", "感" } },
        { "かんき", { "換気", "寒気" } },
        { "かんたん", { "簡単" } },
        { "かんな", { "鉋" } },
      }
    )
  end
end

T["completion"]["an empty prefix returns nothing"] = function()
  eq(
    run(COMPLETION_PRE .. [[
    local lib = Library.new({ skk.load_memory(path, "utf-8") }, user)
    return lib:get_completion_result("", "")
  ]]),
    {}
  )
end

T["completion"]["feed adds the kana of the table keys that start with it"] = function()
  for _, name in ipairs({ "memory", "db" }) do
    eq(
      run(COMPLETION_PRE .. ([[
        local lib = Library.new({ backends(path, "utf-8")[%q] }, user)
        -- かな + "k" の続き: かんか、かんき、かんく、...
        return lib:get_completion_result("かん", "k")
      ]]):format(name)),
      { { "かんき", { "換気", "寒気" } } }
    )
    eq(
      run(COMPLETION_PRE .. ([[
        local lib = Library.new({ backends(path, "utf-8")[%q] }, user)
        -- "n" は な行（かんな）と、"nn" の「ん」（かんん、は無い）
        return lib:get_completion_result("かん", "n")
      ]]):format(name)),
      { { "かんな", { "鉋" } } }
    )
  end
end

T["completion"]["a feed that no key starts with returns nothing"] = function()
  eq(
    run(COMPLETION_PRE .. [[
    local lib = Library.new({ skk.load_memory(path, "utf-8") }, user)
    return lib:get_completion_result("かん", "q")
  ]]),
    {}
  )
end

T["completion"]["the number of readings is limited"] = function()
  eq(
    run(COMPLETION_PRE .. [[
      local lib = Library.new({ skk.load_memory(path, "utf-8") }, user)
      local r = lib:get_completion_result("かん", "", 2)
      return { #r, r[1][1], r[2][1] }
    ]]),
    { 2, "かんじ", "かんぱい" }
  )
end

T["completion"]["SKK-JISYO.L returns quickly"] = function()
  local path = "/usr/share/skk/SKK-JISYO.L"
  if vim.uv.fs_stat(path) == nil then
    MiniTest.skip(path .. " is not installed")
  end
  local r = run(
    [[
    local lib = dictionary.load({
      globalDictionaries = { ... },
      userDictionary = TMP .. "/user",
      databasePath = TMP .. "/db",
    })
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

T["skk.split_candidates"] = MiniTest.new_set()

T["skk.split_candidates"]["splits normal candidates"] = function()
  eq(run([[return skk.split_candidates("/a/b/c/")]], {}), { "a", "b", "c" })
end

T["skk.split_candidates"]["preserves okuri-ari blocks with inner slashes"] = function()
  eq(run([[return skk.split_candidates("/a/[b/c]/d/")]], {}), { "a", "[b/c]", "d" })
end

T["skk.split_candidates"]["ignores trailing empty or whitespace tokens"] = function()
  eq(run([[return skk.split_candidates("/a/b/   ")]], {}), { "a", "b" })
  eq(run([[return skk.split_candidates("/a/b/\n")]], {}), { "a", "b" })
  eq(run([[return skk.split_candidates("/a/b/")]], {}), { "a", "b" })
end

T["skk.split_candidates"]["decodes concat expressions with octal and character escapes"] = function()
  eq(
    run([=[
      return {
        skk.split_candidates([[/(concat "and\057or")/]]),
        skk.split_candidates([[/(concat "DOS\057V")/]]),
        skk.split_candidates([[/(concat "and\057or");annotation/]]),
        skk.split_candidates([[/(concat "a\057b");(concat "c\057d")/]]),
        skk.split_candidates([[/(concat "foo" "bar")/]]),
        skk.split_candidates([[/(concat "a\"b\\c")/]]),
        skk.split_candidates([[/(concat "semi\073colon")/]]),
        skk.split_candidates([[/ao/(concat "and\057or")/]]),
        skk.split_candidates([[/GNU General Public License;(concat "http:\057\057www.gnu.org\057licenses\057gpl.ja.html")/]]),
      }
    ]=]),
    {
      { "and/or" },
      { "DOS/V" },
      { "and/or;annotation" },
      { "a/b;c/d" },
      { "foobar" },
      { 'a"b\\c' },
      { "semi;colon" },
      { "ao", "and/or" },
      { "GNU General Public License;http://www.gnu.org/licenses/gpl.ja.html" },
    }
  )
end

T["skk.parse trims trailing whitespace on candidate lines"] = function()
  local maps = run([[
    local text = table.concat({
      ";; okuri-nasi entries.",
      "hoge /ほげ/  \t ",
      "fuga /ふが/",
    }, "\n")
    return skk.parse(text)
  ]])
  eq(maps.okurinasi["hoge"], "/ほげ/")
  eq(maps.okurinasi["fuga"], "/ふが/")
end

T["skk.load_json allows okuri_ari or okuri_nasi to be omitted"] = function()
  local r = run([[
    local p1 = write("only-nasi.json", vim.json.encode({ okuri_nasi = { hoge = { "ホゲ" } } }))
    local d1 = skk.load_json(p1)
    local p2 = write("only-ari.json", vim.json.encode({ okuri_ari = { ["かe"] = { "帰" } } }))
    local d2 = skk.load_json(p2)
    return {
      d1:get_henkan_result("okurinasi", "hoge"),
      d1:get_henkan_result("okuriari", "かe"),
      d2:get_henkan_result("okuriari", "かe"),
      d2:get_henkan_result("okurinasi", "hoge"),
    }
  ]])
  eq(r, { { "ホゲ" }, {}, { "帰" }, {} })

  local err1 = run([[
    local p = write("empty.json", vim.json.encode({ other = {} }))
    local ok, e = pcall(skk.load_json, p)
    return ok
  ]])
  eq(err1, false)

  local err2 = run([[
    local p = write("bad-type.json", vim.json.encode({ okuri_nasi = 123 }))
    local ok, e = pcall(skk.load_json, p)
    return ok
  ]])
  eq(err2, false)
end

T["skk.detect_encoding recognizes euc-jp-1990 and euc-japan and searches 4096 bytes"] = function()
  local r = run([[
    local e1 = skk.detect_encoding("", "euc-jp-1990")
    local e2 = skk.detect_encoding("", "euc-japan")
    local long_comment = (";; comment\n"):rep(100) .. ";; -*- mode: fundamental; coding: euc-japan -*-\n"
    local e3 = skk.detect_encoding(long_comment)
    return { e1, e2, e3 }
  ]])
  eq(r, { "euc-jp", "euc-jp", "euc-jp" })
end

T["store.set_library closes the previous library"] = function()
  local closed = false
  local prev = {
    close = function()
      closed = true
    end,
  }
  local next_lib = {}
  local store = require("skkeleton.store")
  store.set_library(prev)
  store.set_library(next_lib)
  eq(closed, true)
  store.set_library(nil)
end

return T

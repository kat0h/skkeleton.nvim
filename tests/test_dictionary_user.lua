local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local PRE = [[
local User = require("skkeleton.dictionary.user")
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
]]

local function run(code, ...)
  return child.lua(PRE .. code, { ... })
end

T["registers the most recent candidate first and removes duplicates"] = function()
  eq(
    run([[
      local u = User.new()
      u:register_henkan_result("okurinasi", "test", "a")
      u:register_henkan_result("okurinasi", "test", "b")
      local first = u:get_henkan_result("okurinasi", "test")
      u:register_henkan_result("okurinasi", "test", "a")
      return { first, u:get_henkan_result("okurinasi", "test") }
    ]]),
    { { "b", "a" }, { "a", "b" } }
  )
end

T["does not register an empty candidate"] = function()
  eq(
    run([[
      local u = User.new()
      u:register_henkan_result("okurinasi", "ほげ", "")
      u:register_henkan_result("okuriari", "ほげ", "")
      return { u:get_henkan_result("okurinasi", "ほげ"), u:get_henkan_result("okuriari", "ほげ") }
    ]]),
    { {}, {} }
  )
end

T["purges a candidate, and the entry when it becomes empty"] = function()
  eq(
    run([[
      local u = User.new()
      u:register_henkan_result("okurinasi", "あ", "亜")
      u:register_henkan_result("okurinasi", "あ", "阿")
      u:purge_candidate("okurinasi", "あ", "阿")
      local a = u:get_henkan_result("okurinasi", "あ")
      u:purge_candidate("okurinasi", "あ", "亜")
      u:purge_candidate("okurinasi", "ない", "x")
      return { a, u:get_henkan_result("okurinasi", "あ"), next(u.maps.okurinasi) == nil }
    ]]),
    { { "亜" }, {}, true }
  )
end

T["reads and writes an SKK dictionary"] = function()
  -- upstream の "read/write skk jisyo"
  eq(
    run([[
      local path = write("u", "\n;; okuri-ari entries.\n;; okuri-nasi entries.\nあ /あ/\n      ")
      local u = User.new()
      u:load({ path = path })
      local before = u:get_henkan_result("okurinasi", "あ")
      u:register_henkan_result("okurinasi", "あ", "亜")
      u:save()
      local line
      for l in read(path):gmatch("[^\n]+") do
        if vim.startswith(l, "あ") then line = l end
      end
      return { before, line }
    ]]),
    { { "あ" }, "あ /亜/あ/" }
  )
end

T["writes okuri-ari in reverse order and okuri-nasi in order"] = function()
  eq(
    run([[
      local path = TMP .. "/w"
      local u = User.new()
      u:load({ path = path })
      for _, w in ipairs({ "いs", "うs", "あs" }) do u:register_henkan_result("okuriari", w, "x") end
      for _, w in ipairs({ "う", "あ", "い" }) do u:register_henkan_result("okurinasi", w, "y") end
      u:save()
      return read(path)
    ]]),
    ";; okuri-ari entries.\nうs /x/\nいs /x/\nあs /x/\n;; okuri-nasi entries.\nあ /y/\nい /y/\nう /y/\n"
  )
end

T["round trips what it wrote"] = function()
  eq(
    run([[
      local path = TMP .. "/rt"
      local u = User.new()
      u:load({ path = path })
      u:register_henkan_result("okuriari", "わるs", "悪")
      u:register_henkan_result("okurinasi", "かんじ", "漢字;注釈")
      u:register_henkan_result("okurinasi", "かんじ", "感じ")
      u:save()
      local v = User.new()
      v:load({ path = path })
      return { v:get_henkan_result("okuriari", "わるs"), v:get_henkan_result("okurinasi", "かんじ") }
    ]]),
    { { "悪" }, { "感じ", "漢字;注釈" } }
  )
end

T["excludes candidates starting with [ but keeps them in the file"] = function()
  eq(
    run([[
      local path = write("b", ";; okuri-ari entries.\nおくr /送/[り/送]/贈/\n;; okuri-nasi entries.\nあ /[x]/亜/\n")
      local u = User.new()
      u:load({ path = path })
      local before = u:get_henkan_result("okuriari", "おくr")
      local raw = u.maps.okuriari["おくr"]
      u:save()
      return { before, raw, u:get_henkan_result("okurinasi", "あ"), read(path) }
    ]]),
    {
      { "送", "贈" },
      { "送", "[り/送]", "贈" },
      { "亜" },
      ";; okuri-ari entries.\nおくr /送/[り/送]/贈/\n;; okuri-nasi entries.\nあ /[x]/亜/\n",
    }
  )
end

T["handles CRLF files"] = function()
  eq(
    run([[
      local path = write("c", ";; okuri-ari entries.\r\n;; okuri-nasi entries.\r\nあ /亜/阿/\r\n")
      local u = User.new()
      u:load({ path = path })
      return u:get_henkan_result("okurinasi", "あ")
    ]]),
    { "亜", "阿" }
  )
end

T["reloads only when the mtime changes"] = function()
  eq(
    run([[
      local path = write("m", ";; okuri-nasi entries.\nあ /亜/\n")
      local u = User.new()
      u:load({ path = path })
      -- 内容が同じ mtime のままなら読み直さない（メモリ上の変更が残る）
      u:register_henkan_result("okurinasi", "い", "伊")
      u:load({})
      local kept = u:get_henkan_result("okurinasi", "い")
      -- 外から書き換えられたら読み直す
      vim.uv.sleep(20)
      write("m", ";; okuri-nasi entries.\nあ /亜/阿/\n")
      u:load({})
      return { kept, u:get_henkan_result("okurinasi", "あ"), u:get_henkan_result("okurinasi", "い") }
    ]]),
    { { "伊" }, { "亜", "阿" }, {} }
  )
end

T["does not reload after its own save"] = function()
  eq(
    run([[
      local path = TMP .. "/s"
      local u = User.new()
      u:load({ path = path })
      u:register_henkan_result("okurinasi", "あ", "亜")
      u:save()
      u:register_henkan_result("okurinasi", "い", "伊")
      u:load({})
      return u:get_henkan_result("okurinasi", "い")
    ]]),
    { "伊" }
  )
end

T["load of a missing file keeps working, and save creates it"] = function()
  eq(
    run([[
      local path = TMP .. "/new"
      local u = User.new()
      u:load({ path = path })
      u:register_henkan_result("okurinasi", "あ", "亜")
      u:save()
      return read(path)
    ]]),
    ";; okuri-ari entries.\n;; okuri-nasi entries.\nあ /亜/\n"
  )
end

T["save creates parent directory if it does not exist"] = function()
  eq(
    run([[
      local path = TMP .. "/deep/nested/sub/user_dict"
      local u = User.new()
      u:load({ path = path })
      u:register_henkan_result("okurinasi", "あ", "亜")
      u:save()
      return { vim.uv.fs_stat(path) ~= nil, read(path):find("あ /亜/", 1, true) ~= nil }
    ]]),
    { true, true }
  )
end

T["save without a path does nothing, and save to an unwritable path warns"] = function()
  eq(
    run([[
      local msgs = {}
      vim.notify = function(m) msgs[#msgs + 1] = m end
      local u = User.new()
      u:save()
      local unwrite_dir = TMP .. "/unwritable"
      vim.fn.mkdir(unwrite_dir, "p")
      vim.uv.fs_chmod(unwrite_dir, 320) -- 0500: r-x, no write
      u:load({ path = unwrite_dir .. "/file" })
      u:save()
      vim.uv.fs_chmod(unwrite_dir, 511)
      return { #msgs, msgs[1] and msgs[1]:find("can't write", 1, true) ~= nil }
    ]]),
    { 1, true }
  )
end

T["load only sets load_time on successful read"] = function()
  eq(
    run([[
      local path = write("bad_perm_dict", ";; okuri-nasi entries.\nあ /亜/\n")
      local u = User.new()
      local old_read = u.read_file
      u.read_file = function() error("read error") end
      u:load({ path = path })
      local time_after_fail = u.load_time
      u.read_file = old_read
      u:load({ path = path })
      local time_after_success = u.load_time
      return { time_after_fail == "", time_after_success ~= "" }
    ]]),
    { true, true }
  )
end

T["get_prefix"] = function()
  eq(
    run([[
      local u = User.new()
      u:register_henkan_result("okurinasi", "かん", "缶")
      u:register_henkan_result("okurinasi", "かんじ", "漢字")
      u:register_henkan_result("okurinasi", "かんたん", "簡単")
      u:register_henkan_result("okurinasi", "き", "木")
      return { u:get_prefix("okurinasi", "かん", 10), #u:get_prefix("okurinasi", "かん", 2) }
    ]]),
    { { { "かん", { "缶" } }, { "かんじ", { "漢字" } }, { "かんたん", { "簡単" } } }, 2 }
  )
end

T["save keeps a symlink, the file mode and leaves no temporary file"] = function()
  eq(
    run([[
      local real = write("real", "")
      vim.uv.fs_chmod(real, 384)
      local link = TMP .. "/link"
      vim.uv.fs_symlink(real, link)
      local u = User.new()
      u:load({ path = link })
      u:register_henkan_result("okurinasi", "あ", "亜")
      u:save()
      local leftovers = vim.fn.glob(TMP .. "/*.tmp", true, true)
      return {
        vim.uv.fs_lstat(link).type,
        read(real):find("あ /亜/", 1, true) ~= nil,
        bit.band(vim.uv.fs_stat(real).mode, 511),
        #leftovers,
      }
    ]]),
    { "link", true, 384, 0 }
  )
end

T["load_ranks and save_ranks"] = function()
  eq(
    run([[
      local path = TMP .. "/ranks.json"
      local u = User.new()
      u:register_henkan_result("okurinasi", "かんじ", "感じ")
      u:register_henkan_result("okurinasi", "かんじ", "漢字")
      u:save_ranks(path)

      local content = read(path)
      local decoded = vim.json.decode(content)

      local u2 = User.new()
      u2:load_ranks(path)

      return {
        decoded,
        u2:get_ranks(),
        u2.rank_counter,
      }
    ]]),
    {
      { "感じ", "漢字" },
      { ["感じ"] = 1, ["漢字"] = 2 },
      2,
    }
  )
end

T["load_ranks handles missing or invalid file gracefully"] = function()
  eq(
    run([[
      local u = User.new()
      u:load_ranks("")
      u:load_ranks(nil)
      u:load_ranks(TMP .. "/nonexistent_ranks.json")

      local bad_path = write("bad_rank.json", "{ not a valid json")
      u:load_ranks(bad_path)

      return { u:get_ranks(), u.rank_counter }
    ]]),
    { {}, 0 }
  )
end

T["save_ranks creates parent directories"] = function()
  eq(
    run([[
      local deep_path = TMP .. "/deep/nested/ranks/rank.json"
      local u = User.new()
      u:register_henkan_result("okurinasi", "あ", "亜")
      u:save_ranks(deep_path)
      return { vim.uv.fs_stat(deep_path) ~= nil, vim.json.decode(read(deep_path)) }
    ]]),
    { true, { "亜" } }
  )
end

return T

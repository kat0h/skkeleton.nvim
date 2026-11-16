local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

local PRE = helpers.dict_pre([[
local User = require("skkeleton.dictionary.user")
local skk = require("skkeleton.dictionary.skk")
local db = require("skkeleton.dictionary.db")
]])

local function run(code, ...)
  return child.lua(PRE .. code, { ... })
end

T["dictionary round trip"] = MiniTest.new_set()

T["dictionary round trip"]["saving and reading preserves generated candidates"] = function()
  eq(
    run([[
      math.randomseed(265)
      local path = TMP .. "/generated-user-dictionary"
      local u = User.new()
      u:load({ path = path })
      local expected = {}
      local alphabet = { "あ", "漢", "/", ";", "[", "]", '"', "\\", " ", "(concat" }
      local function part()
        local out = {}
        for _ = 1, math.random(1, 5) do
          out[#out + 1] = alphabet[math.random(#alphabet)]
        end
        return table.concat(out)
      end
      for i = 1, 36 do
        local key = "よみ" .. string.format("%02d", i)
        local candidates = {}
        for j = 1, 3 do
          local word = part()
          if j == 1 and i % 4 == 0 then word = "(concat" .. part() end
          if word:sub(1, 1) == "[" then word = "語" .. word end
          local note = i % 2 == 0 and (";" .. part()) or ""
          local candidate = word .. note
          for index = #candidates, 1, -1 do
            if candidates[index] == candidate then
              table.remove(candidates, index)
            end
          end
          table.insert(candidates, 1, candidate)
          u:register_henkan_result("okurinasi", key, candidate)
        end
        expected[key] = candidates
      end
      u:save()
      local restored = User.new()
      restored:read_file(path)
      local actual = {}
      for key in pairs(expected) do actual[key] = restored:get_henkan_result("okurinasi", key) end
      assert(vim.deep_equal(actual, expected), vim.inspect({ expected = expected, actual = actual }))
      return true
    ]]),
    true
  )
end

T["dictionary round trip"]["reading and writing preserves valid dictionary meanings"] = function()
  eq(
    run([[
      math.randomseed(265)
      local alphabet = { "あ", "漢", "/", ";", "[", "]", '"', "\\", " ", "(concat" }
      local function part()
        local out = {}
        for _ = 1, math.random(1, 4) do out[#out + 1] = alphabet[math.random(#alphabet)] end
        return table.concat(out)
      end
      local lines = { ";; okuri-ari entries.", ";; okuri-nasi entries." }
      local expected = {}
      for i = 1, 32 do
        local key = "よみ" .. string.format("%02d", i)
        local cands = {}
        for _ = 1, 3 do
          local word = part()
          if word:sub(1, 1) == "[" then word = "候補" .. word end
          cands[#cands + 1] = word .. (i % 2 == 0 and (";" .. part()) or "")
        end
        expected[key] = cands
        local encoded = vim.tbl_map(User.encode_candidate, cands)
        lines[#lines + 1] = key .. " /" .. table.concat(encoded, "/") .. "/"
      end
      local path = write("roundtrip-source", table.concat(lines, "\n") .. "\n")
      local first = User.new()
      first:read_file(path)
      local before = {}
      for key in pairs(expected) do before[key] = first:get_henkan_result("okurinasi", key) end
      first.path = write("roundtrip-destination", "")
      first:save()
      local second = User.new()
      second:read_file(first.path)
      local after = {}
      for key in pairs(expected) do after[key] = second:get_henkan_result("okurinasi", key) end
      assert(vim.deep_equal(before, after), vim.inspect({ before = before, after = after }))
      return true
    ]]),
    true
  )
end

T["dictionary round trip"]["building a database preserves lookup results"] = function()
  eq(
    run([[
      math.randomseed(265)
      local alphabet = { "あ", "漢", "/", ";", "[", "]", '"', "\\", " ", "(concat" }
      local function part()
        local out = {}
        for _ = 1, math.random(1, 4) do out[#out + 1] = alphabet[math.random(#alphabet)] end
        return table.concat(out)
      end
      local lines = { ";; okuri-ari entries.", ";; okuri-nasi entries." }
      local keys = {}
      for i = 1, 32 do
        local key = "よみ" .. string.format("%02d", i)
        keys[#keys + 1] = key
        local cands = { part(), part() .. ";" .. part(), "(concat" .. part() }
        lines[#lines + 1] = key .. " /" .. table.concat(vim.tbl_map(User.encode_candidate, cands), "/") .. "/"
      end
      local src = write("db-roundtrip-source", table.concat(lines, "\n") .. "\n")
      local memory = skk.load_memory(src)
      local memory_results = {}
      for _, key in ipairs(keys) do memory_results[key] = memory:get_henkan_result("okurinasi", key) end
      local dict = db.open_dictionary(src, { dir = TMP .. "/db-cache" })
      local db_results = {}
      for _, key in ipairs(keys) do
        db_results[key] = skk.split_candidates(dict:get_raw("okurinasi", key))
      end
      dict:close()
      assert(vim.deep_equal(memory_results, db_results), vim.inspect({ memory = memory_results, database = db_results }))
      return true
    ]]),
    true
  )
end

T["dictionary round trip"]["malformed lines do not prevent later entries from loading"] = function()
  eq(
    run([[
      local path = write("malformed-dictionary", table.concat({
        ";; okuri-nasi entries.",
        "壊れた行",
        " /見出しなし/",
        "よみ1 /候補1/",
        "よみ2 候補が壊れている",
        "よみ3 /候補3/",
      }, "\n"))
      local u = User.new()
      local ok = pcall(u.read_file, u, path)
      return { ok, u:get_henkan_result("okurinasi", "よみ1"), u:get_henkan_result("okurinasi", "よみ3") }
    ]]),
    { true, { "候補1" }, { "候補3" } }
  )
end

return T

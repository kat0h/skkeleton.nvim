-- #262 の共通ケースを skkeleton.nvim の core に流すドライバ
local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h:h:h")
local cases = dofile(root .. "/semantics/conformance/cases.lua")

local function tokenize(keys)
  local result = {}
  local i = 1
  while i <= #keys do
    if keys:sub(i, i) == "<" then
      local last = assert(keys:find(">", i, true), "閉じていないキー表記")
      result[#result + 1] = keys:sub(i, last)
      i = last + 1
    else
      result[#result + 1] = keys:sub(i, i)
      i = i + 1
    end
  end
  return result
end

local function normalized_observe(child, keys)
  return child.lua([[
    local keys = ...
    local notation = require("skkeleton.notation")
    local keymap = require("skkeleton.keymap")
    local text = ""
    for _, key in ipairs(keys) do
      keymap.handle_key(ctx, notation.normalize(key))
      local committed = ctx.preedit:take_kakutei()
      for index = 0, vim.fn.strchars(committed) - 1 do
        local ch = vim.fn.strcharpart(committed, index, 1)
        if ch == "\b" then
          local chars = vim.fn.strchars(text)
          if chars > 0 then text = vim.fn.strcharpart(text, 0, chars - 1) end
        else
          text = text .. ch
        end
      end
    end
    local st = ctx.state
    local register = registered
    local stage = register and "register" or (st.type == "henkan" and "select" or (st.mode ~= "direct" and "reading" or "none"))
    local result = { text = text, stage = stage }
    local reading, okuri, pending = st.henkan_feed or "", st.okuri_feed or "", st.feed or ""
    if register then reading, okuri = registered.reading, registered.okuri end
    result.reading = reading
    result.okuri = okuri
    if st.mode == "abbrev" then
      if reading ~= "" then result.reading = reading end
      pending = ""
    end
    result.pending = pending
    local candidate = st.type == "henkan" and st.candidates and st.candidates[st.candidate_index + 1]
    if candidate then result.candidate = candidate:match("^[^;]*") end
    result.mode = H.called("disable")[1] and "ascii" or ctx.mode
    return result
  ]], { tokenize(keys) })
end

local function run_case(case)
  local child = MiniTest.new_child_neovim()
  local ok, result = pcall(function()
    child.restart({ "-u", root .. "/tests/minimal_init.lua" })
    child.lua([=[
      require("core_helpers").init_core({ spy_host = true })
      ctx = Context.new()
      registered = nil
      require("skkeleton.host").input = function()
        registered = { reading = ctx.state.henkan_feed or "", okuri = ctx.state.okuri_feed or "" }
        return nil
      end
      local dictionary = ...
      for _, entry in ipairs(dictionary.okuri_nasi) do
        lib.data["okurinasi:" .. entry[1]] = vim.deepcopy(entry[2])
      end
      for _, entry in ipairs(dictionary.okuri_ari) do
        lib.data["okuriari:" .. entry[1]] = vim.deepcopy(entry[2])
      end
    ]=], { cases.dictionary })
    return normalized_observe(child, case.keys)
  end)
  child.stop()
  if not ok then return { error = tostring(result) } end
  return { observe = result }
end

local results = {}
for _, case in ipairs(cases.cases) do
  results[case.id] = run_case(case)
end

local output = {
  impl = "skkeleton.nvim",
  version = "08cc791",
  settings = { driver = "tests/core_helpers.lua core only" },
  results = results,
}
local path = root .. "/semantics/conformance/results/skkeleton.nvim.json"
vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
local file = assert(io.open(path, "wb"))
file:write(vim.json.encode(output), "\n")
file:close()
print(("Ran %d cases; results: %s"):format(#cases.cases, path))

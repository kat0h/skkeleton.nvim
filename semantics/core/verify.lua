-- core の参照モデルと実装に有限のキー列を流す差分検査。
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/tests/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local model = dofile(root .. "/semantics/core/model.lua")
local H = require("core_helpers")
local kana = require("skkeleton.kana")
local options = require("skkeleton.config").options
local D = {
  ["okurinasi:かき"] = { "柿", "牡蠣;貝", "夏期", "火器", "下記", "花器" },
  ["okurinasi:あい"] = { "愛" }, ["okurinasi:か"] = { "蚊" },
  ["okurinasi:か>"] = { "可>" }, ["okurinasi:>か"] = { ">化" },
  ["okuriari:かk"] = { "書", "欠" },
}
local answers = {
  cancel = { input = nil, confirm = false }, word = { input = "登録", confirm = false },
  purge = { input = nil, confirm = true }, word_purge = { input = "登録", confirm = true },
}
local function stub(name, t)
  package.loaded["skkeleton.kana." .. name] = { new = function()
    local entries = {}
    for from, result in pairs(t.entries) do entries[#entries + 1] = { from, result } end
    local tbl = kana.KanaTable.new(entries)
    tbl.kana_functions = t.kana_functions
    return tbl
  end }
end
local function reset(overrides, answer)
  require("skkeleton.config").reset()
  for k, v in pairs(overrides or {}) do options[k] = v end
  stub("rom_hira", model.tables.rom); stub("rom_zen", model.tables.zen)
  kana.reset(); require("skkeleton.keymap").reset()
  H.init_core({ spy_host = true })
  H.ret.input, H.ret.confirm = answer.input, answer.confirm
  H.calls = {}
  local lib = _G.lib
  for key, val in pairs(D) do
    local kind, word = key:match("^(.-):(.*)$")
    lib.data[key] = vim.deepcopy(val)
  end
  return lib
end
local function actual_observe(ctx)
  local s = ctx.state
  local phase = s.type == "input" and (s.mode == "okurinasi" and "input:okurinasi" or s.mode == "okuriari" and "input:okuriari" or "input") or s.type
  return { phase = phase, henkanFeed = s.henkan_feed or "", preedit = s.type ~= "escape" and ctx:to_string() or "", mode = H.called("disable")[1] and "" or ctx.mode }
end
local function equal(a, b)
  return vim.deep_equal(a, b)
end
local failures, count, by_length, executed_keys = {}, 0, {}, 0
local function run(seq, override, answer_name)
  count = count + 1
  by_length[#seq] = (by_length[#seq] or 0) + 1
  local answer = answers[answer_name or "cancel"]
  local C = model.config(override)
  local sigma, ctx = model.initial(C), nil
  reset(override, answer)
  ctx = require("skkeleton.context").new()
  local final_observed, final_commit, final_calls
  for i, key in ipairs(seq) do
    H.calls = {}
    local next_sigma, out = model.step(C, D, {
      input = function() return answer.input end,
      confirm = function() return answer.confirm end,
    }, sigma, key)
    if key == "@disable" then require("skkeleton.function.disable").disable(ctx)
    elseif model.stage(C, sigma) ~= "off" then require("skkeleton.keymap").handle_key(ctx, key) end
    local observed = actual_observe(ctx)
    local commit = ctx.preedit:take_kakutei()
    local expected = model.observe(next_sigma, C)
    local actual_calls = {}
    for _, call in ipairs(H.calls) do
      if call[1] == "disable" or call[1] == "input" or call[1] == "confirm" or call[1] == "show_candidates" then
        actual_calls[#actual_calls + 1] = { call[1], call[2] }
      end
    end
    local expected_host_calls = {}
    for _, call in ipairs(out.calls) do
      if call[1] == "disable" or call[1] == "input" or call[1] == "confirm" or call[1] == "show_candidates" then
        expected_host_calls[#expected_host_calls + 1] = call
      end
    end
    if not equal(observed, expected) or commit ~= out.commit or not equal(actual_calls, expected_host_calls) then
      failures[#failures + 1] = { seq = vim.deepcopy(seq), at = i, key = key, observed = observed, expected = expected,
        commit = commit, expected_commit = out.commit, calls = actual_calls, expected_calls = expected_host_calls, rules = out.rules }
      return
    end
    final_observed, final_commit, final_calls = observed, commit, actual_calls
    executed_keys = executed_keys + 1
    sigma = next_sigma
    if model.stage(C, sigma) == "off" then return final_observed, final_commit, final_calls end
  end
  return final_observed, final_commit, final_calls
end
local keys = vim.tbl_filter(function(k) return k ~= "@enable" and k ~= "@disable" end, model.keys)
local seq = {}
local function enumerate(n)
  if #seq == n then
    for answer in pairs(answers) do run(seq, nil, answer) end
    return
  end
  for _, key in ipairs(keys) do seq[#seq + 1] = key; enumerate(n); seq[#seq] = nil end
end
local targeted = {
  { { "K", "a", "N", "k" }, "cancel" }, { { "K", "a", ";", "z" }, "cancel" },
  { { "K", "a", "N", "q" }, "cancel" }, { { "K", "a", "k", "<space>" }, "cancel" },
  { { "K", "a", ";", "<space>" }, "cancel" }, { { "K", "a", ";", ">" }, "cancel" },
  { { "q", "K", "a", "<space>", "X", "a" }, "purge" }, { { "L", "k", "K", "l", "q", ">" }, "cancel" },
  { { "q", "/", "a", "<nl>" }, "cancel" },
}
local fixed_only = vim.env.SKK_CORE_FIXED == "1"
if fixed_only then
  for _, case in ipairs(targeted) do
    local observed, commit, calls = run(case[1], nil, case[2])
    print(vim.inspect({ keys = case[1], observed = observed, commit = commit, calls = calls }))
  end
  reset(nil, answers.cancel)
  local ctx = require("skkeleton.context").new()
  ctx.state.type, ctx.state.candidates, ctx.state.candidate_index, ctx.state.henkan_feed = "henkan", {}, 0, "か"
  require("skkeleton.function.common").kakutei(ctx)
  print(vim.inspect({ rule = "R-CK-14", commit = ctx.preedit:take_kakutei() }))
  reset(nil, answers.cancel)
  ctx = require("skkeleton.context").new()
  require("skkeleton.keymap").handle_key(ctx, "<esc>")
  local ok, err = pcall(require("skkeleton.keymap").handle_key, ctx, "a")
  print(vim.inspect({ rule = "R-EN-09", ok = ok, error = err }))
else
  for n = 1, 3 do enumerate(n) end
  -- 固定 seed の LCG で長さ 8 の列を再現可能に作る。
  local seed = 261
  local function rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
  for _, override in ipairs({ { immediatelyCancel = false }, { eggLikeNewline = true }, { immediatelyOkuriConvert = false }, { acceptIllegalResult = true } }) do
    for _ = 1, 5000 do
      local random = {}; for i = 1, 8 do random[i] = keys[rand(#keys)] end
      run(random, override, "cancel")
    end
  end
  for _, case in ipairs(targeted) do run(case[1], nil, case[2]) end
end
if #failures > 0 then
  for _, failure in ipairs(failures) do print(vim.inspect(failure)) end
  error((#failures .. " mismatch(es)"), 0)
end
print(("verified %d sequences; no mismatches"):format(count))

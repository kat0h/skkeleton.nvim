-- SPIN で model.pml を検査し、Lua の model_check.lua と同じ反例になるかを見る（#193）
--
-- 使い方（リポジトリの一番上で動かす。重いので flock と timeout を付ける）:
--   flock /tmp/heavy.lock timeout 1800 nvim --headless -u NONE -i NONE -l semantics/spin/check.lua
--
-- すること:
--   1. model.lua から P1/P3/P5/P10/P13 の違反を、model_check.lua と同じ規則で数える
--   2. P1 の違反遷移それぞれについて「到達できるか」の LTL を足した targets.pml を作る
--   3. SPIN で P1/P3/P5/P10 と P13 を検査し、P1 の反例の遷移列を取り出す
--   4. Lua 側の違反と SPIN が見つけた違反を突き合わせる（M.known なら △、知らなければ ✗）
--   5. P8 は SPIN の LTL では表せない（存在経路）ので、Lua と同じ有向グラフの検査をする
--
-- 終了コード: 知らない反例が無ければ 0、あれば 1。

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local root = dir:match("^(.*)/semantics/spin$")
if not root then
  error("semantics/spin の中から動かしてください: " .. dir, 0)
end
local model = dofile(dir .. "/../model/model.lua")
local work = root .. "/.tests/spin"
os.execute(("mkdir -p %s"):format(work))

local function sh(cmd)
  local code = os.execute(cmd)
  return code == 0 or code == true
end

local function capture(cmd)
  local pipe = assert(io.popen(cmd .. " 2>&1"))
  local out = pipe:read("*a")
  pipe:close()
  return out
end

local function last_number(text, pattern)
  local found
  for n in text:gmatch(pattern) do
    found = tonumber(n)
  end
  return found
end

-- ---------------------------------------------------------------------------
-- モデルの違反（model_check.lua の書き方に合わせる）

local EFFECTS = {
  "commit_reading", "commit_candidate", "cancel", "drop", "keep", "reset_state",
  "restore_mapping", "install_mapping", "save_mapping", "clear_extmark",
  "clean_cmdline", "render", "feed_key", "pass_key",
}

local by_from = {}
for _, t in ipairs(model.transitions) do
  by_from[t.from] = by_from[t.from] or {}
  table.insert(by_from[t.from], t)
end

local function effect_counts(t)
  local counts = {}
  for _, name in ipairs(t.effects) do
    counts[name] = (counts[name] or 0) + 1
  end
  return counts
end

local READING = { romaji = true, point = true, henkan = true, any = true }

local function p1_violations()
  local out = {}
  for _, t in ipairs(model.transitions) do
    local from = model.states[t.from]
    local to = model.states[t.to]
    if READING[from.reading] and to.reading == "none" then
      local set = effect_counts(t)
      local kept = set.commit_reading or set.commit_candidate or set.cancel or set.keep
      if set.drop and not kept then
        table.insert(out, t)
      end
    end
  end
  return out
end

local function p3_violations()
  local out = {}
  local off = { N_OFF = true, I_OFF = true, R_OFF = true }
  for _, t in ipairs(model.transitions) do
    if off[t.to] and model.states[t.from].enabled then
      local set = effect_counts(t)
      if not (set.reset_state and set.restore_mapping) then
        table.insert(out, t)
      end
    end
  end
  return out
end

local function double_violations()
  local out = {}
  for _, t in ipairs(model.transitions) do
    local set = effect_counts(t)
    local duplicate = false
    for _, n in pairs(set) do
      if n > 1 then
        duplicate = true
      end
    end
    if duplicate or (set.commit_reading and set.commit_candidate) then
      table.insert(out, t)
    end
  end
  return out
end

local function p13_violations()
  local out = {}
  for name, st in pairs(model.states) do
    if st.transient and #(by_from[name] or {}) == 0 then
      table.insert(out, { transition = "-", detail = name })
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Lua 側の到達性（model_check.lua の guard と同じ）

local function resolve(var, state_name, config)
  local prefix, name = var:match("^([%w_]+)%.(.+)$")
  if prefix == "config" then
    return config[name]
  end
  return model.states[state_name][var]
end

local function eval_atom(atom, state_name, config)
  if atom[1] == "not" then
    return not eval_atom(atom[2], state_name, config)
  end
  local var, op, value = atom[1], atom[2], atom[3]
  local actual = resolve(var, state_name, config)
  if op == "=" then
    return actual == value
  elseif op == "in" then
    for _, v in ipairs(value) do
      if actual == v then
        return true
      end
    end
    return false
  end
  error("知らない guard の演算子: " .. tostring(op), 0)
end

local function guard_ok(t, config)
  for _, atom in ipairs(t.guard or {}) do
    if not eval_atom(atom, t.from, config) then
      return false
    end
  end
  return true
end

-- 初期状態から、各遷移への最短の遷移列を返す（どちらの keepState でもよい）
local function shortest_trails()
  local best = {}
  for _, keep in ipairs({ false, true }) do
    local config = { keepState = keep }
    local paths = { [model.initial[1]] = {} }
    local queue, head = { model.initial[1] }, 1
    while head <= #queue do
      local state_name = queue[head]
      head = head + 1
      for _, t in ipairs(by_from[state_name] or {}) do
        if guard_ok(t, config) then
          local path = {}
          for _, id in ipairs(paths[state_name]) do
            path[#path + 1] = id
          end
          path[#path + 1] = t.id
          if not best[t.id] or #path < #best[t.id] then
            best[t.id] = path
          end
          if not paths[t.to] or #path < #paths[t.to] then
            paths[t.to] = path
            queue[#queue + 1] = t.to
          end
        end
      end
    end
  end
  return best
end

-- P8: 有効な状態から、無効な状態へ（逆向きに）たどれるか。model_check.lua と同じ
local function p8_violations()
  local reachable = {}
  for _, keep in ipairs({ false, true }) do
    local config = { keepState = keep }
    local queue, head = { model.initial[1] }, 1
    local seen = { [model.initial[1]] = true }
    while head <= #queue do
      local state_name = queue[head]
      head = head + 1
      for _, t in ipairs(by_from[state_name] or {}) do
        if guard_ok(t, config) and not seen[t.to] then
          seen[t.to] = true
          queue[#queue + 1] = t.to
        end
      end
    end
    for name in pairs(seen) do
      reachable[name] = true
    end
  end

  local reverse = {}
  for _, t in ipairs(model.transitions) do
    reverse[t.to] = reverse[t.to] or {}
    table.insert(reverse[t.to], t.from)
  end

  local out = {}
  for name, st in pairs(model.states) do
    if reachable[name] and st.enabled then
      local seen, queue, head = { [name] = true }, { name }, 1
      local found = false
      while head <= #queue do
        local cur = queue[head]
        head = head + 1
        if not model.states[cur].enabled then
          found = true
          break
        end
        for _, prev in ipairs(reverse[cur] or {}) do
          if not seen[prev] then
            seen[prev] = true
            queue[#queue + 1] = prev
          end
        end
      end
      if not found then
        table.insert(out, { transition = "-", detail = name })
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- 反例をキー列にするための、遷移→キーの対応
--
-- event.keys の 1 つ目を使う。internal / autocmd はキーが無いので、そのままでは再生できない。

local PREFERRED = {
  ["t.I_ROMAJI.ctrl_a"] = "<C-a>",
  ["t.I_ROMAJI.ctrl_at"] = "<C-@>",
  ["t.I_ROMAJI.ctrl_k"] = "<C-k>a:",
  ["t.I_ROMAJI.ctrl_r"] = "<C-r>a",
  ["t.I_ROMAJI.ctrl_t"] = "<C-t>",
  ["t.I_ROMAJI.ctrl_u"] = "<C-u>",
  ["t.I_ROMAJI.ctrl_v"] = "<C-v>065",
  ["t.I_ROMAJI.ctrl_w"] = "<C-w>",
  ["t.I_ROMAJI.tab"] = "<Tab>",
  ["t.I_POINT.ctrl_a"] = "<C-a>",
  ["t.I_POINT.ctrl_at"] = "<C-@>",
  ["t.I_POINT.ctrl_k"] = "<C-k>a:",
  ["t.I_POINT.ctrl_r"] = "<C-r>a",
  ["t.I_POINT.ctrl_t"] = "<C-t>",
  ["t.I_POINT.ctrl_u"] = "<C-u>",
  ["t.I_POINT.ctrl_v"] = "<C-v>065",
  ["t.I_POINT.ctrl_w"] = "<C-w>",
  ["t.I_POINT.tab"] = "<Tab>",
  ["t.I_SELECT.completion_open"] = "<C-n>",
  ["t.I_ROMAJI.completion_open"] = "<C-n>",
  ["t.I_POINT.completion_open"] = "<C-n>",
  ["t.NI_POINT.return_drop"] = "x",
  ["t.NI_SELECT.return_drop"] = "x",
  ["t.N_OFF.enable"] = "<Plug>(skkeleton-enable)",
  ["t.I_DIRECT.char_shift.point"] = "K",
  ["t.I_DIRECT.char_shift"] = "K",
  ["t.I_DIRECT.char.romaji"] = "a",
}

local function key_of(t)
  local preferred = PREFERRED[t.id]
  if preferred then
    return preferred
  end
  local event = model.events[t.event]
  return (event.keys or {})[1]
end

local function ids_text(trail)
  local out = {}
  for _, id in ipairs(trail) do
    out[#out + 1] = id
  end
  return table.concat(out, " -> ")
end

local function keys_text(trail)
  local out = {}
  for _, id in ipairs(trail) do
    local t
    for _, candidate in ipairs(model.transitions) do
      if candidate.id == id then
        t = candidate
        break
      end
    end
    if not t then
      return "?"
    end
    local key = key_of(t)
    if not key then
      out[#out + 1] = ("<%s>"):format(t.event)
    else
      out[#out + 1] = key
    end
  end
  return table.concat(out, " -> ")
end

-- ---------------------------------------------------------------------------

local failures = 0
local function fail(message)
  failures = failures + 1
  io.write("✗ " .. message .. "\n")
end

local p1 = p1_violations()
local p3 = p3_violations()
local doubles = double_violations()
local p13 = p13_violations()
local p8 = p8_violations()
local trails = shortest_trails()

local function index_of(t)
  for i, candidate in ipairs(model.transitions) do
    if candidate == t then
      return i
    end
  end
  return nil
end

-- SPIN を動かさずに、Lua 側の違反と遷移列だけを見る（開発用）
if os.getenv("SPIN_CHECK_DRY") == "1" then
  io.write(("Lua の違反: P1 %d、P3 %d、P5/P10 %d、P13 %d、P8 %d\n"):format(
    #p1,
    #p3,
    #doubles,
    #p13,
    #p8
  ))
  for _, t in ipairs(p1) do
    local trail = trails[t.id]
    io.write(("%-28s %s\n"):format(t.id, trail and ids_text(trail) or "（届かない）"))
    if trail then
      io.write(("    %s\n"):format(keys_text(trail)))
    end
  end
  os.exit(0)
end

-- targets.pml: P1 の違反遷移に「到達できるか」の LTL を足す
local targets = {}
targets[#targets + 1] = ('#include "%s/model.pml"'):format(dir)
targets[#targets + 1] = ""
local target_by_claim = {}
local target_order = {}
for _, t in ipairs(p1) do
  local index = index_of(t)
  local claim = ("hit_%04d"):format(index)
  target_by_claim[claim] = { transition = t, index = index }
  target_order[#target_order + 1] = claim
  targets[#targets + 1] = ("ltl %s { [] (last != %d) }"):format(claim, index)
end
local targets_path = work .. "/targets.pml"
local file = assert(io.open(targets_path, "w"))
file:write(table.concat(targets, "\n") .. "\n")
file:close()

io.write(("モデル: 状態 %d、イベント %d、遷移 %d\n"):format(
  (function()
    local n = 0
    for _ in pairs(model.states) do
      n = n + 1
    end
    return n
  end)(),
  (function()
    local n = 0
    for _ in pairs(model.events) do
      n = n + 1
    end
    return n
  end)(),
  #model.transitions
))
io.write(("Lua の違反: P1 %d、P3 %d、P5/P10 %d、P13 %d、P8 %d\n"):format(
  #p1,
  #p3,
  #doubles,
  #p13,
  #p8
))

if not sh(("cd %s && spin -a targets.pml > spin.log 2>&1"):format(work)) then
  fail("spin -a が失敗しました: " .. work .. "/spin.log")
  os.exit(1)
end
if not sh(("cd %s && gcc -O0 -DREACH -o pan pan.c >> spin.log 2>&1"):format(work)) then
  fail("gcc が失敗しました: " .. work .. "/spin.log")
  os.exit(1)
end

-- 一般の性質
local claims = { "p1", "p3", "p5", "p10", "p13" }
local claim_errors = {}
for _, claim in ipairs(claims) do
  local command = ("cd %s && ./pan -N %s %s"):format(work, claim, claim == "p13" and "-a" or "")
  local out = capture(command)
  local errors = last_number(out, "errors:%s*(%d+)")
  claim_errors[claim] = errors
  if errors == nil then
    fail(("%s の結果を読めませんでした"):format(claim))
  elseif errors > 0 then
    if claim == "p1" then
      io.write(("P1: SPIN が反例を見つけました（%d 件）\n"):format(errors))
    else
      fail(("%s が破れています（%d 件）"):format(claim, errors))
    end
  else
    io.write(("✓ %s\n"):format(claim))
  end
end

-- P1 の反例を遷移ごとに取り出す
local known = {}
for _, k in ipairs(model.known or {}) do
  known[k.property .. "\0" .. k.transition] = k
end

io.write("\n== P1 の反例（SPIN） ==\n")
local spin_p1 = {}
for _, claim in ipairs(target_order) do
  local entry = target_by_claim[claim]
  os.execute(("rm -f %s/model.pml.trail %s/targets.pml.trail %s/*.trail"):format(work, work, work))
  local out = capture(("cd %s && ./pan -N %s -i"):format(work, claim))
  local errors = last_number(out, "errors:%s*(%d+)")
  if errors == nil then
    fail(("%s の結果を読めませんでした"):format(claim))
  elseif errors > 0 then
    spin_p1[entry.transition.id] = true
    local trail_file = capture(("ls -t %s/*.trail 2>/dev/null | head -1"):format(work)):gsub("%s+$", "")
    if trail_file ~= "" then
      if trail_file ~= work .. "/targets.pml.trail" then
        os.execute(("cp %s %s/targets.pml.trail"):format(trail_file, work))
      end
      if trail_file ~= work .. "/model.pml.trail" then
        os.execute(("cp %s %s/model.pml.trail"):format(trail_file, work))
      end
    end
    local replay = capture(("cd %s && spin -t -p targets.pml"):format(work))
    local trail = {}
    for n in replay:gmatch("TRANS (%d+)") do
      trail[#trail + 1] = tonumber(n)
    end
    local k = known["P1\0" .. entry.transition.id]
    local mark = k and "△" or "✗"
    if not k then
      fail(("P1 の知らない反例: %s"):format(entry.transition.id))
    end
    io.write(("%s %-28s（%s）\n"):format(
      mark,
      entry.transition.id,
      k and table.concat(k.refs or {}, ", ") or "M.known に無い"
    ))
    if #trail == 0 then
      io.write("    遷移列: （取り出せませんでした）\n")
    else
      local names = {}
      for _, index in ipairs(trail) do
        names[#names + 1] = model.transitions[index].id
      end
      io.write(("    遷移列: %s\n"):format(table.concat(names, " -> ")))
      io.write(("    キー列: %s\n"):format(keys_text(names)))
      local lua_trail = trails[entry.transition.id]
      if lua_trail then
        io.write(("    Lua の最短列: %s\n"):format(ids_text(lua_trail)))
      end
    end
  end
end

for _, t in ipairs(p1) do
  if not spin_p1[t.id] then
    io.write(("－ %-28s SPIN の探索では届かない（Lua は遷移の形だけで挙げている）\n"):format(t.id))
  end
end

local spin_count = 0
for _ in pairs(spin_p1) do
  spin_count = spin_count + 1
end
io.write(("SPIN の P1: %d 件（Lua: %d 件）\n"):format(spin_count, #p1))

-- Lua の違反が SPIN の集合から漏れていないか
for id in pairs(spin_p1) do
  local found = false
  for _, t in ipairs(p1) do
    if t.id == id then
      found = true
    end
  end
  if not found then
    fail(("SPIN だけが見つけた P1 の反例: %s"):format(id))
  end
end

-- ほかの性質の違反（Lua 側）
for _, t in ipairs(p3) do
  fail(("P3 の違反: %s"):format(t.id))
end
for _, t in ipairs(doubles) do
  fail(("P5/P10 の違反: %s"):format(t.id))
end
for _, v in ipairs(p13) do
  fail(("P13 の違反: %s"):format(v.detail))
end
for _, v in ipairs(p8) do
  fail(("P8 の違反: %s"):format(v.detail))
end
if #p8 == 0 then
  io.write("✓ p8（Lua と同じ有向グラフの検査）\n")
end

io.write("\n")
if failures == 0 then
  io.write("== まとめ: 知らない反例 0 ==\n")
  os.exit(0)
end
io.write(("== まとめ: 失敗 %d ==\n"):format(failures))
os.exit(1)

-- モデルの検査器（#184、親は #179）
--
-- semantics/model/model.lua だけを読み、幅優先（BFS）で性質を調べる。
-- 性質が破れたら、そこへ行くまでのイベント列（反例）を出す。
-- 既知の破れ（M.known）は △ として出し、失敗にしない。知らない破れは ✗ で失敗にする。
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua
--   nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua --verbose
--   nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua --config keepState=true
--
-- 返す値: 失敗が無ければ 0、あれば 1。
local M = {}

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local model = dofile(dir .. "/model.lua")

-- nvim の print は長い行を折り返して \r を混ぜることがあるので、stdout に直接書く
local function say(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  io.write(table.concat(parts), "\n")
end

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do
    out[k] = v
  end
  return out
end

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------
-- 遷移の索引

local by_from = {}
for _, t in ipairs(model.transitions) do
  by_from[t.from] = by_from[t.from] or {}
  table.insert(by_from[t.from], t)
end

local state_names = sorted_keys(model.states)
local event_names = sorted_keys(model.events)

-- 遷移が参照する名前や効果の語が正しいか
local function validate()
  local errors = {}
  local seen_id = {}
  local observed_ids = {}
  for _, obs in ipairs(model.observations) do
    observed_ids[obs.id] = true
  end
  local effect_ok = {}
  for _, name in ipairs({
    "commit_reading", "commit_candidate", "cancel", "drop", "keep", "reset_state",
    "restore_mapping", "install_mapping", "save_mapping", "clear_extmark", "clean_cmdline",
    "render", "feed_key", "pass_key",
  }) do
    effect_ok[name] = true
  end
  local function check_guard(atom, t, where)
    if atom[1] == "not" then
      if type(atom[2]) ~= "table" then
        table.insert(errors, ("%s: not の後ろが文ではない"):format(t.id))
      else
        check_guard(atom[2], t, where)
      end
      return
    end
    if atom[2] ~= "=" and atom[2] ~= "in" then
      table.insert(errors, ("%s: guard の演算子が = / in / not でない: %s"):format(t.id, tostring(atom[2])))
    end
    local var = atom[1]
    local prefix = var:match("^([%w_]+)%.")
    if prefix ~= "config" and model.states[t.from][var] == nil then
      table.insert(errors, ("%s: guard の変数 %s が状態 %s に無い"):format(t.id, var, t.from))
    end
  end
  for _, t in ipairs(model.transitions) do
    if seen_id[t.id] then
      table.insert(errors, ("遷移の id が重複: %s"):format(t.id))
    end
    seen_id[t.id] = true
    if not model.states[t.from] then
      table.insert(errors, ("%s: 知らない from %s"):format(t.id, t.from))
    end
    if not model.states[t.to] then
      table.insert(errors, ("%s: 知らない to %s"):format(t.id, t.to))
    end
    if not model.events[t.event] then
      table.insert(errors, ("%s: 知らない event %s"):format(t.id, t.event))
    end
    for _, e in ipairs(t.effects) do
      if not effect_ok[e] then
        table.insert(errors, ("%s: GLOSSARY に無い効果 %s"):format(t.id, e))
      end
    end
    for _, atom in ipairs(t.guard) do
      check_guard(atom, t, "guard")
    end
    for _, oid in ipairs(t.observed) do
      if not observed_ids[oid] then
        table.insert(errors, ("%s: M.observations に無い観測 %s"):format(t.id, oid))
      end
    end
  end
  for _, k in ipairs(model.known or {}) do
    if not seen_id[k.transition] then
      table.insert(errors, ("M.known の遷移が無い: %s"):format(k.transition))
    end
  end
  -- gap は「今の振る舞いが性質を破っている」遷移だけ。破れを M.known に書いていなければ失敗にする
  local known_transitions = {}
  for _, k in ipairs(model.known or {}) do
    known_transitions[k.transition] = true
  end
  for _, t in ipairs(model.transitions) do
    if t.status == "gap" and not known_transitions[t.id] then
      table.insert(errors, ("%s: gap だが M.known に無い（破っている性質と issue を書く）"):format(t.id))
    end
  end
  return errors
end

-- ---------------------------------------------------------------------------
-- guard の評価
--
-- guard は { { 変数, "=", 値 }, { 変数, "in", { 値 } }, { "not", 文 } } の連言。
-- 変数は config.<名前> か、状態クラスの事実（M.states[from] の項目）。

local function resolve(var, state_name, config)
  local prefix, name = var:match("^([%w_]+)%.(.+)$")
  if prefix == "config" then
    return config[name]
  end
  local st = model.states[state_name]
  return st and st[var]
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
  error(("知らない guard の演算子: %s"):format(tostring(op)), 0)
end

local function guard_ok(t, config)
  for _, atom in ipairs(t.guard or {}) do
    if not eval_atom(atom, t.from, config) then
      return false
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- キーの解決
--
-- ある状態からキーを打ったときの遷移を返す。イベントは keys に表記を持つ。
local function transitions_for_key(state_name, key, config)
  local out = {}
  for _, t in ipairs(by_from[state_name] or {}) do
    local event = model.events[t.event]
    local hit = false
    for _, k in ipairs(event.keys or {}) do
      if k == key then
        hit = true
        break
      end
    end
    if hit and guard_ok(t, config) then
      table.insert(out, t)
    end
  end
  return out
end

-- 内部の片付け（SafeState、escape の片付け、i→R の移り変わり）を、なくなるまで進める
local function settle(paths, config)
  local out = {}
  local queue = paths
  local guard_count = 0
  while #queue > 0 do
    guard_count = guard_count + 1
    if guard_count > 200 then
      error("内部の片付けが止まりません（遷移が循環しています）", 0)
    end
    local next_queue = {}
    for _, path in ipairs(queue) do
      local advanced = false
      for _, t in ipairs(by_from[path.state] or {}) do
        if model.events[t.event].kind == "internal" and guard_ok(t, config) then
          advanced = true
          local p = { state = t.to, trail = copy(path.trail) }
          table.insert(p.trail, t.id)
          table.insert(next_queue, p)
        end
      end
      if not advanced then
        table.insert(out, path)
      end
    end
    queue = next_queue
  end
  return out
end

local function project(state_name)
  local st = model.states[state_name]
  return st and st.class or state_name
end

-- キー列を流す。途中で分かれる道は、すべて残す
local function run_keys(keys, config, start)
  local paths = {}
  for _, s in ipairs(start or model.initial) do
    table.insert(paths, { state = s, trail = {} })
  end
  for _, key in ipairs(keys) do
    local next_paths = {}
    for _, path in ipairs(paths) do
      for _, t in ipairs(transitions_for_key(path.state, key, config)) do
        local p = { state = t.to, trail = copy(path.trail) }
        table.insert(p.trail, t.id)
        table.insert(next_paths, p)
      end
    end
    if #next_paths == 0 then
      local states = {}
      for _, path in ipairs(paths) do
        table.insert(states, path.state)
      end
      return nil, ("%s（状態 %s）"):format(key, table.concat(states, "/"))
    end
    paths = settle(next_paths, config)
  end
  return paths
end

-- ---------------------------------------------------------------------------
-- 棚卸し（01 のキーと 02 のイベント）の網羅

local function event_has_transition(name)
  for _, t in ipairs(model.transitions) do
    if t.event == name then
      return true
    end
  end
  return false
end

local function coverage()
  local result = { missing_keys = {}, missing_events = {}, counts = {} }
  local event_keys = {}
  for _, name in ipairs(event_names) do
    local event = model.events[name]
    for _, key in ipairs(event.keys or {}) do
      event_keys[key] = event_keys[key] or {}
      table.insert(event_keys[key], name)
    end
  end

  local keys = {}
  for _, k in ipairs(model.inventory.keys) do
    keys[k] = true
  end
  for _, k in ipairs(model.inventory.other_keys) do
    keys[k] = true
  end
  local total = 0
  for _, key in ipairs(sorted_keys(keys)) do
    total = total + 1
    local covered = false
    for _, name in ipairs(event_keys[key] or {}) do
      if event_has_transition(name) then
        covered = true
        break
      end
    end
    if not covered then
      table.insert(result.missing_keys, key)
    end
  end
  result.counts.keys = total
  result.counts.keys_covered = total - #result.missing_keys

  local out_of_scope_events = {}
  for _, entry in ipairs(model.inventory.events) do
    if entry.out_of_scope then
      out_of_scope_events[entry.id] = true
    elseif entry.covered_by then
      local ok = true
      for _, name in ipairs(entry.covered_by) do
        if not model.events[name] or not event_has_transition(name) then
          ok = false
          break
        end
      end
      if not ok then
        table.insert(result.missing_events, entry.id)
      end
    else
      table.insert(result.missing_events, entry.id)
    end
  end
  result.counts.events = #model.inventory.events
  result.counts.events_out = 0
  for _ in pairs(out_of_scope_events) do
    result.counts.events_out = result.counts.events_out + 1
  end
  result.counts.events_covered = result.counts.events - #result.missing_events - result.counts.events_out
  return result
end

-- ---------------------------------------------------------------------------
-- 到達性（BFS）
--
-- 現実には設定で分かれるので、keepState の両方で BFS し、どちらかで届く状態を
-- 「届く」とする。経路は反例を出すために覚える。

local function bfs(config)
  local seen = {}
  local parent = {}
  local queue = {}
  for _, s in ipairs(model.initial) do
    seen[s] = true
    queue[#queue + 1] = s
  end
  local head = 1
  while head <= #queue do
    local state = queue[head]
    head = head + 1
    for _, t in ipairs(by_from[state] or {}) do
      if guard_ok(t, config) and not seen[t.to] then
        seen[t.to] = true
        parent[t.to] = { state = state, transition = t }
        queue[#queue + 1] = t.to
      end
    end
  end
  return seen, parent
end

-- 状態から初期状態までさかのぼって、イベント列を作る
local function trail_to(state, parent)
  local trail = {}
  local cur = state
  while parent[cur] do
    table.insert(trail, 1, parent[cur].transition.id)
    cur = parent[cur].state
  end
  return trail
end

local function reachability()
  local reachable = {}
  local parent = {}
  for _, keep in ipairs({ false, true }) do
    local config = copy(model.config)
    config.keepState = keep
    local seen, par = bfs(config)
    for state in pairs(seen) do
      reachable[state] = true
      if not parent[state] and par[state] then
        parent[state] = par[state]
      end
    end
  end
  local unreachable = {}
  for _, name in ipairs(state_names) do
    if not reachable[name] then
      table.insert(unreachable, name)
    end
  end
  return reachable, unreachable, parent
end

-- ---------------------------------------------------------------------------
-- 性質

local function effect_set(t)
  local set = {}
  for _, e in ipairs(t.effects) do
    set[e] = (set[e] or 0) + 1
  end
  return set
end

local READING = { romaji = true, point = true, henkan = true }

-- P1: 読みが黙って消えない。読みを持っていた状態から、確定・取消の効果なしに
-- 読みが無い状態へ移る遷移を違反とする
local function check_no_silent_loss()
  local out = {}
  for _, t in ipairs(model.transitions) do
    local from = model.states[t.from]
    local to = model.states[t.to]
    if READING[from.reading] and to.reading == "none" then
      local set = effect_set(t)
      local kept = set.commit_reading or set.commit_candidate or set.cancel or set.keep
      if set.drop and not kept then
        table.insert(out, { transition = t.id, detail = "drop だけで読みが無くなっている" })
      end
    end
  end
  return out
end

-- P3: normal / visual / select / R では、状態とマッピングが元に戻っている
local function check_return_to_normal()
  local out = {}
  local off = { N_OFF = true, I_OFF = true, R_OFF = true }
  for _, t in ipairs(model.transitions) do
    local from = model.states[t.from]
    if off[t.to] and from.enabled then
      local set = effect_set(t)
      if not (set.reset_state and set.restore_mapping) then
        table.insert(out, {
          transition = t.id,
          detail = ("%s へ戻るのに reset_state / restore_mapping が揃っていない"):format(t.to),
        })
      end
    end
  end
  return out
end

-- P5 / P10: 1 つのキーで二重に処理しない・同じ読みを 2 度確定しない
local function check_double_commit()
  local out = {}
  for _, t in ipairs(model.transitions) do
    local set = effect_set(t)
    for effect, count in pairs(set) do
      if count > 1 and effect ~= nil then
        table.insert(out, { transition = t.id, detail = ("効果 %s が %d 回"):format(effect, count) })
      end
    end
    if set.commit_reading and set.commit_candidate then
      table.insert(out, { transition = t.id, detail = "commit_reading と commit_candidate が同じ遷移にある" })
    end
  end
  return out
end

-- P13: 遷移の途中の状態が、必ず先へ進める
local function check_transient_progress()
  local out = {}
  for _, name in ipairs(state_names) do
    local st = model.states[name]
    if st.transient and #(by_from[name] or {}) == 0 then
      table.insert(out, { transition = "-", detail = ("途中の状態 %s から出る遷移が無い"):format(name) })
    end
  end
  return out
end

-- P14: terminal でジョブへ渡すキーは、読みを確定してから渡す（#121）
--
-- pass_key（skk が奪わずにジョブへ渡す）の効果がある遷移で、読みを捨てていて
-- commit_reading / commit_candidate が無いものを違反とする。guard は確定してから
-- キーを流し直すので、この形になる。
local function check_terminal_ctrl_commit()
  local out = {}
  for _, t in ipairs(model.transitions) do
    local from = model.states[t.from]
    local to = model.states[t.to]
    if from.vim_mode == "t" and READING[from.reading] then
      local set = effect_set(t)
      if set.pass_key and to.reading == "none" and not (set.commit_reading or set.commit_candidate) then
        table.insert(out, {
          transition = t.id,
          detail = "terminal でジョブへ渡すのに、読みを確定していない",
        })
      end
    end
  end
  return out
end

-- P4: terminal の t → nt → t で、読みと pre-edit が保たれる（#74）
--
-- t の pre-edit は端末の行に本物の文字として書くので、t → nt で読みを消すと
-- 状態と端末の行が食い違う。nt を経ても読みが同じまま残り、戻ったときに続きから
-- 打てることを見る。
local function check_terminal_normal_keep()
  local out = {}
  for _, t in ipairs(model.transitions) do
    local from = model.states[t.from]
    local to = model.states[t.to]
    if from.vim_mode == "t" and to.vim_mode == "nt" and from.reading ~= "none" and to.reading ~= from.reading then
      table.insert(out, {
        transition = t.id,
        detail = ("t → nt で読み %s が %s になる"):format(from.reading, to.reading),
      })
    end
    if from.vim_mode == "nt" and to.vim_mode == "t" and from.reading ~= "none" and to.reading ~= from.reading then
      table.insert(out, {
        transition = t.id,
        detail = ("nt → t で読み %s が %s になる"):format(from.reading, to.reading),
      })
    end
  end
  return out
end

-- P8: 有効な状態から、必ず無効な状態へ戻れる（enable / disable の往復）
local function check_recoverable(reachable)
  local out = {}
  local reverse = {}
  for _, t in ipairs(model.transitions) do
    reverse[t.to] = reverse[t.to] or {}
    table.insert(reverse[t.to], t.from)
  end
  for _, name in ipairs(state_names) do
    if reachable[name] and model.states[name].enabled then
      local seen = { [name] = true }
      local queue = { name }
      local head, found = 1, false
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
        table.insert(out, { transition = "-", detail = ("%s から無効な状態へ戻れない"):format(name) })
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- 既知の破れ
--
-- 性質の検査で出た違反のうち、issue にしてあるものを M.known に書く。
-- 知らない違反は失敗にする。known の項目が実際の違反と合わなければ「古い」として失敗にする。

local function known_key(property, transition)
  return property .. "\0" .. transition
end

local function apply_known(property, violations)
  local known = {}
  for _, k in ipairs(model.known or {}) do
    if k.property == property then
      known[known_key(k.property, k.transition)] = k
    end
  end
  local fresh, known_hit = {}, {}
  for _, v in ipairs(violations) do
    local k = known[known_key(property, v.transition)]
    if k then
      table.insert(known_hit, { violation = v, known = k })
    else
      table.insert(fresh, v)
    end
  end
  local stale = {}
  for key, k in pairs(known) do
    local hit = false
    for _, h in ipairs(known_hit) do
      if h.known == k then
        hit = true
        break
      end
    end
    if not hit then
      table.insert(stale, k)
      known[key] = nil
    end
  end
  return fresh, known_hit, stale
end

-- ---------------------------------------------------------------------------
-- 反例のイベント列
--
-- 遷移 id の列を、そのまま読める形（イベント名と from→to）にする
local function trail_text(trail)
  local parts = {}
  for _, id in ipairs(trail) do
    for _, t in ipairs(model.transitions) do
      if t.id == id then
        table.insert(parts, ("%s[%s→%s]"):format(t.event, t.from, t.to))
        break
      end
    end
  end
  return table.concat(parts, " ⇒ ")
end

-- ---------------------------------------------------------------------------
-- 観測と NOTES の再生

local function replay_observation(obs, verbose)
  local config = copy(model.config)
  for k, v in pairs(obs.config or {}) do
    config[k] = v
  end
  local paths, bad_key = run_keys(obs.keys, config)
  if not paths then
    return false, ("キー %s をモデルで処理できない"):format(bad_key)
  end
  local finals = {}
  for _, path in ipairs(paths) do
    finals[project(path.state)] = true
  end
  local missing = {}
  for _, want in ipairs(obs.expect) do
    if not finals[want] then
      table.insert(missing, want)
    end
  end
  if #missing > 0 then
    local got = sorted_keys(finals)
    return false, ("期待 %s、モデルの終わり %s"):format(table.concat(obs.expect, "/"), table.concat(got, "/")), paths
  end
  if verbose then
    local others = {}
    for _, class in ipairs(sorted_keys(finals)) do
      local used = false
      for _, want in ipairs(obs.expect) do
        if class == want then
          used = true
        end
      end
      if not used then
        table.insert(others, class)
      end
    end
    if #others > 0 then
      return true, ("（モデルは %s も許す）"):format(table.concat(others, "/"))
    end
  end
  return true
end

local function replay_replays()
  local out = {}
  for _, r in ipairs(model.replays) do
    local config = copy(model.config)
    local paths, bad_key = run_keys(r.keys, config)
    if not paths then
      table.insert(out, { replay = r, ok = false, why = ("キー %s を処理できない"):format(bad_key) })
    else
      local finals = {}
      local example
      for _, path in ipairs(paths) do
        local class = project(path.state)
        finals[class] = true
        if r.expect[1] == class then
          example = path
        end
      end
      local ok = true
      for _, want in ipairs(r.expect) do
        if not finals[want] then
          ok = false
        end
      end
      table.insert(out, {
        replay = r,
        ok = ok,
        why = ok and nil or ("期待 %s、モデルの終わり %s"):format(
          table.concat(r.expect, "/"),
          table.concat(sorted_keys(finals), "/")
        ),
        trail = example and trail_text(example.trail) or nil,
      })
    end
  end
  return out
end

-- observed は「その遷移を通った観測」だけを指す。終わりのクラスが合っていても、
-- 再生の経路がその遷移を通らなければ取り違えなので失敗にする（#204 のレビュー 1）。
local function check_observed_paths()
  local observations = {}
  for _, obs in ipairs(model.observations) do
    observations[obs.id] = obs
  end
  local bad = {}
  for _, t in ipairs(model.transitions) do
    for _, oid in ipairs(t.observed or {}) do
      local obs = observations[oid]
      if not obs then
        table.insert(bad, { transition = t.id, observed = oid, why = "M.observations に無い" })
      else
        local config = copy(model.config)
        for k, v in pairs(obs.config or {}) do
          config[k] = v
        end
        local paths, bad_key = run_keys(obs.keys, config)
        if not paths then
          table.insert(bad, {
            transition = t.id,
            observed = oid,
            why = ("キー %s を処理できない"):format(bad_key),
          })
        else
          local hit = false
          for _, path in ipairs(paths) do
            for _, id in ipairs(path.trail) do
              if id == t.id then
                hit = true
                break
              end
            end
            if hit then
              break
            end
          end
          if not hit then
            table.insert(bad, {
              transition = t.id,
              observed = oid,
              why = "再生の経路がその遷移を通らない",
            })
          end
        end
      end
    end
  end
  return bad
end

-- ---------------------------------------------------------------------------
-- 表示

local function mark(ok)
  return ok and "✓" or "✗"
end

local function main(argv)
  local verbose = false
  local only
  local config_args = {}
  local i = 1
  while i <= #argv do
    local arg = argv[i]
    if arg == "--verbose" or arg == "-v" then
      verbose = true
    elseif arg == "--help" or arg == "-h" then
      say([[
使い方: nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua [オプション]

  --verbose        状態の一覧と、分かれる道も出す
  --only <名前>    properties / coverage / observations / replays / reachability だけを流す
  --config k=v     M.config を上書きする（例: --config keepState=true）
]])
      return 0
    elseif arg == "--only" then
      i = i + 1
      only = argv[i]
      local allowed = {
        properties = true,
        coverage = true,
        observations = true,
        replays = true,
        reachability = true,
      }
      if not allowed[only] then
        error("--only は properties / coverage / observations / replays / reachability のどれかです", 0)
      end
    elseif arg == "--config" then
      i = i + 1
      local k, v = (argv[i] or ""):match("^([%w_]+)=(.*)$")
      if not k then
        error("--config は 名前=値 の形で書いてください", 0)
      end
      if v == "true" then
        v = true
      elseif v == "false" then
        v = false
      end
      model.config[k] = v
      config_args[k] = v
    else
      error(("知らない引数です: %s"):format(arg), 0)
    end
    i = i + 1
  end

  local failures = 0
  local function fail(msg)
    failures = failures + 1
    say(("✗ %s"):format(msg))
  end
  local function section(name)
    return only == nil or only == name
  end

  say("== モデル ==")
  say(("issue #%d（親 #%d）: %s"):format(model.issue, model.parent, model.scope))
  say(("状態 %d / イベント %d / 遷移 %d"):format(#state_names, #event_names, #model.transitions))
  local errors = validate()
  for _, e in ipairs(errors) do
    fail(e)
  end

  -- 到達性
  local reachable, unreachable, parent = reachability()
  if section("reachability") then
    say("")
    say("== 到達性 ==")
    for _, name in ipairs(state_names) do
      local st = model.states[name]
      if reachable[name] then
        if verbose then
          say(("✓ %-12s %s（%s）"):format(name, st.label or "", st.class))
        end
      else
        local unknown = st.reachable == "unknown"
        say(("%s %-12s %s%s"):format(unknown and "?" or "✗", name, st.label or "", unknown and "（未観測。届く遷移が無い）" or ""))
        if not unknown then
          fail(("状態 %s に届かない"):format(name))
        end
      end
    end
  end

  -- 網羅
  local cov = coverage()
  if section("coverage") then
    say("")
    say("== 棚卸しの網羅（01 のキー・02 のイベント） ==")
    say(("キー: %d / %d を網羅"):format(cov.counts.keys_covered, cov.counts.keys))
    for _, key in ipairs(cov.missing_keys) do
      fail(("キー %s が遷移にも対象外にも無い"):format(key))
    end
    say(("イベント: %d 件（遷移 %d / 対象外 %d）"):format(
      cov.counts.events,
      cov.counts.events_covered,
      cov.counts.events_out
    ))
    for _, id in ipairs(cov.missing_events) do
      fail(("イベント %s が遷移にも対象外にも無い"):format(id))
    end
  end

  -- 性質
  local property_checks = {
    P1 = { title = "読みが黙って消えない", run = check_no_silent_loss },
    P3 = { title = "n / v / s / R では状態とマッピングが元に戻っている", run = check_return_to_normal },
    P4 = { title = "terminal の t → nt → t で読みと pre-edit が保たれる", run = check_terminal_normal_keep },
    P5 = { title = "1 つのキーを二重に処理しない", run = check_double_commit },
    P10 = { title = "同じ読みを 2 度確定しない", run = check_double_commit },
    P13 = { title = "pending（途中の状態）が片付く", run = check_transient_progress },
    P14 = { title = "terminal の Ctrl は確定してからジョブへ渡す", run = check_terminal_ctrl_commit },
    P8 = {
      title = "enable のあと disable すると元に戻る（戻れる）",
      run = function()
        return check_recoverable(reachable)
      end,
    },
  }
  local known_hits = 0
  local fresh = 0
  if section("properties") then
    say("")
    say("== 性質 ==")
    for _, id in ipairs({ "P1", "P3", "P4", "P5", "P10", "P13", "P14", "P8" }) do
      local check = property_checks[id]
      local violations = check.run()
      local unknown, hits, stale = apply_known(id, violations)
      for _, s in ipairs(stale) do
        fail(("%s の known が古い: %s"):format(id, s.transition))
      end
      if #violations == 0 then
        say(("✓ %s %s"):format(id, check.title))
      else
        say(("%s %s %s（%d 件。既知 %d / 知らない %d）"):format(
          (check == nil or #unknown == 0) and "✓" or "✗",
          id,
          check.title,
          #violations,
          #hits,
          #unknown
        ))
        for _, h in ipairs(hits) do
          known_hits = known_hits + 1
          say(("  △ %s: %s（%s）"):format(
            h.violation.transition,
            h.violation.detail,
            table.concat(h.known.refs or {}, ", ")
          ))
        end
        for _, v in ipairs(unknown) do
          fresh = fresh + 1
          fail(("%s の知らない違反 %s: %s"):format(id, v.transition, v.detail))
        end
      end
    end
    -- 決めていない性質
    say("")
    say("== このモデルでは決めない性質 ==")
    for _, p in ipairs(model.properties or {}) do
      if not p.decided then
        say(("－ %s %s: %s"):format(p.id, p.title, p.why or ""))
      end
    end
  end

  -- 観測の再生
  if section("observations") then
    say("")
    say("== 観測の再生（モデルが同じ状態クラスに届くか） ==")
    local ok_count, ng_count, loose = 0, 0, 0
    for _, obs in ipairs(model.observations) do
      local ok, why = replay_observation(obs, verbose)
      if ok then
        ok_count = ok_count + 1
        if obs.uncertain then
          loose = loose + 1
        end
        if verbose then
          say(("✓ %-24s %s%s"):format(obs.id, table.concat(obs.expect, "/"), why and (" " .. why) or ""))
        end
      else
        ng_count = ng_count + 1
        if obs.uncertain then
          say(("? %-24s %s（未確定の観測）"):format(obs.id, why))
        else
          fail(("観測 %s: %s"):format(obs.id, why))
        end
      end
    end
    say(("観測 %d 件: 一致 %d（うち未確定 %d）/ 不一致 %d"):format(
      #model.observations,
      ok_count,
      loose,
      ng_count
    ))
    for _, b in ipairs(check_observed_paths()) do
      fail(("observed の取り違え %s ← %s: %s"):format(b.transition, b.observed, b.why))
    end
  end

  -- NOTES の再現
  if section("replays") then
    say("")
    say("== NOTES の再現キー列の再生 ==")
    local results = replay_replays()
    local ok_count = 0
    for _, r in ipairs(results) do
      if r.ok then
        ok_count = ok_count + 1
        say(("✓ %-20s %s → %s"):format(r.replay.id, r.replay.title, table.concat(r.replay.expect, "/")))
        if r.trail and verbose then
          say(("    %s"):format(r.trail))
        end
      else
        fail(("%s %s: %s"):format(r.replay.id, r.replay.title, r.why or ""))
      end
    end
    say(("再現 %d 本中 %d 本がモデルで再生できた"):format(#results, ok_count))
  end

  -- 分かれる道（条件を guard で書けていない組）
  local split = {}
  local split_count = 0
  for _, from in ipairs(state_names) do
    local seen = {}
    for _, t in ipairs(by_from[from] or {}) do
      if not seen[t.event] then
        seen[t.event] = {}
      end
      table.insert(seen[t.event], t)
    end
    for event, list in pairs(seen) do
      if #list > 1 then
        split_count = split_count + 1
        table.insert(split, { from = from, event = event, list = list })
      end
    end
  end
  if verbose or only == nil then
    say("")
    say(("== 同じ状態・イベントで分かれる組: %d =="):format(split_count))
    say("（辞書に候補があるか、バッファに文字があるかなど、状態クラスに持っていない条件で分かれる）")
    if verbose then
      for _, s in ipairs(split) do
        local targets = {}
        for _, t in ipairs(s.list) do
          table.insert(targets, t.to)
        end
        say(("  %s --%s--> %s"):format(s.from, s.event, table.concat(targets, " / ")))
      end
    end
  end

  say("")
  io.stdout:flush()
  if failures == 0 then
    say(("== まとめ: 失敗 0（既知の破れ %d 件、分かれる組 %d 件） =="):format(known_hits, split_count))
    io.stdout:flush()
    return 0
  end
  say(("== まとめ: 失敗 %d ==（知らない破れ %d、既知の破れ %d）"):format(failures, fresh, known_hits))
  io.stdout:flush()
  return 1
end

M.main = main

-- nvim -l からも、ほかの Lua から dofile しても動くようにする
if arg and arg[0] and arg[0]:match("model_check%.lua$") then
  local ok, code = pcall(main, arg)
  if not ok then
    say(("✗ 検査器が落ちました: %s"):format(tostring(code)))
    os.exit(2)
  end
  os.exit(code)
end

return M

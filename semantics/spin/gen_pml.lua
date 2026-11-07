-- Promela のモデル（model.pml）を semantics/model/model.lua から作る（#193、親は #179）
--
-- model.lua がモデルの唯一のデータ源で、このスクリプトはそれを Promela に写すだけ。
-- 状態・イベント・遷移の数が model.lua と合わなければ止める。
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/spin/gen_pml.lua
--
-- できるもの: semantics/spin/model.pml
--
-- guard は model.lua の 等号・in だけを読む。状態クラスの事実（reading / enabled）は
-- from の状態で決まるので、ここで真偽を決めて Promela の式にする。
-- config.keepState だけは Promela の変数 keep_state にする（SPIN が両方の設定を探索する）。

local M = {}

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local model = dofile(dir .. "/../model/model.lua")

-- model.lua の今の数を固定しておく。変わったら、この検査の前提も見直す
local EXPECTED = { states = 19, events = 56, transitions = 238 }

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function fail(message)
  io.stderr:write("✗ " .. message .. "\n")
  os.exit(1)
end

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

local states = sorted_keys(model.states)
local events = sorted_keys(model.events)

if #states ~= EXPECTED.states then
  fail(("状態の数が %d（model.lua は %d）"):format(#states, EXPECTED.states))
end
if #events ~= EXPECTED.events then
  fail(("イベントの数が %d（model.lua は %d）"):format(#events, EXPECTED.events))
end
if #model.transitions ~= EXPECTED.transitions then
  fail(("遷移の数が %d（model.lua は %d）"):format(#model.transitions, EXPECTED.transitions))
end

local event_used = {}
for _, t in ipairs(model.transitions) do
  if not model.events[t.event] then
    fail(("知らないイベント: %s（%s）"):format(t.event, t.id))
  end
  event_used[t.event] = (event_used[t.event] or 0) + 1
end
for _, name in ipairs(events) do
  if not event_used[name] then
    fail(("遷移の無いイベント: %s"):format(name))
  end
end

-- GLOSSARY の効果の語彙。model_check.lua と同じ並び
local EFFECTS = {
  "commit_reading", "commit_candidate", "cancel", "drop", "keep", "reset_state",
  "restore_mapping", "install_mapping", "save_mapping", "clear_extmark",
  "clean_cmdline", "render", "feed_key", "pass_key",
}
local effect_known = {}
for _, name in ipairs(EFFECTS) do
  effect_known[name] = true
end

local reading_value = {
  none = 0,
  romaji = 1,
  point = 2,
  henkan = 3,
  any = 4,
}

-- guard の 1 つの文を、いまの from の状態で真偽に決める。
-- config.keepState だけは Promela の変数にする。
local function eval_atom(atom, from)
  if atom[1] == "not" then
    return not eval_atom(atom[2], from)
  end
  local var, op, value = atom[1], atom[2], atom[3]
  if var == "config.keepState" then
    if op ~= "=" then
      fail(("config.keepState の演算子が = でない: %s"):format(tostring(op)))
    end
    return value
  end
  local actual = from[var]
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
  fail(("知らない guard の演算子: %s"):format(tostring(op)))
end

-- SPIN に渡す guard の式。from は状態の事実なので、偽なら 0（実行しない）にする
local function guard_expr(t)
  local from = model.states[t.from]
  local terms = { "state == " .. t.from }
  for _, atom in ipairs(t.guard or {}) do
    if atom[1] == "not" then
      if not eval_atom(atom, from) then
        terms[#terms + 1] = "0"
      end
    elseif atom[1] == "config.keepState" then
      if atom[2] ~= "=" then
        fail(("%s: config.keepState の演算子が = でない"):format(t.id))
      end
      terms[#terms + 1] = atom[3] and "keep_state" or "!keep_state"
    else
      if not eval_atom(atom, from) then
        terms[#terms + 1] = "0"
      end
    end
  end
  return table.concat(terms, " && ")
end

local function effect_counts(t)
  local counts = {}
  for _, name in ipairs(t.effects) do
    if not effect_known[name] then
      fail(("%s: GLOSSARY に無い効果 %s"):format(t.id, name))
    end
    counts[name] = (counts[name] or 0) + 1
  end
  return counts
end

local function has_duplicate(counts)
  for _, n in pairs(counts) do
    if n > 1 then
      return true
    end
  end
  return false
end

local function reading_of(name)
  local st = model.states[name]
  if not st then
    fail(("知らない状態: %s"):format(name))
  end
  local value = reading_value[st.reading or "none"]
  if value == nil then
    fail(("%s: 知らない reading %s"):format(name, tostring(st.reading)))
  end
  return value
end

local function enabled_of(name)
  return model.states[name].enabled == true
end

local out = {}
local function w(line)
  out[#out + 1] = line
end

w("/*")
w(" * skkeleton.nvim の状態機械（#193、親は #179）")
w(" *")
w(" * これは semantics/model/model.lua を Promela に写したもの。手で直さない。")
w(" * 作り直すとき: nvim --headless -u NONE -i NONE -l semantics/spin/gen_pml.lua")
w(" *")
w((" * 状態 %d・イベント %d・遷移 %d。model.lua と同じ数を gen_pml.lua が確かめる。"):format(
  #states,
  #events,
  #model.transitions
))
w(" *")
w(" * 前提:")
w(" * - config.keepState は最初に 0/1 を選び、その実行の間は変えない。SPIN は両方を探索する。")
w(" * - 辞書に候補があるか、バッファに文字があるか、補完のメニューが出ているかは状態クラスに")
w(" *   持っていない。同じ (状態, イベント) で結果が分かれるところは、Promela の")
w(" *   非決定選択として両方の遷移を並べる。これは「分かれる」ことの記録で、望ましさの判断ではない。")
w(" * - autocmd（winleave / bufleave / stale / completion_open など）とキーの割り込み順は、")
w(" *   次にどの遷移を選ぶかで表す。SPIN はそのすべての順番を探索する。")
w(" * - バッファの中身・jumplist・辞書は持たない。状態は有限（状態クラスと keepState だけ）。")
w(" * - c / terminal / 辞書登録の中 / 補完の中の細部は 07a–07d の担当。ここでは入口と出口だけ。")
w(" *")
w(" * 性質は末尾の ltl。P1/P3/P5/P10 は遷移ごとの assert 相当（フラグ）、P13 は liveness。")
w(" * P2/P4/P6/P7/P9/P11/P12/P14/P15 は、このモデルが持っていない層が要るので検査しない。")
w(" */")
w("")
w("mtype = { " .. table.concat(states, ", ") .. " };")
w("")
w("mtype state = N_OFF;")
w("bool keep_state = false;")
w("byte last = 0;")
w("")
w("/* 直前の遷移の、from の事実と to の reading */")
w("byte old_reading = 0;")
w("bool old_enabled = false;")
w("byte to_reading = 0;")
w("bool duplicate_effect = false;")
w("")
w("/* 効果のフラグ（遷移ごとに reset_effects で戻す） */")
for _, name in ipairs(EFFECTS) do
  w(("bool eff_%s = false;"):format(name))
end
w("")
w("/* 性質のフラグ。false になったら、その性質は破れている */")
w("bool p1_ok = true;")
w("bool p3_ok = true;")
w("bool p5_ok = true;")
w("bool p10_ok = true;")
w("")
w("inline reset_effects() {")
for _, name in ipairs(EFFECTS) do
  w(("  eff_%s = false;"):format(name))
end
w("}")
w("")
w("inline check_properties() {")
w("  /* P1: 読みが黙って消えない。確定・取消・keep の効果なしに reading が none へ移らない */")
w("  if")
w("  :: (old_reading != 0) && (to_reading == 0) &&")
w("     !(eff_commit_reading || eff_commit_candidate || eff_cancel || eff_keep) ->")
w("     p1_ok = false")
w("  :: else -> skip")
w("  fi;")
w("  /* P3: n / v / s / R へ戻るときは reset_state と restore_mapping が揃っている */")
w("  if")
w("  :: old_enabled && (state == N_OFF || state == I_OFF || state == R_OFF) &&")
w("     !(eff_reset_state && eff_restore_mapping) ->")
w("     p3_ok = false")
w("  :: else -> skip")
w("  fi;")
w("  /* P5 / P10: 同じ効果を 2 度、または読みと候補を同じ遷移で確定しない */")
w("  if")
w("  :: duplicate_effect ->")
w("     p5_ok = false; p10_ok = false")
w("  :: else -> skip")
w("  fi;")
w("  if")
w("  :: eff_commit_reading && eff_commit_candidate ->")
w("     p5_ok = false; p10_ok = false")
w("  :: else -> skip")
w("  fi")
w("}")
w("")
w("active proctype skk() {")
w("  /* 設定は実行の初めに 1 つ選ぶ。SPIN は両方の実行を調べる */")
w("  atomic {")
w("    if")
w("    :: keep_state = false")
w("    :: keep_state = true")
w("    fi")
w("  }")
w("  do")

for index, t in ipairs(model.transitions) do
  local counts = effect_counts(t)
  local from = model.states[t.from]
  local to = model.states[t.to]
  local reading = reading_of(t.to)
  w("")
  w(("  /* TRANS %s event=%s from=%s to=%s */"):format(t.id, t.event, t.from, t.to))
  w(("  :: (%s) ->"):format(guard_expr(t)))
  w("      atomic {")
  w(("        last = %d;"):format(index))
  w(("        old_reading = %d;"):format(reading_of(t.from)))
  w(("        old_enabled = %s;"):format(enabled_of(t.from) and "true" or "false"))
  w(("        to_reading = %d;"):format(reading))
  w(("        duplicate_effect = %s;"):format(has_duplicate(counts) and "true" or "false"))
  w("        reset_effects();")
  for _, name in ipairs(EFFECTS) do
    if counts[name] then
      w(("        eff_%s = true;"):format(name))
    end
  end
  w(("        state = %s;"):format(t.to))
  w("        check_properties();")
  w("        printf(\"TRANS %d\\n\", last);")
  w("      }")
end

w("  od")
w("}")
w("")
w("/* P13: 途中の状態（transient）から必ず出られる */")
w("#define TRANSIENT(s) (((s) == I_ESCAPE) || ((s) == N_WAIT) || ((s) == R_MID))")
w("")
w("ltl p1 { [] (p1_ok) }")
w("ltl p3 { [] (p3_ok) }")
w("ltl p5 { [] (p5_ok) }")
w("ltl p10 { [] (p10_ok) }")
w("ltl p13 { [] (TRANSIENT(state) -> <> (!TRANSIENT(state))) }")
w("")

local text = table.concat(out, "\n")
local path = dir .. "/model.pml"
local file = assert(io.open(path, "w"))
file:write(text)
file:close()

-- 書いたファイルを読み直して、状態・イベント・遷移の名前と数が model.lua と合うか確かめる
local reread = assert(io.open(path, "r")):read("*a")
local pml_states = {}
local mtype = reread:match("mtype = { ([^}]+) };")
if not mtype then
  fail("model.pml に mtype の一覧が無い")
end
for name in mtype:gmatch("[^,%s]+") do
  pml_states[name] = true
end
local pml_events = {}
local pml_transitions = 0
for line in reread:gmatch("[^\n]+") do
  local id, event = line:match("/%* TRANS (%S+) event=(%S+) ")
  if id and event then
    pml_transitions = pml_transitions + 1
    pml_events[event] = true
  end
end
if count(pml_states) ~= #states then
  fail(("model.pml の状態が %d 個（model.lua は %d）"):format(count(pml_states), #states))
end
if count(pml_events) ~= #events then
  fail(("model.pml のイベントが %d 個（model.lua は %d）"):format(count(pml_events), #events))
end
if pml_transitions ~= #model.transitions then
  fail(("model.pml の遷移が %d 個（model.lua は %d）"):format(pml_transitions, #model.transitions))
end
for _, name in ipairs(states) do
  if not pml_states[name] then
    fail(("model.pml に状態 %s が無い"):format(name))
  end
end
for _, name in ipairs(events) do
  if not pml_events[name] then
    fail(("model.pml にイベント %s が無い"):format(name))
  end
end

print(("モデルを書きました: %s（状態 %d、イベント %d、遷移 %d）"):format(
  path,
  count(pml_states),
  count(pml_events),
  pml_transitions
))

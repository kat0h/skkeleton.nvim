-- モデルと観測の差を出す（#186、親は #179）
--
-- semantics/compare/probe.lua が書いた観測（JSONL）と、semantics/model/model.lua を比べ、
-- 差を次の 4 種類に分ける。
--
--   model-only  モデルにだけある遷移（観測で確かめられなかったもの）
--   observed-only 観測にだけある遷移（モデルに無いもの）
--   effects     遷移の結果（effects・終わりの状態）が食い違うもの
--   非決定      同じ状態・同じイベントで結果が分かれるもの（モデルの中では 25 組）
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/compare/compare.lua
--   nvim --headless -u NONE -i NONE -l semantics/compare/compare.lua --probe <path> --out <path>
--
-- `--out` を付けると、差の表を Markdown で書く（semantics/compare/diff.md）。
-- 説明の付かない observed-only があれば終了コード 1。
local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local root = dir .. "/../.."
local model = dofile(dir .. "/../model/model.lua")

local M = {}

local function say(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  io.write(table.concat(parts), "\n")
end

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function class_of(state_name)
  local st = model.states[state_name]
  return st and st.class or state_name
end

-- 観測の値を 1 つずつ比べる（nil を JSON で落とさないため）
local function same(a, b)
  return a == b
end

-- ---------------------------------------------------------------------------
-- モデルの索引

local by_from = {}
local by_id = {}
for _, t in ipairs(model.transitions) do
  by_from[t.from] = by_from[t.from] or {}
  table.insert(by_from[t.from], t)
  by_id[t.id] = t
end

-- イベントが持ちうるキー（models.events[].keys）。観測のキーを引くのに使う
local keys_of_event = {}
for name, ev in pairs(model.events) do
  keys_of_event[name] = {}
  for _, k in ipairs(ev.keys or {}) do
    keys_of_event[name][k] = true
  end
end

-- (状態, キー) -> 遷移の一覧
local key_index = {}
for _, t in ipairs(model.transitions) do
  for k in pairs(keys_of_event[t.event] or {}) do
    key_index[t.from .. "\0" .. k] = key_index[t.from .. "\0" .. k] or {}
    table.insert(key_index[t.from .. "\0" .. k], t)
  end
end

-- 人が読むクラスごとの (クラス, キー) -> 遷移先クラス
local class_key_index = {}

local function add_class_key(class, key, target)
  class_key_index[class] = class_key_index[class] or {}
  class_key_index[class][key] = class_key_index[class][key] or {}
  class_key_index[class][key][target] = true
end

-- 遷移の終わり先（internal を進めたあと）のクラス
local function eval_atom(atom, state_name, config)
  if atom[1] == "not" then
    return not eval_atom(atom[2], state_name, config)
  end
  local var, op, value = atom[1], atom[2], atom[3]
  local prefix, name = var:match("^([%w_]+)%.(.+)$")
  local actual
  if prefix == "config" then
    actual = config[name]
  else
    actual = model.states[state_name][var]
  end
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
  return false
end

local function guard_ok(t, config)
  for _, atom in ipairs(t.guard or {}) do
    if not eval_atom(atom, t.from, config) then
      return false
    end
  end
  return true
end

-- internal の片付けを最後まで進める（probe.lua と同じ）
local function settle(state_name, config)
  local out = {}
  local queue = { state_name }
  local seen = {}
  local count = 0
  while #queue > 0 do
    count = count + 1
    if count > 200 then
      break
    end
    local next_queue = {}
    for _, s in ipairs(queue) do
      if seen[s] then
        goto continue
      end
      seen[s] = true
      local advanced = false
      for _, t in ipairs(by_from[s] or {}) do
        if model.events[t.event].kind == "internal" and guard_ok(t, config) then
          advanced = true
          table.insert(next_queue, t.to)
        end
      end
      if not advanced then
        table.insert(out, s)
      end
      ::continue::
    end
    queue = next_queue
  end
  return out
end

local function configs()
  local out = {}
  for _, keep in ipairs({ false, true }) do
    local c = { keepState = keep }
    for k, v in pairs(model.config) do
      c[k] = v
    end
    c.keepState = keep
    out[#out + 1] = c
  end
  return out
end

-- 到達性（model_check.lua と同じ BFS）。keepState の両方で BFS し、
-- どちらかで届く状態を「届く」とする。model.states[].reachable は一部の
-- 状態にしか無いので、理由の判定には使わない。
local function reachable_states()
  local reachable = {}
  for _, config in ipairs(configs()) do
    local seen = {}
    local queue = {}
    for _, s in ipairs(model.initial) do
      if not seen[s] then
        seen[s] = true
        queue[#queue + 1] = s
      end
    end
    local head = 1
    while head <= #queue do
      local state = queue[head]
      head = head + 1
      for _, t in ipairs(by_from[state] or {}) do
        if guard_ok(t, config) and not seen[t.to] then
          seen[t.to] = true
          queue[#queue + 1] = t.to
        end
      end
    end
    for s in pairs(seen) do
      reachable[s] = true
    end
  end
  return reachable
end

-- 遷移の終わり先が、観測で見えるクラスになるか（probe.lua と同じ）
---@param t table
---@param config table
---@return string[]
local function expected_classes(t, config)
  local out = {}
  for _, s in ipairs(settle(t.to, config)) do
    out[class_of(s)] = true
  end
  local list = {}
  for c in pairs(out) do
    list[#list + 1] = c
  end
  table.sort(list)
  return list
end

local function config_of(p)
  local c = { keepState = false }
  for k, v in pairs(model.config) do
    c[k] = v
  end
  if p.world == "keepstate" then
    c.keepState = true
  end
  return c
end

-- クラスの索引を作る（keepState の両方で）
for _, config in ipairs(configs()) do
  for _, t in ipairs(model.transitions) do
    if guard_ok(t, config) then
      for k in pairs(keys_of_event[t.event] or {}) do
        local from_class = class_of(t.from)
        for _, settled in ipairs(settle(t.to, config)) do
          add_class_key(from_class, k, class_of(settled))
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- 観測を読む

---@param path string
---@return table[]
local function read_jsonl(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  for line in f:lines() do
    if line ~= "" then
      local ok, rec = pcall(vim.json.decode, line)
      if ok then
        out[#out + 1] = rec
      end
    end
  end
  f:close()
  return out
end

-- ---------------------------------------------------------------------------
-- 比較

-- 観測が「何か起きた」か（自己ループと区別する）
local function changed(p)
  local a = p.after_prefix or {}
  local b = p.after or {}
  if (a.class or "") ~= (b.class or "") then
    return true
  end
  if not same(a.enabled, b.enabled) then
    return true
  end
  if not same(a.preedit, b.preedit) then
    return true
  end
  if not same(a.henkan_feed, b.henkan_feed) then
    return true
  end
  if not same(a.buffer, b.buffer) then
    return true
  end
  if not same(a.register_depth, b.register_depth) then
    return true
  end
  if not same(a.cmdline_type, b.cmdline_type) then
    return true
  end
  if not same(a.popup_shown, b.popup_shown) then
    return true
  end
  return false
end

-- observed-only の説明を付ける。説明が付かなければ nil を返す（完了の条件に反する）
--
-- ここで言う「説明」は、モデルがその遷移を書いていない理由です。理由は
-- (1) 別のタスクの担当（cmdline・terminal・辞書登録・補完・マクロ・その他の入力）、
-- (2) モデルの境界（skk が無効なときの Vim のキー処理、niI の normal コマンド、
--     visual の Vim のコマンド）、(3) モデルのキーの一覧が代表だけ、のどれかです。
---@param p table
---@return string?
local function explain_observed_only(p)
  local from = p.after_prefix and p.after_prefix.class or "?"
  local to = p.after and p.after.class or "?"
  local key = p.keys or ""

  -- 07a cmdline
  if to == "C_DIRECT" or to == "C_POINT" or to == "C_REPLACE" then
    return "cmdline の中（07a #187）"
  end
  if from == "C_DIRECT" or from == "C_POINT" or from == "C_REPLACE" then
    return "cmdline の中（07a #187）"
  end
  if key:sub(1, 6) == "<C-o>:" then
    return "cmdline の中（07a #187）"
  end
  -- 07b terminal
  if to:match("^T_") or from:match("^T_") then
    return "terminal（07b #188）"
  end
  -- 07c 辞書登録
  if to == "P_PROMPT" or from == "P_PROMPT" then
    return "辞書登録のプロンプトの中（07c #189）"
  end
  -- 07d 補完
  if to == "IC" or from == "IC" then
    return "組み込みの補完の中（07d #190）"
  end
  -- 07e 貼り付け・マウス・ホイール
  if key == "<Paste>" or key == "<LeftMouse>" or key == "<RightMouse>" or key:match("Wheel") then
    return "貼り付け・マウス・ホイール（07e #191）"
  end
  -- 07f マクロと `.`
  if key == "." then
    return "マクロと `.` の繰り返し（07f #192）"
  end

  -- キーを打った結果、何も変わらない自己ループ。モデルは同じ形を一部だけ書いている
  if not changed(p) then
    return "モデルに無い自己遷移（観測では何も変わらない）"
  end

  -- モデルの境界 1: skk が無効な insert / replace。キーは Vim が処理する
  if from == "I_OFF" or from == "R_OFF" then
    if key == "<C-c>" then
      return "Vim の <C-c>（insert / replace を抜けて normal に戻る）。無効なのでモデルに無い"
    end
    if key == "<C-o>" or key == "<C-o>v" or key == "<C-o>R" then
      return "Vim のモード遷移（無効な insert / replace から <C-o> で niI・visual・replace へ）。モデルは無効な状態からのモード遷移を書いていない"
    end
    return "skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない）"
  end

  -- モデルの境界 2: niI（<C-o>）の normal コマンド
  if from == "NI" then
    if key == "<C-c>" then
      return "Vim の <C-c>（niI から normal に戻る）"
    end
    return "niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ"
  end

  -- モデルの境界 3: visual / select の Vim のコマンド
  if from == "V_PRE" or from == "V_IDLE" then
    if key == "<C-c>" then
      return "Vim の <C-c>（visual から normal に戻る）"
    end
    return "visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている"
  end

  -- モデルの境界 4: normal の Vim のコマンド
  if from == "N_OFF" then
    return "normal の Vim のコマンド。モデルは insert に入る道と <Insert>・R だけを書いている"
  end

  return nil
end

-- effects の食い違いを見る。遷移の効果から、観測で見えるはずのことを作る
---@param p table
---@param t table
---@return table[]
local function check_effects(p, t)
  local out = {}
  local before = p.after_prefix or {}
  local after = p.after or {}
  local settled = settle(t.to, { keepState = (p.world == "keepstate") })
  local target_states = {}
  for _, s in ipairs(settled) do
    target_states[model.states[s].enabled] = model.states[s]
  end

  -- 有効・無効
  local want_enabled
  for _, s in ipairs(settled) do
    if model.states[s].class == after.class then
      want_enabled = model.states[s].enabled
    end
  end
  if want_enabled ~= nil and after.enabled ~= nil and want_enabled ~= after.enabled then
    table.insert(out, ("enabled が %s（モデル %s）"):format(tostring(after.enabled), tostring(want_enabled)))
  end

  -- 読みの確定・取り消し・破棄
  local set = {}
  for _, e in ipairs(t.effects) do
    set[e] = true
  end
  local reading = before.henkan_feed or ""
  if set.commit_reading and reading ~= "" then
    -- かなモードの切替（q / L / <C-q>）は converter を通すので、読みと違う文字が入る。
    -- バッファが変わったかだけを見る。
    if not (after.buffer or ""):find(reading, 1, true) and (after.buffer or "") == (before.buffer or "") then
      table.insert(out, ("commit_reading なのにバッファが変わっていない（読み %q）"):format(reading))
    end
  end
  if set.commit_candidate and not set.feed_key then
    local candidate = before.preedit or ""
    if candidate ~= "" and not (after.buffer or ""):find(candidate, 1, true) then
      -- 候補の表記は preedit と違うことがあるので、バッファが変わったかだけを見る
      if (before.buffer or "") == (after.buffer or "") then
        table.insert(out, "commit_candidate なのにバッファが変わっていない")
      end
    end
  end
  if set.drop and not (set.commit_reading or set.commit_candidate or set.cancel or set.keep) then
    if reading ~= "" and (after.buffer or ""):find(reading, 1, true) then
      table.insert(out, ("drop なのにバッファに %q がある"):format(reading))
    end
  end
  -- pre-edit の有無（終わりの状態が pre-edit を持つか）
  local target_has_preedit
  for _, s in ipairs(settled) do
    if model.states[s].class == after.class then
      local p2 = model.states[s].preedit
      target_has_preedit = p2 ~= "none" and p2 ~= nil
    end
  end
  -- 補完の中の表示は 07d（#190）の担当なので、ここでは見ない
  if t.to and model.states[t.to] and model.states[t.to].class == "IC" then
    return out
  end
  if target_has_preedit ~= nil then
    local observed_has = (after.preedit or "") ~= "" or (after.mark or "") ~= ""
    if target_has_preedit ~= observed_has then
      table.insert(out, ("pre-edit が %s（モデル %s）"):format(tostring(observed_has), tostring(target_has_preedit)))
    end
  end
  return out
end

-- 非決定の組（同じ状態・イベントで遷移が 2 つ以上）
local function split_pairs()
  local groups = {}
  for _, t in ipairs(model.transitions) do
    local k = t.from .. "\0" .. t.event
    groups[k] = groups[k] or {}
    table.insert(groups[k], t)
  end
  local out = {}
  for _, k in ipairs(sorted_keys(groups)) do
    if #groups[k] > 1 then
      local from, event = k:match("^(.-)%z(.*)$")
      if not from then
        -- Lua の版によっては %z が使えないので、NUL で分ける
        local pos = k:find("\0", 1, true)
        from = k:sub(1, pos - 1)
        event = k:sub(pos + 1)
      end
      out[#out + 1] = { from = from, event = event, list = groups[k] }
    end
  end
  return out
end

-- 分かれる理由（状態クラスに持っていない前提）
local PREMISE = {
  char = "打った文字（かなになるか、ローマ字が続くか）",
  char_shift = "打った文字（1 打でかなになるか、▽ を始めるか）",
  bs = "読みの長さ（1 文字か、2 文字以上か）",
  ctrl_w = "バッファに消す文字があるか",
  ctrl_u = "バッファに消す文字があるか",
  ctrl_a = "前に挿入した文字があるか（バッファの中身）",
  mouse_click = "クリックでカーソルが動くか（クリックした位置）",
  key_x = "候補の位置（最初の候補か、2 つ目以降か）",
  key_X = "候補の位置（最後の候補で登録に入るか）",
  space = "辞書に候補があるか／候補の位置",
  stale = "どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか）",
  insert_enter = "config.keepState",
  esc = "config.keepState",
}

local function premise_of(pair)
  return PREMISE[pair.event] or "その他（要確認）"
end

-- ---------------------------------------------------------------------------
-- 本体

---@param argv string[]
function M.main(argv)
  local probe_path = dir .. "/probe.jsonl"
  local out_path
  local i = 1
  while i <= #argv do
    local arg = argv[i]
    if arg == "--probe" then
      i = i + 1
      probe_path = argv[i]
    elseif arg == "--out" then
      i = i + 1
      out_path = argv[i]
    elseif arg == "--help" or arg == "-h" then
      say([[
使い方: nvim --headless -u NONE -i NONE -l semantics/compare/compare.lua [オプション]

  --probe <path>  観測の JSONL（既定は semantics/compare/probe.jsonl）
  --out <path>    差の表を Markdown で書く
]])
      return 0
    else
      error(("知らない引数です: %s"):format(arg))
    end
    i = i + 1
  end

  local probes = read_jsonl(probe_path)
  if not probes then
    error(("観測を読めません: %s（先に probe.lua を流してください）"):format(probe_path))
  end

  local failures = 0
  local match, mismatch = 0, {}
  local observed_only = {}
  local effect_mismatch = {}
  local blocked = 0
  local blocked_ids = {}
  local unknown_result = {}
  local covered = {}
  local prefix_bad = {}

  for _, p in ipairs(probes) do
    if p.error or p.blocked or p.final_class == "BLOCKED" then
      blocked = blocked + 1
      if p.transition then
        blocked_ids[p.transition] = true
      end
    else
      local state = p.state or p.from
      local from_class = p.prefix_class
      if p.transition then
        covered[p.transition] = true
        local t = by_id[p.transition]
        local expected = t and expected_classes(t, config_of(p)) or p.expect or {}
        local ok = false
        for _, want in ipairs(expected) do
          if want == p.final_class then
            ok = true
          end
        end
        if ok then
          match = match + 1
          local t = by_id[p.transition]
          if t then
            local diffs = check_effects(p, t)
            if #diffs > 0 then
              effect_mismatch[#effect_mismatch + 1] = { probe = p, transition = t, diffs = diffs }
            end
          end
        elseif t and t.status == "unknown" then
          -- モデルが決めていない遷移（前提が状態クラスに無い）。差ではなく「未確定」として出す
          p.expected = expected
          unknown_result[#unknown_result + 1] = p
        else
          p.expected = expected
          mismatch[#mismatch + 1] = p
        end
        if model.states[state] and from_class ~= class_of(state) then
          prefix_bad[#prefix_bad + 1] = p
        end
      else
        -- モデルに遷移が無いキー（または状態クラスの確認用）
        local hit = class_key_index[from_class] and class_key_index[from_class][p.keys]
        if not hit then
          observed_only[#observed_only + 1] = p
        end
      end
    end
  end

  -- 観測にだけある遷移の説明
  local unexplained = {}
  for _, p in ipairs(observed_only) do
    p.explanation = explain_observed_only(p)
    if not p.explanation then
      unexplained[#unexplained + 1] = p
    end
  end

  -- model-only: 観測で確かめられなかった遷移
  local reachable = reachable_states()
  local model_only = {}
  for _, t in ipairs(model.transitions) do
    if not covered[t.id] then
      local ev = model.events[t.event]
      local why
      if ev.kind == "internal" then
        why = "遷移の途中（internal）。キーで観測できない"
      elseif ev.kind == "autocmd" then
        why = "autocmd。キーで観測できない（probe では stale / winleave を打っていない）"
      elseif ev.kind == "input" then
        why = "入力（マウス・貼り付け）。キーで観測できない（07e #191）"
      elseif blocked_ids[t.id] then
        why = "観測できず（BLOCKED）。probe では観測できなかった"
      elseif not reachable[t.from] then
        why = "到達しない状態からの遷移"
      elseif t.from == "I_ESCAPE" or t.from == "N_WAIT" or t.from == "R_MID" then
        why = "遷移の途中の状態からの遷移"
      else
        why = "観測していない"
      end
      model_only[#model_only + 1] = { transition = t, why = why }
    end
  end

  local pairs_ = split_pairs()

  -- 人が読むクラスごとに、内部の状態で結果が割れるか（クラスを分ける根拠）
  local class_split = {}
  local class_states = {}
  for name, st in pairs(model.states) do
    class_states[st.class] = class_states[st.class] or {}
    table.insert(class_states[st.class], name)
  end
  for class, names in pairs(class_states) do
    if #names > 1 then
      table.sort(names)
      local events = {}
      for _, name in ipairs(names) do
        for _, t in ipairs(by_from[name] or {}) do
          events[t.event] = true
        end
      end
      local rows = {}
      for _, event in ipairs(sorted_keys(events)) do
        local targets = {}
        for _, name in ipairs(names) do
          for _, t in ipairs(by_from[name] or {}) do
            if t.event == event then
              for _, s in ipairs(settle(t.to, { keepState = false })) do
                targets[class_of(s)] = true
              end
            end
          end
        end
        if vim.tbl_count(targets) > 1 then
          rows[#rows + 1] = { event = event, targets = sorted_keys(targets) }
        end
      end
      if #rows > 0 then
        local labels = {}
        for _, name in ipairs(names) do
          table.insert(labels, model.states[name].label or name)
        end
        class_split[#class_split + 1] = { class = class, labels = labels, rows = rows }
      end
    end
  end

  -- 表示
  say("== モデルと観測の比較 ==")
  say(("観測 %d 件（一致 %d / 不一致 %d / 観測できず %d）"):format(#probes, match, #mismatch, blocked))
  say("")
  say(("モデルにだけある遷移: %d"):format(#model_only))
  say(("観測にだけある遷移: %d（説明付き %d / 説明なし %d）"):format(
    #observed_only,
    #observed_only - #unexplained,
    #unexplained
  ))
  say(("effects の食い違い: %d"):format(#effect_mismatch))
  say(("未確定（モデルが決めていない遷移）: %d"):format(#unknown_result))
  say(("非決定（同じ状態・イベントで分かれる組）: %d"):format(#pairs_))
  say("")

  if #mismatch > 0 then
    say("-- 終わりの状態がモデルと違う観測 --")
    for _, p in ipairs(mismatch) do
      say(("  %-40s %s --%s--> %s（モデル %s）"):format(
        p.id,
        p.prefix_class,
        p.keys,
        p.final_class,
        table.concat(p.expected or {}, "/")
      ))
    end
    say("")
  end

  if #unknown_result > 0 then
    say("-- 未確定（前提が状態クラスに無く、モデルが決めていない） --")
    for _, p in ipairs(unknown_result) do
      say(("  %-40s %s --%s--> %s（モデル %s）"):format(
        p.id,
        p.prefix_class,
        p.keys,
        p.final_class,
        table.concat(p.expected or {}, "/")
      ))
    end
    say("")
  end

  if #effect_mismatch > 0 then
    say("-- effects の食い違い --")
    for _, row in ipairs(effect_mismatch) do
      say(("  %-40s %s"):format(row.transition.id, table.concat(row.diffs, " / ")))
    end
    say("")
  end

  if #observed_only > 0 then
    say("-- 観測にだけある遷移の内訳 --")
    local by_reason = {}
    for _, p in ipairs(observed_only) do
      local reason = p.explanation or "説明なし"
      by_reason[reason] = (by_reason[reason] or 0) + 1
    end
    local reasons = {}
    for reason in pairs(by_reason) do
      table.insert(reasons, reason)
    end
    table.sort(reasons, function(a, b)
      return by_reason[a] > by_reason[b]
    end)
    for _, reason in ipairs(reasons) do
      say(("  %3d %s"):format(by_reason[reason], reason))
    end
    say("")
    say("-- 観測にだけある遷移 --")
    for _, p in ipairs(observed_only) do
      say(("  %-40s %s --%s--> %s（%s）"):format(
        p.id,
        p.after_prefix and p.after_prefix.class or "?",
        p.keys,
        p.after and p.after.class or "?",
        p.explanation or "説明なし"
      ))
    end
    say("")
  end

  if #pairs_ > 0 then
    say("-- 非決定の組（前提） --")
    for _, pair in ipairs(pairs_) do
      local targets = {}
      for _, t in ipairs(pair.list) do
        table.insert(targets, t.to)
      end
      say(("  %-12s --%-14s--> %-32s %s"):format(
        pair.from,
        pair.event,
        table.concat(targets, " / "),
        premise_of(pair)
      ))
    end
    say("")
  end

  if #class_split > 0 then
    say("-- 人が読むクラスの中で、相によって終わりが割れるイベント --")
    for _, row in ipairs(class_split) do
      say(("  %-10s %s"):format(row.class, table.concat(row.labels, " / ")))
      for _, r in ipairs(row.rows) do
        say(("    --%-14s--> %s"):format(r.event, table.concat(r.targets, " / ")))
      end
    end
    say("")
  end

  if #prefix_bad > 0 then
    say("-- 前置きが狙った状態にならなかった観測 --")
    for _, p in ipairs(prefix_bad) do
      say(("  %-40s %s"):format(p.id, p.prefix_class))
    end
    say("")
  end

  if #unexplained > 0 then
    say("-- 説明の付かない observed-only --")
    for _, p in ipairs(unexplained) do
      say(("  %-40s %s --%s--> %s"):format(
        p.id,
        p.after_prefix and p.after_prefix.class or "?",
        p.keys,
        p.after and p.after.class or "?"
      ))
    end
    failures = failures + #unexplained
  end

  -- Markdown
  if out_path then
    local md = { "# モデルと観測の差（`probe.lua` の結果）", "" }
    md[#md + 1] = ("- 観測: %d 件（一致 %d / 不一致 %d / 観測できず %d）"):format(#probes, match, #mismatch, blocked)
    md[#md + 1] = ("- モデルにだけある遷移: %d"):format(#model_only)
    md[#md + 1] = ("- 観測にだけある遷移: %d（説明付き %d / 説明なし %d）"):format(
      #observed_only,
      #observed_only - #unexplained,
      #unexplained
    )
    md[#md + 1] = ("- effects の食い違い: %d"):format(#effect_mismatch)
    md[#md + 1] = ("- 非決定: %d 組"):format(#pairs_)
    md[#md + 1] = ""

    if #mismatch > 0 then
      md[#md + 1] = "## 終わりの状態がモデルと違う観測"
      md[#md + 1] = ""
      md[#md + 1] = "| 観測 | 前 | キー | 観測の終わり | モデル |"
      md[#md + 1] = "|---|---|---|---|---|"
      for _, p in ipairs(mismatch) do
        md[#md + 1] = ("| `%s` | `%s` | `%s` | `%s` | `%s` |"):format(
          p.id,
          p.prefix_class,
          p.keys,
          p.final_class,
          table.concat(p.expected or {}, "/")
        )
      end
      md[#md + 1] = ""
    end

    if #unknown_result > 0 then
      md[#md + 1] = "## 未確定（モデルが決めていない遷移）"
      md[#md + 1] = ""
      md[#md + 1] = "| 観測 | 前 | キー | 観測の終わり | モデル |"
      md[#md + 1] = "|---|---|---|---|---|"
      for _, p in ipairs(unknown_result) do
        md[#md + 1] = ("| `%s` | `%s` | `%s` | `%s` | `%s` |"):format(
          p.id,
          p.prefix_class,
          p.keys,
          p.final_class,
          table.concat(p.expected or {}, "/")
        )
      end
      md[#md + 1] = ""
    end

    if #effect_mismatch > 0 then
      md[#md + 1] = "## effects の食い違い"
      md[#md + 1] = ""
      md[#md + 1] = "| 遷移 | 観測との違い |"
      md[#md + 1] = "|---|---|"
      for _, row in ipairs(effect_mismatch) do
        md[#md + 1] = ("| `%s` | %s |"):format(row.transition.id, table.concat(row.diffs, " / "))
      end
      md[#md + 1] = ""
    end

    if #observed_only > 0 then
      md[#md + 1] = "## 観測にだけある遷移"
      md[#md + 1] = ""
      md[#md + 1] = "| 観測 | 前 | キー | 後 | 説明 |"
      md[#md + 1] = "|---|---|---|---|---|"
      for _, p in ipairs(observed_only) do
        md[#md + 1] = ("| `%s` | `%s` | `%s` | `%s` | %s |"):format(
          p.id,
          p.after_prefix and p.after_prefix.class or "?",
          p.keys,
          p.after and p.after.class or "?",
          p.explanation or "**説明なし**"
        )
      end
      md[#md + 1] = ""
    end

    if #model_only > 0 then
      md[#md + 1] = "## モデルにだけある遷移"
      md[#md + 1] = ""
      md[#md + 1] = "| 遷移 | 確かめなかった理由 |"
      md[#md + 1] = "|---|---|"
      for _, row in ipairs(model_only) do
        md[#md + 1] = ("| `%s` | %s |"):format(row.transition.id, row.why)
      end
      md[#md + 1] = ""
    end

    md[#md + 1] = "## 非決定の組（同じ状態・イベントで分かれる）"
    md[#md + 1] = ""
    md[#md + 1] = "| 前 | イベント | 遷移先 | 前提（状態クラスに持っていない条件） |"
    md[#md + 1] = "|---|---|---|---|"
    for _, pair in ipairs(pairs_) do
      local targets = {}
      for _, t in ipairs(pair.list) do
        table.insert(targets, t.to)
      end
      md[#md + 1] = ("| `%s` | `%s` | `%s` | %s |"):format(
        pair.from,
        pair.event,
        table.concat(targets, " / "),
        premise_of(pair)
      )
    end
    md[#md + 1] = ""

    if #class_split > 0 then
      md[#md + 1] = "## 人が読むクラスの中で、相によって終わりが割れるイベント"
      md[#md + 1] = ""
      for _, row in ipairs(class_split) do
        md[#md + 1] = ("### `%s`"):format(row.class)
        md[#md + 1] = ""
        md[#md + 1] = "| イベント | 終わり |"
        md[#md + 1] = "|---|---|"
        for _, r in ipairs(row.rows) do
          md[#md + 1] = ("| `%s` | `%s` |"):format(r.event, table.concat(r.targets, " / "))
        end
        md[#md + 1] = ""
      end
    end

    vim.fn.mkdir(vim.fs.dirname(out_path), "p")
    vim.fn.writefile(vim.split(table.concat(md, "\n"), "\n", { plain = true }), out_path)
    say(("差の表: %s"):format(out_path))
  end

  say(("== まとめ: 説明の付かない observed-only %d、効果の食い違い %d、終わりの不一致 %d =="):format(
    #unexplained,
    #effect_mismatch,
    #mismatch
  ))
  io.stdout:flush()
  return failures == 0 and 0 or 1
end

if arg and arg[0] and arg[0]:match("compare%.lua$") then
  local ok, code = pcall(M.main, arg)
  if not ok then
    say(("✗ 比較が落ちました: %s"):format(tostring(code)))
    os.exit(2)
  end
  os.exit(code)
end

return M

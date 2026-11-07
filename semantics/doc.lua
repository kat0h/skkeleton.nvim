-- 人が読む仕様書（semantics/STATE_MACHINE.md）の生成器（#194、親は #179）
--
-- semantics/model/model.lua だけをデータ源にする。モデルは変えない。
-- 出力は時刻や環境に依存させない（生成し直しても差分が出ないこと）。
--
-- 使い方（リポジトリの一番上で）:
--   nvim --headless -u NONE -i NONE -l semantics/doc.lua
--
-- 図（Graphviz）は semantics/figures/gen.lua が別に作る。
--   nvim --headless -u NONE -i NONE -l semantics/figures/gen.lua
--
-- 手置きの図（作者の手元の statediagram の data.js、18 状態・49 遷移）は
-- リポジトリに無い。対応は model.lua の M.sources にあるとおり、状態クラス名と
-- 遷移 id で取る。この文書と図の id は model.lua の class / event / transition id を
-- そのまま使う。

local M = {}

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local model = dofile(dir .. "/model/model.lua")

-- ---------------------------------------------------------------------------
-- 小さな道具

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

local function sorted_keys(t)
  local out = {}
  for k in pairs(t or {}) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function cell(s)
  s = tostring(s or "")
  s = s:gsub("\r", " "):gsub("\n", " ")
  s = s:gsub("|", "\\|")
  return s
end

local function code(s)
  s = tostring(s or "")
  s = s:gsub("|", "\\|")
  return "`" .. s .. "`"
end

local function cap(items, n, sep)
  local out = {}
  for i = 1, math.min(#items, n) do
    out[#out + 1] = items[i]
  end
  if #items > n then
    out[#out + 1] = ("ほか %d"):format(#items - n)
  end
  return table.concat(out, sep or ", ")
end

local function uniq(list)
  local seen, out = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  return out
end

local function ref_sort(a, b)
  local na = tonumber(a:match("^#(%d+)"))
  local nb = tonumber(b:match("^#(%d+)"))
  if na and nb then
    return na < nb
  elseif na then
    return true
  elseif nb then
    return false
  end
  return a < b
end

local function sorted_refs(t)
  local list = sorted_keys(t)
  table.sort(list, ref_sort)
  return list
end

-- ---------------------------------------------------------------------------
-- 状態クラスとモードのまとまり

local CLASS_ORDER = {
  "N_OFF", "N_WAIT", "V_IDLE", "V_PRE",
  "I_OFF", "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT", "I_ESCAPE",
  "NI", "R_OFF",
  "C_DIRECT", "C_POINT", "C_REPLACE",
  "T_DIRECT", "T_POINT", "T_NORMAL",
  "IC", "P_PROMPT",
}

local CLASS_RANK = {}
for i, c in ipairs(CLASS_ORDER) do
  CLASS_RANK[c] = i
end

local GROUPS = {
  {
    id = "normal", title = "normal", classes = { "N_OFF", "N_WAIT" },
    section = "3.1",
    intro = "normal で skk が無効のときと、normal へ移った直後の片付け待ち。"
      .. "insert から `<Esc>` / `<C-c>` / `<Insert>` でここへ出る。",
  },
  {
    id = "visual", title = "visual / select", classes = { "V_IDLE", "V_PRE" },
    section = "3.2",
    intro = "visual / select で skk が有効のまま残る状態。`<C-o>v` で insert から入り、"
      .. "pre-edit が無い `V_IDLE` と、▽ / ▼ を抱えた `V_PRE` に分かれる。",
  },
  {
    id = "insert", title = "insert", classes = {
      "I_OFF", "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT", "I_ESCAPE",
    },
    section = "3.3",
    intro = "insert の本体。無効（`I_OFF`）、読みが無い（`I_DIRECT`）、ローマ字の打ちかけ"
      .. "（`I_ROMAJI`）、▽（`I_POINT`）、▼（`I_SELECT`）、`<Esc>` の片付け待ち（`I_ESCAPE`）。",
  },
  {
    id = "insert_normal", title = "insert-normal（`ni`）", classes = { "NI" },
    section = "3.4",
    intro = "`<C-o>` で入る `niI`。読みを抱えたまま normal の 1 コマンドを実行し、"
      .. "insert に戻る。相（direct / point / select）で戻り先の結果が変わる。",
  },
  {
    id = "replace", title = "replace（`R`）", classes = { "R_OFF" },
    section = "3.5",
    intro = "replace で skk が無効の状態。`<Insert>` の前後で `R_MID`（途中の状態）を通る。",
  },
  {
    id = "cmdline", title = "cmdline（`c` / `cr`）", classes = {
      "C_DIRECT", "C_POINT", "C_REPLACE",
    },
    section = "3.6",
    intro = "cmdline。pre-edit を extmark ではなく cmdline の本物の文字として書く。"
      .. "置換モード（`cr`）は `C_REPLACE`。",
  },
  {
    id = "terminal", title = "terminal（`t` / `nt`）", classes = {
      "T_DIRECT", "T_POINT", "T_NORMAL",
    },
    section = "3.7",
    intro = "terminal。pre-edit を端末の行に本物の文字として書く。`nt` へ移っても読みと"
      .. "pre-edit を抱えたまま。",
  },
  {
    id = "prompt", title = "辞書登録のプロンプト（`@`）", classes = { "P_PROMPT" },
    section = "3.8",
    intro = "辞書登録の `input()`（cmdtype は `@`）。外側の pre-edit は凍結し、"
      .. "欄の中は直接入力。入れ子は深さ 2 まで。",
  },
  {
    id = "completion", title = "補完（`ic` / `ix` / blink）", classes = { "IC" },
    section = "3.9",
    intro = "補完のメニューが開いている状態。組み込み（`ic`）、`<C-x>` のキー待ち（`ix`）、"
      .. "blink.cmp（Vim のモードは `i` のまま）を、人が読むクラスでは `IC` にまとめる。",
  },
}

local GROUP_OF = {}
for _, g in ipairs(GROUPS) do
  for _, c in ipairs(g.classes) do
    GROUP_OF[c] = g.id
  end
end

local SHORT_LABEL = {
  N_OFF = "normal（無効）",
  N_WAIT = "normal（確定待ち）",
  V_IDLE = "visual（pre-edit 無し）",
  V_PRE = "visual（pre-edit 付き）",
  I_OFF = "insert（無効）",
  I_DIRECT = "direct",
  I_ROMAJI = "打ちかけ",
  I_POINT = "▽",
  I_SELECT = "▼",
  I_ESCAPE = "escape（片付け待ち）",
  NI = "insert-normal",
  R_OFF = "replace（無効）",
  C_DIRECT = "cmdline（pre-edit 無し）",
  C_POINT = "cmdline（▽ / ▼）",
  C_REPLACE = "cmdline replace",
  T_DIRECT = "terminal（pre-edit 無し）",
  T_POINT = "terminal（▽ / ▼）",
  T_NORMAL = "terminal-normal",
  IC = "補完",
  P_PROMPT = "辞書登録",
}

-- 人が読むクラスの中の相（作者の判断 4）。ここに無いクラスは相を持たない。
local ASPECTS = {
  NI = { "direct", "point", "select" },
  V_PRE = { "point", "select" },
  P_PROMPT = { "point", "select" },
}

local CLASS_PROSE = {
  N_OFF = "skk は無効で、キーは Vim がそのまま処理する。`enable` / `toggle` で insert に入る。"
    .. "`keepState` の one-shot 待ち（`N_KEEP`）とマクロの記録中（`N_REC`）も、人が読むクラスはここ。",
  N_WAIT = "`<C-c>` などのあと、`SafeState` の one-shot の片付けを待つ途中の状態。"
    .. "片付けが走ると `N_OFF` になる。",
  V_IDLE = "visual / select で skk は有効のまま、pre-edit は無い。`<C-o>v` を direct から押すとここに入る。",
  V_PRE = "visual / select で、`<C-o>v` の前に抱えていた pre-edit が残っている。"
    .. "`<Esc>` で insert に戻る。マウスのドラッグで一瞬残るものは遷移の途中として扱う。",
  I_OFF = "insert で skk が無効。キーは Vim が処理し、有効化するまで skk は関与しない。"
    .. "blink の buffer 補完のメニューが開いている間（`I_OFF_MENU`）もここ。",
  I_DIRECT = "insert が有効で、読みが無い。文字キーで読みを始め、`<Space>` や `<CR>` などは Vim に流れる。",
  I_ROMAJI = "ローマ字の打ちかけ（`state.feed`）を抱えている。次の文字で ▽ へ進む。"
    .. "制御キーの多くは読みを捨てる（P1 の既知の破れ）。",
  I_POINT = "▽ / ▽* を抱えている。文字キーで読みを進め、`<Space>` / `>` で ▼、"
    .. "`<BS>` で 1 文字戻る。`<CR>` で確定する。",
  I_SELECT = "▼ を抱えている。候補を選び、`<Space>` / `<CR>` で確定、`x` / `<C-g>` で"
    .. "候補を移る・取り消す。",
  I_ESCAPE = "マップされた `<Esc>` のあと、`ModeChanged` か `SafeState` の片付けまでの"
    .. "途中の状態。片付けが終わると `N_OFF`。",
  NI = "`<C-o>` で入った `niI`。normal の 1 コマンドを実行してから insert に戻る。"
    .. "読みを抱えたままなら、戻るときに確定するか捨てるかが分かれる（#199 の gap）。",
  R_OFF = "replace で skk が無効。`<Insert>` の前後で `R_MID`（途中の状態）を通る。",
  C_DIRECT = "cmdline に pre-edit が無い。skk が有効でないとき、c のマッピングが無いとき"
    .. "（visual から入ったとき）もここ。",
  C_POINT = "cmdline に ▽ / ▽* / ▼ / 打ちかけを本物の文字として書いている。確定・取消のほか、"
    .. "ずれの検出で読みが捨てられる（P1 の既知の破れ）。",
  C_REPLACE = "cmdline の置換モード（`cr`）。`<Insert>` で入り、`<C-j>` で確定しても `cr` のまま、"
    .. "`<CR>` でコマンドを実行して抜ける。",
  T_DIRECT = "terminal で pre-edit が無い。skk が無効のとき（`T_OFF`）と `<Esc>` の片付け待ち"
    .. "（`T_ESCAPE`）もここ。",
  T_POINT = "terminal の行に ▽ / ▼ / 打ちかけを本物の文字として書いている。"
    .. "ジョブへ渡すキーは確定してから渡す（P14）。",
  T_NORMAL = "terminal-normal（`nt`）。`<C-\\><C-n>` で移っても skk は有効のままで、"
    .. "読みと pre-edit を抱えたまま。`t` に戻ると続きから打てる（P4）。",
  IC = "補完のメニューが開いている。組み込み（`ic`）、`<C-x>` のキー待ち（`ix`）、"
    .. "blink.cmp（Vim のモードは `i` のまま）を含む。組み込みは入った時点で pre-edit が消える。",
  P_PROMPT = "辞書登録の `input()`（cmdtype は `@`）。外側の pre-edit は凍結して残り、欄の中は直接入力。"
    .. "取り消すと凍結した外側に、確定すると insert に戻る。入れ子は深さ 2 まで。",
}

local ASPECT_PROSE = {
  NI = {
    direct = "読みは無い。normal の 1 コマンドを実行してから insert に戻る。",
    point = "▽ を抱えたまま。戻るときに読みを確定するか、捨てるかが分かれる（#199 の gap）。",
    select = "▼ を抱えたまま。戻るときに候補を確定するか、捨てるかが分かれる（#199 の gap）。",
  },
  V_PRE = {
    point = "▽ が pre-edit として残り続ける。`<Esc>` で insert に戻る。",
    select = "▼ が pre-edit として残り続ける。`<Esc>` で insert に戻る。",
  },
  P_PROMPT = {
    point = "外側の ▽ は凍結する。取り消すと凍結した外側に、確定すると insert に戻る。",
    select = "外側の ▼ は凍結する。取り消すと凍結した外側に、確定すると insert に戻る。",
  },
}

-- ---------------------------------------------------------------------------
-- モデルの索引

local state_names = sorted_keys(model.states)
local event_names = sorted_keys(model.events)

local function state(name)
  return model.states[name]
end

local function class_of(name)
  return state(name).class
end

local function modes_of(name)
  local set, list = {}, {}
  for m in (state(name).vim_mode or ""):gmatch("[^|]+") do
    if not set[m] then
      set[m] = true
      list[#list + 1] = m
    end
  end
  table.sort(list)
  return list
end

local function is_cross_mode(tr)
  local a, b = {}, {}
  for _, m in ipairs(modes_of(tr.from)) do
    a[m] = true
  end
  for _, m in ipairs(modes_of(tr.to)) do
    b[m] = true
  end
  for m in pairs(a) do
    if b[m] then
      return false
    end
  end
  return true
end

local observed_keys = {}
for _, o in ipairs(model.observations or {}) do
  observed_keys[o.id] = o.keys
end
for _, p in ipairs(model.probes or {}) do
  observed_keys[p.id] = p.keys
end

local known_by_transition = {}
for _, k in ipairs(model.known or {}) do
  local list = known_by_transition[k.transition] or {}
  known_by_transition[k.transition] = list
  for _, r in ipairs(k.refs or {}) do
    list[#list + 1] = r
  end
end

local function known_refs_for_ids(ids)
  local set = {}
  for _, id in ipairs(ids) do
    for _, r in ipairs(known_by_transition[id] or {}) do
      set[r] = true
    end
  end
  return sorted_refs(set)
end

-- ---------------------------------------------------------------------------
-- 遷移のまとまり（状態クラスの組ごと）

local function aggregate(filter)
  local index, list = {}, {}
  for _, tr in ipairs(model.transitions) do
    if not filter or filter(tr) then
      local fc, tc = class_of(tr.from), class_of(tr.to)
      local key = fc .. "\0" .. tc
      local p = index[key]
      if not p then
        p = {
          from = fc, to = tc, n = 0,
          events = {}, effects = {}, status = {}, refs = {}, observed = {}, ids = {},
        }
        index[key] = p
        list[#list + 1] = p
      end
      p.n = p.n + 1
      p.events[tr.event] = true
      for _, e in ipairs(tr.effects or {}) do
        p.effects[e] = true
      end
      p.status[tr.status] = (p.status[tr.status] or 0) + 1
      for _, r in ipairs(tr.refs or {}) do
        p.refs[r] = true
      end
      for _, o in ipairs(tr.observed or {}) do
        p.observed[o] = true
      end
      p.ids[#p.ids + 1] = tr.id
    end
  end
  table.sort(list, function(a, b)
    if a.from ~= b.from then
      return (CLASS_RANK[a.from] or 99) < (CLASS_RANK[b.from] or 99)
    end
    return (CLASS_RANK[a.to] or 99) < (CLASS_RANK[b.to] or 99)
  end)
  for _, p in ipairs(list) do
    table.sort(p.ids)
  end
  return list
end

local all_pairs = aggregate(nil)
local cross_pairs = aggregate(function(tr)
  return is_cross_mode(tr)
end)

local pair_by_key = {}
for _, p in ipairs(all_pairs) do
  pair_by_key[p.from .. "\0" .. p.to] = p
end

local STATUS_ORDER = { "ok", "gap", "unknown", "impossible" }

local function status_cell(p)
  local parts = {}
  for _, s in ipairs(STATUS_ORDER) do
    if p.status[s] then
      parts[#parts + 1] = ("%s %d"):format(s, p.status[s])
    end
  end
  local text = table.concat(parts, " / ")
  if (p.status.gap or 0) > 0 then
    local refs = known_refs_for_ids(p.ids)
    if #refs > 0 then
      text = text .. ("（既知: %s）"):format(cap(refs, 3))
    else
      text = text .. "（既知の登録なし）"
    end
  end
  return code(text)
end

local function events_cell(p)
  local list = sorted_keys(p.events)
  for i, v in ipairs(list) do
    list[i] = code(v)
  end
  return cap(list, 8)
end

local function effects_cell(p)
  local list = sorted_keys(p.effects)
  if #list == 0 then
    return "—"
  end
  for i, v in ipairs(list) do
    list[i] = code(v)
  end
  return cap(list, 8)
end

local function refs_cell(p)
  local parts = {}
  if #p.ids > 0 then
    parts[#parts + 1] = code(p.ids[1])
  end
  local refs = sorted_refs(p.refs)
  if #refs > 0 then
    parts[#parts + 1] = cap(refs, 3)
  end
  local obs = sorted_keys(p.observed)
  if #obs > 0 then
    local keys = observed_keys[obs[1]] or {}
    local shown = {}
    for i = 1, math.min(#keys, 8) do
      shown[#shown + 1] = code(keys[i])
    end
    local text = table.concat(shown, " ")
    if #keys > #shown then
      text = text .. " …"
    end
    parts[#parts + 1] = "観測: " .. text
  end
  return table.concat(parts, " / ")
end

local function pair_table(pairs)
  local rows = {
    "| 状態 | イベント | effects | 遷移先 | status | 根拠 |",
    "| --- | --- | --- | --- | --- | --- |",
  }
  for _, p in ipairs(pairs) do
    rows[#rows + 1] = ("| %s | %s | %s | %s | %s | %s |"):format(
      code(p.from), events_cell(p), effects_cell(p), code(p.to), status_cell(p), refs_cell(p)
    )
  end
  return table.concat(rows, "\n")
end

local function verified(p)
  return (p.status.ok or 0) > 0 or (p.status.gap or 0) > 0 or next(p.observed) ~= nil
end

local function pairs_from(classes)
  local set = {}
  for _, c in ipairs(classes) do
    set[c] = true
  end
  local out = {}
  for _, p in ipairs(all_pairs) do
    if set[p.from] then
      out[#out + 1] = p
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Mermaid / 図

local function mlabel(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "＜"):gsub(">", "＞")
  s = s:gsub('"', "'")
  s = s:gsub(":", "：")
  s = s:gsub("|", "/")
  s = s:gsub("\n", " ")
  return s
end

local function mermaid_nodes(classes)
  local out = {}
  for _, c in ipairs(CLASS_ORDER) do
    local wanted = false
    for _, x in ipairs(classes) do
      if x == c then
        wanted = true
        break
      end
    end
    if wanted then
      out[#out + 1] = ('  state "%s" as %s'):format(mlabel(c .. " " .. SHORT_LABEL[c]), c)
    end
  end
  return out
end

local function mermaid_edges(pairs, seen_classes)
  local out = {}
  for _, p in ipairs(pairs) do
    local events = sorted_keys(p.events)
    for i, v in ipairs(events) do
      events[i] = mlabel(v)
    end
    local label = cap(events, 3, " / ")
    if p.n > 1 then
      label = label .. ("（%d 遷移）"):format(p.n)
    end
    out[#out + 1] = ("  %s --> %s: %s"):format(p.from, p.to, label)
  end
  return out
end

local function mermaid(classes, pairs)
  local lines = { "```mermaid", "stateDiagram-v2" }
  for _, line in ipairs(mermaid_nodes(classes)) do
    lines[#lines + 1] = line
  end
  -- 外へ出る辺の遷移先も宣言する
  local declared = {}
  for _, c in ipairs(classes) do
    declared[c] = true
  end
  for _, p in ipairs(pairs) do
    if not declared[p.to] then
      declared[p.to] = true
      lines[#lines + 1] = ('  state "%s" as %s'):format(mlabel(p.to .. " " .. SHORT_LABEL[p.to]), p.to)
    end
  end
  for _, line in ipairs(mermaid_edges(pairs, declared)) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = "```"
  return table.concat(lines, "\n")
end

local function figure_link(id, title)
  return ("![%s](figures/%s.svg)"):format(title, id)
end

-- ---------------------------------------------------------------------------
-- 状態クラスの一覧

local function internal_states(class, aspect)
  local out = {}
  for _, name in ipairs(state_names) do
    local s = model.states[name]
    if s.class == class and (aspect == nil or s.aspect == aspect) then
      out[#out + 1] = name
    end
  end
  return out
end

local function display_class(class, aspect)
  if aspect then
    return ("%s（%s）"):format(class, aspect)
  end
  return class
end

local function incoming_text(class, aspect, states)
  local set = {}
  for _, name in ipairs(states) do
    set[name] = true
  end
  local items, seen = {}, {}
  for _, tr in ipairs(model.transitions) do
    if set[tr.to] and class_of(tr.from) ~= class then
      local key = (model.events[tr.event].keys or {})[1] or tr.event
      local from = class_of(tr.from)
      local item = ("%s から %s"):format(code(from), code(key))
      if not seen[item] then
        seen[item] = true
        items[#items + 1] = item
      end
    end
  end
  if #items == 0 then
    return "（入り口は無い）"
  end
  local text = cap(items, 6)
  if class == "N_OFF" then
    text = "起動直後、または " .. text
  end
  return text
end

-- ---------------------------------------------------------------------------
-- 文書

local out = {}

local function add(...)
  for i = 1, select("#", ...) do
    out[#out + 1] = tostring(select(i, ...))
  end
end

local function add_table(headers, rows)
  local head = {}
  local sep = {}
  for i, h in ipairs(headers) do
    head[i] = cell(h)
    sep[i] = "---"
  end
  add("| " .. table.concat(head, " | ") .. " |")
  add("| " .. table.concat(sep, " | ") .. " |")
  for _, row in ipairs(rows) do
    add("| " .. table.concat(row, " | ") .. " |")
  end
end

-- 数の集計
local state_count = #state_names
local event_count = #event_names
local transition_count = #model.transitions
local class_count = #CLASS_ORDER
local known_count = #(model.known or {})
local oos_count = #(model.out_of_scope or {})

local split_groups = 0
do
  local by = {}
  for _, tr in ipairs(model.transitions) do
    local key = tr.from .. "\0" .. tr.event
    by[key] = by[key] or {}
    by[key][tr.to] = true
  end
  for _, tos in pairs(by) do
    local n = 0
    for _ in pairs(tos) do
      n = n + 1
    end
    if n > 1 then
      split_groups = split_groups + 1
    end
  end
end

-- 冒頭
add("# skkeleton の状態機械（今の振る舞い）")
add("")
add("<!-- このファイルは `semantics/doc.lua` が `semantics/model/model.lua` から生成する。手で編集しない。 -->")
add("")
add(("- 親の issue: #%d"):format(model.parent))
add(("- モデルの issue: #%d"):format(model.issue))
add(("- データ源: `semantics/model/model.lua`（状態 %d / イベント %d / 遷移 %d）"):format(
  state_count, event_count, transition_count
))
add(("- 生成: `nvim --headless -u NONE -i NONE -l semantics/doc.lua`"))
add(("- 図の生成: `nvim --headless -u NONE -i NONE -l semantics/figures/gen.lua`")
  .. "（Graphviz の `dot` を使う）")
add("- この文書は**今の**振る舞いだけを書く。望ましい振る舞いは決めない。")
add("")

-- 0. 読み方
add("## 0. 読み方")
add("")
add("### 0.1 この文書の立場")
add("")
add("状態は 3 つの層に分けて書く。")
add("")
add("1. **Vim のモード**：`n` / `i` / `ni`（`<C-o>`）/ `R` / `v`・`s` / `c` / `cr` / `t` / `nt` / `ic` / `@`（辞書登録のプロンプト）。")
add("2. **skkeleton の入力相**：off / direct / ▽ / ▼ / escape。かなのモードは hira / kata / hankata / zenkaku / abbrev。")
add("3. **表示**：pre-edit がどこにあるか（extmark / cmdline の文字 / terminal の文字）、popup、pending。")
add("")
add("このモデルが持つのは、主に 1 と 2 と、表示のうち状態クラスに落とせる部分（pre-edit の有無と種類）だけ。"
  .. "extmark の位置・メニューの位置・タイミングは状態クラスに持っていない（P2 / P6 / P15 が決められない理由）。")
add("")
add("### 0.2 用語と status")
add("")
add(("用語は [GLOSSARY.md](GLOSSARY.md) に合わせる。状態クラスは人が読む名前、内部状態は `model.lua` の `M.states` の名前。"
  .. "人は %d 個のクラスを読み、モデルは %d 個の内部状態に分けている。"):format(class_count, state_count))
add("")
add("- `ok`：モデルが今の振る舞いに合っている（コード読解か観測で確かめた）")
add("- `gap`：今の振る舞いが性質を破っている（`M.known` に issue を書く）")
add("- `unknown`：まだ確かめていない")
add("- `impossible`：起こり得ない")
add("")
add("遷移の表は、同じ状態クラスの組（from → to）を 1 行にまとめている。"
  .. "イベントはその組に含まれるイベント名（`model.lua` の `M.events` のキー）、"
  .. "effects は語彙（GLOSSARY）の和、status は遷移の数、根拠は代表の遷移 id・`refs`・観測のキー列。"
  .. "1 行に複数の遷移があるので、status の数は行の遷移数と一致する。")
add("")
add("`refs` は `ファイル:行`、issue 番号、棚卸しの節（`keys.md §6` など）。"
  .. "`観測:` は `M.observations` / `M.probes` のキー列を流したもの。"
  .. "遷移id は `model.lua` と 1 対 1 で、手置きの図（`data.js`）とはこの id と状態クラス名で対応を取る。"
  .. "`data.js` は作者の手元だけにあり、リポジトリには無い。")
add("")
add("### 0.3 図")
add("")
add("各モードの節に Mermaid の図と、Graphviz で作った SVG を置く。"
  .. "図は status が `ok` / `gap` の遷移、または観測のある遷移だけを描く。"
  .. "`unknown` だけの辺は表にだけ出す。")
add("")
add("### 0.4 生成し直す")
add("")
add("```sh")
add("nvim --headless -u NONE -i NONE -l semantics/doc.lua")
add("nvim --headless -u NONE -i NONE -l semantics/figures/gen.lua")
add("```")
add("")
add("どちらも時刻や環境に依存する値を書かない。生成し直しても差分が出ないことを確かめてある。")
add("")

-- 1. 3 層
add("## 1. 3 層のモデル")
add("")
add("### 1.1 Vim のモード")
add("")
add("状態クラスは Vim のモードをまたぐ。`n` / `v` / `s` / `o` は skk が無効な `N_OFF` にまとめ、"
  .. "`i` は無効（`I_OFF`）と有効（`I_DIRECT` ほか）に分ける。"
  .. "`ni` は `NI`、`R` は `R_OFF`、`c` / `cr` は `C_*`、`t` / `nt` は `T_*`、"
  .. "`ic` / `ix` は `IC`、辞書登録の `@` は `P_PROMPT`。")
add("")
add("### 1.2 skkeleton の入力相")
add("")
add("入力相は off / direct / ▽ / ▼ / escape。状態クラスの `reading` が romaji / point / henkan のどれか、"
  .. "`phase` が `input:direct` / `input:okurinasi|okuriari` / `henkan` / `escape` / `prompt` のどれかで表す。"
  .. "かなのモード（hira / kata / hankata / zenkaku / abbrev）は状態クラスに持っていない（P11 が決められない理由）。")
add("")
add("### 1.3 表示")
add("")
add("pre-edit の置き場所は Vim のモードで変わる。insert は extmark、cmdline は cmdline の本物の文字、"
  .. "terminal は端末の行の本物の文字。状態クラスは「pre-edit があるか」「どの種類か」だけを持ち、"
  .. "位置・数・メニューの位置は持たない（P2 / P15）。")
add("")

-- 2. 状態とイベント
add("## 2. 状態とイベントの一覧")
add("")
add("### 2.1 状態クラス")
add("")
add(("人が読むクラスは %d 個。`NI` / `V_PRE` / `P_PROMPT` は相を括弧で書く（作者の判断 4）。"
  .. "「どう入るか」は、ほかのクラスから入る遷移のキーを並べたもの。"):format(class_count))
add("")
do
  local rows = {}
  for _, class in ipairs(CLASS_ORDER) do
    local aspects = ASPECTS[class]
    local list = aspects or { false }
    for _, aspect in ipairs(list) do
      local a = aspect or nil
      local states = internal_states(class, a)
      local display = display_class(class, a)
      local readings, vims, labels = {}, {}, {}
      for _, name in ipairs(states) do
        local s = model.states[name]
        readings[s.reading] = true
        for _, m in ipairs(modes_of(name)) do
          vims[m] = true
        end
        if s.label then
          labels[s.label] = true
        end
      end
      local reading_list = sorted_keys(readings)
      local vim_list = sorted_keys(vims)
      local prose = (ASPECT_PROSE[class] and ASPECT_PROSE[class][a]) or CLASS_PROSE[class] or ""
      rows[#rows + 1] = {
        code(display),
        cell(table.concat(vim_list, " / ")),
        cell(table.concat(reading_list, " / ")),
        cap(states, 6, "<br>"),
        incoming_text(class, a, states),
        cell(prose),
      }
    end
  end
  add_table({ "クラス", "Vim のモード", "reading", "内部状態", "どう入るか", "そこで何が起きるか" }, rows)
end
add("")
add("内部状態が複数あるクラスは、モデルの中だけで分けたもの。"
  .. "`IC` は組み込み・キー待ち・blink を、`C_DIRECT` / `T_DIRECT` は無効・有効・マッピング無しを、"
  .. "`N_OFF` は one-shot 待ちとマクロ記録中を含む。")
add("")

-- 2.2 イベント
add("### 2.2 イベント")
add("")
add(("モデルのイベントは %d 個。種類は key（キー）/ autocmd（Vim のイベント）/ api（skkeleton の関数）/ "
  .. "input（キー以外の入力）/ internal（キーの処理の途中で走る片付け）/ vim（Vim 本体の動き）。"):format(event_count))
add("")
do
  local KIND_ORDER = { "key", "api", "autocmd", "input", "internal", "vim" }
  local KIND_RANK = {}
  for i, k in ipairs(KIND_ORDER) do
    KIND_RANK[k] = i
  end
  local KIND_LABEL = {
    key = "キー",
    api = "関数",
    autocmd = "Vim のイベント",
    input = "キー以外の入力",
    internal = "内部の片付け",
    vim = "Vim の動き",
  }
  local list = {}
  for _, name in ipairs(event_names) do
    list[#list + 1] = name
  end
  table.sort(list, function(a, b)
    local ka = KIND_RANK[model.events[a].kind] or 99
    local kb = KIND_RANK[model.events[b].kind] or 99
    if ka ~= kb then
      return ka < kb
    end
    return a < b
  end)
  local rows = {}
  for _, name in ipairs(list) do
    local e = model.events[name]
    local keys = {}
    for _, k in ipairs(e.keys or {}) do
      keys[#keys + 1] = code(k)
    end
    rows[#rows + 1] = {
      code(name),
      cell(KIND_LABEL[e.kind] or e.kind),
      cap(keys, 6),
      cell(table.concat(e.modes or {}, " / ")),
      cap(sorted_refs((function()
        local t = {}
        for _, r in ipairs(e.refs or {}) do
          t[r] = true
        end
        return t
      end)()), 3),
    }
  end
  add_table({ "イベント", "種類", "キー", "モード", "根拠" }, rows)
end
add("")

-- 3. モードごと
add("## 3. Vim のモードごとの図と遷移表")
add("")
add("各節は、そのモードの状態クラスから出る遷移をまとめる。"
  .. "外のモードへ出る遷移もここに出る（モードが変わるものだけを集めた表は §4）。"
  .. "表の見方は §0.2。")
add("")

for _, g in ipairs(GROUPS) do
  add(("### %s %s"):format(g.section, g.title))
  add("")
  add(g.intro)
  add("")
  local pairs = pairs_from(g.classes)
  local shown = {}
  for _, p in ipairs(pairs) do
    if verified(p) then
      shown[#shown + 1] = p
    end
  end
  local classes = {}
  for _, c in ipairs(g.classes) do
    classes[#classes + 1] = c
  end
  for _, p in ipairs(shown) do
    if not GROUP_OF[p.to] or GROUP_OF[p.to] ~= g.id then
      classes[#classes + 1] = p.to
    end
  end
  add(mermaid(g.classes, shown))
  add("")
  add(figure_link("mode_" .. g.id, g.title .. " の状態遷移"))
  add("")
  add(("状態クラス %d 個、遷移の組 %d 行（この節から出るもの）。"):format(#g.classes, #pairs))
  add("")
  add(pair_table(pairs))
  add("")
end

-- 4. モードをまたぐ
add("## 4. モードをまたぐ遷移")
add("")
add("Vim のモードが変わる遷移だけを集めた。モードの対応が無い遷移（`i` → `n`、`t` → `nt`、`c` → `cr` など）がここに入る。"
  .. "同じクラスの中でもモードが変わるもの（`T_DIRECT` の `t` → `T_NORMAL` の `nt` など）を含む。")
add("")
add(figure_link("state_machine", "状態クラス全体（モードをまたぐ遷移）"))
add("")
add("```mermaid")
add("stateDiagram-v2")
for _, c in ipairs(CLASS_ORDER) do
  add(('  state "%s" as %s'):format(mlabel(c .. " " .. SHORT_LABEL[c]), c))
end
for _, line in ipairs(mermaid_edges((function()
  local t = {}
  for _, p in ipairs(cross_pairs) do
    if verified(p) then
      t[#t + 1] = p
    end
  end
  return t
end)(), {})) do
  add(line)
end
add("```")
add("")
add(pair_table(cross_pairs))
add("")

-- 5. 性質
add("## 5. 性質 P1–P15")
add("")
add("性質は [GLOSSARY.md](GLOSSARY.md) の P1–P15。`model.lua` の `M.properties` が、"
  .. "このモデルで決められるか（`decided`）と、決められない理由を持つ。"
  .. "決められる性質は `semantics/model/model_check.lua` が検査する。")
add("")

local checked = { P1 = true, P3 = true, P4 = true, P5 = true, P8 = true, P9 = true,
  P10 = true, P13 = true, P14 = true }
local known_by_property = {}
for _, k in ipairs(model.known or {}) do
  known_by_property[k.property] = (known_by_property[k.property] or 0) + 1
end
do
  local rows = {}
  for _, p in ipairs(model.properties or {}) do
    local verdict, reason
    if not p.decided then
      verdict = "決められない"
      reason = p.why or ""
    elseif (known_by_property[p.id] or 0) > 0 then
      verdict = "破れている（既知）"
      local refs = {}
      for _, k in ipairs(model.known) do
        if k.property == p.id then
          for _, r in ipairs(k.refs or {}) do
            refs[r] = true
          end
        end
      end
      reason = ("%d 件の遷移が破れている。根拠: %s"):format(
        known_by_property[p.id], cap(sorted_refs(refs), 8)
      )
    else
      verdict = "いまのモデルで決められる"
      reason = "model_check の検査が通る。"
    end
    rows[#rows + 1] = {
      code(p.id),
      cell(p.title),
      cell(verdict),
      cell(checked[p.id] and "検査する" or "検査しない"),
      cell(reason),
    }
  end
  add_table({ "性質", "内容", "いまのモデルでの判定", "model_check", "根拠・理由" }, rows)
end
add("")
add(("`model_check.lua` の現在の結果は失敗 0。P1 は既知の破れ %d 件だけで、知らない破れは無い。"
  .. "P2 / P6 / P7 / P11 / P12 / P15 は、状態クラスに持っていない層（表示・かなモード・マッピング・タイミング）が要るので、このモデルでは決めない。"):format(known_count))
add("")
add("### 5.1 P1 の既知の破れ")
add("")
add(("P1（読みが黙って消えない）の破れは %d 件。すべて `M.known` に issue か棚卸しの節が付いている。"
  .. "1 つの遷移が複数の根拠を持つので、下の件数の合計は %d と一致しない。"):format(known_count, known_count))
add("")
do
  local byref = {}
  for _, k in ipairs(model.known or {}) do
    for _, r in ipairs(k.refs or {}) do
      byref[r] = byref[r] or { property = k.property, transitions = {} }
      byref[r].transitions[#byref[r].transitions + 1] = k.transition
    end
  end
  local refs = sorted_refs(byref)
  local rows = {}
  for _, r in ipairs(refs) do
    local entries = byref[r]
    local ids = {}
    for _, t in ipairs(entries.transitions) do
      ids[#ids + 1] = code(t)
    end
    rows[#rows + 1] = {
      cell(r),
      code(entries.property),
      cell(tostring(#entries.transitions)),
      cap(ids, 3),
    }
  end
  add_table({ "根拠", "性質", "遷移数", "遷移（先頭 3 件）" }, rows)
end
add("")
add("<details>")
add("<summary>P1 の既知の遷移をすべて出す</summary>")
add("")
do
  local byref = {}
  for _, k in ipairs(model.known or {}) do
    for _, r in ipairs(k.refs or {}) do
      byref[r] = byref[r] or {}
      byref[r][#byref[r] + 1] = k.transition
    end
  end
  for _, r in ipairs(sorted_refs(byref)) do
    local ids = {}
    for _, t in ipairs(byref[r]) do
      ids[#ids + 1] = code(t)
    end
    table.sort(ids)
    add(("- %s: %s"):format(r, table.concat(ids, " ")))
  end
end
add("")
add("</details>")
add("")

-- 6. 未解決の gap と過去のバグ
add("## 6. 未解決の gap と過去のバグ")
add("")
add("### 6.1 いまの gap（`M.known`）")
add("")
add(("`M.known` の項目は %d 件で、すべて P1。既知の破れとして `model_check.lua` が △ で出す。"):format(known_count))
add("")
local ISSUE_TITLES = {
  ["#8"] = "変換中の <C-u> でバッファだけ消え、pre-edit と状態が残る",
  ["#12"] = "辞書登録の欄でカーソルを動かすと、▽ ごと語が登録・確定される",
  ["#18"] = "補完で候補が入ると、インジケータが元の位置に残る",
  ["#19"] = "▽ の入力中に補完を入れたり取り消したりすると、pre-edit が行の途中に描かれる",
  ["#20"] = "▽ の入力中に <C-r>= で式を入れると、pre-edit の表示だけが残る",
  ["#47"] = "マウスで visual から insert に戻ると、インジケータがクリック前のカーソル位置に残る",
  ["#67"] = "変換などの関数はキーマップだけに置き、かなテーブルは文字だけにする",
  ["#116"] = "辞書登録の欄で <C-w> のあと <C-g> で取り消すと、取り消しの印が崩れて語として登録される",
  ["#169"] = "変換中にマウスで別のウィンドウに移ると変換中の文字が消える",
  ["#190"] = "formal-semantics: 組み込みの補完（ic）と blink の状態機械をモデルに足して探索する",
  ["#199"] = "pre-edit のときにバッファが変わると、打った読みが黙って消える（<C-o>x、外部からの変更）",
  ["#205"] = "cmdline の ▽ で <C-f> を押すと、cmdline window に pre-edit が引き継がれず消える",
  ["#206"] = "cmdline の ▽ で <C-r>= を使うと、cmdline に ▽ と読みが残り、そのまま実行される",
  ["#210"] = "変換中に <Plug>(skkeleton-enable) を押すと、打った読みが確定せずに消える",
}
do
  local byref = {}
  for _, k in ipairs(model.known or {}) do
    for _, r in ipairs(k.refs or {}) do
      byref[r] = byref[r] or { transitions = {} }
      byref[r].transitions[#byref[r].transitions + 1] = k.transition
    end
  end
  local refs = sorted_refs(byref)
  local rows = {}
  for _, r in ipairs(refs) do
    rows[#rows + 1] = {
      cell(r),
      cell(ISSUE_TITLES[r] or "—（棚卸し・観測の節）"),
      cell(tostring(#byref[r].transitions)),
    }
  end
  add_table({ "根拠", "題（issue の題。棚卸しの節には無い）", "遷移数" }, rows)
end
add("")
add("題は生成時点のもの。issue の状態（OPEN / CLOSED）は GitHub で見る。")
add("")

-- 6.2 未考慮
add("### 6.2 未考慮の遷移（`M.out_of_scope`）")
add("")
add(("このモデルが対象にしていない遷移は %d 件。どれも理由と根拠が付いている。"):format(oos_count))
add("")
do
  local rows = {}
  for _, o in ipairs(model.out_of_scope or {}) do
    local refs = {}
    for _, r in ipairs(o.refs or {}) do
      refs[#refs + 1] = code(r)
    end
    local keys = {}
    for _, k in ipairs(o.keys or {}) do
      keys[#keys + 1] = code(k)
    end
    rows[#rows + 1] = {
      code(o.id),
      cell(o.what),
      cell(o.why),
      cap(refs, 3),
      #keys > 0 and cap(keys, 4) or "—",
    }
  end
  add_table({ "id", "何を", "なぜ対象外か", "根拠", "キー" }, rows)
end
add("")

-- 6.3 過去のバグ
add("### 6.3 過去のバグ（`semantics/issues.md`）")
add("")
local issues_text = read_file(dir .. "/issues.md") or ""
local issue_total = tonumber(issues_text:match("全部で (%d+) 件"))
local property_counts, unfixed = {}, {}
do
  for num, list, count in issues_text:gmatch("| P(%d+) | ([^|]*) | (%d+) |") do
    property_counts[#property_counts + 1] = {
      id = "P" .. num,
      issues = trim(list),
      count = tonumber(count),
    }
  end
  local sec = issues_text:match("## 直していないもの・再現しなかったもの(.-)\n## ")
  if sec then
    for n, state_name, why in sec:gmatch("| (%#%d+) | ([^|]+) | ([^|]+) |") do
      unfixed[#unfixed + 1] = { issue = n, state = trim(state_name), why = trim(why) }
    end
  end
end
if issue_total then
  add(("`issues.md` は %d 件のバグの issue を、状態クラス・イベント・性質で引けるようにした表。"
    .. "P1–P15 の外の話（辞書層・入力エンジン・undo のまとまりなど）も含む。"):format(issue_total))
else
  add("`issues.md` を読めなかった。件数はそちらを見る。")
end
add("")
if #property_counts > 0 then
  add("| 性質 | 件数 | issue |")
  add("| --- | ---: | --- |")
  for _, row in ipairs(property_counts) do
    add(("| %s | %d | %s |"):format(code(row.id), row.count, cell(row.issues)))
  end
  add("")
end
if #unfixed > 0 then
  add("直していない・再現しなかった・仕様として受け入れたもの（`issues.md` の表から）。")
  add("")
  add("| issue | 状態 | 理由 |")
  add("| --- | --- | --- |")
  for _, row in ipairs(unfixed) do
    add(("| %s | %s | %s |"):format(cell(row.issue), cell(row.state), cell(row.why)))
  end
  add("")
end
add("`issues.md` に無い新しい gap（#199・#205・#206・#210）は `M.known` に直接書いてある（§6.1）。")
add("")

-- 6.4 観測との差
add("### 6.4 観測との差（`semantics/compare/diff.md`）")
add("")
local diff_text = read_file(dir .. "/compare/diff.md") or ""
do
  local lines = {}
  for line in diff_text:gmatch("[^\n]+") do
    if line:match("^%- ") then
      lines[#lines + 1] = line
    end
    if #lines >= 5 then
      break
    end
  end
  if #lines > 0 then
    add("06（#186）の比較の結果。")
    add("")
    for _, line in ipairs(lines) do
      add(line)
    end
    add("")
  else
    add("`diff.md` を読めなかった。")
    add("")
  end
end
add("この差は、モデルが状態クラスに持っていない条件（辞書・バッファ・設定・タイミング）で説明できるものを含む。"
  .. "説明の付いていない差は `diff.md` を見る。")
add("")
add("### 6.5 同じ状態・イベントで分かれる組")
add("")
add(("`model_check.lua` は、同じ `from` と `event` で遷移先が複数ある組を %d 組と数える。"
  .. "辞書に候補があるか、バッファに文字があるか、設定がどちらか、といった状態クラスに持っていない条件で分かれる。"
  .. "P6（決定的に振る舞う）を決められない理由の 1 つ。"):format(split_groups))
add("")

-- 7. 決めないこと
add("## 7. ここでは決めないこと")
add("")
add("以下は #179 の節をそのまま写したもの。望ましい振る舞いの判断は作者に委ねる。")
add("")
add("- #169 の 2 案")
add("- insert の制御キー（`<C-r>` `<C-v>` `<C-k>` `<C-t>` `<Tab>`）を確定してから流すか、今のとおり捨てるか")
add("- `<C-o>` から visual / replace に入ったときの扱い")
add("- 組み込みの補完を対象外にするか")
add("- `<C-a>` / `<C-@>` の E29")
add("")

-- 8. 作者の判断
add("## 8. 付録: 作者の判断（`M.decisions`）")
add("")
add("モデルの粒度を決めた作者の判断。仕様書はこの判断に合わせてクラスを書いている。")
add("")
do
  local rows = {}
  for _, d in ipairs(model.decisions or {}) do
    rows[#rows + 1] = {
      cell(tostring(d.id)),
      cell(d.title),
      cell(d.decision),
      cap(d.reflected_in or {}, 6),
    }
  end
  add_table({ "#", "題", "判断", "反映先" }, rows)
end
add("")

-- 9. 図の一覧
add("## 9. 図の一覧")
add("")
add("`semantics/figures/` に Graphviz の `.dot` と `.svg` がある。生成は `semantics/figures/gen.lua`。")
add("")
add("| ファイル | 内容 |")
add("| --- | --- |")
add("| `figures/state_machine.svg` | 状態クラス全体（モードをまたぐ遷移） |")
for _, g in ipairs(GROUPS) do
  add(("| `figures/mode_%s.svg` | %s |"):format(g.id, cell(g.title)))
end
add("")

-- 書き出し
local text = table.concat(out, "\n") .. "\n"
local path = dir .. "/STATE_MACHINE.md"
local f = assert(io.open(path, "w"))
f:write(text)
f:close()

io.write(("書いた: %s（%d 行）\n"):format(path, select(2, text:gsub("\n", "\n"))))
io.write(("状態 %d / イベント %d / 遷移 %d / クラス %d / known %d / out_of_scope %d\n"):format(
  state_count, event_count, transition_count, class_count, known_count, oos_count
))

return M

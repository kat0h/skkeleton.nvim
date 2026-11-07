-- 仕様書の図（Graphviz）の生成器（#194、親は #179）
--
-- semantics/model/model.lua だけをデータ源にする。モデルは変えない。
-- 状態クラス（人が読む名前）を箱にして、遷移をまとめた図を dot で作る。
--
-- 使い方（リポジトリの一番上で）:
--   nvim --headless -u NONE -i NONE -l semantics/figures/gen.lua
--
-- 出力: semantics/figures/state_machine.svg と mode_<group>.svg

local M = {}

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local model = dofile(dir .. "/../model/model.lua")

-- 状態クラスごとの見出し。model.lua の label を使う（人が読む名前は class）
local function class_of(state)
  local st = model.states[state]
  return st and st.class or state
end

-- 遷移を状態クラス単位にまとめる。ok / gap / unknown の数を持つ
local edges = {}
for _, t in ipairs(model.transitions or {}) do
  local from, to = class_of(t.from), class_of(t.to)
  if from and to and from ~= to then
    local key = from .. "\0" .. to
    local e = edges[key]
    if not e then
      e = { from = from, to = to, n = 0, ok = 0, gap = 0, unknown = 0, examples = {} }
      edges[key] = e
    end
    e.n = e.n + 1
    local s = t.status or "unknown"
    if s == "ok" then
      e.ok = e.ok + 1
    elseif s == "gap" then
      e.gap = e.gap + 1
    else
      e.unknown = e.unknown + 1
    end
    if #e.examples < 2 then
      e.examples[#e.examples + 1] = (t.event or "?")
    end
  end
end

local MODE_OF = {
  I_DIRECT = "insert", I_ROMAJI = "insert", I_POINT = "insert", I_SELECT = "insert",
  I_OFF = "insert", I_ESCAPE = "insert", NI = "insert_normal",
  N_OFF = "normal", N_WAIT = "normal", N_LOST = "normal", V_PRE = "visual", V_IDLE = "visual",
  R_OFF = "replace", R_MID = "replace",
  C_DIRECT = "cmdline", C_POINT = "cmdline", C_REPLACE = "cmdline",
  P_PROMPT = "prompt",
  T_DIRECT = "terminal", T_NORMAL = "terminal", T_POINT = "terminal",
  IC = "completion",
}

local function tone(from, to)
  local e = edges[from .. "\0" .. to]
  if not e then
    return "#9aa3ad"
  end
  if e.gap > 0 then
    return "#d64545"
  end
  if e.ok > 0 then
    return "#3b5bdb"
  end
  return "#9aa3ad"
end

local function dot_for(classes)
  local lines = { "digraph {" }
  lines[#lines + 1] = '  rankdir=LR; splines=true; nodesep=0.45; ranksep=0.8;'
  lines[#lines + 1] = '  node [shape=box, style="rounded,filled", fillcolor="#ffffff", fontname="Noto Sans CJK JP", fontsize=11];'
  lines[#lines + 1] = '  edge [fontname="Noto Sans CJK JP", fontsize=9];'
  for _, c in ipairs(classes) do
    local color = "#6b7280"
    if c:match("^I_") then
      color = "#2f6feb"
    elseif c:match("^C_") then
      color = "#12857d"
    elseif c:match("^R_") then
      color = "#b3261e"
    elseif c:match("^T_") then
      color = "#6b46c1"
    elseif c == "P_PROMPT" then
      color = "#9a6400"
    elseif c == "IC" then
      color = "#6b7280"
    elseif c:match("^N_") or c:match("^V_") then
      color = "#5b6472"
    end
    lines[#lines + 1] = ('  "%s" [color="%s"];'):format(c, color)
  end
  local seen = {}
  for _, e in pairs(edges) do
    if (not classes or seen[e.from] ~= nil) and classes_set[e.from] and classes_set[e.to] then
      local color = tone(e.from, e.to)
      local style = e.unknown == e.n and 'style=dashed,' or ""
      lines[#lines + 1] = ('  "%s" -> "%s" [label="%d", %scolor="%s", fontcolor="%s"];')
        :format(e.from, e.to, e.n, style, color, color)
    end
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

local out = dir
local function write_svg(name, classes)
  classes_set = {}
  for _, c in ipairs(classes) do
    classes_set[c] = true
  end
  local dot = dot_for(classes)
  local dot_path = out .. "/" .. name .. ".dot"
  local svg_path = out .. "/" .. name .. ".svg"
  local fd = assert(io.open(dot_path, "w"))
  fd:write(dot)
  fd:close()
  local ok = os.execute(("dot -Tsvg %q -o %q"):format(dot_path, svg_path))
  if ok then dot_path = dot_path end
  if not ok then
    io.write(("dot が失敗した: %s\n"):format(name))
  end
end

-- 全体（人が読むクラス全部）
local all, order = {}, {}
local known = {}
for _, st in pairs(model.states or {}) do
  if st.class and not known[st.class] then
    known[st.class] = true
    order[#order + 1] = st.class
  end
end
table.sort(order)
write_svg("state_machine", order)

-- モードごと
local by_mode = {}
for _, c in ipairs(order) do
  local m = MODE_OF[c] or "misc"
  by_mode[m] = by_mode[m] or {}
  by_mode[m][#by_mode[m] + 1] = c
end
for mode, list in pairs(by_mode) do
  if #list > 0 then
    table.sort(list)
    write_svg("mode_" .. mode, list)
  end
end

io.write(("書いた: %s（クラス %d / 遷移の組 %d）\n"):format(out, #order, (function()
  local n = 0
  for _ in pairs(edges) do
    n = n + 1
  end
  return n
end)()))

return M

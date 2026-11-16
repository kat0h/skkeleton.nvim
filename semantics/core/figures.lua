-- core の図と、CORE.md の表の生成器（#260、親は #179）
--
-- semantics/core/rules.lua だけをデータ源にする。
-- 使い方（リポジトリの一番上で。luajit でも動く）:
--   nvim --headless -u NONE -i NONE -l semantics/core/figures.lua
--
-- 出力:
--   semantics/core/figures/core.{mmd,dot}        状態の図（全部の規則）
--   semantics/core/figures/<group>.{mmd,dot}     節ごとの図
--   semantics/core/figures/modes.{mmd,dot}       かなモードの図
--   semantics/core/CORE.md の <!-- gen:名前 --> 〜 <!-- /gen:名前 --> の間
--
-- 時刻や環境に依存する値は書かない。並びは rules.lua の順のまま。

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local T = dofile(dir .. "/rules.lua")

local RED = "#d64545"

local state_name, state_order = {}, {}
for i, s in ipairs(T.states) do
  state_name[s.id] = s.name
  state_order[s.id] = i
end
local key_label, key_class = {}, {}
for _, k in ipairs(T.key_classes) do
  key_label[k.id] = k.label
  key_class[k.id] = k
end
key_label["*"] = "どのキーでも"
local recommend = {}
for _, r in ipairs(T.recommends) do
  recommend[r.id] = r
end
local settle_name = {}
for _, s in ipairs(T.settle) do
  settle_name[s.id] = s.name
end

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function breaks(rule)
  for _, v in pairs(rule.views) do
    if v == "breaks" then
      return true
    end
  end
  return false
end

local function keys_of(rule)
  local parts = {}
  for i, k in ipairs(rule.key) do
    parts[i] = key_label[k] or k
  end
  return table.concat(parts, "・")
end

------------------------------------------------------------------------
-- 辺をまとめる。同じ from・to・線の種類の規則は 1 本にする
------------------------------------------------------------------------
local function collect(rules, with_short)
  local edges, index = {}, {}
  for _, r in ipairs(rules) do
    local style = (r.status == "undefined" and "u" or "c") .. (breaks(r) and "b" or "-")
    local line = keys_of(r) .. (with_short and r.short and ("／" .. r.short) or "") .. "（" .. r.id .. "）"
    for _, f in ipairs(r.from) do
      for _, t in ipairs(r.to) do
        local key = f .. "\0" .. t .. "\0" .. style
        local e = index[key]
        if not e then
          e = { from = f, to = t, dashed = r.status == "undefined", red = breaks(r), lines = {}, seen = {} }
          index[key] = e
          edges[#edges + 1] = e
        end
        if not e.seen[line] then
          e.seen[line] = true
          e.lines[#e.lines + 1] = line
        end
      end
    end
  end
  return edges
end

local MM = { [";"] = "#59;", ["<"] = "#lt;", [">"] = "#gt;", ['"'] = "#quot;" }
local function mm(s)
  return (s:gsub('[;<>"]', MM))
end

local function mermaid(nodes, edges, name_of)
  local out = { "flowchart LR" }
  for _, id in ipairs(nodes) do
    out[#out + 1] = ('  %s["%s"]'):format(id, mm(name_of[id]))
  end
  local styles = {}
  for i, e in ipairs(edges) do
    local parts = {}
    for j, l in ipairs(e.lines) do
      parts[j] = mm(l)
    end
    local arrow = e.dashed and "-.->" or "-->"
    out[#out + 1] = ('  %s %s|"%s"| %s'):format(e.from, arrow, table.concat(parts, "<br/>"), e.to)
    if e.red then
      styles[#styles + 1] = ("  linkStyle %d stroke:%s,color:%s"):format(i - 1, RED, RED)
    end
  end
  for _, s in ipairs(styles) do
    out[#out + 1] = s
  end
  return table.concat(out, "\n") .. "\n"
end

local function dq(s)
  return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local function dot(nodes, edges, name_of)
  local out = { "digraph {" }
  out[#out + 1] = "  rankdir=LR; splines=true; nodesep=0.45; ranksep=0.8;"
  out[#out + 1] = '  node [shape=box, style="rounded,filled", fillcolor="#ffffff", color="#2f6feb", fontname="Noto Sans CJK JP", fontsize=11];'
  out[#out + 1] = '  edge [fontname="Noto Sans CJK JP", fontsize=9, color="#3b5bdb", fontcolor="#3b5bdb"];'
  for _, id in ipairs(nodes) do
    out[#out + 1] = ('  "%s" [label="%s"];'):format(id, dq(name_of[id]))
  end
  for _, e in ipairs(edges) do
    local parts = {}
    for j, l in ipairs(e.lines) do
      parts[j] = dq(l)
    end
    local attrs = { ('label="%s"'):format(table.concat(parts, "\\n")) }
    if e.dashed then
      attrs[#attrs + 1] = "style=dashed"
    end
    if e.red then
      attrs[#attrs + 1] = ('color="%s", fontcolor="%s"'):format(RED, RED)
    end
    out[#out + 1] = ('  "%s" -> "%s" [%s];'):format(e.from, e.to, table.concat(attrs, ", "))
  end
  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

-- 辺に出てくる状態だけを、states の順で並べる
local function nodes_of(edges)
  local seen, nodes = {}, {}
  for _, e in ipairs(edges) do
    seen[e.from], seen[e.to] = true, true
  end
  for _, s in ipairs(T.states) do
    if seen[s.id] then
      nodes[#nodes + 1] = s.id
    end
  end
  return nodes
end

local figures = {}
do
  local edges = collect(T.rules, false)
  figures.core = { mmd = mermaid(nodes_of(edges), edges, state_name), dot = dot(nodes_of(edges), edges, state_name) }
  for _, g in ipairs(T.groups) do
    local rules = {}
    for _, r in ipairs(T.rules) do
      if r.group == g.id then
        rules[#rules + 1] = r
      end
    end
    local ge = collect(rules, true)
    figures[g.id] = { mmd = mermaid(nodes_of(ge), ge, state_name), dot = dot(nodes_of(ge), ge, state_name) }
  end
  -- かなモード
  local mode_name, mode_nodes = {}, {}
  for i, m in ipairs(T.modes) do
    mode_name[m.id] = m.name
    mode_nodes[i] = m.id
  end
  local me, index = {}, {}
  for _, m in ipairs(T.mode_edges) do
    local key = m.from .. "\0" .. m.to
    local e = index[key]
    if not e then
      e = { from = m.from, to = m.to, dashed = false, red = false, lines = {} }
      index[key] = e
      me[#me + 1] = e
    end
    e.red = e.red or m.breaks == true
    e.lines[#e.lines + 1] = m.key .. "（" .. m.rule .. "）"
  end
  figures.modes = { mmd = mermaid(mode_nodes, me, mode_name), dot = dot(mode_nodes, me, mode_name) }
end

for name, f in pairs(figures) do
  write(dir .. "/figures/" .. name .. ".mmd", f.mmd)
  write(dir .. "/figures/" .. name .. ".dot", f.dot)
end

------------------------------------------------------------------------
-- CORE.md の表
------------------------------------------------------------------------
local function md(s)
  return (tostring(s or ""):gsub("<", "&lt;"):gsub("|", "\\|"):gsub("%*", "\\*"))
end

local function names(ids)
  local parts = {}
  for i, id in ipairs(ids) do
    parts[i] = state_name[id] or id
  end
  return table.concat(parts, "、")
end

local VIEW_WORD = { holds = "守る", breaks = "**破る**", open = "決められない" }
local CONF_WORD = { read = "読んだ", inferred = "推測", open = "分からない" }

local function views_of(rule)
  local ids = {}
  for id in pairs(rule.views) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(a, b)
    if a:sub(1, 1) ~= b:sub(1, 1) then
      return a:sub(1, 1) > b:sub(1, 1) -- V を先に
    end
    return tonumber(a:sub(2)) < tonumber(b:sub(2))
  end)
  local parts = {}
  for i, id in ipairs(ids) do
    parts[i] = id .. " " .. VIEW_WORD[rule.views[id]]
  end
  return table.concat(parts, "、")
end

local blocks = {}

do -- 状態
  local out = { "| id | 状態 | 説明 | 実装の条件 | 結合の層の reading | phase |", "|---|---|---|---|---|---|" }
  for _, s in ipairs(T.states) do
    out[#out + 1] = ("| `%s` | %s | %s | %s | %s | %s |"):format(s.id, md(s.name), md(s.desc), md(s.impl), md(s.reading), md(s.phase))
  end
  blocks.states = table.concat(out, "\n")
end

do -- モード
  local out = { "| id | モード | 実装の条件 | 取りうる状態 |", "|---|---|---|---|" }
  for _, m in ipairs(T.modes) do
    out[#out + 1] = ("| `%s` | %s | %s | %s |"):format(m.id, md(m.name), md(m.impl), md(m.states))
  end
  out[#out + 1] = ""
  out[#out + 1] = "```mermaid"
  out[#out + 1] = figures.modes.mmd:gsub("\n$", "")
  out[#out + 1] = "```"
  blocks.modes = table.concat(out, "\n")
end

do -- キーの種類
  local out = { "| id | キー | 決め方 |", "|---|---|---|" }
  for _, k in ipairs(T.key_classes) do
    local desc = k.desc .. (k.otherwise and ("。ほかの状態では " .. key_label[k.otherwise] .. " と同じ") or "")
    out[#out + 1] = ("| `%s` | %s | %s |"):format(k.id, md(k.label), md(desc))
  end
  blocks.keys = table.concat(out, "\n")
end

do -- 打ちかけの片付け方
  local out = { "| 片付け方 | かなになる打ちかけ（n） | かなにならない打ちかけ（k） | 使う規則 | src |", "|---|---|---|---|---|" }
  for _, s in ipairs(T.settle) do
    local ids = {}
    for _, r in ipairs(T.rules) do
      if r.pending == s.id then
        ids[#ids + 1] = r.id .. "（" .. keys_of(r) .. "）"
      end
    end
    out[#out + 1] = ("| %s | %s | %s | %s | %s |"):format(md(s.name), md(s.complete), md(s.incomplete), md(table.concat(ids, "、")), md(s.src))
  end
  blocks.settle = table.concat(out, "\n")
end

for _, g in ipairs(T.groups) do -- 規則
  local out = { "```mermaid", (figures[g.id].mmd:gsub("\n$", "")), "```", "" }
  out[#out + 1] = "| id | 状態 | キー | 条件 | 行き先 | 出力 | 打ちかけ | 視点 | 確度 | src |"
  out[#out + 1] = "|---|---|---|---|---|---|---|---|---|---|"
  for _, r in ipairs(T.rules) do
    if r.group == g.id then
      local id = r.id .. (r.status == "undefined" and "（未定義）" or "") .. (r.recommend and (" → " .. r.recommend) or "")
      local again = r.again == "same" and "。打ち直す" or r.again == "lower" and "。小文字で打ち直す" or r.again == "henkan" and "。続けて変換" or ""
      out[#out + 1] = ("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |"):format(
        md(id),
        md(names(r.from)),
        md(keys_of(r)),
        md(r.guard or ""),
        md(names(r.to)),
        md(r.out),
        md((settle_name[r.pending] or "") .. again),
        views_of(r),
        CONF_WORD[r.confidence],
        md(r.src)
      )
    end
  end
  blocks["rules-" .. g.id] = table.concat(out, "\n")
end

do -- 全体の図
  blocks["fig-core"] = "```mermaid\n" .. figures.core.mmd:gsub("\n$", "") .. "\n```"
end

do -- 状態 × キー
  local cols = {}
  for _, k in ipairs(T.key_classes) do
    if not k.event or k.id == "ev:enable" or k.id == "ev:disable" then
      cols[#cols + 1] = k
    end
  end
  local function find(state, key)
    local ids = {}
    for _, r in ipairs(T.rules) do
      local in_from, in_key = false, false
      for _, f in ipairs(r.from) do
        in_from = in_from or f == state
      end
      for _, k in ipairs(r.key) do
        in_key = in_key or k == key
      end
      if in_from and in_key then
        ids[#ids + 1] = (r.id:gsub("^R%-", ""))
      end
    end
    return ids
  end
  local head, sep = { "| 状態" }, { "|---" }
  for _, k in ipairs(cols) do
    head[#head + 1] = md(k.label)
    sep[#sep + 1] = "---"
  end
  local out = { table.concat(head, " | ") .. " |", table.concat(sep, "|") .. "|" }
  local holes = {}
  for _, s in ipairs(T.states) do
    local row = { "| " .. md(s.name) }
    for _, k in ipairs(cols) do
      local ids = find(s.id, k.id)
      local note = ""
      if #ids == 0 and k.otherwise then
        ids = find(s.id, k.otherwise)
        note = "＝" .. key_label[k.otherwise]
      end
      if #ids == 0 then
        ids = find(s.id, "*")
      end
      if #ids == 0 then
        holes[#holes + 1] = s.name .. " × " .. k.label
      end
      row[#row + 1] = note ~= "" and md(note) or table.concat(ids, " ")
    end
    out[#out + 1] = table.concat(row, " | ") .. " |"
  end
  out[#out + 1] = ""
  out[#out + 1] = #holes == 0 and "どの組にも規則がある。" or ("規則の無い組：" .. md(table.concat(holes, "、")))
  blocks.matrix = table.concat(out, "\n")
end

do -- 視点ごとの結論
  local out = { "| 視点 | 内容 | 結論 | 破る規則 | 決められない規則 | 根拠 |", "|---|---|---|---|---|---|" }
  for _, v in ipairs(T.views) do
    local br, op = {}, {}
    for _, r in ipairs(T.rules) do
      if r.views[v.id] == "breaks" then
        br[#br + 1] = r.id
      elseif r.views[v.id] == "open" then
        op[#op + 1] = r.id
      end
    end
    local verdict = #br > 0 and "破っている" or (v.verdict == "open" or #op > 0) and "決められない" or "守っている"
    out[#out + 1] = ("| %s | %s | %s | %s | %s | %s |"):format(v.id, md(v.title), verdict, table.concat(br, "、"), table.concat(op, "、"), md(v.note))
  end
  blocks.views = table.concat(out, "\n")
end

do -- 推奨の一覧
  local out = {}
  for _, rec in ipairs(T.recommends) do
    local ids, now = {}, nil
    for _, r in ipairs(T.rules) do
      if r.recommend == rec.id then
        ids[#ids + 1] = r.id
        now = now or r.out
      end
    end
    if #ids > 0 then
      local alts = {}
      for i, a in ipairs(rec.alternatives or {}) do
        alts[i] = a.action .. "（" .. a.breaks .. "）"
      end
      local tags = (rec.ask and "【作者に選んでほしい】" or "") .. (rec.differs_from_upstream and "【upstream と違う推奨】" or "")
      out[#out + 1] = ("- [ ] **%s**（%s）%s：推奨 %s。理由：%s。upstream：%s。今の動き：%s／ほかの選択肢：%s"):format(
        table.concat(ids, "、"),
        rec.id,
        tags,
        md(rec.action),
        md(rec.why),
        md(rec.upstream),
        md(now),
        md(table.concat(alts, "／"))
      )
    end
  end
  blocks.recommend = table.concat(out, "\n")
end

do -- 数
  local conf, undefined, with_rec, br = { read = 0, inferred = 0, open = 0 }, 0, 0, 0
  for _, r in ipairs(T.rules) do
    conf[r.confidence] = conf[r.confidence] + 1
    undefined = undefined + (r.status == "undefined" and 1 or 0)
    with_rec = with_rec + (r.recommend and 1 or 0)
    br = br + (breaks(r) and 1 or 0)
  end
  blocks.stats = ("状態 %d 個、モード %d 個、キーの種類 %d 個、規則 %d 個（読んだ %d、推測 %d、分からない %d）。未定義 %d 個、視点を破る規則 %d 個、推奨を付けた規則 %d 個（推奨は %d 種類）。src は main の %s。"):format(
    #T.states,
    #T.modes - 1,
    #T.key_classes,
    #T.rules,
    conf.read,
    conf.inferred,
    conf.open,
    undefined,
    br,
    with_rec,
    #T.recommends,
    T.revision
  )
end

-- CORE.md の印の間を差し替える
do
  local path = dir .. "/CORE.md"
  local f = io.open(path, "r")
  if f then
    local text = f:read("*a")
    f:close()
    local names_sorted = {}
    for name in pairs(blocks) do
      names_sorted[#names_sorted + 1] = name
    end
    table.sort(names_sorted)
    for _, name in ipairs(names_sorted) do
      local open, close = "<!-- gen:" .. name .. " -->", "<!-- /gen:" .. name .. " -->"
      local s, e = text:find(open, 1, true)
      local s2, e2 = text:find(close, e or 1, true)
      if s and s2 then
        text = text:sub(1, e) .. "\n" .. blocks[name] .. "\n" .. text:sub(s2)
      else
        io.stderr:write("CORE.md に印が無い: " .. name .. "\n")
      end
    end
    write(path, text)
  end
end

print(blocks.stats)

-- かなテーブルと入力キーマップの静的検査。
local root = vim.fn.getcwd()
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local function entries_of(table_)
  local entries = {}
  for key, result in table_:entries() do
    if type(result) == "table" then
      entries[key] = { kana = result[1] or "", feed = result[2] or "" }
    else
      entries[key] = { function_value = result }
    end
  end
  return entries
end

local function read_input_functions(path)
  local file = assert(io.open(path or (root .. "/lua/skkeleton/keymap.lua"), "r"))
  local source = file:read("*a")
  file:close()
  local input = source:match("input = {%s*default =.-map = {(.-)},%s*},%s*henkan =")
  assert(input, "input keymap block not found")
  local keys = {}
  for line in input:gmatch("[^\n]+") do
    local key, value = line:match('%["(.-)"%]%s*=%s*(.-),?$')
    if key then
      keys[key] = value
    end
  end
  return keys
end

local function utf8_chars(text)
  local chars, i = {}, 1
  while i <= #text do
    local b = text:byte(i)
    local n = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    chars[#chars + 1] = text:sub(i, i + n - 1)
    i = i + n
  end
  return chars
end

local small = {}
for _, c in ipairs(utf8_chars("ぁぃぅぇぉゃゅょゎゕゖァィゥェォャュョヮヵヶ")) do
  small[c] = true
end
local function kana_units(text)
  local chars, units = utf8_chars(text), {}
  for _, c in ipairs(chars) do
    if small[c] and #units > 0 then
      units[#units] = units[#units] .. c
    else
      units[#units + 1] = c
    end
  end
  return units
end

local function is_kana_output(text)
  for _, c in ipairs(utf8_chars(text)) do
    local n = c:byte(1)
    if not (n >= 0xE3 and (c >= "ぁ" and c <= "ゖ" or c >= "ァ" and c <= "ヺ" or c == "ー")) then
      return false
    end
  end
  return text ~= ""
end

local function key_tokens(key)
  local tokens, i = {}, 1
  while i <= #key do
    if key:sub(i, i) == "<" then
      local stop = key:find(">", i, true)
      if stop then
        tokens[#tokens + 1] = key:sub(i, stop)
        i = stop + 1
      else
        tokens[#tokens + 1] = key:sub(i, i)
        i = i + 1
      end
    else
      tokens[#tokens + 1] = key:sub(i, i)
      i = i + 1
    end
  end
  return tokens
end

local function notation_key(key)
  return ({ ["<space>"] = " ", ["<lt>"] = "<", ["<bar>"] = "|", ["<bslash>"] = "\\" })[key] or key
end

local function keymap_key(key)
  if key == " " then
    return "<space>"
  end
  if key:match("^[A-Z]$") then
    return "<s-" .. key:lower() .. ">"
  end
  return key
end

local function output(table_, key)
  local entry = table_[key]
  return entry and entry.kana
end

local function table_node(table_, prefix)
  for key in pairs(table_) do
    if key:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

local function confirmed_kana(table_, key)
  local feed, output = "", ""
  local function press(token, seen)
    local joined = feed .. token
    local descendants = 0
    for candidate in pairs(table_) do
      if candidate:sub(1, #joined) == joined then
        descendants = descendants + 1
      end
    end
    local exact = table_[joined]
    if descendants > 0 then
      if exact and descendants == 1 and exact.kana then
        output = output .. exact.kana
        feed = exact.feed or ""
      else
        feed = joined
      end
    elseif feed ~= "" and not seen[feed] then
      local previous = table_[feed]
      if previous and previous.kana then
        output = output .. previous.kana
        feed = previous.feed or ""
      else
        feed = ""
      end
      seen[feed] = true
      press(token, seen)
    else
      feed = ""
      output = output .. token
    end
  end
  for _, token in ipairs(key_tokens(key)) do
    press(token, {})
  end
  return output
end

local function inspect(name, table_, keymap, historical, baseline)
  local keys, count = {}, 0
  for key in pairs(table_) do
    keys[#keys + 1] = key
    count = count + 1
  end
  table.sort(keys)
  local findings = { name = name, entries = count, unreachable = {}, v4 = {}, v10 = {}, nonkana = 0 }

  -- キーマップ関数が単独のテーブル項目を先に処理する衝突を報告する。
  for key, handler in pairs(keymap) do
    local literal = notation_key(key)
    local result = table_[literal]
    if result and result.function_value then
      local same_function = type(result.function_value) == "string"
        and handler:find(result.function_value, 1, true) ~= nil
      if historical or not same_function then
        findings.unreachable[#findings.unreachable + 1] = key .. " (keymap and function-valued table item overlap)"
      end
    elseif result and historical then
      findings.unreachable[#findings.unreachable + 1] = key .. " (pre-fix keymap precedes the table item)"
    elseif
      result
      and handler:find("kf%(") == nil
      and handler:find("henkanFirst") == nil
      and handler:find("prefix") == nil
    then
      findings.unreachable[#findings.unreachable + 1] = key .. " (keymap and table overlap)"
    end
    if historical then
      for _, table_key in ipairs(keys) do
        local tokens = key_tokens(table_key)
        for i = 2, #tokens do
          if tokens[i] == literal then
            local prefix = table.concat(tokens, "", 1, i - 1)
            findings.unreachable[#findings.unreachable + 1] = key
              .. " interrupts table entry "
              .. table_key
              .. " after "
              .. prefix
          end
        end
      end
    end
  end
  for _, key in ipairs(keys) do
    local function_name = table_[key].function_value
    local mapped_handler = keymap[key] or keymap[keymap_key(key)]
    if
      type(function_name) == "string"
      and function_name == "henkanFirst"
      and (not mapped_handler or not mapped_handler:find(function_name, 1, true))
    then
      findings.unreachable[#findings.unreachable + 1] = key .. " (henkanFirst table entry bypasses the keymap)"
    end
    if table_[key].function_value and historical then
      findings.unreachable[#findings.unreachable + 1] = key .. " (pre-fix callable table item)"
    elseif table_[key].function_value and not (keymap[key] or keymap[keymap_key(key)]) then
      local has_longer = false
      for _, longer in ipairs(keys) do
        if #longer > #key and longer:sub(1, #key) == key then
          has_longer = true
          findings.unreachable[#findings.unreachable + 1] = key .. " (function item prefixes " .. longer .. ")"
        end
      end
      if not has_longer and historical then
        findings.unreachable[#findings.unreachable + 1] = key
          .. " (function-valued table item without matching keymap function)"
      end
    end
  end
  if baseline then
    for key, old in pairs(baseline) do
      if old.function_value and table_[key] and not table_[key].function_value then
        findings.unreachable[#findings.unreachable + 1] = key .. " (callable item overwritten by text)"
      end
    end
  end

  -- V4: 短い項目のかなが、長い項目のかなの先頭に残るかを調べる。
  for _, short in ipairs(keys) do
    local a = table_[short]
    if a.kana then
      for _, long in ipairs(keys) do
        if #long > #short and long:sub(1, #short) == short then
          local b = table_[long]
          local suffix = long:sub(#short + 1)
          local first = key_tokens(suffix)[1]
          local intercepted = historical and first and keymap[keymap_key(first)] ~= nil
          local before = intercepted and a.kana or confirmed_kana(table_, short)
          local after = intercepted and b.kana or confirmed_kana(table_, long)
          if before ~= "" and after:sub(1, #before) ~= before then
            findings.v4[#findings.v4 + 1] = { short, long, before, after }
          end
        end
      end
    end
  end

  -- V10: 大文字開始キーで送りに入れる場所が、かな単位の境界かを調べる。
  for _, short in ipairs(keys) do
    local a = table_[short]
    if a.kana then
      for _, long in ipairs(keys) do
        if #long > #short and long:sub(1, #short) == short then
          local suffix = long:sub(#short + 1)
          local first = key_tokens(suffix)[1]
          if first and first:match("^[a-z]$") then
            local b = table_[long]
            if b.kana and b.kana:sub(1, #a.kana) == a.kana and is_kana_output(a.kana) and is_kana_output(b.kana) then
              local units, prefix = kana_units(b.kana), ""
              local boundaries = { [""] = true }
              for _, unit in ipairs(units) do
                prefix = prefix .. unit
                boundaries[prefix] = true
              end
              if not boundaries[a.kana] then
                findings.v10[#findings.v10 + 1] = { short, long, a.kana, b.kana }
              end
            end
          end
        end
      end
    end
  end

  -- 第3項：feed 状態を含む遷移で、かなが出ない cycle があるか調べる。
  local states, alphabet = { [""] = true }, {}
  for _, key in ipairs(keys) do
    local byte_prefix = ""
    for _, char in ipairs(utf8_chars(key)) do
      byte_prefix = byte_prefix .. char
      states[byte_prefix] = true
      alphabet[char] = true
    end
    local prefix = ""
    for _, token in ipairs(key_tokens(key)) do
      prefix = prefix .. token
      states[prefix] = true
      alphabet[token] = true
    end
    local feed = table_[key].feed
    if feed and feed ~= "" then
      states[feed] = true
      for _, char in ipairs(utf8_chars(feed)) do
        alphabet[char] = true
      end
      for _, token in ipairs(key_tokens(feed)) do
        alphabet[token] = true
      end
    end
  end
  local function next_feed(feed, token, seen)
    local joined = feed .. token
    local has_child, child_count = false, 0
    for key in pairs(table_) do
      if key:sub(1, #joined) == joined then
        has_child = true
        child_count = child_count + 1
      end
    end
    local exact = table_[joined]
    if has_child then
      if exact and child_count == 1 then
        return exact.feed or "", true
      end
      return joined, false
    end
    if feed ~= "" and not seen[feed] then
      local flushed = table_[feed]
      local reset = flushed and flushed.feed or ""
      local next_seen = vim.tbl_extend("force", seen, { [feed] = true })
      local target = next_feed(reset, token, next_seen)
      -- ミスマッチで元の feed は確定または破棄される。再入力キーの feed は次の判定単位。
      return target, true
    end
    -- テーブルにないキーはそのまま確定するので、先読みはここで終わる。
    return "", true
  end
  local graph = {}
  for state in pairs(states) do
    graph[state] = {}
    for token in pairs(alphabet) do
      local target, has_output = next_feed(state, token, {})
      if states[target] then
        graph[state][#graph[state] + 1] = { target = target, decided = has_output, key = token }
      end
    end
  end
  local active, memo, trail, trail_keys, cycle = {}, {}, {}, {}, nil
  local function wait_length(state)
    if active[state] then
      cycle = cycle or {}
      for i = active[state], #trail do
        cycle[#cycle + 1] = { state = trail[i], key = trail_keys[i] }
      end
      cycle[#cycle + 1] = { state = state }
      return math.huge
    end
    if memo[state] then
      return memo[state]
    end
    active[state] = #trail + 1
    trail[#trail + 1] = state
    local longest = 0
    for _, edge in ipairs(graph[state] or {}) do
      trail_keys[#trail + 1] = edge.key
      local length = edge.decided and 1 or 1 + wait_length(edge.target)
      if length > longest then
        longest = length
      end
      trail_keys[#trail_keys] = nil
    end
    active[state] = nil
    trail[#trail] = nil
    memo[state] = longest
    return longest
  end
  local max_lookahead = 0
  local infinite_states = {}
  for state in pairs(states) do
    local length = wait_length(state)
    if length == math.huge then
      infinite_states[#infinite_states + 1] = state
    end
    max_lookahead = math.max(max_lookahead, length)
  end
  findings.unbounded_lookahead = max_lookahead == math.huge
  findings.infinite_states = infinite_states
  findings.lookahead_cycle = cycle
  findings.max_lookahead = findings.unbounded_lookahead and "unbounded" or max_lookahead
  for _, key in ipairs(keys) do
    if table_[key].kana and not is_kana_output(table_[key].kana) then
      findings.nonkana = findings.nonkana + 1
    end
  end
  return findings
end

local function print_findings(result)
  print(
    ("%s: 項目=%d, 先読み上限=%s, 非かな出力=%d"):format(
      result.name,
      result.entries,
      result.max_lookahead,
      result.nonkana
    )
  )
  print(("  V1 衝突=%d, V4=%d, V10=%d"):format(#result.unreachable, #result.v4, #result.v10))
  if result.unbounded_lookahead then
    local states = {}
    for _, item in ipairs(result.lookahead_cycle or {}) do
      states[#states + 1] = item.state == "" and "∅" or item.state
    end
    print("  無出力cycle: " .. table.concat(states, " → "))
  end
  for _, item in ipairs(result.unreachable) do
    print(("  V1 %q"):format(item))
  end
  for _, item in ipairs(result.v4) do
    print(("  V4 %q -> %q: %q / %q"):format(item[1], item[2], item[3], item[4]))
  end
  for _, item in ipairs(result.v10) do
    print(("  V10 %q -> %q: %q / %q"):format(item[1], item[2], item[3], item[4]))
  end
end

-- 検査条件が小さな境界例でも合うことを確かめる。
local split_unit = inspect("self-check", {
  k = { kana = "き", feed = "" },
  ka = { kana = "きゃ", feed = "" },
}, {})
assert(#split_unit.v10 == 1 and #split_unit.v4 == 0, "V10 unit-boundary check failed")
local pending_n = inspect("self-check", {
  n = { kana = "ん", feed = "" },
  na = { kana = "な", feed = "" },
}, {})
assert(#pending_n.v4 == 0 and #pending_n.v10 == 0, "pending n must not count as confirmed kana")

local kana = require("skkeleton.kana")
local keymap = read_input_functions()
for _, name in ipairs({ "rom", "zen" }) do
  local table_ = entries_of(kana.get_table(name))
  print_findings(inspect(name, table_, keymap))
end
local azik_file = io.open(root .. "/.tests/azik-us.json", "r")
if azik_file then
  local azik = vim.json.decode(azik_file:read("*a"))
  azik_file:close()
  local entries = {}
  for key, result in pairs(azik) do
    if type(result) == "table" then
      entries[key] = { kana = result[1] or "", feed = result[2] or "" }
    else
      entries[key] = { function_value = result }
    end
  end
  print_findings(inspect("AZIK (k16em, US)", entries, keymap))
end

local historical_dir = root .. "/.tests/pre-fix"
local old_table_path = historical_dir .. "/lua/skkeleton/kana/rom_hira.lua"
local old_file = io.open(old_table_path, "r")
if old_file then
  old_file:close()
  local old_keymap = read_input_functions(historical_dir .. "/lua/skkeleton/keymap.lua")
  local old_table = entries_of(assert(loadfile(old_table_path))().new())
  local case41 = vim.deepcopy(old_table)
  case41.z = { function_value = "henkanFirst" }
  print_findings(inspect("#41 修正前 table + issue entry", case41, old_keymap, true, old_table))

  local case42 = vim.deepcopy(old_table)
  case42.z = { kana = "ab", feed = "" }
  case42["z "] = { kana = "　", feed = "" }
  case42[" "] = { kana = " ", feed = "" }
  local case42map = vim.deepcopy(old_keymap)
  case42map["<space>"] = "henkanFirst (issue keymap override)"
  print_findings(inspect("#42 修正前 rom_hira + issue table/keymap", case42, case42map, true, old_table))

  local case43 = vim.deepcopy(old_table)
  case43[" "] = { kana = "　", feed = "" }
  print_findings(inspect("#43 修正前 table + issue space override", case43, old_keymap, true, old_table))
end

-- 06 の観測（probe.jsonl）から、model.lua の M.probes に貼る表を作る（#186、親は #179）
--
-- semantics/compare/probe.lua が書いた JSONL を読み、遷移ごとに 1 つの観測を選んで、
-- model.lua に貼れる Lua の断片を出す。条件は次のとおり。
--
--   - 遷移の観測である（transition がある）
--   - 前置きが狙った状態になっている（prefix_class が状態クラスと一致）
--   - 終わりの状態が、モデルの期待（expect）に含まれている
--   - 同じ遷移について 1 つだけ（id の順で最初）
--
-- 使い方（リポジトリの一番上で動かす）:
--   nvim --headless -u NONE -i NONE -l semantics/compare/gen_probes.lua \
--     --probe semantics/compare/probe.jsonl --out /tmp/probes.lua
local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local model = dofile(dir .. "/../model/model.lua")

-- probe.lua と同じ分け方
local function chars(s)
  local out = {}
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    out[#out + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return out
end

local function scan_keys(s)
  local keys = {}
  local i = 1
  while i <= #s do
    if s:sub(i, i + 5) == "<Plug>" then
      local close = s:find(")", i, true)
      if close then
        keys[#keys + 1] = s:sub(i, close)
        i = close + 1
      else
        keys[#keys + 1] = s:sub(i, i)
        i = i + 1
      end
    elseif s:sub(i, i) == "<" then
      local close = s:find(">", i, true)
      if close then
        keys[#keys + 1] = s:sub(i, close)
        i = close + 1
      else
        keys[#keys + 1] = s:sub(i, i)
        i = i + 1
      end
    else
      local j = s:find("<", i, true) or (#s + 1)
      for _, ch in ipairs(chars(s:sub(i, j - 1))) do
        keys[#keys + 1] = ch
      end
      i = j
    end
  end
  return keys
end

local function tokens_to_keys(s)
  local keys = {}
  if not s or s == "" then
    return keys
  end
  for token in s:gmatch("[^,]+") do
    token = vim.trim(token)
    if token ~= "" then
      for _, k in ipairs(scan_keys(token)) do
        keys[#keys + 1] = k
      end
    end
  end
  return keys
end

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

local function main(argv)
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
      print("使い方: nvim --headless -u NONE -i NONE -l semantics/compare/gen_probes.lua --probe <path> --out <path>")
      return
    else
      error(("知らない引数です: %s"):format(arg))
    end
    i = i + 1
  end

  local probes = read_jsonl(probe_path)
  if not probes then
    error(("観測を読めません: %s"):format(probe_path))
  end
  table.sort(probes, function(a, b)
    return (a.id or "") < (b.id or "")
  end)

  local seen = {}
  local lines = {}
  for _, p in ipairs(probes) do
    if p.transition and not seen[p.transition] and not p.error and not p.blocked then
      local state = p.state or p.from
      local st = model.states[state]
      local ok_prefix = st ~= nil and p.prefix_class == st.class
      local ok_final = false
      for _, want in ipairs(p.expect or {}) do
        if want == p.final_class then
          ok_final = true
        end
      end
      if ok_prefix and ok_final then
        seen[p.transition] = true
        -- 前置きは 1 キーずつに開く（Kan -> K, a, n）。イベントのキーは
        -- `<C-o>v` のようなまとまりを 1 つのキーとして扱う（model.lua の events.keys と同じ）。
        local keys = tokens_to_keys(p.prefix)
        for token in (p.keys or ""):gmatch("[^,]+") do
          token = vim.trim(token)
          if token ~= "" then
            keys[#keys + 1] = token
          end
        end
        local quoted = {}
        for _, k in ipairs(keys) do
          quoted[#quoted + 1] = ("%q"):format(k)
        end
        local line = ('  { id = "P.%s", transition = "%s", keys = { %s }, expect = { "%s" }'):format(
          p.transition,
          p.transition,
          table.concat(quoted, ", "),
          p.final_class
        )
        if p.world == "keepstate" then
          line = line .. ', config = { keepState = true }'
        end
        line = line .. " },"
        lines[#lines + 1] = line
      end
    end
  end

  local text = table.concat(lines, "\n")
  if out_path then
    vim.fn.mkdir(vim.fs.dirname(out_path), "p")
    vim.fn.writefile(vim.split(text, "\n", { plain = true }), out_path)
    print(("観測 %d 件のうち、遷移ごとの観測 %d 件を書きました: %s"):format(#probes, #lines, out_path))
  else
    print(text)
  end
end

main(arg)

-- SKK-JISYO.L の全候補が変換で出ることの確認。重いので make test には入れず、必要なときだけ流す。
-- 使い方: make jisyotest ARGS="--sample 2000"
--   nvim --headless -u NONE -i NONE -l tests/jisyo/run.lua [--dict PATH] [--sample N] [--seed S] [--jobs J] [--filter 読みの前方一致] [--max-fail N]
-- 辞書が無ければ skip して終了コード 0 で終わる（CI では流さないが、手元で落ちないように）。
-- 読みごとに、ローマ字で打って Space を候補の数だけ押し、そのつど pre-edit が「▼候補」になるか見る。
-- 期待値は辞書ファイルを自前で読んで作る（本体の辞書パーサは使わない）。
-- 対象外（件数は数えて出す）: 読みに打てない文字を含むもの、候補が (concat ...) などの式のもの、
--   送りの子音が okuri.lua の表にないもの
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")

local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end
vim.opt.rtp:append(mini)
package.path = root .. "/tests/?.lua;" .. package.path
MiniTest = require("mini.test")
local helpers = require("helpers")

local opts = {
  dict = "/usr/share/skk/SKK-JISYO.L",
  sample = nil,
  seed = 20261031,
  jobs = math.max(1, #vim.uv.cpu_info() - 2),
  filter = nil,
  max_fail = 50,
  worker = nil,
}
do
  local i = 1
  local num = { ["--sample"] = "sample", ["--seed"] = "seed", ["--jobs"] = "jobs", ["--max-fail"] = "max_fail" }
  while i <= #arg do
    local k = arg[i]
    if num[k] then
      opts[num[k]] = tonumber(arg[i + 1])
      i = i + 1
    elseif k == "--dict" then
      opts.dict = arg[i + 1]
      i = i + 1
    elseif k == "--filter" then
      opts.filter = arg[i + 1]
      i = i + 1
    elseif k == "--worker" then
      opts.worker = arg[i + 1]
      i = i + 1
    end
    i = i + 1
  end
end

-- ひらがな → ローマ字。小書きは x 付き、っ は xtu、ん は nn で打つ（曖昧さを避ける）
local ROMA = {}
do
  local rows = {
    { "", { "あ", "い", "う", "え", "お" } },
    { "k", { "か", "き", "く", "け", "こ" } },
    { "g", { "が", "ぎ", "ぐ", "げ", "ご" } },
    { "s", { "さ", "し", "す", "せ", "そ" } },
    { "z", { "ざ", "じ", "ず", "ぜ", "ぞ" } },
    { "t", { "た", "ち", "つ", "て", "と" } },
    { "d", { "だ", "ぢ", "づ", "で", "ど" } },
    { "n", { "な", "に", "ぬ", "ね", "の" } },
    { "h", { "は", "ひ", "ふ", "へ", "ほ" } },
    { "b", { "ば", "び", "ぶ", "べ", "ぼ" } },
    { "p", { "ぱ", "ぴ", "ぷ", "ぺ", "ぽ" } },
    { "m", { "ま", "み", "む", "め", "も" } },
    { "r", { "ら", "り", "る", "れ", "ろ" } },
    { "x", { "ぁ", "ぃ", "ぅ", "ぇ", "ぉ" } },
  }
  local vow = { "a", "i", "u", "e", "o" }
  for _, r in ipairs(rows) do
    for j, ch in ipairs(r[2]) do
      ROMA[ch] = r[1] .. vow[j]
    end
  end
  ROMA["や"], ROMA["ゆ"], ROMA["よ"] = "ya", "yu", "yo"
  ROMA["ゃ"], ROMA["ゅ"], ROMA["ょ"] = "xya", "xyu", "xyo"
  ROMA["わ"], ROMA["を"], ROMA["ん"] = "wa", "wo", "nn"
  ROMA["ゎ"], ROMA["っ"], ROMA["ゔ"], ROMA["ー"] = "xwa", "xtu", "vu", "-"
end

-- 読み（送りの子音を除いたもの）を打つキー列。打てない文字があれば nil, その文字
local function romaji_keys(yomi)
  local keys = {}
  for i, c in ipairs(vim.fn.split(yomi, "\\zs")) do
    local r = ROMA[c]
    if not r then
      return nil, c
    end
    if i == 1 then
      -- ー は大文字にできないので ; で変換を始める
      r = c == "ー" and ";-" or r:sub(1, 1):upper() .. r:sub(2)
    end
    keys[#keys + 1] = r
  end
  return table.concat(keys)
end

-- 末尾か先頭の印を落として、重複を除く
local function dedupe(cands, pat)
  local out, seen = {}, {}
  for _, c in ipairs(cands) do
    c = c:gsub(pat, "")
    if c ~= "" and not seen[c] then
      seen[c] = true
      out[#out + 1] = c
    end
  end
  return out
end

-- 仮名の読みではない見出し（abbrev・接頭辞・接尾辞・数値変換）を打つキー列。該当しなければ nil
local function special_entry(base)
  if base:find("^[ -~]+$") and not base:find("^#") then
    return { kind = "abbrev", keys = "/" .. base:gsub("<", "<lt>") }
  end
  local stem = base:match("^(.+)>$")
  if stem and not stem:find("[ -~]") then
    local k = romaji_keys(stem)
    return k and { kind = "prefix", affix = "prefix", keys = k .. ">", first_shown = true }
  end
  stem = base:match("^>(.+)$")
  if stem and not stem:find("[ -~]") then
    -- 接尾辞は、前の語を変換した直後に > を打って続ける。1 文字目は小文字で打つ
    local k = romaji_keys(stem)
    return k and { kind = "suffix", affix = "suffix", keys = "Kan<Space>>" .. k:sub(1, 1):lower() .. k:sub(2) }
  end
  stem = base:match("^#(.+)$")
  if stem and not stem:find("[ -~]") then
    local k = romaji_keys(stem)
    return k and { kind = "numeral", keys = ";12" .. k:sub(1, 1):lower() .. k:sub(2), loose = true }
  end
end

-- okuri.lua の表にある送りの子音
local OKURI_OK = {}
for c in ("xaiueokgszjtdnhbpmyrwv"):gmatch(".") do
  OKURI_OK[c] = true
end

-- 辞書ファイルを読んで、テスト項目 { yomi, keys, okuri, cands, ... } の一覧と、対象外の件数を返す
local function load_entries(path)
  local f = assert(io.open(path, "rb"))
  local raw = f:read("*a")
  f:close()
  local text = vim.iconv(raw, "euc-jp", "utf-8")
  assert(text, "iconv failed")
  local entries = {}
  local skipped = { yomi = 0, expr = 0, okuri = 0, dup = 0, nokey = {}, special = {} }
  local index = {}
  local okuri_ari = false
  for line in text:gmatch("[^\n]+") do
    if line:find("^;; okuri%-ari") then
      okuri_ari = true
    elseif line:find("^;; okuri%-nasi") then
      okuri_ari = false
    elseif line:sub(1, 1) ~= ";" then
      local yomi, rest = line:match("^(%S+) (/.*)$")
      if yomi then
        local okuri
        local base = yomi
        if okuri_ari then
          okuri = base:match("([a-z])$")
          if okuri then
            base = base:sub(1, -2)
          end
        end
        local cands, seen, expr = {}, {}, false
        for tok in rest:gmatch("/([^/]*)") do
          if tok ~= "" then
            if tok:find("^%(") then
              expr = true
            else
              local c = tok:gsub(";.*$", "")
              if not seen[c] then
                seen[c] = true
                cands[#cands + 1] = c
              end
            end
          end
        end
        local keys, bad = romaji_keys(base)
        local special = not okuri_ari and special_entry(base)
        if special then
          if special.affix == "prefix" then
            cands = dedupe(cands, ">$")
          elseif special.affix == "suffix" then
            cands = dedupe(cands, "^>")
          end
          special.yomi, special.cands = yomi, cands
          local id = "n:" .. yomi
          if expr then
            skipped.expr = skipped.expr + 1
          elseif #cands > 0 then
            if index[id] then
              entries[index[id]] = special
              skipped.dup = skipped.dup + 1
            else
              entries[#entries + 1] = special
              index[id] = #entries
              skipped.special[special.kind] = (skipped.special[special.kind] or 0) + 1
            end
          end
        elseif okuri_ari and not okuri then
          -- 送りあり側にあるのに末尾が子音でない見出し（辞書の誤り）。入力のしようがない
          skipped.yomi = skipped.yomi + 1
        elseif okuri and not OKURI_OK[okuri] then
          -- 送り仮名から引く子音は okuri.lua の表で決まるので、この見出しには仮名の入力からは届かない
          skipped.okuri = skipped.okuri + 1
        elseif not keys then
          if base:find("^[%z\1-\127]") or base:find("[>#]") or okuri_ari ~= (okuri ~= nil) then
            skipped.yomi = skipped.yomi + 1
          else
            skipped.nokey[bad] = (skipped.nokey[bad] or 0) + 1
          end
        elseif expr then
          skipped.expr = skipped.expr + 1
        elseif #cands > 0 then
          -- 同じ見出しが 2 行以上ある辞書では、あとの行を使う (#48)
          local id = (okuri_ari and "a:" or "n:") .. yomi
          local entry = { yomi = yomi, keys = keys, okuri = okuri, cands = cands }
          if index[id] then
            entries[index[id]] = entry
            skipped.dup = skipped.dup + 1
          else
            entries[#entries + 1] = entry
            index[id] = #entries
          end
        end
      end
    end
  end
  return entries, skipped
end

-- 子に entries を順に打って、食い違いを返す。キー入力の流し方は tests/helpers.lua と同じ
local SHOW, KEYS = 4, "asdfjkl"
local function check(child, entries, max_fail)
  local fails = {}
  local function reset()
    helpers.type(child, "<Esc><Esc><Esc>")
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    helpers.type(child, "i<Plug>(skkeleton-enable)")
  end
  reset()
  for _, e in ipairs(entries) do
    local keys = e.keys
    if e.okuri then
      local o = e.okuri
      if o:find("[aiueo]") then
        keys = keys .. o:upper()
      elseif o == "c" then
        keys = keys .. "Cha"
      else
        keys = keys .. o:upper() .. "a"
      end
    end
    helpers.type(child, keys)
    local bad
    local n = #e.cands
    local function expect_preedit(i)
      local got = helpers.preedit(child)
      local want = "▼" .. e.cands[i]
      local ok
      if e.loose then
        -- 数値変換の候補は #0 などが数に置き換わる。リテラルの部分が並んでいるかだけ見る
        local pat = "^" .. vim.pesc(want):gsub("#%d", ".*") .. ".*"
        ok = got:find(pat) ~= nil
      else
        ok = got:sub(1, #want) == want
      end
      if not ok then
        bad = { yomi = e.yomi, index = i, want = e.cands[i], got = got }
      end
      return not bad
    end
    -- 4 個目までは Space 1 回で 1 個ずつ。5 個目からは popup に 7 個ずつ出て、Space で次のページに進む
    local i = 1
    while i <= math.min(n, SHOW) and not bad do
      if i > 1 or not (e.okuri or e.first_shown) then
        helpers.type(child, "<Space>")
      end
      expect_preedit(i)
      i = i + 1
    end
    if not bad and n > SHOW then
      local p = SHOW + 1
      helpers.type(child, "<Space>")
      while not bad do
        local want = {}
        for k = p, math.min(p + #KEYS - 1, n) do
          want[#want + 1] = KEYS:sub(k - p + 1, k - p + 1) .. ": " .. e.cands[k]
        end
        if expect_preedit(p) then
          local got = helpers.popup(child)
          -- 数値変換では、popup に辞書にない数の表記が足される。数値の見出しは、辞書の候補が先頭に並んでいればよい
          local lenient = e.loose or e.yomi:find("^%d+$")
          local same = vim.deep_equal(got, want)
          if lenient and type(got) == "table" then
            same = e.loose or vim.deep_equal(vim.list_slice(got, 1, #want), want)
          end
          if not same then
            bad = { yomi = e.yomi, index = p, want = table.concat(want, " "), got = vim.inspect(got) }
          end
        end
        if bad or p + #KEYS > n then
          break
        end
        p = p + #KEYS
        helpers.type(child, "<Space>")
      end
    end
    if bad then
      fails[#fails + 1] = bad
      if #fails >= max_fail then
        break
      end
      reset()
    else
      -- 最後の候補を確定して、行を空に戻す（skkeleton は有効のまま）
      helpers.type(child, "<C-j>")
      child.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
      child.api.nvim_win_set_cursor(0, { 1, 0 })
    end
  end
  return fails
end

local function run_worker(spec)
  local entries = vim.json.decode(vim.fn.readfile(spec.file)[1])
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local child = MiniTest.new_child_neovim()
  child.start({ "-u", root .. "/tests/minimal_init.lua" })
  child.lua("require('skkeleton').setup(...)", {
    {
      globalDictionaries = { { opts.dict, "euc-jp" } },
      userDictionary = dir .. "/user",
      databasePath = dir .. "/db",
      indicator = false,
    },
  })
  local all = {}
  local batch = 500
  for i = 1, #entries, batch do
    local part = vim.list_slice(entries, i, math.min(i + batch - 1, #entries))
    vim.list_extend(all, check(child, part, opts.max_fail - #all))
    io.stderr:write(string.format("worker %s: %d/%d\n", spec.id, math.min(i + batch - 1, #entries), #entries))
    if #all >= opts.max_fail then
      break
    end
  end
  child.stop()
  vim.fn.writefile({ vim.json.encode(all) }, spec.out)
end

if opts.worker then
  run_worker(vim.json.decode(opts.worker))
  vim.cmd("qa!")
  return
end

-- 親: 辞書を読み、絞り込み、worker に分けて流す
-- 辞書が無い環境（CI など）では落とさず、skip して終わる
do
  local f = io.open(opts.dict, "rb")
  if not f then
    print(string.format("skip: 辞書が無い（%s）", opts.dict))
    os.exit(0)
  end
  f:close()
end
local entries, skipped = load_entries(opts.dict)
local total_cands = 0
for _, e in ipairs(entries) do
  total_cands = total_cands + #e.cands
end
print(string.format("読み込み: %d エントリ、候補 %d 個", #entries, total_cands))
local nokey = 0
for _, n in pairs(skipped.nokey) do
  nokey = nokey + n
end
print(
  string.format(
    "対象外: 仮名以外の読み %d、式の候補 %d、打てない文字を含む読み %d、届かない送りの子音 %d",
    skipped.yomi,
    skipped.expr,
    nokey,
    skipped.okuri
  )
)
print("特別な見出し: " .. vim.inspect(skipped.special):gsub("%s+", " "))
print(string.format("同じ見出しが複数行ある: %d 件（あとの行を期待値にした）", skipped.dup))
if nokey > 0 then
  local parts = {}
  for c, n in pairs(skipped.nokey) do
    parts[#parts + 1] = c .. "=" .. n
  end
  print("  打てない文字: " .. table.concat(parts, " "))
end

if opts.filter then
  entries = vim.tbl_filter(function(e)
    return vim.startswith(e.yomi, opts.filter)
  end, entries)
end
if opts.sample and opts.sample < #entries then
  math.randomseed(opts.seed)
  for i = #entries, 2, -1 do
    local j = math.random(i)
    entries[i], entries[j] = entries[j], entries[i]
  end
  entries = vim.list_slice(entries, 1, opts.sample)
end
print(string.format("実行: %d エントリ、%d worker", #entries, opts.jobs))

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local procs = {}
for w = 1, opts.jobs do
  local part = {}
  for i = w, #entries, opts.jobs do
    part[#part + 1] = entries[i]
  end
  local spec = { id = w, file = tmp .. "/in" .. w, out = tmp .. "/out" .. w }
  vim.fn.writefile({ vim.json.encode(part) }, spec.file)
  procs[w] = vim.system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-i",
    "NONE",
    "-l",
    here .. "/run.lua",
    "--dict",
    opts.dict,
    "--max-fail",
    tostring(opts.max_fail),
    "--worker",
    vim.json.encode(spec),
  }, { text = true, env = { MINI_PATH = mini } })
end
local fails = {}
for w, p in ipairs(procs) do
  local r = p:wait()
  if r.code ~= 0 then
    print(string.format("worker %d が異常終了 (code %d)\n%s", w, r.code, r.stderr or ""))
    fails[#fails + 1] = { yomi = "(worker crash)", index = 0, want = "", got = tostring(r.code) }
  else
    local out = vim.fn.readfile(tmp .. "/out" .. w)
    vim.list_extend(fails, vim.json.decode(out[1]))
  end
end
if #fails == 0 then
  print("OK: 全部の候補が出た")
  os.exit(0)
end
print(string.format("NG: %d 件", #fails))
for i, f in ipairs(fails) do
  if i > opts.max_fail then
    break
  end
  print(string.format("  %s [%d番目] 期待 ▼%s / 実際 %q", f.yomi, f.index, f.want, f.got))
end
os.exit(1)

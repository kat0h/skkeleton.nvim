-- denops 版に共通のキー列を流し、観測結果を保存する
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
local here = root .. "/semantics/conformance"
local diff_dir = root .. "/tests/diff"
local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
if not vim.startswith(mini, "/") then
  mini = root .. "/" .. mini
end
vim.opt.rtp:append(mini)
package.path = diff_dir .. "/?.lua;" .. package.path
local MiniTest = require("mini.test")
MiniTest.setup()

local cases = dofile(here .. "/cases.lua")
local driver = require("driver")
local function dictionary_text()
  local out = { ";; okuri-ari entries." }
  for _, row in ipairs(cases.dictionary.okuri_ari) do
    out[#out + 1] = row[1] .. " /" .. table.concat(row[2], "/") .. "/"
  end
  out[#out + 1] = ";; okuri-nasi entries."
  for _, row in ipairs(cases.dictionary.okuri_nasi) do
    out[#out + 1] = row[1] .. " /" .. table.concat(row[2], "/") .. "/"
  end
  return table.concat(out, "\n") .. "\n"
end

local function split_okuri_candidate(candidate)
  local matches = {}
  for _, row in ipairs(cases.dictionary.okuri_ari) do
    local reading = row[1]:sub(1, -2)
    for _, word in ipairs(row[2]) do
      if #candidate >= #word and candidate:sub(1, #word) == word then
        local okuri = candidate:sub(#word + 1)
        local key = table.concat({ word, reading, okuri }, "\0")
        matches[key] = { word = word, reading = reading, okuri = okuri }
      end
    end
  end
  local only
  for _, match in pairs(matches) do
    if only then
      return nil, true
    end
    only = match
  end
  if only and only.okuri ~= "" then
    return only
  end
end

local function observe(s)
  local out = {}
  local text = table.concat(s.lines or { "" }, "\n")
  local hira_marker = text:find("▽", 1, true)
  local select_marker = text:find("▼", 1, true)
  local marker = hira_marker
  if not marker or (select_marker and select_marker < marker) then
    marker = select_marker
  end
  if marker then
    out.text = text:sub(1, marker - 1)
    local mark = text:sub(marker, marker == hira_marker and marker + #"▽" - 1 or marker + #"▼" - 1)
    local rest = text:sub(marker + #mark)
    local okuri_at = rest:find("*", 1, true)
    local preedit = okuri_at and rest:sub(1, okuri_at - 1) or rest
    local okuri = okuri_at and rest:sub(okuri_at + 1) or ""
    local pending = preedit:match("([A-Za-z]+)$")
    if pending then
      preedit = preedit:sub(1, #preedit - #pending)
      out.pending = pending
    end
    out.stage = mark == "▽" and "reading" or "select"
    if mark == "▽" then
      out.reading = preedit
      out.okuri = okuri
    else
      -- 候補に送りが連結されるため、辞書で分け方が一意なときだけ分ける。
      local okuri_candidate, ambiguous = split_okuri_candidate(preedit)
      if okuri_candidate then
        out.candidate = okuri_candidate.word
        out.reading = okuri_candidate.reading
        out.okuri = okuri_candidate.okuri
      elseif not ambiguous then
        out.candidate = preedit
      end
    end
  else
    out.text = text
    out.stage = "none"
  end
  if s.vim and s.vim:sub(1, 1) == "c" then
    out.stage = "register"
    local edit = s.cmdline or text
    local reg_hira = edit:find("▽", 1, true)
    local reg_select = edit:find("▼", 1, true)
    local regmark = reg_hira
    if not regmark or (reg_select and reg_select < regmark) then
      regmark = reg_select
    end
    if regmark then
      local mark = edit:sub(regmark, regmark == reg_hira and regmark + #"▽" - 1 or regmark + #"▼" - 1)
      local tail = edit:sub(regmark + #mark)
      out.reading = tail:match("([^*]*)") or ""
      out.okuri = tail:match("%*(.*)") or ""
    end
  end
  local modes = { hira = "hira", kata = "kata", hankata = "hankata", zenkaku = "zenkaku", abbrev = "abbrev", ascii = "ascii" }
  if s.mode then
    out.mode = modes[s.mode] or s.mode
  end
  if s.enabled == false then
    out.mode = "ascii"
  end
  return out
end

local function main()
  local reason = driver.unavailable()
  local out = { impl = "denops", settings = vim.empty_dict(), results = {} }
  if reason then
    for _, case in ipairs(cases.cases) do
      out.results[case.id] = { na = reason }
    end
  else
    out.version = os.getenv("SKKELETON_UPSTREAM_VERSION") or "unknown"
    local child = MiniTest.new_child_neovim()
    local dict = dictionary_text()
    for _, case in ipairs(cases.cases) do
      local r = driver.run("denops", child, dict, case.keys, nil, true)
      if r.error then
        out.results[case.id] = { error = r.error }
      else
        local last = r.steps[#r.steps]
        if last and last.key == "<Esc>(cancel)" then
          last = r.steps[#r.steps - 1]
        end
        out.results[case.id] = { observe = observe(last) }
      end
    end
  end
  local dir = here .. "/results"
  vim.fn.mkdir(dir, "p")
  local f = assert(io.open(dir .. "/denops.json", "w"))
  f:write(vim.json.encode(out), "\n")
  f:close()
  local lua = assert(io.open(dir .. "/denops.lua", "w"))
  lua:write("return ", vim.inspect(out), "\n")
  lua:close()
  vim.cmd("qall!")
end

main()

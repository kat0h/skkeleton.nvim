-- 形式検証の PoC: 見つけた反例のキー列を、Lua 版と upstream（denops 版）の両方に流して見比べる。
-- 探索は Lua 版だけでする。denops 版は起動に時間がかかるので、反例を確かめるときだけ使う。
-- tests/diff の driver を使うので、空のバッファで有効にした状態から始まる（初期状態の "#mid" などは捨てる）
--
-- 使い方: nvim --headless -u NONE -i NONE -l tests/formal/upstream.lua 'A<Space>A<Left><CR><C-g>'
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")
local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")
vim.opt.rtp:append(mini)
package.path = root .. "/tests/diff/?.lua;" .. root .. "/tests/?.lua;" .. package.path
MiniTest = require("mini.test")
MiniTest.setup()

local driver = require("driver")
local profiles = require("formal.profiles")

local keys = (arg[1] or ""):gsub("#%w+", "")
local reason = driver.unavailable()
if reason then
  print("skip: " .. reason)
  vim.cmd("qall!")
end

local function line(s)
  local t = table.concat(s.lines or {}, "⏎")
  if s.cmdline then
    t = t .. "  cmdline=" .. s.cmdline
  end
  return ("%s [%s] %s"):format(s.vim, tostring(s.mode), t)
end

local results = {}
for _, impl in ipairs({ "lua", "denops" }) do
  results[impl] = driver.run(impl, MiniTest.new_child_neovim(), profiles.default.dict, keys)
end
local a, b = results.lua, results.denops
print(("%-10s %-36s %s"):format("key", "Lua 版", "denops 版"))
local differ = false
for i = 1, math.max(#a.steps, #b.steps) do
  local sa, sb = a.steps[i], b.steps[i]
  local la, lb = sa and line(sa) or "-", sb and line(sb) or "-"
  local mark = la == lb and " " or "≠"
  differ = differ or la ~= lb
  print(("%s %-10s %-36s %s"):format(mark, (sa or sb).key, la, lb))
end
for impl, r in pairs(results) do
  if r.error then
    print(impl .. ": " .. r.error)
  end
end
print(differ and "違いあり" or "同じ（upstream でも同じことが起きる）")
vim.cmd("qall!")

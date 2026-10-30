-- enable / disable / toggle とモード、User イベント、キーマップの出し入れ
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function enable()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
end

local function vim_mode()
  return child.fn["skkeleton#mode"]()
end

-- User イベントを { 名前, enabled, mode } で _G.log に積む
local function log_events(names)
  child.lua(
    [[
    _G.log = {}
    for _, name in ipairs(...) do
      vim.api.nvim_create_autocmd("User", {
        pattern = name,
        callback = function()
          table.insert(_G.log, { name, vim.g["skkeleton#enabled"], vim.g["skkeleton#mode"] })
        end,
      })
    end
  ]],
    { names }
  )
end

T["Can get skkeleton mode"] = function()
  eq(vim_mode(), "")
  eq(child.fn["skkeleton#is_enabled"](), false)
  enable()
  eq(vim_mode(), "hira")
  eq(child.fn["skkeleton#is_enabled"](), true)
  type("<Plug>(skkeleton-disable)")
  eq(vim_mode(), "")
  enable()
  type("q")
  eq(vim_mode(), "kata")
  type("q")
  eq(vim_mode(), "hira")
  type("<C-q>")
  eq(vim_mode(), "hankata")
  child.lua([[require("skkeleton.function.mode").zenkaku(require("skkeleton.store").context())]])
  eq(vim_mode(), "zenkaku")
end

T["the Lua API agrees with the variables"] = function()
  eq(child.lua_get([[require("skkeleton").mode() ]]), "")
  eq(child.lua_get([[require("skkeleton").is_enabled() ]]), false)
  enable()
  eq(child.lua_get([[require("skkeleton").mode() ]]), "hira")
  eq(child.lua_get([[require("skkeleton").is_enabled() ]]), true)
end

T["Fire autocmd for mode changed"] = function()
  child.cmd([[autocmd User skkeleton-mode-changed let g:mode_actual = g:skkeleton#mode]])
  enable()
  type("q")
  eq(child.g.mode_actual, "kata")
  type("q")
  eq(child.g.mode_actual, "hira")
  type("<C-q>")
  eq(child.g.mode_actual, "hankata")
end

T["mode change at enable"] = function()
  child.cmd([[autocmd User skkeleton-mode-changed let g:mode_actual = skkeleton#mode()]])
  enable()
  eq(child.g.mode_actual, "hira")
end

T["User events are fired after the variables are updated"] = function()
  log_events({
    "skkeleton-initialize-pre",
    "skkeleton-initialize-post",
    "skkeleton-enable-pre",
    "skkeleton-enable-post",
    "skkeleton-disable-pre",
    "skkeleton-disable-post",
    "skkeleton-mode-changed",
  })
  enable()
  eq(child.lua_get("_G.log"), {
    { "skkeleton-initialize-pre", false, "" },
    { "skkeleton-initialize-post", false, "" },
    { "skkeleton-enable-pre", false, "" },
    { "skkeleton-mode-changed", true, "hira" },
    { "skkeleton-enable-post", true, "hira" },
  })
  child.lua("_G.log = {}")
  type("<Plug>(skkeleton-disable)")
  eq(child.lua_get("_G.log"), {
    { "skkeleton-disable-pre", true, "hira" },
    { "skkeleton-mode-changed", true, "" },
    { "skkeleton-disable-post", true, "" },
  })
  eq(child.g["skkeleton#enabled"], false)
end

T["User skkeleton-handled is fired after each key"] = function()
  enable()
  child.cmd([[let g:handled = 0 | autocmd User skkeleton-handled let g:handled += 1]])
  type("k")
  eq(child.g.handled, 1)
  type("a")
  eq(child.g.handled, 2)
  type("Ka")
  eq(child.g.handled, 4)
end

T["kakutei at disable"] = function()
  enable()
  type("<Space>")
  type("<Plug>(skkeleton-disable)")
  eq(helpers.buffer(child), { " " })
  type("<Plug>(skkeleton-enable)")
  type("n")
  type("<Plug>(skkeleton-disable)")
  eq(helpers.buffer(child), { " ん" })
end

T["disable just after completion"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "変換結果", "" })
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  enable()
  type(";hoge")
  -- 補完などでバッファが動くと pre-edit は捨てられる
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("skkeleton.main").handle("disable", { key = {} })]])
  eq(child.g["skkeleton#enabled"], false)
end

T["toggle enables and disables"] = function()
  child.type_keys("i")
  type("<Plug>(skkeleton-toggle)")
  eq(vim_mode(), "hira")
  type("<Plug>(skkeleton-toggle)")
  eq(vim_mode(), "")
  type("<Plug>(skkeleton-toggle)")
  eq(vim_mode(), "hira")
end

T["<C-j> assigned to toggle works as kakutei while converting"] = function()
  child.lua([[vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)", { remap = true })]])
  child.type_keys("i")
  type("<C-j>")
  eq(vim_mode(), "hira")
  type("ka")
  eq(helpers.buffer(child), { "か" })
  type("Kan<Space><C-j>")
  eq(helpers.buffer(child), { "か缶" })
  eq(vim_mode(), "hira")
  type("<C-j>")
  eq(vim_mode(), "")
  type("ka")
  eq(helpers.buffer(child), { "か缶ka" })
  type("<C-j>")
  eq(vim_mode(), "hira")
end

T["enable is refused in replace mode"] = function()
  child.type_keys("R")
  child.lua([[require("skkeleton").enable()]])
  eq(child.g["skkeleton#enabled"], false)
end

T["the former mappings come back after disabling"] = function()
  child.cmd([[inoremap <buffer> k x]])
  child.cmd([[inoremap <buffer> <silent> <nowait> @ y]])
  enable()
  type("ka")
  eq(helpers.buffer(child), { "か" })
  type("<Plug>(skkeleton-disable)")
  type("k@")
  eq(helpers.buffer(child), { "かxy" })
end

T["pre-existing buffer-local keymap on unmapped key is preserved"] = function()
  child.cmd([[inoremap <buffer> <F5> special_f5]])
  enable()
  type("ka")
  eq(helpers.buffer(child), { "か" })
  type("<Plug>(skkeleton-disable)")
  local map = child.lua_get([[vim.fn.maparg("<F5>", "i", false, true)]])
  eq(_G.type(map) == "table" and map.buffer == 1 and map.rhs == "special_f5", true)
  type("<F5>")
  eq(helpers.buffer(child), { "かspecial_f5" })
end

T["pre-existing buffer-local lua keymap with callback on unmapped key is preserved"] = function()
  child.lua([[
    _G.f6_pressed = 0
    vim.keymap.set("i", "<F6>", function()
      _G.f6_pressed = _G.f6_pressed + 1
    end, { buffer = 0 })
  ]])
  enable()
  type("ka")
  type("<Plug>(skkeleton-disable)")
  type("<F6>")
  eq(child.lua_get("_G.f6_pressed"), 1)
end

T["iminsert is saved and restored across enable and disable"] = function()
  child.bo.iminsert = 1
  enable()
  eq(child.bo.iminsert, 0)
  type("<Plug>(skkeleton-disable)")
  eq(child.bo.iminsert, 1)
end

T["leaving buffer disables"] = function()
  enable()
  type("Ka")
  eq(helpers.preedit(child), "▽か")
  child.lua([[
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(b)
  ]])
  eq(child.g["skkeleton#enabled"], false)
  eq(helpers.preedit(child), "")
end

T["no mappings are left after disabling"] = function()
  local before = child.lua_get([[#vim.api.nvim_buf_get_keymap(0, "i")]])
  enable()
  eq(child.lua_get([[#vim.api.nvim_buf_get_keymap(0, "i")]]) > before, true)
  type("<Esc>")
  eq(child.lua_get([[#vim.api.nvim_buf_get_keymap(0, "i")]]), before)
end

T["g:skkeleton#mapped_keys adds keys"] = function()
  child.g["skkeleton#mapped_keys"] = { "<F3>" }
  enable()
  eq(child.lua_get([[vim.fn.maparg("<F3>", "i", false, true).desc]]), "skkeleton")
end

T["leaving the window disables"] = function()
  enable()
  type("Ka")
  child.cmd("new")
  eq(child.g["skkeleton#enabled"], false)
  eq(helpers.preedit(child), "")
end

T["leaving insert mode with <C-c> disables"] = function()
  enable()
  type("<C-c>")
  child.lua("vim.wait(50)")
  eq(child.g["skkeleton#enabled"], false)
  eq(child.fn.mode(), "n")
end

T["enabling twice keeps working"] = function()
  enable()
  type("<Plug>(skkeleton-enable)")
  type("ka")
  eq(helpers.buffer(child), { "か" })
  type("<Esc>")
  eq(child.g["skkeleton#enabled"], false)
end

T["register_keymap"] = function()
  child.lua([[
    local sk = require("skkeleton")
    sk.register_keymap("henkan", "x", "")
    sk.register_keymap("henkan", "<BS>", "henkanBackward")
  ]])
  enable()
  -- x を外したので、変換中の x は確定してから次の入力になる
  type("Kan<Space>x")
  eq(helpers.buffer(child), { "缶" })
  eq(helpers.preedit(child), "x")
end

T["register_keymap: <BS> goes back to the pre-edit"] = function()
  child.lua([[require("skkeleton").register_keymap("henkan", "<BS>", "henkanBackward")]])
  enable()
  type("Kan<Space><BS>")
  eq(helpers.preedit(child), "▽かん")
end

T["register_keymap: a capital letter"] = function()
  child.lua([[require("skkeleton").register_keymap("henkan", "B", "henkanBackward")]])
  enable()
  type("Kan<Space>B")
  eq(helpers.preedit(child), "▽かん")
end

T["register_keymap: removing a key"] = function()
  child.lua([[
    local sk = require("skkeleton")
    sk.register_keymap("henkan", "B", "henkanBackward")
    sk.register_keymap("henkan", "B", "")
  ]])
  enable()
  type("Kan<Space>B")
  eq(helpers.buffer(child), { "缶" })
  eq(helpers.preedit(child), "▽b")
end

T["send multiple keys into handleKey"] = function()
  enable()
  child.lua([[require("skkeleton.main").handle("handleKey", { key = { "W", "a", "r", "e" } })]])
  eq(helpers.preedit(child), "▽われ")
end

T["the state is exposed in g:skkeleton#state"] = function()
  enable()
  type("K")
  eq(child.g["skkeleton#state"].phase, "input:okurinasi")
  type("a")
  eq(child.g["skkeleton#state"].henkanFeed, "か")
  type("n<Space>")
  eq(child.g["skkeleton#state"].phase, "henkan")
end

T["register_kanatable adds a table"] = function()
  child.lua([[require("skkeleton").register_kanatable("rom", { ["!"] = { "！", "" }, jj = "disable" })]])
  enable()
  type("!")
  eq(helpers.buffer(child), { "！" })
end

T["get_config returns the options"] = function()
  eq(child.lua_get([[require("skkeleton").get_config().markerHenkan ]]), "▽")
end

T["setup rejects unknown options"] = function()
  local ok = pcall(child.lua, [[require("skkeleton").setup({ unknownOption = 1 })]])
  eq(ok, false)
end

T["initialize prepares the dictionary without blocking"] = function()
  log_events({ "skkeleton-initialize-pre", "skkeleton-initialize-post" })
  child.lua([[require("skkeleton").initialize()]])
  eq(child.lua_get("#_G.log"), 2)
  local ready = child.lua_get([[vim.wait(5000, function()
    return #vim.fn.glob(_G.dir .. "/db/**", false, true) > 0
  end, 20)]])
  eq(ready, true)
  -- 準備した辞書で変換できる
  enable()
  type("Nihon<Space>")
  eq(helpers.preedit(child), "▼日本")
  -- 二度目の initialize で User イベントはもう発火しない
  child.lua([[require("skkeleton").initialize()]])
  eq(child.lua_get("#_G.log"), 2)
end

T["update_database builds the cache"] = function()
  child.lua([[require("skkeleton").update_database(_G.dir .. "/dict", "utf-8", true)]])
  eq(#child.lua_get([[vim.fn.glob(_G.dir .. "/db/**", false, true)]]) > 0, true)
  eq(child.lua_get([[vim.fn.execute("messages"):find("updated database", 1, true) ~= nil]]), true)
end

local K, kchild = helpers.e2e_set({ config = { keepMode = true } })
T["keepMode"] = K
K["keeps the last mode"] = function()
  helpers.type(kchild, "i", "<Plug>(skkeleton-enable)", "q")
  eq(kchild.g["skkeleton#mode"], "kata")
  helpers.type(kchild, "<Plug>(skkeleton-disable)")
  helpers.type(kchild, "<Plug>(skkeleton-enable)")
  eq(kchild.g["skkeleton#mode"], "kata")
end

K["does not keep abbrev mode"] = function()
  helpers.type(kchild, "i", "<Plug>(skkeleton-enable)")
  eq(kchild.g["skkeleton#mode"], "hira")
  helpers.type(kchild, "/word<Space>")
  eq(kchild.g["skkeleton#mode"], "abbrev")
  helpers.type(kchild, "<Plug>(skkeleton-disable)")
  eq(kchild.g["skkeleton#mode"], "")
  helpers.type(kchild, "<Plug>(skkeleton-enable)")
  eq(kchild.g["skkeleton#mode"], "hira")
end

K["preserves previous mode after abbrev mode and re-enable"] = function()
  helpers.type(kchild, "i", "<Plug>(skkeleton-enable)")
  helpers.type(kchild, "q")
  eq(kchild.g["skkeleton#mode"], "kata")
  helpers.type(kchild, "/word<Space>")
  eq(kchild.g["skkeleton#mode"], "abbrev")
  helpers.type(kchild, "<Plug>(skkeleton-disable)")
  eq(kchild.g["skkeleton#mode"], "")
  helpers.type(kchild, "<Plug>(skkeleton-enable)")
  eq(kchild.g["skkeleton#mode"], "kata")
end

local S, schild = helpers.e2e_set({ config = { keepState = true } })
T["keepState"] = S
S["enables again on the next InsertEnter"] = function()
  helpers.type(schild, "i", "<Plug>(skkeleton-enable)", "<Esc>")
  eq(schild.g["skkeleton#enabled"], false)
  helpers.type(schild, "i")
  eq(schild.g["skkeleton#enabled"], true)
  helpers.type(schild, "ka")
  eq(helpers.buffer(schild), { "か" })
end

local I, ichild = helpers.e2e_set({ config = { indicator = {} } })
T["indicator"] = I
I["follows the mode"] = function()
  helpers.type(ichild, "i")
  eq(helpers.indicator(ichild).text, "英字")
  helpers.type(ichild, "<Plug>(skkeleton-enable)")
  eq(helpers.indicator(ichild).text, "ひら")
  helpers.type(ichild, "q")
  eq(helpers.indicator(ichild).text, "カタ")
  helpers.type(ichild, "<Plug>(skkeleton-disable)")
  eq(helpers.indicator(ichild).text, "英字")
end

return T

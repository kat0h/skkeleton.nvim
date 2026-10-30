-- blink.cmp を使う補完の E2E。blink.cmp が無ければ skip する
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local BLINK = vim.fn.expand("~/.local/share/nvim/lazy/blink.cmp")
if vim.uv.fs_stat(BLINK) == nil then
  local T = MiniTest.new_set()
  T["skipped when blink.cmp is not installed"] = function() end
  return T
end

local INIT = ([[
  vim.opt.rtp:append(%q)
  vim.cmd("runtime plugin/blink-cmp.lua")
  require("blink.cmp").setup({
    keymap = { preset = "super-tab", ["<Space>"] = {} },
    completion = { list = { selection = { preselect = true, auto_insert = true } } },
    sources = {
      default = function()
        if require("skkeleton").is_enabled() then
          return { "skkeleton" }
        end
        return { "buffer" }
      end,
      providers = { skkeleton = { name = "skkeleton", module = "skkeleton.completion.blink" } },
    },
    fuzzy = { implementation = "lua" },
  })
]]):format(BLINK)

local T, child = helpers.e2e_set({ init = INIT })
local type = function(...)
  helpers.type(child, ...)
end

local function enable()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
end

local function wait(cond)
  for _ = 1, 200 do
    helpers.settle(child)
    if child.lua_get(cond) then
      return true
    end
    vim.uv.sleep(10)
  end
  return false
end

local function menu_visible()
  return child.lua_get("require('blink.cmp').is_menu_visible()")
end

local function labels()
  return child.lua_get("vim.tbl_map(function(i) return i.label end, require('blink.cmp').get_items())")
end

local function user_dict()
  return child.lua_get("require('skkeleton.store').library():get_henkan_result('okurinasi', 'かんじ')")
end

T["hooks"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      if vim.uv.fs_stat(BLINK) == nil then
        MiniTest.skip(BLINK .. " is not installed")
      end
    end,
  },
})

T["hooks"]["the menu shows candidates for the reading"] = function()
  enable()
  type("Kanj")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  eq(labels(), { "漢字", "幹事" })
  eq(helpers.buffer(child), { "" })
  eq(helpers.preedit(child), "▽かんj")
end

T["hooks"]["candidates are not filtered out by the text before the cursor"] = function()
  child.type_keys("ihello ")
  type("<Plug>(skkeleton-enable)")
  type("Kanj")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  eq(labels(), { "漢字", "幹事" })
end

T["hooks"]["the menu is not shown for a reading shorter than minLength"] = function()
  enable()
  type("Ka")
  helpers.settle(child)
  eq(menu_visible(), false)
end

T["hooks"]["accepting with Tab commits only the word"] = function()
  enable()
  type("Kanj")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  type("<Tab>")
  eq(wait("vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] ~= ''"), true)
  eq(helpers.buffer(child), { "漢字" })
  eq(helpers.preedit(child), "")
  eq(menu_visible(), false)
  eq(user_dict()[1], "漢字")
  eq(child.lua_get("require('skkeleton.store').context().last_candidate.candidate"), "漢字")
  -- undo で 1 単位で戻る
  type("<Esc>u")
  eq(helpers.buffer(child), { "" })
end

T["hooks"]["selecting the second candidate with C-n and accepting"] = function()
  enable()
  type("Kanj")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  type("<C-n>")
  helpers.settle(child)
  -- auto_insert の試し挿入でバッファは変わらない
  eq(helpers.buffer(child), { "" })
  eq(helpers.preedit(child), "▽かんj")
  type("<Tab>")
  eq(wait("vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] ~= ''"), true)
  eq(helpers.buffer(child), { "幹事" })
  eq(helpers.preedit(child), "")
end

T["hooks"]["leaving the preedit closes the menu"] = function()
  enable()
  type("Kanj")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  type("<C-g>")
  eq(wait("not require('blink.cmp').is_menu_visible()"), true)
  eq(helpers.buffer(child), { "" })
end

T["hooks"]["Enter with eggLikeNewline commits the selected item"] = function()
  child.lua("require('skkeleton.config').options.eggLikeNewline = true")
  enable()
  type("Kanj")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  type("<C-n>")
  helpers.settle(child)
  type("<CR>")
  eq(wait("vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] ~= ''"), true)
  eq(helpers.buffer(child), { "幹事" })
  eq(helpers.preedit(child), "")
end

T["hooks"]["Enter with eggLikeNewline and nothing selected commits the reading"] = function()
  child.lua("require('skkeleton.config').options.eggLikeNewline = true")
  enable()
  type("Kanj")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  type("<CR>")
  helpers.settle(child)
  eq(helpers.buffer(child), { "かんj" })
end

T["hooks"]["completion.enabled = false never opens the menu"] = function()
  child.lua("require('skkeleton').setup({ completion = { enabled = false }, indicator = false })")
  enable()
  type("Kanj")
  helpers.settle(child)
  vim.uv.sleep(100)
  eq(menu_visible(), false)
end

T["hooks"]["enabling skkeleton closes any previously open completion menu (#24)"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "Kanji", "" })
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.type_keys("iKan")
  eq(wait("require('blink.cmp').is_menu_visible()"), true)
  type("<Plug>(skkeleton-enable)")
  helpers.settle(child)
  eq(menu_visible(), false)
end

return T

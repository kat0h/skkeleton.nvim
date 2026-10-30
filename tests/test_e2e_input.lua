-- 実際のキー入力を子の nvim に流して、バッファ・pre-edit・モードを確かめる
local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.e2e_set()
local type = function(...)
  helpers.type(child, ...)
end

local function start()
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
end

-- { 名前, 打つキー, 確定した行, pre-edit, モード }
local cases = {
  { "hiragana", "aiueo", { "あいうえお" }, "", "hira" },
  { "n is kept until the next consonant", "kan", { "か" }, "n", "hira" },
  { "nn", "kann", { "かん" }, "", "hira" },
  { "sokuon", "kitte", { "きって" }, "", "hira" },
  { "henkan point", "Kan", { "" }, "▽かn", "hira" },
  { "henkan point is fixed by <C-j>", "Kan<C-j>", { "かん" }, "", "hira" },
  { "okurinasi: first candidate", "Kan<Space>", { "" }, "▼缶", "hira" },
  { "okurinasi: kakutei by <C-j>", "Kan<Space><C-j>", { "缶" }, "", "hira" },
  { "okurinasi: second candidate", "Kan<Space><Space><C-j>", { "感" }, "", "hira" },
  { "okurinasi: next input confirms", "Kan<Space>a", { "缶あ" }, "", "hira" },
  { "okurinasi: kakutei by <CR> inserts a newline", "Kan<Space><CR>", { "缶", "" }, "", "hira" },
  { "okurinasi: x goes back", "Kan<Space>x", { "" }, "▽かん", "hira" },
  { "okurinasi: <C-g> cancels", "Kan<Space><C-g>", { "" }, "", "hira" },
  { "okurinasi: word with two characters", "Kanzi<Space><C-j>", { "漢字" }, "", "hira" },
  { "okuriari", "KaeRu", { "" }, "▼帰る", "hira" },
  { "okuriari: kakutei", "KaeRu<C-j>", { "帰る" }, "", "hira" },
  { "okuriari: a word with a stem of two characters", "WaruKu", { "" }, "▼悪く", "hira" },
  { "okuriari: followed by input", "WaruKuka", { "悪くか" }, "", "hira" },
  { "candidate popup is not used for the first few candidates", "Kan<Space><Space>", { "" }, "▼感", "hira" },
  { "backspace in the pre-edit", "Kan<BS>", { "" }, "▽か", "hira" },
  { "backspace on the buffer", "ka<BS>", { "" }, "", "hira" },
  { "katakana", "qka", { "カ" }, "", "kata" },
  { "katakana toggles back", "qkaqka", { "カか" }, "", "hira" },
  { "katakana henkan point", "qKa<C-j>", { "カ" }, "", "kata" },
  { "hankaku katakana", "<C-q>ka", { "ｶ" }, "", "hankata" },
  { "zenkaku", "Lab", { "ａｂ" }, "", "zenkaku" },
  { "abbrev", "/abc<Space>", { "" }, "▼ＡＢＣ", "abbrev" },
  { "abbrev: kakutei", "/abc<Space><C-j>", { "ＡＢＣ" }, "", "hira" },
  { "<C-j> without pre-edit is hiragana", "q<C-j>ka", { "か" }, "", "hira" },
  { "symbols", ",.", { "、。" }, "", "hira" },
  { "symbols with a sequence", "z,", { "‥" }, "", "hira" },
  { "an unmapped sequence is kept as typed", "ka1", { "か1" }, "", "hira" },
  { "<Bar> is input", "|", { "|" }, "", "hira" },
  { "<lt> is passed to the kana table", "<LT>", { "" }, "<", "hira" },
  { "space without pre-edit", "ka ka", { "か か" }, "", "hira" },
  {
    "okurinasi with a candidate that has an annotation-less single entry",
    "Nihon<Space><C-j>",
    { "日本" },
    "",
    "hira",
  },
}

for _, c in ipairs(cases) do
  T[c[1]] = function()
    start()
    type(c[2])
    eq(helpers.buffer(child), c[3])
    eq(helpers.preedit(child), c[4])
    eq(helpers.mode(child), c[5])
  end
end

T["<Esc> confirms the pre-edit and leaves insert mode"] = function()
  start()
  type("Ka")
  eq(helpers.preedit(child), "▽か")
  type("<Esc>")
  eq(helpers.buffer(child), { "か" })
  eq(helpers.preedit(child), "")
  eq(child.fn.mode(), "n")
  eq(helpers.mode(child), "")
  eq(child.lua_get([[vim.g["skkeleton#enabled"] ]]), false)
end

T["<Esc> after converting inserts the candidate"] = function()
  start()
  type("Kan<Space><Esc>")
  eq(helpers.buffer(child), { "缶" })
  eq(child.fn.mode(), "n")
end

T["the pre-edit follows the cursor in the middle of a line"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
  child.api.nvim_win_set_cursor(0, { 1, 3 })
  start()
  type("Ka")
  eq(helpers.preedit(child), "▽か")
  eq(helpers.cursor(child), { 1, 3 })
  type("<C-j>")
  eq(helpers.buffer(child), { "abcかdef" })
  eq(helpers.cursor(child), { 1, 6 })
end

T["moving the cursor drops the pre-edit"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
  child.api.nvim_win_set_cursor(0, { 1, 3 })
  start()
  type("Ka")
  child.api.nvim_win_set_cursor(0, { 1, 1 })
  type("ka")
  eq(helpers.preedit(child), "")
  eq(helpers.buffer(child), { "aかbcdef" })
end

T["text inserted by completion drops the pre-edit"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "foobar", "" })
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  start()
  type("Ka")
  eq(helpers.preedit(child), "▽か")
  type("<C-n>")
  eq(helpers.buffer(child), { "foobar", "foobar" })
  type("<C-y>ka")
  eq(helpers.preedit(child), "")
  eq(helpers.buffer(child), { "foobar", "foobarか" })
end

T["each conversion is one undo step"] = function()
  start()
  type("Kan<Space><C-j>Kanzi<Space><C-j>Nihon<Space><C-j>")
  eq(helpers.buffer(child), { "缶漢字日本" })
  type("<Esc>u")
  eq(helpers.buffer(child), { "缶漢字" })
  type("u")
  eq(helpers.buffer(child), { "缶" })
  type("u")
  eq(helpers.buffer(child), { "" })
end

T["the inserted text can be repeated with dot"] = function()
  start()
  type("Kan<Space><C-j><Esc>")
  eq(helpers.buffer(child), { "缶" })
  type(".")
  eq(helpers.buffer(child), { "缶缶" })
end

T["textwidth is restored after disabling"] = function()
  child.o.textwidth = 5
  start()
  eq(child.o.textwidth, 0)
  type("<Esc>")
  eq(child.o.textwidth, 5)
end

T["a long line is not broken by textwidth"] = function()
  child.o.textwidth = 5
  start()
  type("aiueoaiueoaiueo")
  eq(helpers.buffer(child), { "あいうえおあいうえおあいうえお" })
end

T["indent is kept by a newline"] = function()
  child.o.autoindent = true
  child.type_keys("i")
  child.lua([[vim.keymap.set("i", "J", "<Plug>(skkeleton-enable)")]])
  type("J<Tab>hoge<CR>hoge;hoge<CR><Esc>")
  eq(helpers.buffer(child), { "\tほげ", "\tほげほげ", "" })
end

local E, echild = helpers.e2e_set({ config = { eggLikeNewline = true } })
T["eggLikeNewline"] = E

E["<CR> after selecting from the completion menu is passed on as <C-y>"] = function()
  -- UI の無い子では pum が出ないので、pum が出ている状態を作る。
  -- メニューが無いときの <C-y> は上の行の文字を写すので、それで <C-y> が流れたことが分かる
  echild.api.nvim_buf_set_lines(0, 0, -1, false, { "foobar", "" })
  echild.api.nvim_win_set_cursor(0, { 2, 0 })
  helpers.type(echild, "i", "<Plug>(skkeleton-enable)")
  echild.lua([[
    vim.fn.pumvisible = function() return 1 end
    vim.fn.complete_info = function() return { selected = 0 } end
  ]])
  helpers.type(echild, "<CR>")
  eq(helpers.buffer(echild), { "foobar", "f" })
end

E["<CR> with a pum but nothing selected is a newline"] = function()
  echild.api.nvim_buf_set_lines(0, 0, -1, false, { "foobar", "" })
  echild.api.nvim_win_set_cursor(0, { 2, 0 })
  helpers.type(echild, "i", "<Plug>(skkeleton-enable)")
  echild.lua([[
    vim.fn.pumvisible = function() return 1 end
    vim.fn.complete_info = function() return { selected = -1 } end
  ]])
  helpers.type(echild, "<CR>")
  eq(helpers.buffer(echild), { "foobar", "", "" })
end

E["<CR> while converting only confirms"] = function()
  helpers.type(echild, "i", "<Plug>(skkeleton-enable)")
  helpers.type(echild, "Kan<Space><CR>")
  eq(helpers.buffer(echild), { "缶" })
end

T["candidate popup scratch buffer is wiped on close"] = function()
  start()
  local bufs_before = child.lua_get([[
    vim.tbl_filter(function(b) return vim.api.nvim_buf_is_valid(b) end, vim.api.nvim_list_bufs())
  ]])
  type("Kan<Space><Space><Space><Space><Space>")
  eq(helpers.popup(child) ~= vim.NIL, true)
  local bufs_during = child.lua_get([[
    vim.tbl_filter(function(b) return vim.api.nvim_buf_is_valid(b) end, vim.api.nvim_list_bufs())
  ]])
  eq(#bufs_during, #bufs_before + 1)
  -- Kakutei to close the popup
  type("<C-j>")
  eq(helpers.popup(child), vim.NIL)
  local bufs_after = child.lua_get([[
    vim.tbl_filter(function(b) return vim.api.nvim_buf_is_valid(b) end, vim.api.nvim_list_bufs())
  ]])
  eq(#bufs_after, #bufs_before)
end

T["popup scratch buffer is wiped when popup closes directly"] = function()
  child.lua([[
    local popup = require("skkeleton.popup")
    _G.bufs_before = #vim.api.nvim_list_bufs()
    popup.set({ "1: 候補1", "2: 候補2" })
    popup.open()
    _G.bufs_open = #vim.api.nvim_list_bufs()
    popup.close()
    _G.bufs_closed = #vim.api.nvim_list_bufs()
  ]])
  eq(child.lua_get("_G.bufs_open"), child.lua_get("_G.bufs_before") + 1)
  eq(child.lua_get("_G.bufs_closed"), child.lua_get("_G.bufs_before"))
end

T["cmdline <Esc> and <C-g> are not left mapped on the buffer after host.input"] = function()
  start()
  child.lua([[
    local orig_input = vim.fn.input
    vim.fn.input = function() return "辞書登録語" end
    require("skkeleton.host").input("単語: ")
    vim.fn.input = orig_input
  ]])
  local c_maps = child.lua_get([[vim.api.nvim_buf_get_keymap(0, "c")]])
  local leaked = {}
  for _, m in ipairs(c_maps) do
    if m.lhs == "<Esc>" or m.lhs == "<C-g>" or m.rhs == "__skkeleton_return__<CR>" then
      table.insert(leaked, m.lhs)
    end
  end
  eq(leaked, {})
end

T["cmdline mappings are cleaned up even if host.input errors or cancels"] = function()
  start()
  child.lua([[
    local orig_input = vim.fn.input
    vim.fn.input = function() error("cancelled") end
    pcall(require("skkeleton.host").input, "単語: ")
    vim.fn.input = orig_input
  ]])
  local c_maps = child.lua_get([[vim.api.nvim_buf_get_keymap(0, "c")]])
  local leaked = {}
  for _, m in ipairs(c_maps) do
    if m.lhs == "<Esc>" or m.lhs == "<C-g>" or m.rhs == "__skkeleton_return__<CR>" then
      table.insert(leaked, m.lhs)
    end
  end
  eq(leaked, {})
end

T["preedit renders semantic highlight chunks and inline ghost annotation"] = function()
  start()
  type("KaN")
  local chunks = child.lua_get([[
    (function()
      local ns = vim.api.nvim_get_namespaces()["skkeleton-preedit"]
      local m = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })[1]
      return m and m[4].virt_text or {}
    end)()
  ]])
  eq(chunks, {
    { "▽", "SkkeletonMarkerHenkan" },
    { "か", "SkkeletonPreedit" },
    { "*", "SkkeletonOkuri" },
    { "n", "SkkeletonRomaji" },
  })

  -- Register an annotated candidate and verify inline ghost annotation in henkan state
  child.lua([[
    local store = require("skkeleton.store")
    store.library():register_henkan_result("okurinasi", "ちゅうしゃく", "注釈語;これは説明です")
  ]])
  type("<C-g><C-g>Chuushaku<Space>")
  local henkan_info = child.lua_get([[
    (function()
      local ns = vim.api.nvim_get_namespaces()["skkeleton-preedit"]
      local ns_a = vim.api.nvim_get_namespaces()["skkeleton-annotation"]
      local m = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })[1]
      local ma = vim.api.nvim_buf_get_extmarks(0, ns_a, 0, -1, { details = true })[1]
      return {
        chunks = m and m[4].virt_text or {},
        annot = ma and ma[4].virt_text or {},
      }
    end)()
  ]])
  eq(henkan_info.chunks, {
    { "▼", "SkkeletonMarkerSelect" },
    { "注釈語", "SkkeletonPreedit" },
  })
  eq(henkan_info.annot, {
    { " ;これは説明です", "SkkeletonAnnotation" },
  })
end

T["stale preedit: 補完のキャンセルで extmark がずれたらリセットされる (#19)"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
  child.api.nvim_win_set_cursor(0, { 1, 5 })
  child.type_keys("a")
  type("<Plug>(skkeleton-enable)")
  child.type_keys("Kan<C-n>R<C-e>")
  local marks =
    child.lua_get([[vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()["skkeleton-preedit"], 0, -1, {})]])
  eq(#marks, 0)
end

T["stale preedit: insert 中に <C-r>= で cmdline に入ったとき extmark が残らない (#20)"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "ab cd" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("i")
  type("<Plug>(skkeleton-enable)")
  child.type_keys("O<C-r>=1<CR>")
  local marks =
    child.lua_get([[vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()["skkeleton-preedit"], 0, -1, {})]])
  eq(#marks, 0)
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(lines, { "1ab cd" })
end

return T

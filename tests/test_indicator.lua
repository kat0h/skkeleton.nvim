local helpers = require("helpers")
local eq = MiniTest.expect.equality

local T, child = helpers.child_set()

-- 子の中で浮動ウィンドウの情報を返す関数を用意する
local function prepare()
  child.lua([[
    function _G.floats()
      local res = {}
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(w)
        if cfg.relative ~= "" then
          local buf = vim.api.nvim_win_get_buf(w)
          local ns = vim.api.nvim_get_namespaces()["skkeleton-indicator"]
          local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
          table.insert(res, {
            text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
            width = cfg.width,
            row = cfg.row,
            col = cfg.col,
            relative = cfg.relative,
            border = cfg.border,
            hl = marks[1] and marks[1][4].hl_group or nil,
            marks = marks,
            winhl = vim.wo[w].winhighlight,
            winblend = vim.wo[w].winblend,
          })
        end
      end
      return res
    end
    function _G.fire(name)
      vim.api.nvim_exec_autocmds("User", { pattern = name })
    end
  ]])
end

-- schedule とタイマーが片付くのを待つ
local function wait(ms)
  child.lua(("vim.wait(%d, function() return false end)"):format(ms))
end

local function floats()
  return child.lua_get("_G.floats()")
end

local function setup(opts)
  child.lua("require('skkeleton.indicator').setup(...)", { opts })
end

T["hooks"] = MiniTest.new_set({ hooks = { pre_case = prepare } })

T["hooks"]["insert モードに入ると英字が出て、出ると閉じる"] = function()
  setup({})
  eq(#floats(), 0)
  child.type_keys("i")
  local f = floats()
  eq(#f, 1)
  eq(f[1].text, "Aa")
  eq(f[1].width, 2)
  eq(f[1].hl, "SkkeletonIndicatorEiji")
  child.type_keys("<Esc>")
  eq(#floats(), 0)
end

T["hooks"]["mode-changed でテキスト、幅、ハイライトが変わる"] = function()
  setup({})
  child.type_keys("i")
  local cases = {
    { "hira", "あ", 2, "SkkeletonIndicatorHira" },
    { "kata", "ア", 2, "SkkeletonIndicatorKata" },
    { "hankata", "ｶﾅ", 2, "SkkeletonIndicatorHankata" },
    { "zenkaku", "Ａ", 2, "SkkeletonIndicatorZenkaku" },
    { "abbrev", "ab", 2, "SkkeletonIndicatorAbbrev" },
    { "", "Aa", 2, "SkkeletonIndicatorEiji" },
  }
  for _, c in ipairs(cases) do
    child.g["skkeleton#mode"] = c[1]
    child.lua("_G.fire('skkeleton-mode-changed')")
    wait(30)
    local f = floats()
    eq(#f, 1)
    eq({ f[1].text, f[1].width, f[1].hl, f[1].winhl }, { c[2], c[3], c[4], "FloatBorder:" .. c[4] })
  end
end

T["hooks"]["未知のモード名は英字になる"] = function()
  setup({})
  child.g["skkeleton#mode"] = "unknown"
  child.type_keys("i")
  eq(floats()[1].text, "Aa")
end

T["hooks"]["既定のハイライトグループが定義される"] = function()
  setup({})
  local hl = child.lua_get("vim.api.nvim_get_hl(0, { name = 'SkkeletonIndicatorHira' })")
  eq(hl.bold, true)
  eq(hl.ctermbg ~= nil, true)
end

T["hooks"]["fadeOutMs 後に閉じる。次の更新でまた出る"] = function()
  setup({ fadeOutMs = 50 })
  child.type_keys("i")
  eq(#floats(), 1)
  wait(200)
  eq(#floats(), 0)
  child.g["skkeleton#mode"] = "hira"
  child.lua("_G.fire('skkeleton-mode-changed')")
  wait(30)
  eq(floats()[1].text, "あ")
end

T["hooks"]["fadeOutMs = 0 なら閉じない"] = function()
  setup({ fadeOutMs = 0 })
  child.type_keys("i")
  wait(200)
  eq(#floats(), 1)
end

T["hooks"]["更新のたびに fadeOutMs のタイマーが張り直される"] = function()
  setup({ fadeOutMs = 150 })
  child.type_keys("i")
  wait(100)
  child.lua("_G.fire('skkeleton-mode-changed')")
  wait(100)
  eq(#floats(), 1)
  wait(150)
  eq(#floats(), 0)
end

T["hooks"]["alwaysShown = false は skkeleton が有効なときだけ出す"] = function()
  setup({ alwaysShown = false })
  child.type_keys("i")
  eq(#floats(), 0)
  child.g["skkeleton#enabled"] = true
  child.g["skkeleton#mode"] = "hira"
  child.lua("_G.fire('skkeleton-enable-post')")
  wait(30)
  eq(floats()[1].text, "あ")
  child.g["skkeleton#enabled"] = false
  child.g["skkeleton#mode"] = ""
  child.lua("_G.fire('skkeleton-disable-post')")
  wait(30)
  eq(#floats(), 0)
end

T["hooks"]["alwaysShown = false で有効な状態の insert に入ると出る"] = function()
  setup({ alwaysShown = false })
  child.g["skkeleton#enabled"] = true
  child.type_keys("i")
  eq(#floats(), 1)
end

T["hooks"]["alwaysShown = true は無効でも disable-post で閉じない"] = function()
  setup({})
  child.type_keys("i")
  child.lua("_G.fire('skkeleton-disable-post')")
  wait(30)
  eq(floats()[1].text, "Aa")
end

T["hooks"]["ignoreFt のファイルタイプでは出ない"] = function()
  setup({ ignoreFt = { "help" } })
  child.bo.filetype = "help"
  child.type_keys("i")
  eq(#floats(), 0)
  child.type_keys("<Esc>")
  child.bo.filetype = "lua"
  child.type_keys("i")
  eq(#floats(), 1)
end

T["hooks"]["bufFilter が false を返すバッファでは出ない"] = function()
  child.lua([[
    require('skkeleton.indicator').setup({
      bufFilter = function(buf) return vim.b[buf].show_indicator == true end,
    })
  ]])
  child.type_keys("i")
  eq(#floats(), 0)
  child.type_keys("<Esc>")
  child.b.show_indicator = true
  child.type_keys("i")
  eq(#floats(), 1)
end

T["hooks"]["border と row の既定値"] = function()
  setup({})
  child.type_keys("i")
  eq(floats()[1].row, 1)
  child.type_keys("<Esc>")
  setup({ border = "single" })
  child.type_keys("i")
  local f = floats()[1]
  eq(f.row, 0)
  eq(#f.border, 8)
end

T["hooks"]["border に関数を渡すとモードごとに変えられる"] = function()
  child.lua([[
    require('skkeleton.indicator').setup({
      border = function(args)
        if args.mode == "hira" then return "rounded" end
      end,
    })
  ]])
  child.type_keys("i")
  eq(floats()[1].border[1], " ")
  child.g["skkeleton#mode"] = "hira"
  child.lua("_G.fire('skkeleton-mode-changed')")
  wait(30)
  eq(floats()[1].border[1], "╭")
end

T["hooks"]["テキストの設定を変えられる（camelCase）"] = function()
  setup({ hiraText = "あ", hiraHlName = "MyHira" })
  child.g["skkeleton#mode"] = "hira"
  child.type_keys("i")
  local f = floats()[1]
  eq({ f.text, f.width, f.hl }, { "あ", 2, "MyHira" })
end

T["hooks"]["CursorMovedI で表示が残る"] = function()
  setup({})
  child.type_keys("ihello<Esc>o")
  eq(#floats(), 1)
  child.type_keys("abc")
  eq(#floats(), 1)
end

T["hooks"]["setup を何度呼んでも 1 つしか出ない。設定は最後のものになる"] = function()
  setup({ eijiText = "A" })
  setup({ eijiText = "B" })
  setup({})
  child.type_keys("i")
  local f = floats()
  eq(#f, 1)
  eq(f[1].text, "Aa")
  eq(#child.api.nvim_get_autocmds({ group = "skkeleton-indicator" }), 11)
end

T["hooks"]["style = rounded / minimal / pill と winblend が反映される"] = function()
  setup({ style = "rounded", winblend = 15 })
  child.type_keys("i")
  local f1 = floats()[1]
  eq(f1.border[1], "╭")
  eq(f1.winblend, 15)
  child.type_keys("<Esc>")

  setup({ style = "minimal" })
  child.g["skkeleton#mode"] = "hira"
  child.type_keys("i")
  local f2 = floats()[1]
  eq(f2.text, "あ")
  eq(f2.width, 2)
  child.type_keys("<Esc>")

  setup({ style = "pill" })
  child.g["skkeleton#mode"] = "hira"
  child.type_keys("i")
  local f3 = floats()[1]
  eq(f3.text, "\238\130\182あ\238\130\180")
  eq(#f3.marks, 3)
  eq(f3.marks[1][4].hl_group, "SkkeletonIndicatorHiraCap")
  eq(f3.marks[2][4].hl_group, "SkkeletonIndicatorHira")
  eq(f3.marks[3][4].hl_group, "SkkeletonIndicatorHiraCap")
  child.type_keys("<Esc>")
end

T["hooks"]["コマンドラインモード（: や /）でもインジケーターが表示・更新・クローズされる"] = function()
  setup({})
  child.type_keys(":")
  local f = floats()
  eq(#f, 1)
  eq(f[1].text, "Aa")
  eq(f[1].relative, "editor")

  child.g["skkeleton#mode"] = "hira"
  child.lua("_G.fire('skkeleton-mode-changed')")
  eq(floats()[1].text, "あ")

  child.type_keys("<Esc>")
  eq(#floats(), 0)
end

T["hooks"]["insert 中に setup すると設定が反映される"] = function()
  setup({})
  child.type_keys("i")
  setup({ eijiText = "EN" })
  wait(30)
  local f = floats()
  eq(#f, 1)
  eq(f[1].text, "EN")
end

T["hooks"]["setup(false) で autocmd とウィンドウを片付ける"] = function()
  setup({})
  child.type_keys("i")
  eq(#floats(), 1)
  setup(false)
  eq(#floats(), 0)
  eq(child.lua_get("pcall(vim.api.nvim_get_autocmds, { group = 'skkeleton-indicator' })"), false)
  child.type_keys("<Esc>i")
  eq(#floats(), 0)
  -- 無効のあとにもう一度有効にできる
  setup({})
  child.type_keys("<Esc>i")
  eq(#floats(), 1)
  -- 何も無いときの setup(false) もエラーにならない
  setup(false)
  setup(false)
end

T["hooks"]["知らないオプションはエラー"] = function()
  eq(child.lua_get("(pcall(require('skkeleton.indicator').setup, { fooBar = 1 }))"), false)
  eq(child.lua_get("(pcall(require('skkeleton.indicator').setup, { fadeOutMs = 'x' }))"), false)
end

T["hooks"]["background が変わると色を作り直す"] = function()
  setup({})
  child.type_keys("i")
  child.o.background = "light"
  wait(30)
  local hl = child.lua_get("vim.api.nvim_get_hl(0, { name = 'SkkeletonIndicatorEiji' })")
  eq(hl.bold, true)
  eq(#floats(), 1)
end

T["hooks"]["ColorScheme イベントでもハイライトが再作成される"] = function()
  setup({ style = "pill" })
  child.type_keys("i")
  child.cmd("highlight clear")
  child.cmd("doautocmd ColorScheme")
  wait(30)
  local hl = child.lua_get("vim.api.nvim_get_hl(0, { name = 'SkkeletonIndicatorEiji' })")
  local cap = child.lua_get("vim.api.nvim_get_hl(0, { name = 'SkkeletonIndicatorEijiCap' })")
  eq(hl.bold, true)
  eq(cap.fg ~= nil, true)
  eq(#floats(), 1)
end

T["hooks"]["insert 中に input() へ入り抜けてもインジケーターが連動する"] = function()
  setup({ showInCmdline = true })
  child.type_keys("i")
  eq(floats()[1].relative, "win")

  -- Insert 中に Cmdline へ遷移したとき即座に relative=editor になる
  child.type_keys("<C-r>=")
  local f_cmd = floats()
  eq(#f_cmd, 1)
  eq(f_cmd[1].relative, "editor")

  -- Cmdline を抜けて Insert に戻ると再びインジケーターが開く
  child.type_keys("<Esc>")
  wait(30)
  local f_ins = floats()
  eq(#f_ins, 1)
  eq(f_ins[1].relative, "win")
end

T["hooks"]["indicator のバッファは閉じたときに wipe される"] = function()
  setup({})
  local before = child.lua_get("#vim.api.nvim_list_bufs()")
  child.type_keys("i")
  local during = child.lua_get("#vim.api.nvim_list_bufs()")
  eq(during, before + 1)
  child.type_keys("<Esc>")
  wait(30)
  local after = child.lua_get("#vim.api.nvim_list_bufs()")
  eq(after, before)
end

T["hooks"]["Modes.is_insert は <C-o>（niI）で false を返す"] = function()
  setup({})
  child.type_keys("i")
  eq(child.lua_get([[require("skkeleton.indicator.modes").is_insert()]]), true)
  child.type_keys("<C-o>")
  eq(child.lua_get([[require("skkeleton.indicator.modes").is_insert()]]), false)
  child.type_keys("l")
  eq(child.lua_get([[require("skkeleton.indicator.modes").is_insert()]]), true)
  child.type_keys("<Esc>")
end

T["hooks"]["fade_epoch により古いタイマーコールバックが新しいインジケータを閉じない"] = function()
  setup({ fadeOutMs = 100 })
  child.type_keys("i")
  wait(50)
  -- タイマー発火前にモードを変更してインジケータを更新
  child.g["skkeleton#mode"] = "hira"
  child.lua("_G.fire('skkeleton-mode-changed')")
  -- 最初の 100ms が経過するタイミング（開始から計 120ms）
  wait(70)
  -- fade_epoch が上がっているため、古いタイマーで閉じずにひらが出ている
  local f = floats()
  eq(#f, 1)
  eq(f[1].text, "あ")
  -- 更新後の fadeOutMs が経過すると閉じる
  wait(100)
  eq(#floats(), 0)
end

T["config"] = MiniTest.new_set()

T["config"]["row は border によって既定値が変わる"] = function()
  local cases = {
    { {}, 1 },
    { { border = "none" }, 1 },
    { { border = "shadow" }, 1 },
    { { border = "single" }, 0 },
    { { border = "single", row = 3 }, 3 },
  }
  for _, c in ipairs(cases) do
    child.lua("_G.cfg = require('skkeleton.indicator.config'); _G.cfg.setup(...)", { c[1] })
    eq(child.lua_get("_G.cfg.row"), c[2])
  end
end

T["config"]["setup は既定値から作り直す"] = function()
  child.lua("_G.cfg = require('skkeleton.indicator.config')")
  child.lua("_G.cfg.setup({ eijiText = 'X', fadeOutMs = 1 })")
  child.lua("_G.cfg.setup({})")
  eq(child.lua_get("{ _G.cfg.eiji_text, _G.cfg.fade_out_ms, _G.cfg.always_shown }"), { "Aa", 3000, true })
end

-- strings（skkeleton_indicator.nvim の strings.test.lua の移植）
T["strings"] = MiniTest.new_set()

T["strings"]["snake_case"] = function()
  local snake_case = require("skkeleton.indicator.strings").snake_case
  eq(snake_case("abcdefg"), "abcdefg")
  eq(snake_case("abcdEfg"), "abcd_efg")
  eq(snake_case("aBcdEfg"), "a_bcd_efg")
  eq(snake_case("fadeOutMs"), "fade_out_ms")
  eq(snake_case("ignoreFT"), "ignore_ft")
  eq(snake_case("XMLParser"), "xml_parser")
  eq(snake_case("HTML"), "html")
  eq(snake_case("HTTPResponseCode"), "http_response_code")
end

T["strings"]["snake_case_dict"] = function()
  local snake_case_dict = require("skkeleton.indicator.strings").snake_case_dict
  eq(
    snake_case_dict({
      eijiHlName = "SkkeletonIndicatorEiji",
      hiraHlName = "SkkeletonIndicatorHira",
      kataHlName = "SkkeletonIndicatorKata",
      hankataHlName = "SkkeletonIndicatorHankata",
      eijiText = "英字",
      hiraText = "ひら",
      kataText = "カタ",
      hankataText = "半ｶﾀ",
      fadeOutMs = 3000,
      ignoreFt = {},
    }),
    {
      eiji_hl_name = "SkkeletonIndicatorEiji",
      hira_hl_name = "SkkeletonIndicatorHira",
      kata_hl_name = "SkkeletonIndicatorKata",
      hankata_hl_name = "SkkeletonIndicatorHankata",
      eiji_text = "英字",
      hira_text = "ひら",
      kata_text = "カタ",
      hankata_text = "半ｶﾀ",
      fade_out_ms = 3000,
      ignore_ft = {},
    }
  )
end

return T

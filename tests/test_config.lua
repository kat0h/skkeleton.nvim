-- config の既定値と検証（config.ts）
local helpers = require("helpers")
local eq = MiniTest.expect.equality
local T, child = helpers.child_set()

T["defaults"] = function()
  local defaults = child.lua_get([[require("skkeleton.config").options]])
  eq(defaults, {
    acceptIllegalResult = false,
    completionRankFile = "",
    databasePath = "",
    debug = false,
    eggLikeNewline = false,
    globalDictionaries = {},
    globalKanaTableFiles = {},
    immediatelyCancel = true,
    immediatelyDictionaryRW = true,
    immediatelyOkuriConvert = true,
    kanaTable = "rom",
    keepMode = false,
    keepState = false,
    lowercaseMap = {},
    markerHenkan = "▽",
    markerHenkanSelect = "▼",
    popupBorder = "none",
    registerConvertResult = false,
    selectCandidateKeys = "asdfjkl",
    setUndoPoint = true,
    showCandidatesCount = 4,
    skkServerHost = "127.0.0.1",
    skkServerPort = 1178,
    skkServerReqEnc = "euc-jp",
    skkServerResEnc = "euc-jp",
    sources = { "skk_dictionary" },
    userDictionary = "~/.skkeleton",
  })
end

T["set applies valid options"] = function()
  child.lua([[
    config = require("skkeleton.config")
    options = config.options
    config.set({ eggLikeNewline = true, markerHenkan = "*", showCandidatesCount = 7, lowercaseMap = { ["+"] = "a" } })
  ]])
  eq(child.lua_get([[options.eggLikeNewline]]), true)
  eq(child.lua_get([[options.markerHenkan]]), "*")
  eq(child.lua_get([[options.showCandidatesCount]]), 7)
  eq(child.lua_get([[options.lowercaseMap]]), { ["+"] = "a" })
  -- 参照を持っていても、config.options は同じ表のまま
  eq(child.lua_get([[config.options == options]]), true)
end

T["set expands ~ and normalizes dictionary lists"] = function()
  child.lua([[
    config = require("skkeleton.config")
    config.set({
      userDictionary = "~/user",
      databasePath = "~/db",
      completionRankFile = "~/rank",
      globalDictionaries = { "~/a", { "~/b", "euc-jp" } },
    })
    home = vim.fn.expand("~")
  ]])
  eq(child.lua_get([[config.options.userDictionary == home .. "/user"]]), true)
  eq(child.lua_get([[config.options.databasePath == home .. "/db"]]), true)
  eq(child.lua_get([[config.options.completionRankFile == home .. "/rank"]]), true)
  eq(
    child.lua_get(
      [[vim.deep_equal(config.options.globalDictionaries, { { home .. "/a", "" }, { home .. "/b", "euc-jp" } })]]
    ),
    true
  )
  -- 絶対パスはそのまま
  child.lua([[config.set({ userDictionary = "/tmp/x" })]])
  eq(child.lua_get([[config.options.userDictionary]]), "/tmp/x")
end

T["set rejects illegal options"] = function()
  child.lua([[
    config = require("skkeleton.config")
    err = function(tbl)
      local ok, e = pcall(config.set, tbl)
      return ok and "" or e
    end
  ]])
  local cases = {
    { [[{ noSuchOption = 1 }]], "Illegal option detected: unknown option: noSuchOption" },
    { [[{ debug = "yes" }]], "Illegal option detected: expected boolean, got string" },
    { [[{ showCandidatesCount = "4" }]], "Illegal option detected: expected number, got string" },
    { [[{ selectCandidateKeys = "abc" }]], "Illegal option detected: selectCandidateKeys.length !== 7" },
    { [[{ kanaTable = "nothing" }]], "Illegal option detected: can't use undefined kanaTable: nothing" },
    { [[{ skkServerReqEnc = "latin" }]], "Illegal option detected: latin is invalid encoding" },
    {
      [[{ globalDictionaries = { 1 } }]],
      "Illegal option detected: 'globalDictionaries' must be array of two string tuple",
    },
    {
      [[{ globalKanaTableFiles = { { "a" } } }]],
      "Illegal option detected: 'globalKanaTableFiles' must be array of two string tuple",
    },
    { [[{ lowercaseMap = { a = 1 } }]], "Illegal option detected: expected record of string" },
  }
  for _, c in ipairs(cases) do
    eq(child.lua_get("err(" .. c[1] .. ")"), c[2])
  end
  -- 削除済みのオプション
  eq(child.lua_get([[err({ useSkkServer = true })]]):find("`useSkkServer` is removed", 1, true) ~= nil, true)
  eq(child.lua_get([[err({ useGoogleJapaneseInput = true })]]):find("is removed", 1, true) ~= nil, true)
end

T["set changes nothing when an option is illegal"] = function()
  child.lua([[
    config = require("skkeleton.config")
    pcall(config.set, { eggLikeNewline = true, debug = "x" })
  ]])
  eq(child.lua_get([[config.options.eggLikeNewline]]), false)
end

T["options not used in v1 are accepted"] = function()
  child.lua([[
    config = require("skkeleton.config")
    config.set({
      skkServerHost = "localhost",
      skkServerPort = 1234,
      skkServerReqEnc = "utf-8",
      skkServerResEnc = "utf-8",
      completionRankFile = "",
      sources = { "skk_dictionary", "skk_server" },
    })
  ]])
  eq(child.lua_get([[config.options.skkServerPort]]), 1234)
  eq(child.lua_get([[config.options.sources]]), { "skk_dictionary", "skk_server" })
end

T["reset"] = function()
  child.lua([[
    config = require("skkeleton.config")
    config.set({ debug = true })
    config.reset()
  ]])
  eq(child.lua_get([[config.options.debug]]), false)
end

return T

-- Ported from skkeleton (denops/skkeleton/config.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
local util = require("skkeleton.util")

local M = {}

-- 設定の既定値。キーは upstream と同じ camelCase
local function defaults()
  return {
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
  }
end

-- 他のモジュールが参照を持ち続けられるように、options は同じ表を書き換えて使う
M.options = defaults()

local encodings = {
  ["utf-32"] = true,
  ["utf-16"] = true,
  ["utf-16be"] = true,
  ["utf-16le"] = true,
  binary = true,
  ascii = true,
  jis = true,
  ["utf-8"] = true,
  ["euc-jp"] = true,
  sjis = true,
  unicode = true,
  auto = true,
}

local function ensure_type(x, t)
  if type(x) ~= t then
    error(("expected %s, got %s"):format(t, type(x)), 0)
  end
  return x
end

local function ensure_encoding(x)
  if type(x) == "string" and encodings[x] then
    return x
  end
  error(tostring(x) .. " is invalid encoding", 0)
end

local function of_type(t)
  return function(x)
    return ensure_type(x, t)
  end
end

-- 文字列、または 2 つの文字列の組の配列
local function ensure_path_list(name)
  return function(x)
    local ok = type(x) == "table"
    if ok then
      for _, v in ipairs(x) do
        local t = type(v)
        if not (t == "string" or (t == "table" and #v == 2 and type(v[1]) == "string" and type(v[2]) == "string")) then
          ok = false
        end
      end
    end
    if not ok then
      error(("'%s' must be array of two string tuple"):format(name), 0)
    end
    return x
  end
end

local function ensure_record_of_string(x)
  ensure_type(x, "table")
  for k, v in pairs(x) do
    if type(k) ~= "string" or type(v) ~= "string" then
      error("expected record of string", 0)
    end
  end
  return x
end

local validators = {
  acceptIllegalResult = of_type("boolean"),
  completionRankFile = of_type("string"),
  databasePath = of_type("string"),
  debug = of_type("boolean"),
  eggLikeNewline = of_type("boolean"),
  globalDictionaries = ensure_path_list("globalDictionaries"),
  globalKanaTableFiles = ensure_path_list("globalKanaTableFiles"),
  immediatelyCancel = of_type("boolean"),
  immediatelyDictionaryRW = of_type("boolean"),
  immediatelyOkuriConvert = of_type("boolean"),
  kanaTable = function(x)
    local name = ensure_type(x, "string")
    if not pcall(require("skkeleton.kana").get_table, name) then
      error("can't use undefined kanaTable: " .. name, 0)
    end
    return name
  end,
  keepMode = of_type("boolean"),
  keepState = of_type("boolean"),
  lowercaseMap = ensure_record_of_string,
  markerHenkan = of_type("string"),
  markerHenkanSelect = of_type("string"),
  registerConvertResult = of_type("boolean"),
  selectCandidateKeys = function(x)
    local keys = ensure_type(x, "string")
    if vim.fn.strchars(keys) ~= 7 then
      error("selectCandidateKeys.length !== 7", 0)
    end
    return keys
  end,
  setUndoPoint = of_type("boolean"),
  showCandidatesCount = of_type("number"),
  -- skkServer* と completionRankFile は v1 では使わない。upstream の設定を流用できるように受け付けるだけ
  skkServerHost = of_type("string"),
  skkServerPort = of_type("number"),
  skkServerReqEnc = ensure_encoding,
  skkServerResEnc = ensure_encoding,
  sources = function(x)
    ensure_type(x, "table")
    for _, v in ipairs(x) do
      ensure_type(v, "string")
    end
    return x
  end,
  useGoogleJapaneseInput = function()
    error('`useGoogleJapaneseInput` is removed. Please use `sources` with "google_japanese_input"', 0)
  end,
  useSkkServer = function()
    error('`useSkkServer` is removed. Please use `sources` with "skk_server"', 0)
  end,
  userDictionary = of_type("string"),
}

-- パスの先頭の ~ を展開する
local function normalize(o)
  local dicts = {}
  for _, cfg in ipairs(o.globalDictionaries) do
    if type(cfg) == "string" then
      dicts[#dicts + 1] = { util.expand_home(cfg), "" }
    else
      dicts[#dicts + 1] = { util.expand_home(cfg[1]), cfg[2] }
    end
  end
  o.globalDictionaries = dicts
  local files = {}
  for _, cfg in ipairs(o.globalKanaTableFiles) do
    if type(cfg) == "string" then
      files[#files + 1] = util.expand_home(cfg)
    else
      files[#files + 1] = { util.expand_home(cfg[1]), cfg[2] }
    end
  end
  o.globalKanaTableFiles = files
  o.userDictionary = util.expand_home(o.userDictionary)
  o.completionRankFile = util.expand_home(o.completionRankFile)
  o.databasePath = util.expand_home(o.databasePath)
end

-- 設定を検証して反映する。未知のキーや型が違う値があれば、何も反映せずにエラーにする
---@param new_config table<string, any>
function M.set(new_config)
  local options = M.options
  local staged = {}
  for k, v in pairs(new_config) do
    local validator = validators[k]
    local ok, ret
    if validator then
      ok, ret = pcall(validator, v)
    else
      ok, ret = false, "unknown option: " .. tostring(k)
    end
    if not ok then
      error("Illegal option detected: " .. tostring(ret), 0)
    end
    staged[k] = ret
  end
  for k, v in pairs(staged) do
    options[k] = v
  end
  normalize(options)
  require("skkeleton.kana").load_files(options.globalKanaTableFiles)
end

-- 既定値に戻す（テスト用）
function M.reset()
  local options = M.options
  for k in pairs(options) do
    options[k] = nil
  end
  for k, v in pairs(defaults()) do
    options[k] = v
  end
end

return M

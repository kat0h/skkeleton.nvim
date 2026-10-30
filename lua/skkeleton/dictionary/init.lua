-- Ported from skkeleton (denops/skkeleton/dictionary.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua. Global dictionaries are read through a persistent DB cache.
--
-- 辞書の入り口。Library がユーザー辞書とグローバル辞書をまとめ、候補を重複なしで返す。
local db = require("skkeleton.dictionary.db")
local numeral = require("skkeleton.dictionary.numeral")
local skk = require("skkeleton.dictionary.skk")
local User = require("skkeleton.dictionary.user")
local util = require("skkeleton.util")

local M = {}

M.Library = {}
local Library = M.Library
Library.__index = Library

---@class skkeleton.Library
---@field dicts table[]
---@field user_dict? skkeleton.UserDictionary
---@field immediately_rw boolean

-- dicts: get_henkan_result(kind, word) を持つ辞書の配列。user_dict は先に引き、数値変換をつける。
-- cfg.immediatelyDictionaryRW が真なら、検索の前にユーザー辞書を読み、登録と削除のあとに書く
---@param dicts? table[]
---@param user_dict? skkeleton.UserDictionary
---@param cfg? { immediatelyDictionaryRW?: boolean }
---@return skkeleton.Library
function Library.new(dicts, user_dict, cfg)
  local self = setmetatable({ user_dict = user_dict, dicts = {}, immediately_rw = false }, Library)
  if user_dict then
    self.dicts[1] = numeral.wrap(user_dict)
  end
  vim.list_extend(self.dicts, dicts or {})
  self.immediately_rw = cfg ~= nil and cfg.immediatelyDictionaryRW == true
  return self
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@return string[]
function Library:get_henkan_result(kind, word)
  if self.immediately_rw then
    self:load()
  end
  local merged, seen = {}, {}
  for _, dic in ipairs(self.dicts) do
    for _, c in ipairs(dic:get_henkan_result(kind, word)) do
      if not seen[c] then
        seen[c] = true
        merged[#merged + 1] = c
      end
    end
  end
  return merged
end

-- 補完で返す読みの数の上限の既定
M.COMPLETION_LIMIT = 100

-- feed から始まるかなテーブルのキーのうち、かなに変わるもの（{ かな, 次の feed }）の「かな」を足した読みの一覧。
-- 例: prefix "か"、feed "k" なら "かか"、"かき"、... 重複は 1 つにして、バイト順に並べる
---@param prefix string
---@param feed string
---@return string[]
local function feed_prefixes(prefix, feed)
  local tbl = require("skkeleton.kana").get_table()
  local seen, out = {}, {}
  for key, result in pairs(tbl.map) do
    if type(result) == "table" and #result > 1 and vim.startswith(key, feed) then
      local p = prefix .. result[1]
      if not seen[p] then
        seen[p] = true
        out[#out + 1] = p
      end
    end
  end
  table.sort(out)
  return out
end

-- 読みごとの候補を、重複なしで集める
---@param order string[]
---@param map table<string, string[]>
---@param seen table<string, table<string, boolean>>
---@param kana string
---@param cands string[]
local function gather(order, map, seen, kana, cands)
  if not map[kana] then
    map[kana] = {}
    seen[kana] = {}
    order[#order + 1] = kana
  end
  for _, c in ipairs(cands) do
    if not seen[kana][c] then
      seen[kana][c] = true
      table.insert(map[kana], c)
    end
  end
end

-- 補完の候補。{ { 読み, 候補の配列 }, ... } を、ユーザー辞書、グローバル辞書の順に、辞書ごとに読みのバイト順で返す。
-- prefix が 1 文字なら送りなしの完全一致だけ、2 文字以上なら前方一致。
-- feed が空でなければ、かなテーブルで feed から始まるキーのかなを足した読みで前方一致する。
-- 読みの数は limit（既定 M.COMPLETION_LIMIT）まで
---@param prefix string
---@param feed? string
---@param limit? integer
---@return { [1]: string, [2]: string[] }[]
function Library:get_completion_result(prefix, feed, limit)
  feed = feed or ""
  limit = limit or M.COMPLETION_LIMIT
  if self.immediately_rw then
    self:load()
  end
  if prefix == "" then
    return {}
  end
  local order, map, seen = {}, {}, {}
  local exact_match = feed == "" and #util.chars(prefix) == 1
  local prefixes = feed ~= "" and feed_prefixes(prefix, feed) or { prefix }
  for _, dic in ipairs(self.dicts) do
    if exact_match then
      gather(order, map, seen, prefix, dic:get_henkan_result("okurinasi", prefix))
    else
      for _, p in ipairs(prefixes) do
        if #order >= limit then
          break
        end
        for _, e in ipairs(dic:get_prefix("okurinasi", p, limit)) do
          gather(order, map, seen, e[1], e[2])
        end
      end
    end
    if #order >= limit then
      break
    end
  end
  local out = {}
  for i = 1, math.min(#order, limit) do
    local k = order[i]
    if #map[k] > 0 then
      out[#out + 1] = { k, map[k] }
    end
  end
  return out
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@param candidate string
function Library:register_henkan_result(kind, word, candidate)
  if not self.user_dict then
    return
  end
  self.user_dict:register_henkan_result(kind, word, candidate)
  if self.immediately_rw then
    self.user_dict:save()
  end
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@param candidate string
function Library:purge_candidate(kind, word, candidate)
  if not self.user_dict then
    return
  end
  self.user_dict:purge_candidate(kind, word, candidate)
  if self.immediately_rw then
    self.user_dict:save()
  end
end

function Library:load()
  if self.user_dict then
    self.user_dict:load({})
  end
end

function Library:save()
  if self.user_dict then
    self.user_dict:save()
  end
end

-- 開いている DB を閉じる
function Library:close()
  for _, dic in ipairs(self.dicts) do
    if dic.close then
      dic:close()
    end
  end
end

local DEFAULT_USER_DICTIONARY = "~/.skkeleton"

-- globalDictionaries の 1 要素（文字列、{path, encoding}、{path, encoding} の並び）を { path, encoding } にそろえる
---@return { path: string, encoding?: string }[]
local function global_dictionaries(cfg)
  local out = {}
  for _, d in ipairs(cfg.globalDictionaries or {}) do
    local path, encoding
    if type(d) == "string" then
      path = d
    elseif type(d) == "table" then
      path, encoding = d.path or d[1], d.encoding or d[2]
    end
    if type(path) == "string" and path ~= "" then
      out[#out + 1] = { path = util.expand_home(path), encoding = encoding }
    end
  end
  return out
end

local function source_names(cfg)
  return cfg.sources or { "skk_dictionary" }
end

local function is_db_source(name)
  return name == "skk_dictionary" or name == "deno_kv"
end

local function warn(msg)
  vim.notify("skkeleton: " .. msg, vim.log.levels.WARN)
end

local function is_json(path)
  return path:lower():match("%.json$") ~= nil
end

-- グローバル辞書を 1 つ開く。JSON はメモリに読み、SKK 形式は DB を（必要なら作って）開く。
-- DB を作れない（書き込めないなど）ときはメモリに読む
local function open_global(entry, cfg)
  local ok, dict = pcall(function()
    if is_json(entry.path) then
      return skk.load_json(entry.path)
    end
    skk.check_supported(entry.path)
    local dir = db.cache_dir(cfg.databasePath)
    local opened, res = pcall(db.open_dictionary, entry.path, { encoding = entry.encoding, dir = dir })
    if opened then
      return res
    end
    return skk.load_memory(entry.path, entry.encoding)
  end)
  if not ok then
    warn(("globalDictionary loading failed\nat %s\n%s"):format(entry.path, dict))
    return nil
  end
  return numeral.wrap(dict)
end

-- config（camelCase の表）から Library を作る。キャッシュが古ければその場で作る
---@param cfg? table
---@return skkeleton.Library
function M.load(cfg)
  cfg = cfg or {}
  local user = User.new()
  local user_path = cfg.userDictionary
  if user_path == nil then
    user_path = DEFAULT_USER_DICTIONARY
  end
  user:load({ path = user_path })

  local dicts = {}
  local globals_done = false
  for _, name in ipairs(source_names(cfg)) do
    if is_db_source(name) then
      if not globals_done then
        globals_done = true
        for _, entry in ipairs(global_dictionaries(cfg)) do
          local dict = open_global(entry, cfg)
          if dict then
            dicts[#dicts + 1] = dict
          end
        end
      end
    else
      warn(("Invalid source name: %s"):format(tostring(name)))
    end
  end
  return Library.new(dicts, user, cfg)
end

-- load の非同期版。キャッシュが古い辞書を、UI を止めずに作ってから Library を作る。
-- 終わったら on_done(lib)
---@param cfg? table
---@param on_done fun(lib: skkeleton.Library)
function M.prepare(cfg, on_done)
  cfg = cfg or {}
  local entries = {}
  if vim.tbl_contains(source_names(cfg), "skk_dictionary") or vim.tbl_contains(source_names(cfg), "deno_kv") then
    for _, e in ipairs(global_dictionaries(cfg)) do
      if not is_json(e.path) and pcall(skk.check_supported, e.path) then
        entries[#entries + 1] = e
      end
    end
  end
  local dir = db.cache_dir(cfg.databasePath)
  local i = 0
  local function next_entry()
    i = i + 1
    local e = entries[i]
    if not e then
      return on_done(M.load(cfg))
    end
    -- 失敗しても飛ばす（load がもう一度試して、だめならメモリに読むか警告する）
    db.ensure_async(e.path, { encoding = e.encoding, dir = dir }, function()
      next_entry()
    end)
  end
  next_entry()
end

-- 指定した辞書の DB を作り直す（force が偽なら、古いときだけ）。upstream の updateDatabase 相当
---@param cfg? table
---@param path string
---@param encoding? string
---@param force? boolean
function M.update_database(cfg, path, encoding, force)
  cfg = cfg or {}
  db.ensure(util.expand_home(path), { encoding = encoding, dir = db.cache_dir(cfg.databasePath), force = force })
end

return M

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

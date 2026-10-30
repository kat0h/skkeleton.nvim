-- Ported from skkeleton (denops/skkeleton/sources/user_dictionary.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua. The rank file is not supported.
--
-- ユーザー辞書。メモリに読み、登録と削除をして、SKK 形式で書き戻す。
local skk = require("skkeleton.dictionary.skk")
local util = require("skkeleton.util")

local uv = vim.uv
local bit = require("bit")

---@class skkeleton.UserDictionary
---@field path string
---@field load_time string
---@field maps table<string, table<string, string[]>>
local User = {}
User.__index = User

---@return skkeleton.UserDictionary
function User.new()
  return setmetatable({
    maps = { okuriari = {}, okurinasi = {} },
    path = "",
    load_time = "",
  }, User)
end

-- 送りありエントリブロック（"[と/ど]" のようなもの）は今のところ無視する
---@param candidates string[]
local function filter(candidates)
  local out = {}
  for _, c in ipairs(candidates) do
    if c:sub(1, 1) ~= "[" then
      out[#out + 1] = c
    end
  end
  return out
end

-- "/a/[b/c]/d/" を { "a", "[b/c]", "d" } に分ける（ブロックは中に "/" があっても 1 つにする）
---@param value string
local function split_with_blocks(value)
  local out = {}
  local i = 1
  while i <= #value do
    if value:byte(i) == 47 then -- '/'
      i = i + 1
    else
      local a, b = value:find("^%[[^%]]+%]", i)
      if not a then
        a, b = value:find("^[^/]+", i)
      end
      out[#out + 1] = value:sub(a, b)
      i = b + 1
    end
  end
  return out
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@return string[]
function User:get_henkan_result(kind, word)
  return filter(self.maps[kind][word] or {})
end

-- 前方一致する読みを、バイト順に limit 件まで。{ { 読み, 候補の配列 }, ... }
function User:get_prefix(kind, prefix, limit)
  local keys = {}
  for k in pairs(self.maps[kind]) do
    if vim.startswith(k, prefix) then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local cands = filter(self.maps[kind][k])
    if #cands > 0 then
      out[#out + 1] = { k, cands }
      if limit and #out >= limit then
        break
      end
    end
  end
  return out
end

-- 登録した候補を先頭にする（重複は取り除く）
---@param kind "okuriari"|"okurinasi"
---@param word string
---@param candidate string
function User:register_henkan_result(kind, word, candidate)
  if candidate == "" then
    return
  end
  local merged = { candidate }
  for _, c in ipairs(self.maps[kind][word] or {}) do
    if c ~= candidate then
      merged[#merged + 1] = c
    end
  end
  self.maps[kind][word] = merged
end

---@param kind "okuriari"|"okurinasi"
---@param word string
---@param candidate string
function User:purge_candidate(kind, word, candidate)
  local rest = {}
  for _, c in ipairs(self.maps[kind][word] or {}) do
    if c ~= candidate then
      rest[#rest + 1] = c
    end
  end
  self.maps[kind][word] = #rest > 0 and rest or nil
end

local function mtime_of(path)
  local st = uv.fs_stat(path)
  return st and ("%d.%09d"):format(st.mtime.sec, st.mtime.nsec)
end

---@param path string
function User:read_file(path)
  local text = skk.read_file(path)
  local maps = { okuriari = {}, okurinasi = {} }
  local cur
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    if line == skk.OKURI_ARI_MARKER then
      cur = maps.okuriari
    elseif line == skk.OKURI_NASI_MARKER then
      cur = maps.okurinasi
    elseif cur then
      local sp = line:find(" ", 1, true)
      if sp and sp > 1 then
        cur[line:sub(1, sp - 1)] = split_with_blocks(line:sub(sp + 1))
      end
    end
  end
  self.maps = maps
end

-- ファイルから読む。前に読んだときから mtime が変わっていなければ何もしない。
-- 読めなかったときは今の内容を残す（upstream と同じく黙って戻る）
---@param opts? { path?: string }
function User:load(opts)
  local path = opts and opts.path
  if path and path ~= "" then
    path = util.expand_home(path)
    if path ~= self.path then
      self.path = path
      self.load_time = ""
    end
  end
  if self.path == "" then
    return
  end
  local time = mtime_of(self.path)
  if not time or time == self.load_time then
    return
  end
  self.load_time = time
  pcall(self.read_file, self, self.path)
end

local function sorted_lines(map, descending)
  local keys = skk.sorted_keys(map)
  local out = {}
  -- SKK の辞書は、送りありを読みの逆順に並べる
  local first, last, step = 1, #keys, 1
  if descending then
    first, last, step = #keys, 1, -1
  end
  for i = first, last, step do
    out[#out + 1] = ("%s /%s/"):format(keys[i], table.concat(map[keys[i]], "/"))
  end
  return out
end

-- SKK 形式で書き戻す。書けなかったら警告する
function User:save()
  if self.path == "" then
    return
  end
  local lines = { skk.OKURI_ARI_MARKER }
  vim.list_extend(lines, sorted_lines(self.maps.okuriari, true))
  table.insert(lines, skk.OKURI_NASI_MARKER)
  vim.list_extend(lines, sorted_lines(self.maps.okurinasi, false))
  table.insert(lines, "")
  -- 書いている途中で落ちても辞書が欠けないよう、同じディレクトリの一時ファイルに書いてから rename する。
  -- シンボリックリンクはリンク先を書き換える（リンクそのものは残す）
  local target = uv.fs_realpath(self.path) or self.path
  local stat = uv.fs_stat(target)
  local tmp = ("%s.%d.tmp"):format(target, uv.os_getpid())
  local ok = false
  local fd = uv.fs_open(tmp, "w", stat and bit.band(stat.mode, 511) or 420)
  if fd then
    ok = uv.fs_write(fd, table.concat(lines, "\n"), 0) ~= nil
    ok = uv.fs_fsync(fd) ~= nil and ok
    uv.fs_close(fd)
    ok = ok and uv.fs_rename(tmp, target) ~= nil
    if not ok then
      uv.fs_unlink(tmp)
    end
  end
  if not ok then
    vim.notify(("skkeleton: can't write userDictionary to %s"):format(self.path), vim.log.levels.WARN)
    return
  end
  self.load_time = mtime_of(self.path) or ""
end

function User:close() end

return User

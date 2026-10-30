-- SKK 辞書ファイルを読む共通部分（ベンチ用）
local M = {}

M.KINDS = { "okuriari", "okurinasi" }

function M.read_file(path)
  local fd = assert(vim.uv.fs_open(path, "r", 438))
  local stat = assert(vim.uv.fs_fstat(fd))
  local data = assert(vim.uv.fs_read(fd, stat.size, 0))
  vim.uv.fs_close(fd)
  return data, stat
end

-- 先頭の coding 指定を見て UTF-8 に変換する（指定がなければ EUC-JP とみなす）
function M.to_utf8(data, encoding)
  if not encoding or encoding == "" then
    local head = data:sub(1, 200):lower()
    encoding = head:find("coding: *utf%-8") and "utf-8" or "euc-jp"
  end
  if encoding == "utf-8" then
    return data
  end
  return assert(vim.iconv(data, encoding, "utf-8"), "iconv failed")
end

-- 辞書を {okuriari = {[読み] = "/候補/.../"}, okurinasi = {...}} に分ける
-- 同じ読みが 2 回出てきたら先のものを使う
function M.parse(text)
  local maps = { okuriari = {}, okurinasi = {} }
  local cur
  for line in text:gmatch("([^\n]*)\n?") do
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    if line == ";; okuri-ari entries." then
      cur = maps.okuriari
    elseif line == ";; okuri-nasi entries." then
      cur = maps.okurinasi
    elseif cur and line ~= "" and line:byte(1) ~= 59 then -- ';'
      local sp = line:find(" ", 1, true)
      if sp then
        local key = line:sub(1, sp - 1)
        if cur[key] == nil then
          cur[key] = line:sub(sp + 1)
        end
      end
    end
  end
  return maps
end

function M.load(path, encoding)
  local data, stat = M.read_file(path)
  return M.parse(M.to_utf8(data, encoding)), stat
end

-- バイト順にソートした読みの配列
function M.sorted_keys(map)
  local keys = {}
  for k in pairs(map) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

return M

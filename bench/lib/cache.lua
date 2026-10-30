-- C / C' が使う永続キャッシュの形式（v1）
--
--   [0, 128)   ヘッダ: "SKKDB 1 <nari> <nnasi> <src_size> <src_mtime_sec> <src_mtime_nsec>\n" を空白で埋めたもの
--   [128, ...) 索引: リトルエンディアンの u32 で、各行の先頭のファイル内オフセット（0 起点）
--              okuri-ari の nari 個 + 終端 1 個、続けて okuri-nasi の nnasi 個 + 終端 1 個
--   その後     データ: "読み 候補\n" を種類ごとにバイト順にソートして並べたもの（ari, nasi の順）
--
-- 行 i の長さは off[i + 1] - off[i] でわかるので、行を読むときは 1 回の read で済む
local skk = require("lib.skk")
local bit = require("bit")

local M = {}

M.HEADER_SIZE = 128
M.VERSION = 1

local function u32(n)
  return string.char(bit.band(n, 0xff), bit.band(bit.rshift(n, 8), 0xff), bit.band(bit.rshift(n, 16), 0xff), bit.rshift(n, 24))
end

function M.parse_header(s)
  local v, nari, nnasi, size, sec, nsec = s:match("^SKKDB (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)\n")
  if not v or tonumber(v) ~= M.VERSION then
    return nil
  end
  return {
    nari = tonumber(nari),
    nnasi = tonumber(nnasi),
    src_size = tonumber(size),
    src_sec = tonumber(sec),
    src_nsec = tonumber(nsec),
  }
end

function M.build(src, dst, encoding)
  local maps, stat = skk.load(src, encoding)
  local keys = { okuriari = skk.sorted_keys(maps.okuriari), okurinasi = skk.sorted_keys(maps.okurinasi) }
  local nari, nnasi = #keys.okuriari, #keys.okurinasi
  local data_start = M.HEADER_SIZE + (nari + 1 + nnasi + 1) * 4
  local idx, data = {}, {}
  local pos = data_start
  for _, kind in ipairs(skk.KINDS) do
    for _, k in ipairs(keys[kind]) do
      local line = k .. " " .. maps[kind][k] .. "\n"
      idx[#idx + 1] = u32(pos)
      data[#data + 1] = line
      pos = pos + #line
    end
    idx[#idx + 1] = u32(pos) -- 終端
  end
  assert(pos < 2 ^ 32, "dictionary too large")
  local header = ("SKKDB %d %d %d %d %d %d\n"):format(M.VERSION, nari, nnasi, stat.size, stat.mtime.sec, stat.mtime.nsec)
  header = header .. (" "):rep(M.HEADER_SIZE - #header)
  vim.fn.mkdir(vim.fs.dirname(dst), "p")
  local tmp = dst .. ".tmp"
  local fd = assert(vim.uv.fs_open(tmp, "w", 420))
  assert(vim.uv.fs_write(fd, { header, table.concat(idx), table.concat(data) }, 0))
  vim.uv.fs_close(fd)
  assert(vim.uv.fs_rename(tmp, dst))
end

-- キャッシュが元の辞書と食い違っていないか（サイズと mtime で判定する）
function M.is_fresh(src, dst)
  local fd = vim.uv.fs_open(dst, "r", 438)
  if not fd then
    return false
  end
  local h = M.parse_header(vim.uv.fs_read(fd, M.HEADER_SIZE, 0) or "")
  vim.uv.fs_close(fd)
  local st = vim.uv.fs_stat(src)
  return h ~= nil and st ~= nil and h.src_size == st.size and h.src_sec == st.mtime.sec and h.src_nsec == st.mtime.nsec
end

function M.path_for(src, dir)
  return vim.fs.joinpath(dir, vim.fn.sha256(vim.fs.normalize(src)):sub(1, 16) .. ".db")
end

return M

-- bench/ 以下のスクリプトの共通の下準備
local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
M.out = vim.fs.joinpath(M.root, "out")
M.cache_dir = vim.fs.joinpath(M.out, "cache")

M.IMPLS = {
  A = "impl.a_table",
  B = "impl.b_memory",
  C = "impl.c_pread",
  Cp = "impl.cp_mmap",
}

-- キャッシュを使う実装の open に渡すパス
function M.open(name, src)
  local impl = require(M.IMPLS[name])
  if impl.build then
    local cache = require("lib.cache")
    local dst = cache.path_for(src, M.cache_dir)
    assert(cache.is_fresh(src, dst), "cache is not built: run bench/build.lua first")
    return impl.open(dst)
  end
  return impl.open(src)
end

function M.now()
  return vim.uv.hrtime()
end

function M.rss_kb()
  local f = io.open("/proc/self/statm")
  local _, rss = f:read("*a"):match("(%d+) (%d+)")
  f:close()
  return tonumber(rss) * 4
end

-- UTF-8 の文字単位で先頭 n 文字
function M.utf8_head(s, n)
  local out, i = {}, 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    i = i + 1
    if i > n then
      break
    end
    out[i] = ch
  end
  return table.concat(out)
end

return M

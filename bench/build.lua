-- 使い方: nvim --headless -u NONE -l bench/build.lua <dict...>
-- 各辞書のキャッシュを作り直し、かかった時間を JSON で出す
local boot = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/lib/boot.lua")
package.path = boot.root .. "/?.lua;" .. package.path
local cache = require("lib.cache")

for _, src in ipairs(arg) do
  local dst = cache.path_for(src, boot.cache_dir)
  local t0 = boot.now()
  cache.build(src, dst)
  local ms = (boot.now() - t0) / 1e6
  io.stdout:write(vim.json.encode({ kind = "build", dict = vim.fs.basename(src), ms = ms, bytes = vim.uv.fs_stat(dst).size }), "\n")
end

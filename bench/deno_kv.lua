-- D（参考）: 今の skkeleton（denops + deno_kv）で getCandidates の往復時間を測る
-- 使い方: nvim --headless -u NONE -i NONE -c "luafile bench/deno_kv.lua" <dict>
--   環境変数 LAZY に denops.vim と skkeleton がある場所（既定 ~/.local/share/nvim/lazy）
-- DB とユーザー辞書は bench/out/ 以下に別に作るので、普段の環境には触れない
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local out = here .. "/out"
local dict = vim.fn.argv(0)
local lazy = os.getenv("LAZY") or vim.fn.expand("~/.local/share/nvim/lazy")
local function emit(t)
  io.stdout:write(vim.json.encode(t), "\n")
end
local function finish(code)
  io.stdout:flush()
  vim.cmd(code == 0 and "qall!" or "cquit!")
end
local function hr()
  return vim.uv.hrtime()
end

vim.opt.rtp:append(lazy .. "/denops.vim")
vim.opt.rtp:append(lazy .. "/skkeleton")
vim.g["denops#server#deno_args"] = { "--allow-all", "--unstable-kv" }
local t_start = hr()
vim.cmd("runtime! plugin/denops.vim plugin/skkeleton.vim")

-- Note: skkeleton#config() はプラグインの読み込み前だと DenopsPluginPost のあとに
--       後回しで送られ、ここの計測より遅れる。なので読み込み後に同期で送る
local config = {
  globalDictionaries = { dict },
  sources = { "deno_kv" },
  databasePath = out .. "/deno_kv.db",
  userDictionary = out .. "/deno_kv_userjisyo",
}

-- 検索する語は run.lua と同じもの（hit と miss の先頭 1000 個ずつ）
local queries = {}
local nhit, nmiss = 0, 0
for _, line in ipairs(vim.fn.readfile(out .. "/queries.tsv")) do
  local what, kind, key = line:match("^(%S+)\t(%S+)\t(.*)$")
  if (what == "hit" and nhit < 1000) or (what == "miss" and nmiss < 1000) then
    queries[#queries + 1] = { what, kind, key }
    nhit = nhit + (what == "hit" and 1 or 0)
    nmiss = nmiss + (what == "miss" and 1 or 0)
  end
end

vim.defer_fn(function()
  emit({ kind = "deno_kv", error = "timeout" })
  finish(1)
end, 600000)


vim.api.nvim_create_autocmd("User", {
  pattern = "DenopsPluginPost:skkeleton",
  once = true,
  callback = vim.schedule_wrap(function()
    local ok, err = pcall(function()
      local t_loaded = hr()
      vim.fn["denops#request"]("skkeleton", "config", { config })
      -- 初回は Library の初期化（DB の読み込み、無ければ生成）を含む
      local q = queries[1]
      vim.fn["denops#request"]("skkeleton", "getCandidates", { q[3], q[2] })
      local t_first = hr()
      local xs = { hit = {}, miss = {} }
      local found = 0
      for _, qq in ipairs(queries) do
        local s = hr()
        local c = vim.fn["denops#request"]("skkeleton", "getCandidates", { qq[3], qq[2] })
        table.insert(xs[qq[1]], hr() - s)
        if qq[1] == "hit" and #c > 0 then
          found = found + 1
        end
      end
      local function stats(a)
        table.sort(a)
        local function p(r)
          return a[math.max(1, math.ceil(#a * r))] / 1e6
        end
        return { n = #a, p50 = p(0.5), p99 = p(0.99), max = a[#a] / 1e6 }
      end
      emit({
        kind = "deno_kv",
        plugin_load_ms = (t_loaded - t_start) / 1e6,
        first_request_ms = (t_first - t_loaded) / 1e6,
        ready_ms = (t_first - t_start) / 1e6,
        hit_found = found,
        lookup = stats(xs.hit),
        miss = stats(xs.miss),
      })
    end)
    if not ok then
      emit({ kind = "deno_kv", error = tostring(err) })
    end
    finish(ok and 0 or 1)
  end),
})

-- skkeleton.nvim の Lua API
-- 設定やキーマップの登録は upstream の skkeleton#config などに対応する。
local M = {}

-- 設定する。opts.indicator はインジケータの設定（nil なら既定で有効、false なら無効）、
-- opts.completion は blink.cmp 補完の設定（{ enabled, minLength }）
---@param opts? table
function M.setup(opts)
  opts = vim.deepcopy(opts or {})
  local indicator = opts.indicator
  opts.indicator = nil
  local completion = opts.completion
  opts.completion = nil
  require("skkeleton.completion").setup(completion)
  require("skkeleton.config").set(opts)
  if indicator == nil or indicator == true then
    indicator = {}
  end
  require("skkeleton.indicator").setup(indicator)
end

function M.enable()
  require("skkeleton.main").handle("enable", {})
end

function M.disable()
  require("skkeleton.main").handle("disable", {})
end

function M.toggle()
  require("skkeleton.main").handle("toggle", {})
end

-- 有効なときだけモード名（"hira" など）を返す。無効なら ""
---@return string
function M.mode()
  if M.is_enabled() then
    return vim.g["skkeleton#mode"] or ""
  end
  return ""
end

---@return boolean
function M.is_enabled()
  return vim.g["skkeleton#enabled"] == true
end

-- state ("input"|"henkan") のキーに関数を割り当てる。func が空なら削除
---@param state string
---@param key string
---@param func string|function|false|nil
function M.register_keymap(state, key, func)
  require("skkeleton.keymap").register(state, require("skkeleton.notation").normalize(key), func)
end

---@param name string
---@param tbl table
---@param create? boolean
function M.register_kanatable(name, tbl, create)
  require("skkeleton.kana").register(name, tbl, create and true or false)
end

---@param name string
---@param path string
---@param encoding? string
---@param create? boolean
function M.register_kanatable_file(name, path, encoding, create)
  require("skkeleton.kana").load_file(name, path, encoding or "", create and true or false)
end

---@return table
function M.get_config()
  return require("skkeleton.config").options
end

-- 初期化して、辞書を UI を止めずに準備する
---@param force? boolean
function M.initialize(force)
  require("skkeleton.main").init(force)
  local store = require("skkeleton.store")
  require("skkeleton.dictionary").prepare(require("skkeleton.config").options, function(lib)
    store.set_library(lib)
  end)
end

-- 以下は補完 source が使う。upstream の dispatcher の getPrefix などに当たる

-- 今の読み（▽ のあとの、かなになった部分）。入力中でなければ ""
---@return string
function M.get_prefix()
  local st = require("skkeleton.store").context().state
  if st.type ~= "input" then
    return ""
  end
  return st.henkan_feed
end

-- 今の pre-edit の文字列（▽かんj など）
---@return string
function M.get_preedit()
  return require("skkeleton.store").context():to_string()
end

M.get_pre_edit = M.get_preedit

-- 今の読みと feed に合う補完の候補。{ { 読み, 候補の配列 }, ... }
---@return { [1]: string, [2]: string[] }[]
function M.get_completion_result()
  local st = require("skkeleton.store").context().state
  if st.type ~= "input" then
    return {}
  end
  return require("skkeleton.store").library():get_completion_result(st.henkan_feed, st.feed)
end

M.get_completions = M.get_completion_result

---@return table<string, integer>
function M.get_completion_ranks()
  local store = require("skkeleton.store")
  local lib = store.library()
  if lib and lib.get_ranks then
    return lib:get_ranks()
  end
  return {}
end

-- ユーザー辞書と補完ランクを保存する
function M.save_user_dict()
  local store = require("skkeleton.store")
  local lib = store.library()
  if lib then
    lib:save()
    local config = require("skkeleton.config")
    if lib.user_dict and config.options.completionRankFile ~= "" then
      lib.user_dict:save_ranks(config.options.completionRankFile)
    end
  end
end

-- 補完で選んだ語をユーザー辞書に登録する（pre-edit はそのまま）
---@param kana string
---@param word string
---@param kind? "okuriari"|"okurinasi"
function M.complete_callback(kana, word, kind)
  require("skkeleton.main").complete_callback(kana, word, kind)
end

-- 補完で語を選んだとき。pre-edit を捨てて word を確定し、ユーザー辞書に登録する
---@param kana string
---@param word string
---@param kind? "okuriari"|"okurinasi"
function M.complete(kana, word, kind)
  require("skkeleton.main").complete(kana, word, kind)
end

-- 辞書の DB を作り直す（force が偽なら、古いときだけ）
---@param path string
---@param encoding? string
---@param force? boolean
function M.update_database(path, encoding, force)
  require("skkeleton.dictionary").update_database(require("skkeleton.config").options, path, encoding, force)
  vim.cmd(("echomsg 'updated database: \"%s\"'"):format((path:gsub("'", "''"))))
end

return M

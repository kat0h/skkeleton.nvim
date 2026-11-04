-- skkeleton.nvim: blink.cmp との結合。
-- pre-edit はバッファに無いので blink は自分では開かない。skkeleton.nvim が描き直したあと
-- （User skkeleton-handled）に、▽ の入力中で読みが変わったら blink に開くよう頼み、▽ を抜けたら閉じる。
-- blink.cmp が入っていなければ何もしない。
local M = {}

---@class skkeleton.CompletionOptions
---@field enabled boolean skkeleton の描画のあとに blink.cmp のメニューを開閉する
---@field minLength integer 読みがこの文字数（かな）以上になってから開く

local function defaults()
  return { enabled = true, minLength = 2 }
end

---@type skkeleton.CompletionOptions
M.options = defaults()

local validators = {
  enabled = function(x)
    return type(x) == "boolean"
  end,
  minLength = function(x)
    return type(x) == "number" and x >= 1 and x == math.floor(x)
  end,
}

-- blink.cmp が入っていないことを一度確かめたら、setup() まで require を繰り返さない
local blink_missing = false

-- blink.cmp。入っていなければ nil
---@return table?
local function get_blink()
  local loaded = package.loaded["blink.cmp"]
  if loaded then
    return loaded
  end
  if blink_missing then
    return nil
  end
  local ok, blink = pcall(require, "blink.cmp")
  if not ok then
    blink_missing = true
    return nil
  end
  return blink
end

-- 最後に開いた (読み, feed)。同じなら開き直さない
local last_key ---@type string?
-- skkeleton が blink のメニューを開いているか
local shown = false

-- blink のメニューは既定ではキーワードの開始位置に揃う。skkeleton の pre-edit は
-- バッファに無いので、カーソルの前に日本語があるとメニューが行頭に寄る (#143)。
-- メニューを出している間だけカーソルに揃え、閉じたら元の設定へ戻す。
-- blink の開閉は次の tick に回ることがあるので、呼び出し側ではなくメニューの
-- 開閉のイベントに合わせる。閉じる前に戻すと、その間にカーソルが動いたとき
-- メニューが行頭に寄ってから消える (#174)
local align_to_before ---@type string?

local function config_draw()
  local ok, cfg = pcall(require, "blink.cmp.config")
  if not ok then
    return nil
  end
  return cfg.completion and cfg.completion.menu and cfg.completion.menu.draw
end

local function align_menu_to_cursor()
  if align_to_before ~= nil then
    return
  end
  local draw = config_draw()
  if not draw or draw.align_to == "cursor" then
    return
  end
  align_to_before = draw.align_to
  draw.align_to = "cursor"
end

local function restore_menu_align()
  local before = align_to_before
  if before == nil then
    return
  end
  align_to_before = nil
  local draw = config_draw()
  if draw then
    draw.align_to = before
  end
end

local function hide(force)
  last_key = nil
  if not shown and not force then
    return
  end
  shown = false
  local blink = get_blink()
  if blink then
    pcall(blink.hide)
  end
end

M.hide = hide

-- ▽ の入力中か。setup() の autocmd から呼ぶので先に宣言する
local is_pending

-- 設定する。未知のキーや型が違う値があれば、何も反映せずにエラーにする
---@param opts? table
function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("Illegal option detected: completion must be a table", 0)
  end
  for k, v in pairs(opts) do
    if not validators[k] then
      error("Illegal option detected: unknown completion option: " .. tostring(k), 0)
    elseif not validators[k](v) then
      error(("Illegal option detected: invalid completion.%s: %s"):format(k, vim.inspect(v)), 0)
    end
  end
  M.options = vim.tbl_extend("force", defaults(), opts)
  blink_missing = false

  local group = vim.api.nvim_create_augroup("skkeleton-completion", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "skkeleton-handled",
    callback = function()
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "skkeleton-enable-post", "skkeleton-disable-post" },
    -- skkeleton が開いたものではないメニューも閉じるので、shown に関係なく hide を呼ぶ
    callback = function()
      hide(true)
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "BlinkCmpMenuOpen",
    callback = function()
      if M.options.enabled and is_pending() then
        align_menu_to_cursor()
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "BlinkCmpMenuClose",
    callback = function()
      restore_menu_align()
    end,
  })
end

-- ▽ の入力中（送りなしで、読みが空でない）か
---@return boolean
function is_pending()
  if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
    return false
  end
  local store = require("skkeleton.store")
  local st = store.context().state
  return st.type == "input" and st.mode == "okurinasi" and st.henkan_feed ~= ""
end

--- 補完を出してよい状態か（skkeleton が有効で、insert モード、▽ の入力中で読みが空でない）
---@return boolean
function M.can_complete()
  if not require("skkeleton").is_enabled() then
    return false
  end
  return is_pending()
end

---@class skkeleton.CompletionItem
---@field kana string 読み
---@field word string 注釈を除いた単語
---@field raw string 辞書の元の候補文字列
---@field annotation? string 注釈

--- ソート・注釈分離済みの共通補完項目一覧を返す
---@return skkeleton.CompletionItem[]
function M.items()
  if not M.can_complete() then
    return {}
  end
  local skkeleton = require("skkeleton")
  local sort = require("skkeleton.completion.sort")
  local candidate_mod = require("skkeleton.candidate")

  local completions = skkeleton.get_completion_result()
  local sorted = sort.sort_completions(completions, require("skkeleton").get_completion_ranks())

  local items = {}
  for _, entry in ipairs(sorted) do
    local kana = entry.kana
    local cand = entry.word
    local word, annotation = candidate_mod.pair(cand)
    items[#items + 1] = {
      kana = kana,
      word = word,
      raw = cand,
      annotation = (annotation and annotation ~= "") and annotation or nil,
    }
  end
  return items
end

-- 補完で選んだ語を確定する。補完の入口（いまは blink.cmp だけ）は、候補の形を詰め替えてからここを通す。
-- 状態の片付け、ユーザー辞書への登録、確定文字列の出力、undo point は main.complete が一括して行う。
-- kana は読み、word は辞書の候補（注釈つきでもよい）、kind は変換の種類（既定は "okurinasi"）
---@param kana string
---@param word string
---@param kind? skkeleton.HenkanType
function M.confirm(kana, word, kind)
  if not M.can_complete() then
    return
  end
  require("skkeleton.main").complete(kana, word, kind)
end

-- 利用者が providers に書いた skkeleton の source の id。書いていなければ nil
---@return string?
local function provider_id()
  local ok, providers = pcall(function()
    return require("blink.cmp.config").sources.providers
  end)
  if not ok or type(providers) ~= "table" then
    return nil
  end
  for id, p in pairs(providers) do
    if type(p) == "table" and p.module == "skkeleton.completion.blink" then
      return id
    end
  end
  return nil
end

-- User skkeleton-handled のたびに呼ばれる。メニューを開く、開き直す、閉じる
function M.refresh()
  local opts = M.options
  if not opts.enabled then
    return hide()
  end
  if not is_pending() then
    return hide()
  end
  local st = require("skkeleton.store").context().state
  if #require("skkeleton.util").chars(st.henkan_feed) < opts.minLength then
    return hide()
  end

  local key = st.henkan_feed .. "\0" .. st.feed
  if key == last_key then
    return
  end
  local blink = get_blink()
  local id = blink and provider_id()
  if not id then
    return
  end
  last_key = key
  -- blink は設定していない状態や、自分の都合で失敗することがある。skkeleton の入力は止めない
  if pcall(blink.show, { providers = { id } }) then
    shown = true
  end
end

-- blink のメニューが出ていて、項目を選んでいれば、その項目で確定する（blink の accept に回す）。
-- 回したら true。upstream の handleCompleteKey に当たる
---@return boolean
function M.accept_selected()
  if not M.options.enabled or not is_pending() then
    return false
  end
  local blink = package.loaded["blink.cmp"]
  if not blink then
    return false
  end
  local visible = false
  if type(blink.is_visible) == "function" then
    visible = blink.is_visible()
  end
  if not visible and type(blink.is_menu_visible) == "function" then
    visible = blink.is_menu_visible()
  end
  if not visible then
    return false
  end
  local item = blink.get_selected_item and blink.get_selected_item()
  if not item then
    return false
  end
  local is_skk = (item.data and item.data.skkeleton == true)
    or (provider_id() ~= nil and item.source_id == provider_id())
  if not is_skk then
    return false
  end
  -- 先頭の項目が最初から選ばれているだけ（preselect）のときは、選んだことにしない
  local ok, list = pcall(require, "blink.cmp.completion.list")
  if ok and list and list.is_explicitly_selected == false then
    return false
  end
  local res = blink.accept and blink.accept()
  return res ~= false
end

return M

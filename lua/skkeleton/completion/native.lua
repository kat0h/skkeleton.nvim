-- skkeleton.nvim: Neovim 組み込み completefunc による補完
local M = {}

---@param findstart 1|0|string
---@param base string
---@return integer|table[]
function M.completefunc(findstart, base)
  local skkeleton = require("skkeleton")
  if findstart == 1 or findstart == "1" then
    if not skkeleton.is_enabled() or skkeleton.get_prefix() == "" then
      return -3
    end
    local pre_edit = skkeleton.get_pre_edit()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    return math.max(0, col - #pre_edit)
  end

  local sort = require("skkeleton.completion.sort")
  local completions = skkeleton.get_completions()
  local sorted = sort.sort_completions(completions, skkeleton.get_completion_ranks())
  local items = {}
  for _, item in ipairs(sorted) do
    local cand = item.word
    local word, annotation = cand:match("^([^;]*);(.*)$")
    word = word or cand
    items[#items + 1] = {
      word = word,
      abbr = word,
      menu = item.kana,
      info = annotation or "",
      icase = 1,
      dup = 1,
      empty = 1,
      user_data = {
        skkeleton = {
          kana = item.kana,
          word = cand,
        },
      },
    }
  end
  return items
end

local setup_done = false

function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  local group = vim.api.nvim_create_augroup("skkeleton-completion-native", { clear = true })
  vim.api.nvim_create_autocmd("CompleteDone", {
    group = group,
    callback = function()
      local completed = vim.v.completed_item
      if not completed or vim.tbl_isempty(completed) then
        return
      end
      local user_data = completed.user_data
      if type(user_data) == "string" and user_data ~= "" then
        local ok, decoded = pcall(vim.json.decode, user_data)
        if ok and type(decoded) == "table" then
          user_data = decoded
        end
      end
      if type(user_data) == "table" and user_data.skkeleton then
        local skk_data = user_data.skkeleton
        if skk_data.kana and skk_data.word then
          local skkeleton = require("skkeleton")
          skkeleton.complete_callback(skk_data.kana, skk_data.word)
          local store = require("skkeleton.store")
          local ctx = store.context()
          local mode_mod = require("skkeleton.mode")
          mode_mod.initialize_state_with_abbrev(ctx, { "converter", "table" })
          ctx.preedit:output("")
          local render = require("skkeleton.render")
          render.clear()
          local popup = require("skkeleton.popup")
          popup.close()
          vim.g["skkeleton#state"] = { phase = ctx.state.type or "", henkanFeed = ctx.state.henkan_feed or "" }
          pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "skkeleton-handled", modeline = false })
          pcall(function()
            require("skkeleton.indicator").move()
          end)
        end
      end
    end,
  })
end

return M

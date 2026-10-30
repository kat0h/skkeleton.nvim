-- Ported from skkeleton (autoload/skkeleton/popup.vim)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
-- 候補一覧の popup。描画のあとに開き、次のキー入力の最初で閉じる。
local options = require("skkeleton.config").options

local M = {}

local ns = vim.api.nvim_create_namespace("skkeleton.popup")

---@type string[]?
local pending
---@type { index: integer, total: integer }?
local pending_meta
---@type integer[]
local windows = {}

local function ensure_highlights()
  vim.api.nvim_set_hl(0, "SkkeletonPopupKey", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "SkkeletonPopupCandidate", { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "SkkeletonPopupAnnotation", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "SkkeletonPopupFooter", { link = "FloatFooter", default = true })
end

-- 次の open で開く候補を覚える
---@param lines string[]
---@param meta? { index: integer, total: integer }
function M.set(lines, meta)
  pending = lines
  pending_meta = meta
end

function M.has_pending()
  return pending ~= nil
end

---@param buf integer
---@param lines string[]
---@param meta? { index: integer, total: integer, annotations?: table<integer, string> }
---@return integer width
local function decorate_buf(buf, lines, meta)
  ensure_highlights()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local ext_annots = meta and meta.annotations or nil

  -- First pass: measure max width of "<key>: <candidate>" before ";"
  local max_left_width = 0
  local parsed = {}
  for i, line in ipairs(lines) do
    local colon_end = line:find(": ", 1, true)
    local key_end = colon_end and (colon_end + 1) or 0
    local semi_start = line:find(";", key_end + 1, true)
    local left_part = semi_start and line:sub(1, semi_start - 1) or line
    local left_w = vim.fn.strdisplaywidth(left_part)
    if left_w > max_left_width then
      max_left_width = left_w
    end
    parsed[i] = {
      line = line,
      key_end = key_end,
      semi_start = semi_start,
      left_w = left_w,
      ext_annot = ext_annots and ext_annots[i] or nil,
    }
  end

  local max_width = 1
  for i, p in ipairs(parsed) do
    local row = i - 1
    local line = p.line
    if p.key_end > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        end_row = row,
        end_col = p.key_end,
        hl_group = "SkkeletonPopupKey",
      })
    end
    if p.semi_start then
      if p.semi_start - 1 > p.key_end then
        vim.api.nvim_buf_set_extmark(buf, ns, row, p.key_end, {
          end_row = row,
          end_col = p.semi_start - 1,
          hl_group = "SkkeletonPopupCandidate",
        })
      end
      local pad = (max_left_width - p.left_w) + 1
      local annot_opts = {
        end_row = row,
        end_col = #line,
        hl_group = "SkkeletonPopupAnnotation",
      }
      if pad > 0 then
        annot_opts.virt_text = { { string.rep(" ", pad), "SkkeletonPopupCandidate" } }
        annot_opts.virt_text_pos = "inline"
      end
      vim.api.nvim_buf_set_extmark(buf, ns, row, p.semi_start - 1, annot_opts)
      local annot_w = vim.fn.strdisplaywidth(line:sub(p.semi_start))
      max_width = math.max(max_width, max_left_width + 1 + annot_w)
    else
      if #line > p.key_end then
        vim.api.nvim_buf_set_extmark(buf, ns, row, p.key_end, {
          end_row = row,
          end_col = #line,
          hl_group = "SkkeletonPopupCandidate",
        })
      end
      if p.ext_annot and p.ext_annot ~= "" then
        local pad = (max_left_width - p.left_w) + 1
        vim.api.nvim_buf_set_extmark(buf, ns, row, #line, {
          virt_text = {
            { string.rep(" ", pad), "SkkeletonPopupCandidate" },
            { p.ext_annot, "SkkeletonPopupAnnotation" },
          },
          virt_text_pos = "inline",
        })
        max_width = math.max(max_width, max_left_width + 1 + vim.fn.strdisplaywidth(p.ext_annot))
      else
        max_width = math.max(max_width, p.left_w)
      end
    end
  end
  return max_width
end

local function open_float(lines, meta, cfg)
  if #lines == 0 then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  local width = decorate_buf(buf, lines, meta)
  local border = options.popupBorder or "none"
  local has_border = border ~= "none" and border ~= ""
  local border_cols = (has_border and border ~= "shadow") and 2 or 0
  local win_cfg = {
    border = border,
    width = width,
    height = #lines,
    style = "minimal",
    focusable = false,
    noautocmd = true,
  }
  if has_border and meta and meta.total and meta.total > 0 then
    local first = (meta.index or 0) + 1
    local last = math.min((meta.index or 0) + #lines, meta.total)
    local footer_text = (" %d-%d/%d "):format(first, last, meta.total)
    win_cfg.width = math.max(win_cfg.width, vim.fn.strdisplaywidth(footer_text) + 2)
    win_cfg.footer = { { footer_text, "SkkeletonPopupFooter" } }
    win_cfg.footer_pos = "right"
  end
  local merged = vim.tbl_extend("force", win_cfg, cfg)
  if merged.relative == "editor" then
    merged.col = math.max(0, math.min(merged.col or 0, vim.o.columns - merged.width - border_cols))
  end
  local win = vim.api.nvim_open_win(buf, false, merged)
  vim.w[win].skkeleton_popup = true
  windows[#windows + 1] = win
end

-- cmdline では画面の下、cmdline のすぐ上に出す
local function open_cmdline(lines, meta)
  if #lines == 0 then
    return
  end
  local border = options.popupBorder or "none"
  local border_rows = (border ~= "none" and border ~= "" and border ~= "shadow") and 2 or 0
  local top = vim.o.lines - math.max(1, vim.o.cmdheight) - #lines - border_rows
  open_float(lines, meta, {
    relative = "editor",
    col = vim.fn.getcmdscreenpos() - 1,
    row = math.max(0, top),
  })
  vim.cmd("redraw")
end

-- 覚えた候補を開く
function M.open()
  local lines = pending
  local meta = pending_meta
  pending = nil
  pending_meta = nil
  if not lines or #lines == 0 then
    return
  end
  M.close()
  if vim.fn.mode() == "c" then
    open_cmdline(lines, meta)
    return
  end
  local border = options.popupBorder or "none"
  local border_rows = (border ~= "none" and border ~= "" and border ~= "shadow") and 2 or 0
  local spos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  -- cmdheight 分は echo area なので、浮動ウィンドウを被せない
  local invert = vim.o.lines - spos.row - vim.o.cmdheight < (#lines + border_rows)
  open_float(lines, meta, {
    relative = "cursor",
    col = 0,
    row = invert and 0 or 1,
    anchor = invert and "SW" or "NW",
  })
end

function M.close()
  pending = nil
  pending_meta = nil
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  windows = {}
end

return M

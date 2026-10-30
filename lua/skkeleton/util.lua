local M = {}

-- 循環する require を避けるための遅延プロキシ。フィールドに触れたときに初めて require する
---@param name string
function M.lazy(name)
  return setmetatable({}, {
    __index = function(_, k)
      return require(name)[k]
    end,
  })
end

-- UTF-8 の文字単位で分ける
---@param s string
---@return string[]
function M.chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = ch
  end
  return out
end

-- 末尾の 1 文字（UTF-8）を落とす
---@param s string
---@return string
function M.drop_last_char(s)
  if s == "" then
    return s
  end
  local i = #s
  while i > 1 and s:byte(i) >= 0x80 and s:byte(i) < 0xc0 do
    i = i - 1
  end
  return s:sub(1, i - 1)
end

-- 末尾の 1 文字（UTF-8）
---@param s string
---@return string
function M.last_char(s)
  return s:sub(#M.drop_last_char(s) + 1)
end

function M.expand_home(path)
  if path:sub(1, 1) == "~" then
    return vim.fn.expand("~") .. path:sub(2)
  end
  return path
end

return M

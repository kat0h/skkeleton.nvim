-- キー表記の正規化（notation.ts、autoload/skkeleton/notation.vim）
local eq = MiniTest.expect.equality
local notation = require("skkeleton.notation")
local T = MiniTest.new_set()

T["normalize"] = function()
  local cases = {
    -- { 入力, 正規化した表記 }
    { "<C-j>", "<nl>" },
    { "<c-j>", "<nl>" },
    { "<NL>", "<nl>" },
    { "<BS>", "<bs>" },
    { "<C-h>", "<bs>" },
    { "<CR>", "<cr>" },
    { "<C-m>", "<cr>" },
    { "<Return>", "<cr>" },
    { "<Esc>", "<esc>" },
    { "<C-[>", "<esc>" },
    { "<Space>", "<space>" },
    { "<Tab>", "<tab>" },
    { "<C-i>", "<tab>" },
    { "<C-g>", "<c-g>" },
    { "<C-G>", "<c-g>" },
    { "<C-q>", "<c-q>" },
    { "<S-Tab>", "<s-tab>" },
    { "<Up>", "<up>" },
    { "<F5>", "<f5>" },
    { "<lt>", "<lt>" },
    { "<Bar>", "<bar>" },
    { "<Bslash>", "<bslash>" },
    -- 1 文字のもの
    { "a", "a" },
    { "A", "A" },
    { "<S-A>", "A" },
    { "<S-a>", "A" },
    { "x", "x" },
    { "X", "X" },
    { ">", ">" },
    { ";", ";" },
    { " ", "<space>" },
    { "<", "<lt>" },
    { "|", "<bar>" },
    { "\\", "<bslash>" },
    { "\n", "<nl>" },
    { "\r", "<cr>" },
    { "\b", "<bs>" },
    { "\27", "<esc>" },
    { "\t", "<tab>" },
    { "\1", "<c-a>" },
    { "\7", "<c-g>" },
    { "\26", "<c-z>" },
  }
  for _, c in ipairs(cases) do
    eq({ c[1], notation.normalize(c[1]) }, { c[1], c[2] })
  end
end

T["to_key"] = function()
  local cases = {
    { "<space>", " " },
    { "<lt>", "<" },
    { "<bar>", "|" },
    { "<bslash>", "\\" },
    { "<nl>", "\n" },
    { "<cr>", "\r" },
    { "<esc>", "\27" },
    { "<tab>", "\t" },
    { "<c-g>", "\7" },
    { "<c-h>", "\b" },
    { "<s-a>", "A" },
    { "<bs>", vim.api.nvim_replace_termcodes("<BS>", true, true, true) },
    { "<up>", vim.api.nvim_replace_termcodes("<Up>", true, true, true) },
    -- 表記でないものはそのまま
    { "a", "a" },
    { "A", "A" },
    { ">", ">" },
    { "あ", "あ" },
    { "<unknown>", "<unknown>" },
  }
  for _, c in ipairs(cases) do
    eq({ c[1], notation.to_key(c[1]) }, { c[1], c[2] })
  end
end

T["from_key"] = function()
  eq(notation.from_key(" "), "<space>")
  eq(notation.from_key("\n"), "<nl>")
  eq(notation.from_key("A"), "A")
  eq(notation.from_key("a"), "a")
  eq(notation.from_key(vim.api.nvim_replace_termcodes("<BS>", true, true, true)), "<bs>")
end

T["to_key and from_key round trip"] = function()
  local names = { "<space>", "<lt>", "<bar>", "<bslash>", "<nl>", "<cr>", "<esc>", "<tab>", "<bs>", "<c-g>", "<up>" }
  for _, n in ipairs(names) do
    eq(notation.from_key(notation.to_key(n)), n)
  end
end

return T

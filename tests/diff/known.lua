-- upstream（denops 版）と意図して変えたところ、または違いが害にならないところ。
-- 差分テストで違いが出ても、ここに当てはまれば除外する。
-- applies(scenario, step_index, a, b, r) は a = Lua 版、b = denops 版のその時点の状態、
-- r は 2 つの実行結果全体（r.a.steps、r.b.steps）を受けて、除外してよいなら true を返す。
-- 理由は docs/ARCHITECTURE.md、LICENSES/README.md も参照
--
-- ここに入れないもの（Lua 版の不具合）:
--   半角カタカナモードの ▽ で q を押すとカタカナで確定する（denops 版はひらがな）: kat0h/skkeleton.nvim#51
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local function same_lines(a, b)
  return vim.deep_equal(a.lines, b.lines)
end

-- popup 以外が同じか
local function same_but_popup(a, b)
  return same_lines(a, b) and vim.deep_equal(a.cursor, b.cursor) and a.mode == b.mode and a.vim == b.vim
end

-- ▽ を除いた行
local function strip_marker(lines)
  local ret = {}
  for i, l in ipairs(lines or {}) do
    ret[i] = l:gsub("▽", "")
  end
  return ret
end

-- 共通の前置きのあとだけを conv したときに la になるか
local function conv_tail(la, lb, conv)
  local ca, cb = vim.fn.split(la, "\\zs"), vim.fn.split(lb, "\\zs")
  local i = 1
  while ca[i] ~= nil and cb[i] ~= nil and ca[i] == cb[i] do
    i = i + 1
  end
  return table.concat(ca, "", 1, i - 1) .. conv(table.concat(cb, "", i)) == la
end

return {
  {
    -- 空の行に <Space> だけを入れた直後に、モードを替えるキー（q、L、<C-q>、<C-j> など）を打つと、
    -- denops 版は入れたはずの空白を消してしまう。Lua 版は空白を残す。打った文字が消えない Lua 版のほうが自然なので合わせない
    id = "leading-space-kept",
    applies = function(_, index, a, b, r)
      local pa, pb = r.a.steps[index - 1], r.b.steps[index - 1]
      return vim.deep_equal(a.lines, { " " })
        and vim.deep_equal(b.lines, { "" })
        and pa ~= nil
        and pb ~= nil
        and vim.deep_equal(pa.lines, { " " })
        and vim.deep_equal(pb.lines, { " " })
    end,
  },
  {
    -- abbrev モード中の <C-q>（q）。Lua 版は何もしない（ctx.mode == "abbrev" で戻る）。
    -- denops 版は入力中の文字を確定し、▽ だけ消えて abbrev モードのまま残る中途半端な状態になる
    id = "abbrev-ignores-kana-toggle",
    applies = function(sc, index, a, b, r)
      local key = r.a.steps[index] and r.a.steps[index].key
      return (key == "<C-q>" or key == "q")
        and a.mode == "abbrev"
        and b.mode == "abbrev"
        and vim.deep_equal(strip_marker(a.lines), b.lines)
    end,
  },
  {
    -- 「n」を打った直後に「>」（接頭辞の印）を打つと、Lua 版は保留中の n を「ん」にしてから > を置く（かん>）。
    -- denops 版は n が消える（か>）。打った文字が落ちる denops 版の挙動は引き継がない（21732b2 で意図して直した）
    id = "prefix-flushes-pending-n",
    applies = function(_, _, a, b)
      if not (a.lines and b.lines and a.lines[1] and b.lines[1]) then
        return false
      end
      return a.lines[1]:gsub("ん>", ">") == b.lines[1] and a.lines[1] ~= b.lines[1]
    end,
  },
  {
    -- カタカナ、半角カタカナモードで、送り仮名の大文字を打った瞬間の ▽ の表示。
    -- denops 版は送り仮名より前の部分をひらがなで出し、Lua 版は converter をかけて出す。確定する文字は同じ
    id = "okuri-start-preedit-converter",
    applies = function(_, _, a, b)
      if not ((a.mode == "kata" or a.mode == "hankata") and a.mode == b.mode and a.lines and b.lines) then
        return false
      end
      local conv = a.mode == "kata" and require("skkeleton.kana.hira_kata").hira_to_kata
        or require("skkeleton.kana.hira_hankata").hira_to_hankata
      -- ▽ より前の確定済みの文字には converter をかけない
      local head, tail = b.lines[1]:match("^(.-▽)(.*)$")
      return head ~= nil and a.lines[1] ~= b.lines[1] and head .. conv(tail) == a.lines[1]
    end,
  },
  {
    -- 候補ポップアップの出入りが 1 キーずれて見える（どちらかの popup の更新が 1 キー遅れる）。
    -- 行、カーソル、モードは同じで、前後どちらかのキーの状態では popup も同じになる
    id = "popup-timing",
    applies = function(_, index, a, b, r)
      if not same_but_popup(a, b) or vim.deep_equal(a.popup, b.popup) then
        return false
      end
      local na, nb = r.a.steps[index + 1], r.b.steps[index + 1]
      return (na ~= nil and vim.deep_equal(na.popup, b.popup)) or (nb ~= nil and vim.deep_equal(nb.popup, a.popup))
    end,
  },
  {
    -- 送り仮名の入力中（▽く*て など）に、打ちかけの n を残したまま <Space> を打つ。
    -- denops 版は <Space> がかなテーブルのエントリなので、n を「ん」にした時点で送り仮名が揃って変換が走り、
    -- そのあと <Space> 自身がもう一度変換を呼んで、辞書登録の欄が 2 回続けて開く（取り消しを 2 回押す）。
    -- Lua 版は <Space> をキーマップで受けるので（#67）、1 回しか開かない。登録の欄が 1 つで済む Lua 版のほうが自然
    id = "okuri-pending-n-space-registers-once",
    -- 差が出るのは、1 回目の取り消しのキーの段階（denops 版は 2 つめの欄に入ったまま）
    applies = function(_, index, a, b, r)
      local cancel, space, pa = r.a.steps[index], r.a.steps[index - 1], r.a.steps[index - 2]
      if not (cancel and cancel.key == "<Esc>(cancel)" and space and space.key == "<Space>" and pa and pa.lines) then
        return false
      end
      local line = pa.lines[pa.cursor[1]] or ""
      return pa.vim == "i"
        and line:find("*", 1, true) ~= nil
        and line:sub(pa.cursor[2], pa.cursor[2]) == "n"
        and a.vim == "i"
        and (b.vim or ""):sub(1, 1) == "c"
    end,
  },
  {
    -- 打ちかけの子音（k、c、x など、かなに届いていないもの）を残したまま <Space> を打つ。
    -- denops 版は <Space> がかなテーブルのエントリなので、揃わない打ちかけを捨てる（▽k が ▽ に戻る）。
    -- Lua 版は <Space> をキーマップで受けるので（#67）、打ちかけをそのまま残す。打った文字が消えない Lua 版のほうが自然
    id = "pending-consonant-kept-on-space",
    applies = function(_, _, a, b)
      if not (a.lines and b.lines and a.cursor and b.cursor and a.mode == b.mode and a.vim == b.vim) then
        return false
      end
      local col = a.cursor[2]
      local line = a.lines[a.cursor[1]] or ""
      local ch = line:sub(col, col)
      if not ch:match("^[a-z]$") or a.cursor[1] ~= b.cursor[1] or a.cursor[2] ~= b.cursor[2] + 1 then
        return false
      end
      local lines = vim.deepcopy(a.lines)
      lines[a.cursor[1]] = line:sub(1, col - 1) .. line:sub(col + 1)
      return vim.deep_equal(lines, b.lines)
    end,
  },
  {
    -- 打ちかけの n のあとの L（全角モード）。denops 版は L を送り仮名の印（henkanPoint）として扱い、
    -- 続く l でモードが外れる（enabled が false になる）。Lua 版は L をキーマップで受けるので（#67）、
    -- n を「ん」にしてから全角モードに入る
    id = "mode-key-after-pending-n",
    applies = function(_, index, a, b, r)
      local step = r.a.steps[index]
      return step ~= nil and step.key == "L" and a.mode == "zenkaku" and vim.deep_equal(a.lines, b.lines)
    end,
  },
  {
    -- カタカナ、半角カタカナモードで ▽ の入力中に <C-g> で取り消したあとの入力。
    -- denops 版は converter を落として、モードはカタカナのままひらがなが出る（q もカタカナに切り替わらない）。
    -- Lua 版は #87 で直したので、カタカナが出て q でひらがなに戻る
    id = "cancel-keeps-converter",
    applies = function(_, index, a, b, r)
      if b.mode ~= "kata" and b.mode ~= "hankata" then
        return false
      end
      local cancelled = false
      for i = math.max(index - 3, 1), index - 1 do
        cancelled = cancelled or r.a.steps[i].key == "<C-g>"
      end
      if not cancelled or a.vim ~= b.vim or not (a.lines and b.lines) then
        return false
      end
      if a.mode ~= b.mode then
        return a.mode == "hira" and vim.deep_equal(a.lines, b.lines)
      end
      local conv = b.mode == "kata" and require("skkeleton.kana.hira_kata").hira_to_kata
        or require("skkeleton.kana.hira_hankata").hira_to_hankata
      return conv_tail(a.lines[1], b.lines[1], conv)
    end,
  },
}

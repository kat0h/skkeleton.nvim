-- 形式検証の PoC: 本物の端末（tmux）の中で TUI の nvim を動かして、キーごとに確かめる。
-- headless の子では、端末に描いたときの見え方（端末のカーソル、画面の文字）はわからないので、
-- tmux の cursor_x / cursor_y と capture-pane を正解にして、spec.lua の性質と画面を比べる。
--
-- 使い方: nvim --headless -u NONE -i NONE -l tests/formal/tui.lua --profile default --keys '#eol,<C-j>,K,K,<Space>,<Esc>'
--   [--random N --length L --seed S]  ランダムなキー列を N 本流す
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")
package.path = root .. "/tests/?.lua;" .. package.path

local spec = require("formal.spec")
local profiles = require("formal.profiles")

local opts = { profile = "default", keys = nil, random = nil, length = 15, seed = 1, verbose = false }
do
  local i = 1
  while i <= #arg do
    local k, v = arg[i], arg[i + 1]
    if k == "--profile" then
      opts.profile, i = v, i + 1
    elseif k == "--keys" then
      opts.keys, i = vim.split(v, ",", { plain = true }), i + 1
    elseif k == "--random" then
      opts.random, i = tonumber(v), i + 1
    elseif k == "--length" then
      opts.length, i = tonumber(v), i + 1
    elseif k == "--seed" then
      opts.seed, i = tonumber(v), i + 1
    elseif k == "--record" then
      -- asciinema の形式（.cast）で、1 キーごとの画面を書き出す。違反があっても最後のキーまで流す
      opts.record, i = v, i + 1
    elseif k == "--flicker" then
      -- 1 キーごとに、端末に出したフレームの数とカーソルの寄り道を数える（#25）
      opts.flicker = true
    elseif k == "--verbose" then
      opts.verbose = true
    end
    i = i + 1
  end
end

local profile = assert(profiles[opts.profile], "unknown profile")
local flick
local mini = os.getenv("MINI_PATH") or (root .. "/.tests/mini.nvim")

local function sh(cmd)
  local r = vim.system(cmd, { text = true }):wait()
  return r.stdout or "", r.code
end

-- skkeleton のキー表記を tmux send-keys の引数にする
local TMUX_KEYS = {
  ["<C-j>"] = "C-j",
  ["<C-g>"] = "C-g",
  ["<C-u>"] = "C-u",
  ["<C-w>"] = "C-w",
  ["<C-q>"] = "C-q",
  ["<Space>"] = "Space",
  ["<CR>"] = "Enter",
  ["<BS>"] = "BSpace",
  ["<Esc>"] = "Escape",
  ["<Left>"] = "Left",
  ["<Right>"] = "Right",
  ["<Tab>"] = "Tab",
  ["<Insert>"] = "IC",
  ["<Home>"] = "Home",
  ["<End>"] = "End",
  ["<PageDown>"] = "NPage",
  ["<Up>"] = "Up",
  ["<Down>"] = "Down",
  ["<S-Left>"] = "S-Left",
  ["<C-[>"] = "C-[",
}

local function tokenize(keys)
  local out = {}
  local i = 1
  while i <= #keys do
    local s, e = keys:find("^<[%w%-\\]+>", i)
    if s then
      out[#out + 1] = keys:sub(s, e)
      i = e + 1
    else
      out[#out + 1] = keys:sub(i, i)
      i = i + 1
    end
  end
  return out
end

local Session = {}
Session.__index = Session

local counter = 0

function Session.new()
  counter = counter + 1
  local name = ("skkformal%d_%d"):format(vim.uv.os_getpid(), counter)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local sock = dir .. "/nvim.sock"
  local f = assert(io.open(dir .. "/dict", "w"))
  f:write(profile.dict)
  f:close()
  local self = setmetatable({ name = name, dir = dir, sock = sock }, Session)
  -- 端末の大きさは headless の子と同じ 80x24
  sh({
    "tmux",
    "new-session",
    "-d",
    "-s",
    name,
    "-x",
    "80",
    "-y",
    "24",
    "env",
    "MINI_PATH=" .. mini,
    "TERM=xterm-256color",
    vim.v.progpath,
    "--listen",
    sock,
    "-u",
    root .. "/tests/minimal_init.lua",
    "-i",
    "NONE",
  })
  for _ = 1, 500 do
    if vim.uv.fs_stat(sock) then
      break
    end
    vim.uv.sleep(10)
  end
  self.chan = vim.fn.sockconnect("pipe", sock, { rpc = true })
  -- ソケットは init.lua を読み終える前にできるので、読み終わるまで待つ
  for _ = 1, 500 do
    local ok, done = pcall(vim.rpcrequest, self.chan, "nvim_exec_lua", "return package.loaded['mini.test'] ~= nil", {})
    if ok and done then
      break
    end
    vim.uv.sleep(10)
  end
  return self
end

function Session:lua(code, args)
  return vim.rpcrequest(self.chan, "nvim_exec_lua", code, args or {})
end

-- 端末への出力をファイルに写す（ちらつきを数えるため）
function Session:start_pipe()
  self.pipe = self.dir .. "/out.raw"
  sh({ "tmux", "pipe-pane", "-o", "-t", self.name, "cat >> " .. vim.fn.shellescape(self.pipe) })
  self.pipe_pos = 0
end

-- 前に読んだところからの出力を返す
function Session:take_output()
  local f = io.open(self.pipe, "rb")
  if not f then
    return ""
  end
  f:seek("set", self.pipe_pos)
  local data = f:read("*a") or ""
  self.pipe_pos = self.pipe_pos + #data
  f:close()
  return data
end

-- 出力を解析する。Neovim の TUI は 1 回の描き直しを同期出力（ESC[?2026h 〜 ESC[?2026l）で囲むので、
-- その組をフレームとして数え、フレームの終わりのカーソル位置を集める。カーソルは絶対位置（CSI H）、
-- 相対の移動（CSI A/B/C/D）、\r・\n、文字の書き出し（表示幅のぶん進む）で動くので、それを追う
local function analyze(data, start_row, start_col)
  local frames, stops = 0, {}
  local row, col = start_row or 1, start_col or 1
  local in_frame, touched = false, false
  local i, n = 1, #data
  while i <= n do
    local c = data:sub(i, i)
    if c == "\27" then
      local s, e, params, final = data:find("^%[([%d;?]*)([%a])", i + 1)
      if s then
        if params == "?2026" and final == "h" then
          in_frame, touched = true, false
        elseif params == "?2026" and final == "l" then
          if in_frame and touched then
            frames = frames + 1
            stops[#stops + 1] = { row, col }
          end
          in_frame = false
        elseif final == "H" or final == "f" then
          local r, cc = params:match("^(%d*);?(%d*)$")
          row, col = tonumber(r) or 1, tonumber(cc) or 1
          touched = true
        elseif final == "A" then
          row, touched = row - (tonumber(params) or 1), true
        elseif final == "B" then
          row, touched = row + (tonumber(params) or 1), true
        elseif final == "C" then
          col, touched = col + (tonumber(params) or 1), true
        elseif final == "D" then
          col, touched = col - (tonumber(params) or 1), true
        end
        i = e + 1
      else
        -- ESC ( B などの 2 文字のもの
        i = i + 2
      end
    elseif c == "\r" then
      col, i = 1, i + 1
    elseif c == "\n" then
      row, i = row + 1, i + 1
    elseif c:byte() < 32 then
      i = i + 1
    else
      -- UTF-8 の 1 文字を書く
      local len = c:byte() >= 240 and 4 or c:byte() >= 224 and 3 or c:byte() >= 192 and 2 or 1
      local ch = data:sub(i, i + len - 1)
      col = col + math.max(1, vim.fn.strdisplaywidth(ch))
      touched = true
      i = i + len
    end
  end
  return frames, stops, row, col
end

function Session:send(key)
  local ctrl = key:match("^<C%-(.)>$")
  if TMUX_KEYS[key] then
    sh({ "tmux", "send-keys", "-t", self.name, TMUX_KEYS[key] })
  elseif ctrl then
    sh({ "tmux", "send-keys", "-t", self.name, "C-" .. ctrl:lower() })
  elseif key:match("^<Cmd>") then
    -- <Cmd> は端末から送れないので、RPC で流す
    self:lua("vim.api.nvim_input(...)", { key })
  else
    sh({ "tmux", "send-keys", "-t", self.name, "-l", key })
  end
end

-- 端末の描画が落ち着くまで待つ（入力が残っておらず、画面とカーソルが 3 回続けて同じ）
function Session:settle()
  local last, same = nil, 0
  for _ = 1, 300 do
    local ok, mode = pcall(vim.rpcrequest, self.chan, "nvim_get_mode")
    local pending = ok and not mode.blocking and self:lua("return vim.fn.getchar(1)") or 0
    local cur = self:cursor_and_screen()
    if pending == 0 and cur == last then
      same = same + 1
      if same >= 3 then
        return ok and mode.blocking
      end
    else
      same = 0
    end
    last = cur
    vim.uv.sleep(15)
  end
end

function Session:cursor_and_screen()
  local c = sh({ "tmux", "display", "-p", "-t", self.name, "#{cursor_x} #{cursor_y}" })
  local screen = sh({ "tmux", "capture-pane", "-p", "-t", self.name })
  return c .. screen
end

-- 端末のカーソル（1 起点の { row, col }）と画面の行
function Session:terminal()
  local c = sh({ "tmux", "display", "-p", "-t", self.name, "#{cursor_x} #{cursor_y}" })
  local x, y = c:match("(%d+) (%d+)")
  local screen = vim.split(sh({ "tmux", "capture-pane", "-p", "-t", self.name }), "\n")
  return { row = tonumber(y) + 1, col = tonumber(x) + 1 }, screen
end

-- 色つきの画面（エスケープシーケンスつき）
function Session:screen_ansi()
  return sh({ "tmux", "capture-pane", "-p", "-e", "-t", self.name })
end

-- asciinema の形式（v2）の記録。画面の下に、押したキーと違反を出す
local Recorder = {}
Recorder.__index = Recorder

-- keys は記録するキー列（初期状態の名前を除く）。何手目かとキー列の全体を画面の下に出す
function Recorder.new(path, keys)
  return setmetatable({ path = path, t = 0, frames = {}, keys = keys or {} }, Recorder)
end

-- キー列の全体。step 番目（1 起点）を反転表示にする。80 桁に収まるよう、今のキーの前後を残す
function Recorder:sequence(step)
  local parts = {}
  for i, k in ipairs(self.keys) do
    parts[i] = i == step and ("\27[7m" .. k .. "\27[0m") or ("\27[2m" .. k .. "\27[0m")
  end
  local lo, hi = 1, #parts
  local function width(a, b)
    local w = 0
    for i = a, b do
      w = w + vim.fn.strdisplaywidth(self.keys[i]) + 1
    end
    return w
  end
  while width(lo, hi) > 74 and hi > lo do
    if step - lo > hi - step then
      lo = lo + 1
    else
      hi = hi - 1
    end
  end
  return (lo > 1 and "… " or "") .. table.concat(vim.list_slice(parts, lo, hi), " ") .. (hi < #parts and " …" or "")
end

function Recorder:frame(sess, label, note, hold, step)
  step = step or 0
  local term = sess:terminal()
  local lines = vim.split(sess:screen_ansi(), "\n")
  while #lines > 24 do
    table.remove(lines)
  end
  local out = { "\27[0m\27[2J\27[H" }
  for i, l in ipairs(lines) do
    out[#out + 1] = ("\27[%d;1H%s\27[0m"):format(i, l)
  end
  -- 25 行目に区切り、26 行目に押したキー、27 行目に違反
  out[#out + 1] = "\27[25;1H\27[0m\27[2m" .. ("─"):rep(80) .. "\27[0m"
  -- 26 行目: 何手目か と 今のキー、27 行目: キー列の全体（今のキーを反転）、28 行目: 違反
  out[#out + 1] = ("\27[26;1H\27[1;97;44m %d/%d \27[0m \27[1m%s\27[0m"):format(step, #self.keys, label)
  if #self.keys > 0 then
    out[#out + 1] = "\27[27;1H " .. self:sequence(step)
  end
  if note and note ~= "" then
    out[#out + 1] = "\27[28;1H\27[1;97;41m ✗ \27[0m " .. note
  end
  out[#out + 1] = ("\27[%d;%dH"):format(term.row, term.col)
  self.frames[#self.frames + 1] = { self.t, table.concat(out) }
  self.t = self.t + (hold or 0.9)
end

function Recorder:write()
  local f = assert(io.open(self.path, "w"))
  f:write(
    vim.json.encode({ version = 2, width = 80, height = 28, timestamp = os.time(), env = { TERM = "xterm-256color" } }),
    "\n"
  )
  for _, fr in ipairs(self.frames) do
    f:write(vim.json.encode({ fr[1], "o", fr[2] }), "\n")
  end
  f:close()
end

function Session:stop()
  pcall(vim.fn.chanclose, self.chan)
  sh({ "tmux", "kill-session", "-t", self.name })
  vim.fn.delete(self.dir, "rf")
end

local SETUP = [[
  local dir, extra, init, plain = ...
  vim.o.textwidth = 78
  for _, k in ipairs({ "K", "q", "Q", "gQ" }) do vim.keymap.set({ "n", "x" }, k, "<Nop>") end
  -- plain: skkeleton を使わない素の nvim（ちらつきの差分を取るため）
  if not plain then
    require("skkeleton").setup(vim.tbl_deep_extend("force", {
      globalDictionaries = { { dir .. "/dict", "utf-8" } },
      userDictionary = dir .. "/user",
      databasePath = dir .. "/db",
      indicator = {},
    }, extra))
    vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
  else
    vim.keymap.set({ "i", "c" }, "<C-j>", "<Nop>")
  end
  _G.formal_events = {}
  for _, name in ipairs({ "skkeleton-enable-post", "skkeleton-disable-post", "skkeleton-mode-changed" }) do
    _G.formal_events[name] = 0
    vim.api.nvim_create_autocmd("User", { pattern = name, callback = function()
      _G.formal_events[name] = _G.formal_events[name] + 1
    end })
  end
  local function sentinel()
    vim.keymap.set("i", "<C-g>", "<Nop>", { buffer = true, desc = "user-sentinel" })
    vim.b.formal_sentinel = true
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, init.lines)
  sentinel()
  vim.cmd("botright new")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "xy" })
  sentinel()
  vim.cmd("wincmd p")
  vim.api.nvim_win_set_cursor(0, init.cursor)
  if init.cmd then vim.cmd(init.cmd) end
  vim.api.nvim_create_autocmd("CmdlineLeave", { pattern = ":", command = "let v:event.abort = v:true" })
]]

local function snapshot(sess)
  return sess:lua([[return require("formal.observe").snapshot()]])
end

-- 端末で見た画面とカーソルを、headless の観測の代わりに入れる
local function with_terminal(s, term, screen)
  s.term = term
  s.term_line = screen[s.screen_row] or ""
  return s
end

-- 端末で確かめる性質: 端末のカーソルは pre-edit の直後にあり、画面の行はバッファに pre-edit を差し込んだもの
local function check_terminal(s)
  if s.vim_mode:sub(1, 1) ~= "i" or s.pending or s.screen_row <= 0 then
    return
  end
  local line = s.lines[s.cursor[1]] or ""
  if line:find("%c") then
    return
  end
  local before = line:sub(1, s.cursor[2])
  local pre = s.preedit_marks[1] and s.preedit_marks[1].text or ""
  -- 折り返す行は 1 段の画面と比べられないので見ない
  if vim.fn.strdisplaywidth(line .. pre) >= s.win_width - s.textoff then
    return
  end
  local col = s.win_pos[2] + s.textoff + vim.fn.strdisplaywidth(before .. pre) + 1
  if s.term.row ~= s.screen_row or s.term.col ~= col then
    return ("端末のカーソル (%d,%d)、期待 (%d,%d)（headless では (%d,%d)）"):format(
      s.term.row,
      s.term.col,
      s.screen_row,
      col,
      s.screen.row,
      s.screen.col
    )
  end
  local want = before .. pre
  if s.term_line:sub(1, #want) ~= want then
    return ("端末の行 %q が %q で始まらない"):format(s.term_line, want)
  end
end

local function run(keys, plain)
  local sess = Session.new()
  local init_name = profile.inits[keys[1]] and keys[1] or nil
  local init = profile.inits[init_name] or profile.inits[vim.tbl_keys(profile.inits)[1]]
  local result = { keys = keys, violations = {} }
  local ok, err = pcall(function()
    sess:lua(SETUP, { sess.dir, profile.config, init, plain or false })
    for _, k in ipairs(tokenize(init.keys)) do
      sess:send(k)
    end
    sess:settle()
    local rec_keys = {}
    for i, k in ipairs(keys) do
      if not (i == 1 and init_name) then
        rec_keys[#rec_keys + 1] = k
      end
    end
    local rec = opts.record and Recorder.new(opts.record, rec_keys)
    if rec then
      rec:frame(sess, "（初期状態）", nil, 1.5, 0)
    end
    local base = snapshot(sess)
    local prev = base
    local hist = {}
    spec.observe(hist, nil, base)
    if opts.flicker then
      sess:start_pipe()
      result.flicker = {}
      local t0 = sess:terminal()
      sess.cur_row, sess.cur_col = t0.row, t0.col
    end
    for i, key in ipairs(keys) do
      if not (i == 1 and init_name) then
        if opts.flicker then
          sess:take_output()
        end
        local real = profiles.aliases and profiles.aliases[key] or key
        if real:match("^<Cmd>") then
          sess:send(real)
        else
          for _, k in ipairs(tokenize(real)) do
            sess:send(k)
          end
        end
        if sess:settle() then
          result.steps = i
          result.blocked = true
          return
        end
        local term, screen = sess:terminal()
        local s = with_terminal(snapshot(sess), term, screen)
        if opts.flicker then
          -- フレームの数と、最後の位置と違うところでカーソルを出したフレーム（寄り道）
          local frames, stops, lr, lc = analyze(sess:take_output(), sess.cur_row, sess.cur_col)
          sess.cur_row, sess.cur_col = term.row, term.col
          -- まねで追った最後の位置が本物のカーソルと合わないときは、まねが外れているので数えない
          local reliable = lr == term.row and lc == term.col
          local detours = {}
          for _, st in ipairs(stops) do
            if st[1] ~= term.row or st[2] ~= term.col then
              detours[#detours + 1] = ("%d,%d"):format(st[1], st[2])
            end
          end
          if not reliable then
            detours = {}
          end
          result.flicker[#result.flicker + 1] =
            { key = key, frames = frames, detours = detours, mode = s.vim_mode, reliable = reliable }
        end
        if opts.verbose then
          print(
            ("%-10s mode=%s pre-edit=%q 端末=%d,%d 行=%q"):format(
              key,
              s.vim_mode,
              s.ctx_text,
              term.row,
              term.col,
              s.term_line
            )
          )
        end
        local msg = check_terminal(s)
        if msg then
          result.violations[#result.violations + 1] = { name = "terminal: 端末のカーソルと画面", msg = msg }
        end
        for name, f in vim.spairs(spec.state) do
          local okf, m = pcall(f, s, base)
          if not okf or m then
            result.violations[#result.violations + 1] = { name = name, msg = tostring(m) }
          end
        end
        for name, f in vim.spairs(spec.action) do
          local okf, m = pcall(f, prev, key, s, hist)
          if not okf or m then
            result.violations[#result.violations + 1] = { name = name, msg = tostring(m) }
          end
        end
        spec.observe(hist, prev, s)
        prev = s
        if rec then
          local note = #result.violations > 0
              and table.concat(
                vim.tbl_map(function(v)
                  return v.msg
                end, result.violations),
                " / "
              )
            or nil
          if note and vim.fn.strdisplaywidth(note) > 74 then
            note = vim.fn.strcharpart(note, 0, 36) .. "…"
          end
          -- 普通のコマは 1.5 秒、違反が出たコマは 3 秒（最後のコマは agg の --last-frame-duration で 5 秒）
          rec:frame(sess, key, note, note and 3 or 1.5, init_name and i - 1 or i)
          result.violations = {}
        elseif #result.violations > 0 and not opts.flicker then
          result.steps = i
          return
        end
      end
    end
    if rec then
      rec:write()
    end
  end)
  if not ok then
    result.violations[#result.violations + 1] = { name = "error", msg = tostring(err) }
  end
  if opts.flicker and os.getenv("FORMAL_KEEP_RAW") then
    vim.fn.writefile(vim.fn.readfile(sess.pipe, "b"), os.getenv("FORMAL_KEEP_RAW"), "b")
  end
  sess:stop()
  return result
end

local function report(r)
  local prefix = vim.list_slice(r.keys, 1, r.steps or #r.keys)
  for _, v in ipairs(r.violations) do
    local known = spec.is_known(v.name, prefix, v.msg)
    print(("%s %s: %s\n    %s"):format(known and "△" or "✗", table.concat(prefix, " "), v.name, v.msg))
  end
end

local failed = false
if opts.keys then
  opts.verbose = true
  local r = run(opts.keys)
  report(r)
  if opts.flicker then
    local saved = opts.verbose
    opts.verbose = false
    local b = run(opts.keys, true).flicker or {}
    opts.verbose = saved
    for j, f in ipairs(r.flicker or {}) do
      if b[j] and #b[j].detours > 0 then
        f.base = true
      end
      f.base_frames = b[j] and b[j].frames
    end
  end
  for _, f in ipairs(r.flicker or {}) do
    print(
      ("  フレーム %2d（素 %s）  寄り道 %s  %s (%s)%s"):format(
        f.frames,
        tostring(f.base_frames),
        #f.detours > 0 and table.concat(f.detours, " ") or "-",
        f.key,
        f.mode,
        (f.reliable and "" or "  [まねが外れた]") .. (f.base and "  [素の nvim でも]" or "")
      )
    )
  end
  failed = #r.violations > 0
else
  math.randomseed(opts.seed)
  local names = vim.tbl_keys(profile.inits)
  table.sort(names)
  local seen = {}
  flick = {}
  for n = 1, opts.random or 20 do
    local ks = { names[math.random(#names)] }
    for _ = 1, opts.length do
      ks[#ks + 1] = profile.alphabet[math.random(#profile.alphabet)]
    end
    local r = run(ks)
    -- 素の nvim でも同じステップで寄り道するもの（Neovim 本来の描き方）は除く
    local base_flick = opts.flicker and (run(ks, true).flicker or {}) or {}
    for j, f in ipairs(r.flicker or {}) do
      local b = base_flick[j]
      if b and #b.detours > 0 then
        f.detours = {}
      end
    end
    -- ちらつきの候補: 1 つのキーの操作（複数のキーのまとまりでないもの）で、最後と違う位置でフレームが終わった
    for j, f in ipairs(r.flicker or {}) do
      local single = #tokenize(profiles.expand(f.key)) == 1 or f.key:match("^<Cmd>") or profiles.aliases[f.key]
      if single and #f.detours > 0 then
        local prev = (r.flicker[j - 1] or {}).mode or "?"
        local k = ("%s（%s → %s）"):format(f.key, prev, f.mode)
        flick[k] = flick[k] or { count = 0, example = vim.list_slice(r.keys, 1, j + 1), detours = f.detours }
        flick[k].count = flick[k].count + 1
      end
    end
    for _, v in ipairs(r.violations) do
      if not seen[v.name] then
        seen[v.name] = true
        report({ keys = r.keys, steps = r.steps, violations = { v } })
        failed = failed or not spec.is_known(v.name, vim.list_slice(r.keys, 1, r.steps or #r.keys), v.msg)
      end
    end
    if n % 10 == 0 then
      print(("%d 本"):format(n))
    end
  end
end
if flick and next(flick) then
  print("\nちらつきの候補（1 つのキーで、最後と違う位置でフレームが終わった）:")
  local list = {}
  for k, v in pairs(flick) do
    list[#list + 1] = { k = k, v = v }
  end
  table.sort(list, function(a, b)
    return a.v.count > b.v.count
  end)
  for _, e in ipairs(list) do
    print(
      ("  %3d 回  %s  寄り道 %s  例: %s"):format(
        e.v.count,
        e.k,
        table.concat(e.v.detours, " "),
        table.concat(e.v.example, " ")
      )
    )
  end
end
vim.cmd(failed and "cquit 1" or "qall!")

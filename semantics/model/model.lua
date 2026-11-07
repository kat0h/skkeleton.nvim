-- insert / normal / visual / replace の状態機械のモデル（#184、親は #179）
--
-- 今の振る舞いだけを書く。望ましい振る舞いは決めない。
-- このファイルがモデルの唯一のデータ源で、model_check.lua はここだけを読む。
--
-- 形:
--   状態クラス: M.states[name] = { class, layer, vim_mode, enabled, phase, reading, preedit,
--                                 transient, reachable, observed, label, refs }
--   イベント:   M.events[name] = { kind, keys, modes, refs, notes }
--   遷移:       { id, from, event, guard, effects, to, status, refs, observed, notes }
--   性質:       M.properties[i] = { id, kind, title, decided, why }
--   作者の判断: M.decisions[i] = { id, title, decision, reflected_in }
--
-- 用語は semantics/GLOSSARY.md に合わせる。作者の判断は M.decisions に、
-- このモデルでの反映先と一緒に書く。
--
-- 遷移の notes は説明のための欄で、ツール（model_check.lua・SPIN・コード生成）は読まない。
-- 根拠は refs（ファイル:行、issue、棚卸しの節）と observed（M.observations の id）に書く。
--
-- guard は 等号・in・not だけで書く（SPIN とコード生成に使うため）。
--   guard = { { "config.keepState", "=", true } }
--   guard = { { "reading", "in", { "point", "henkan" } }, { "not", { "enabled", "=", false } } }
-- 変数は config.<名前>（M.config の値）か、状態クラスの事実（M.states[from] の項目）だけ。
-- guard が空か nil なら、いつでも成り立つ。
--
-- effects は GLOSSARY の語彙だけを使う。語彙に無い効果は notes に書く。
--
-- status:
--   ok        モデルが今の振る舞いに合っている（コード読解か観測で確かめた）
--   gap       今の振る舞いが性質を破っている（M.known に issue を書く）
--   unknown   まだ確かめていない（コード読解だけ、または未観測）
--   impossible 起こり得ない（BFS で到達しないことを確かめる対象）
--
-- observed: 根拠の観測。M.observations（04 の観測）か M.probes（06 の観測）の id を書く。
--   空なら未観測。その遷移を通った観測だけを書く（model_check が再生の経路で確かめる）。
--
-- 観測の取り方:
--   子の nvim（tests/helpers.lua の e2e_set、一時ディレクトリの辞書、HISTFILE=/dev/null）に、
--   1 つの遷移を 1 回の入力として流し、落ち着いてから observe.classify と同じ見方でクラスを読んだ。
--   06 の観測は M.probes にある（semantics/compare/probe.lua が取り、gen_probes.lua が作る）。
--   <C-r>a のように途中で入力待ちになるキーは、まとめて 1 回で流す（分けて流すと観測が崩れる）。
--   この観測は 04 の作業中だけ使った使い捨てのスクリプトで取った。コマンドは
--   model_check.lua の「観測の再生」で、キー列からモデルの経路をたどって確かめられる。
--
-- 使い方:
--   nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua
--   nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua --verbose

local M = {}

M.issue = 184
M.parent = 179
M.scope = "insert / normal / visual / replace（Vim のモード i / n / v・s / R）"
M.sources = {
  "semantics/GLOSSARY.md",
  "semantics/inventory/keys.md（#181）",
  "semantics/inventory/events.md（#182）",
  "semantics/issues.md（#183）",
  "lua/skkeleton/map.lua、keymap.lua、guard.lua、cleanup.lua、function/",
  "状態遷移図の下書き（作者の手元の data.js。18 状態・49 遷移）",
}

-- 設定。guard から config.<名前> で引く。model_check の --config で上書きできる
M.config = {
  keepState = false,
}

-- 解析の開始状態。BFS はここから広げる
M.initial = { "N_OFF" }

-- 状態クラス
--
-- class は人が読む状態クラス。観測（semantics/explore/observe.lua の classify）が
-- 返す名前と違うときは notes に書く。
-- 内部で分けた状態（NI_POINT など）は、class にまとめ先を書く。
-- aspect は抱えている相（direct / point / select）。NI / V_PRE / P_PROMPT で使う。
-- reading は、その状態が抱えている読み。none / romaji / point / henkan / any。
--   any は「入り方で変わる」の意味で、性質の検査では読みがあるものとして扱う。
M.states = {
  I_OFF = {
    class = "I_OFF",
    layer = "Vim のモードが i、skkeleton は無効",
    vim_mode = "i",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "insert（無効）",
    refs = { "function/disable.lua", "main.lua:129-139", "#38", "#152" },
    notes = "I_DIRECT は有効な insert なので、無効な insert を分けた（作者の判断 1）。",
  },
  I_DIRECT = {
    class = "I_DIRECT",
    layer = "Vim のモードが i、direct（▽ も打ちかけも無い）",
    vim_mode = "i",
    enabled = true,
    phase = "input:direct",
    reading = "none",
    preedit = "none",
    label = "direct",
    refs = { "semantics/inventory/events.md", "GLOSSARY.md" },
  },
  I_ROMAJI = {
    class = "I_ROMAJI",
    layer = "Vim のモードが i、direct でローマ字の打ちかけ（state.feed）がある",
    vim_mode = "i",
    enabled = true,
    phase = "input:direct",
    reading = "romaji",
    preedit = "romaji",
    label = "direct（打ちかけ）",
    refs = { "state.lua", "semantics/issues.md #41 #42" },
    notes = "ローマ字の打ちかけ（state.feed）がある状態。作者の判断 6 で I_PENDING から改名した。"
      .. "pending は render.is_pending() の意味だけに使う。",
  },
  I_POINT = {
    class = "I_POINT",
    layer = "Vim のモードが i、▽ / ▽*（okurinasi / okuriari）",
    vim_mode = "i",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "point",
    preedit = "point",
    label = "▽ / ▽*",
    refs = { "keymap.lua:23-56", "function/input.lua" },
    notes = "▽ と ▽* はまとめた。今の観測では同じ遷移になり、分ける根拠が無い（作者の判断 7）。",
  },
  I_SELECT = {
    class = "I_SELECT",
    layer = "Vim のモードが i、▼（henkan）",
    vim_mode = "i",
    enabled = true,
    phase = "henkan",
    reading = "henkan",
    preedit = "henkan",
    label = "▼",
    refs = { "function/henkan.lua" },
  },
  I_ESCAPE = {
    class = "I_ESCAPE",
    layer = "state.type が escape。マップされた <Esc> のあと、ModeChanged か SafeState の片付けまで",
    vim_mode = "i",
    phase = "escape",
    enabled = false,
    reading = "none",
    preedit = "none",
    transient = true,
    reachable = true,
    label = "escape（片付け待ち）",
    refs = { "function/disable.lua:21-27", "cleanup.lua:218-221" },
    notes = "遷移の途中だけの状態。キーを打ったあとの観測には出てこない（observed = false）。",
  },
  NI_DIRECT = {
    class = "NI",
    aspect = "direct",
    layer = "Vim のモードが niI。読みは無い（direct から <C-o>）",
    vim_mode = "ni",
    enabled = true,
    phase = "input:direct",
    reading = "none",
    preedit = "none",
    label = "insert-normal（direct から）",
    refs = { "cleanup.lua:185,215-217", "#117" },
    notes = "人が読むクラスは NI の 1 つで、相（direct）を aspect に持つ（作者の判断 4）。",
  },
  NI_POINT = {
    class = "NI",
    aspect = "point",
    layer = "Vim のモードが niI。▽ を抱えたまま",
    vim_mode = "ni",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "point",
    preedit = "point",
    label = "insert-normal（▽ から）",
    refs = { "cleanup.lua:185,215-217", "#117" },
    notes = "人が読むクラスは NI（point）の 1 つ（作者の判断 4）。",
  },
  NI_SELECT = {
    class = "NI",
    aspect = "select",
    layer = "Vim のモードが niI。▼ を抱えたまま",
    vim_mode = "ni",
    enabled = true,
    phase = "henkan",
    reading = "henkan",
    preedit = "henkan",
    label = "insert-normal（▼ から）",
    refs = { "cleanup.lua:185,215-217", "#117" },
    notes = "人が読むクラスは NI（select）の 1 つ（作者の判断 4）。",
  },
  IC = {
    class = "IC",
    layer = "Vim のモードが ic（組み込み補完のメニュー）",
    vim_mode = "ic",
    enabled = true,
    phase = "input:direct",
    reading = "none",
    preedit = "none",
    label = "completion",
    refs = { "#18", "#19", "#190" },
    notes = "補完の中の動きは #190（07d）。ここでは入口と出口の境界だけを書く。",
  },
  N_OFF = {
    class = "N_OFF",
    layer = "Vim のモードが n / v / s / o、skkeleton は無効。keepState の one-shot 待ちもここ",
    vim_mode = "n|v|s|o",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "normal（無効）",
    refs = { "host.lua:235-244", "#152" },
    notes = "keepState の one-shot 待ちはクラスを分けず、遷移の guard（config.keepState）で表す（作者の判断 3）。",
  },
  N_WAIT = {
    class = "N_WAIT",
    layer = "Vim のモードが n、SafeState の one-shot を待っている",
    vim_mode = "n",
    enabled = true,
    phase = "input",
    reading = "any",
    preedit = "any",
    transient = true,
    reachable = true,
    label = "normal（確定待ち）",
    refs = { "cleanup.lua:225-248", "#70", "#142" },
    notes = "遷移の途中だけの状態。観測は SafeState のあとの N_OFF になる。",
  },
  V_IDLE = {
    class = "V_IDLE",
    layer = "Vim のモードが v / s、skkeleton は有効で pre-edit は無い（<C-o>v を direct から）",
    vim_mode = "v|s",
    enabled = true,
    phase = "input:direct",
    reading = "none",
    preedit = "none",
    label = "visual（pre-edit 無し・有効）",
    refs = { "probe:C-o-v-direct" },
    notes = "visual で有効のまま pre-edit が無い状態。N_OFF（無効）とは戻ったあとの結果が違うので分けた（作者の判断 2）。",
  },
  V_PRE_POINT = {
    class = "V_PRE",
    aspect = "point",
    layer = "Vim のモードが v / s、skkeleton は有効で ▽ が描かれたまま",
    vim_mode = "v|s",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "point",
    preedit = "point",
    label = "visual（▽ 付き）",
    refs = { "cleanup.lua:179-190" },
    notes = "V_PRE は <C-o>v で visual / select に入ったあと、pre-edit が描かれたまま残り続ける状態（作者の判断 10）。"
      .. "人が読むクラスは V_PRE（point）の 1 つで、相を aspect に持つ（作者の判断 4）。"
      .. "マウスのドラッグで ModeChanged の確定より前に一瞬残るもの（events.md O18）は、状態ではなく遷移の途中として扱う。",
  },
  V_PRE_SELECT = {
    class = "V_PRE",
    aspect = "select",
    layer = "Vim のモードが v / s、skkeleton は有効で ▼ が描かれたまま",
    vim_mode = "v|s",
    enabled = true,
    phase = "henkan",
    reading = "henkan",
    preedit = "henkan",
    label = "visual（▼ 付き）",
    refs = { "cleanup.lua:179-190" },
    notes = "V_PRE は <C-o>v で visual / select に入ったあと、pre-edit が描かれたまま残り続ける状態（作者の判断 10）。"
      .. "人が読むクラスは V_PRE（select）の 1 つで、相を aspect に持つ（作者の判断 4）。",
  },
  R_MID = {
    class = "R_OFF",
    layer = "i と R の移り変わりの途中（ModeChanged の規則 2）",
    vim_mode = "R",
    enabled = true,
    phase = "input",
    reading = "none",
    preedit = "none",
    transient = true,
    reachable = "unknown",
    label = "replace（移り変わりの途中）",
    refs = { "cleanup.lua:183,207-214", "#29", "#156" },
    notes = "観測のクラスにはしない。キーを打ったあとの観測には出てこない遷移の途中の状態（transient）としてだけ残す（作者の判断 8）。",
  },
  R_OFF = {
    class = "R_OFF",
    layer = "Vim のモードが R、skkeleton は無効",
    vim_mode = "R",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "replace（無効）",
    refs = { "#29", "#38", "#156" },
  },
  P_PROMPT_POINT = {
    class = "P_PROMPT",
    aspect = "point",
    layer = "辞書登録の input() の中（cmdtype は @）。外側の ▽ は凍結して残る",
    vim_mode = "c",
    enabled = true,
    phase = "prompt",
    reading = "point",
    preedit = "frozen",
    label = "辞書登録プロンプト（▽ から）",
    refs = { "host.lua:175-213", "#144" },
    notes = "人が読むクラスは P_PROMPT（point）の 1 つで、相を aspect に持つ（作者の判断 4）。"
      .. "プロンプトの中は #189（07c）。ここでは入口と出口の境界だけを書く。",
  },
  P_PROMPT_SELECT = {
    class = "P_PROMPT",
    aspect = "select",
    layer = "辞書登録の input() の中（cmdtype は @）。外側の ▼ は凍結して残る",
    vim_mode = "c",
    enabled = true,
    phase = "prompt",
    reading = "henkan",
    preedit = "frozen",
    label = "辞書登録プロンプト（▼ から）",
    refs = { "host.lua:175-213", "#144" },
    notes = "人が読むクラスは P_PROMPT（select）の 1 つで、相を aspect に持つ（作者の判断 4）。",
  },
}

-- イベント
--
-- kind: key（キー）/ autocmd（Vim のイベント）/ api（skkeleton の関数）/ input（キー以外の入力）/
--       internal（キーの処理の途中で走る片付け）
-- keys: 棚卸し（#181）の表記。イベントが 1 つのキーでないとき（<C-o>v など）はまとめた表記を書く。
-- modes: このモデルで扱う Vim のモード。c / t は別のタスク。
M.events = {
  enable = {
    kind = "api",
    keys = { "<Plug>(skkeleton-enable)", "skkeleton.enable()" },
    modes = { "i", "n" },
    refs = { "main.lua:101-125", "plugin/skkeleton.lua:20-24", "events.md O15" },
  },
  disable = {
    kind = "api",
    keys = { "<Plug>(skkeleton-disable)", "skkeleton.disable()" },
    modes = { "i" },
    refs = { "main.lua:129-139", "function/disable.lua:13-18", "events.md O15" },
  },
  toggle = {
    kind = "api",
    keys = { "<Plug>(skkeleton-toggle)", "skkeleton.toggle()" },
    modes = { "i", "n" },
    refs = { "main.lua:169-175", "events.md O15" },
  },
  char = {
    kind = "key",
    keys = {
      "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "m", "n", "o", "p", "r", "s",
      "t", "u", "v", "w", "x", "y", "z",
      "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
      "!", "\"", "#", "$", "%", "&", "'", "(", ")", ",", ".", ":", "]", "@", "[", "-",
      "^", "\\", "?", "_", "+", "*", "}", "`", "{", "=", "~", "<lt>", "<Bar>",
    },
    modes = { "i" },
    refs = { "keymap.lua:23-56,64-88", "function/input.lua:85-120", "keys.md §1,§3" },
    notes = "l q ; / L > X は、それぞれ別のイベントにした（関数が割り当てられているため）。",
  },
  char_shift = {
    kind = "key",
    keys = {
      "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "M", "N", "O", "P", "Q", "R",
      "S", "T", "U", "V", "W", "Y", "Z",
    },
    modes = { "i" },
    refs = { "function/input.lua:85-120", "keys.md §1" },
    notes = "シフト付きの文字。direct では ▽ を開始する（かなテーブルに単独の項目が無いとき）。",
  },
  key_x = {
    kind = "key",
    keys = { "x" },
    modes = { "i" },
    refs = { "keymap.lua:51", "function/henkan.lua:116-133" },
    notes = "input では文字。henkan では候補を 1 つ前へ（henkanBackward）。",
  },
  key_X = {
    kind = "key",
    keys = { "X" },
    modes = { "i" },
    refs = { "keymap.lua:52", "function/common.lua:89-", "keys.md §3" },
    notes = "input では文字（▽ を開始）。henkan では候補の削除（purgeCandidate）。",
  },
  key_L = {
    kind = "key",
    keys = { "L" },
    modes = { "i" },
    refs = { "keymap.lua:41", "function/mode.lua" },
  },
  key_l = {
    kind = "key",
    keys = { "l" },
    modes = { "i" },
    refs = { "keymap.lua:37", "#67", "#87" },
    notes = "既定のかなテーブルのときだけ disable を呼ぶ。",
  },
  key_q = {
    kind = "key",
    keys = { "q" },
    modes = { "i" },
    refs = { "keymap.lua:38", "function/mode.lua" },
  },
  key_semicolon = {
    kind = "key",
    keys = { ";" },
    modes = { "i" },
    refs = { "keymap.lua:39", "function/input.lua:147-" },
  },
  key_slash = {
    kind = "key",
    keys = { "/" },
    modes = { "i" },
    refs = { "keymap.lua:40", "function/mode.lua" },
  },
  key_gt = {
    kind = "key",
    keys = { ">" },
    modes = { "i" },
    refs = { "keymap.lua:34,53", "function/input.lua:206-223" },
    notes = "input では接頭辞・接尾辞、henkan では送り仮名（suffix）。",
  },
  key_cq = {
    kind = "key",
    keys = { "<C-q>" },
    modes = { "i" },
    refs = { "keymap.lua:33", "function/mode.lua" },
  },
  bs = {
    kind = "key",
    keys = { "<BS>", "<C-h>" },
    modes = { "i" },
    refs = { "keymap.lua:27,29", "function/input.lua:178-204", "keys.md §1" },
    notes = "<C-h> は <bs> に正規化され、keymap.lua:29 の <c-h> の行は引かれない。",
  },
  cr = {
    kind = "key",
    keys = { "<CR>" },
    modes = { "i" },
    refs = { "keymap.lua:30,48", "function/common.lua:59-68" },
  },
  space = {
    kind = "key",
    keys = { "<Space>" },
    modes = { "i" },
    refs = { "keymap.lua:35,50", "function/henkan.lua:21-56,90-113" },
  },
  nl = {
    kind = "key",
    keys = { "<C-j>" },
    modes = { "i" },
    refs = { "keymap.lua:32,49", "function/common.lua:18-45" },
  },
  cg = {
    kind = "key",
    keys = { "<C-g>" },
    modes = { "i" },
    refs = { "keymap.lua:28,47", "function/common.lua:71-86", "#87" },
  },
  esc = {
    kind = "key",
    keys = { "<Esc>", "<C-[>" },
    modes = { "i", "n", "v", "R", "ic" },
    refs = { "keymap.lua:31", "function/disable.lua:21-27", "cleanup.lua:192-251", "#86" },
    notes = "insert では keymap の escape。cmdline から visual へ戻るときなどは ModeChanged の規則 5。",
  },
  insert_key = {
    kind = "key",
    keys = { "<Insert>" },
    modes = { "i", "R" },
    refs = { "guard.lua:15-16", "cleanup.lua:183,207-214", "#29", "#38", "#156" },
  },
  normal_R = {
    kind = "key",
    keys = { "R" },
    modes = { "n" },
    refs = { "Vim 本体" },
    notes = "normal の R は置換モードに入る。skk は置換モードでは有効化を拒否する（main.lua:103-106）。",
  },
  ni_R = {
    kind = "key",
    keys = { "R" },
    modes = { "i" },
    refs = { "cleanup.lua:179-190" },
    notes = "niI（<C-o> のあと）で R を 1 キーで打つ。insert からの <C-o>R と同じ移り先。",
  },
  ni_v = {
    kind = "key",
    keys = { "v" },
    modes = { "i" },
    refs = { "cleanup.lua:179-190" },
    notes = "niI（<C-o> のあと）で v を 1 キーで打つ。insert からの <C-o>v と同じ移り先。",
  },
  ctrl_o = {
    kind = "key",
    keys = { "<C-o>" },
    modes = { "i" },
    refs = { "keymap.lua", "cleanup.lua:185,215-217", "#117" },
  },
  ctrl_c = {
    kind = "key",
    keys = { "<C-c>", "<C-\\><C-n>" },
    modes = { "i", "t" },
    refs = { "cleanup.lua:187,225-248", "#70", "#142", "#74" },
  },
  ctrl_r = {
    kind = "key",
    keys = { "<C-r>", "<C-r><C-r>", "<C-r>=", "<C-r>{reg}", "<C-r>a", "<C-r>=1<CR>" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#8", "#12", "#20" },
    notes = "レジスタの中身を入れる・式の結果を入れる。guard は確定しないので、"
      .. "バッファが変わったあとの TextChangedI が読みを捨てる。",
  },
  ctrl_v = {
    kind = "key",
    keys = { "<C-v>", "<C-v>065" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#12" },
  },
  ctrl_k = {
    kind = "key",
    keys = { "<C-k>", "<C-k>a:" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#12" },
  },
  ctrl_t = {
    kind = "key",
    keys = { "<C-t>" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §5,§6" },
  },
  tab = {
    kind = "key",
    keys = { "<Tab>" },
    modes = { "i" },
    refs = { "guard.lua:89-96", "keys.md §5,§6", "#12" },
    notes = "<S-Tab> は termcap なので guard が確定する。guard_special のほう。",
  },
  ctrl_w = {
    kind = "key",
    keys = { "<C-w>" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#8", "#12" },
  },
  ctrl_u = {
    kind = "key",
    keys = { "<C-u>" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#8", "#12" },
  },
  ctrl_a = {
    kind = "key",
    keys = { "<C-a>" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §6", "NOTES.md 未考慮 7" },
  },
  ctrl_at = {
    kind = "key",
    keys = { "<C-@>" },
    modes = { "i" },
    refs = { "guard.lua:62-65", "keys.md §4,§6", "#56" },
  },
  completion_open = {
    kind = "key",
    keys = { "<C-n>", "<C-p>", "<C-x>", "<C-x><C-n>" },
    modes = { "i" },
    refs = { "guard.lua:78-80", "keys.md §5", "#18", "#19", "#45", "#190" },
  },
  completion_next = {
    kind = "key",
    keys = { "<C-n>", "<C-p>" },
    modes = { "ic" },
    refs = { "keys.md §5", "#190" },
  },
  completion_accept = {
    kind = "key",
    keys = { "<C-y>", "<C-e>" },
    modes = { "i", "ic" },
    refs = { "keys.md §6", "#19", "#190" },
  },
  ctrl_o_colon = {
    kind = "key",
    keys = { "<C-o>:", "<C-o>:<Esc>", "<C-o>:<CR>" },
    modes = { "i" },
    refs = { "cleanup.lua:254-266", "#86" },
    notes = "cmdline の中は #187（07a）。ここでは戻ったときの insert の状態だけを書く。",
  },
  ctrl_o_v = {
    kind = "key",
    keys = { "<C-o>v", "<C-o>V", "<C-o><C-v>" },
    modes = { "i" },
    refs = { "cleanup.lua:179-190" },
  },
  ctrl_o_R = {
    kind = "key",
    keys = { "<C-o>R" },
    modes = { "i" },
    refs = { "cleanup.lua:179-190" },
  },
  guard_special = {
    kind = "key",
    keys = {
      "<S-Up>", "<S-Down>", "<S-Left>", "<S-Right>", "<C-Left>", "<C-Right>",
      "<S-F1>", "<S-F2>", "<S-F3>", "<S-F4>", "<S-F5>", "<S-F6>", "<S-F7>", "<S-F8>",
      "<S-F9>", "<S-F10>", "<S-F11>", "<S-F12>",
      "<Left>", "<Right>", "<Up>", "<Down>", "<Home>", "<End>", "<PageUp>", "<PageDown>",
      "<Del>", "<S-Tab>", "<F5>", "<C-.>", "<S-CR>",
    },
    modes = { "i" },
    refs = { "guard.lua:22-37,50-85", "keys.md §4", "#56" },
    notes = "guard が pre-edit を確定してから、キーを流し直す。",
  },
  mouse_click = {
    kind = "input",
    keys = { "<LeftMouse>", "<RightMouse>", "<DragRight>" },
    modes = { "i" },
    refs = { "keys.md §5", "#56" },
  },
  mouse_select = {
    kind = "input",
    keys = { "<2-LeftMouse>", "<3-LeftMouse>" },
    modes = { "i" },
    refs = { "cleanup.lua:179-190", "events.md O10", "events.md O18" },
    notes = "ダブルクリックは 1 回目の押下の CursorMovedI が先に確定する。ドラッグでは ModeChanged の時点で pre-edit が残る（O18）。",
  },
  wheel = {
    kind = "input",
    keys = { "<ScrollWheelUp>", "<ScrollWheelDown>" },
    modes = { "i" },
    refs = { "guard.lua:59-61", "keys.md §5" },
  },
  winleave = {
    kind = "autocmd",
    keys = {},
    modes = { "i", "n", "v", "R" },
    refs = { "cleanup.lua:269-281", "events.md", "#169" },
  },
  bufleave = {
    kind = "autocmd",
    keys = {},
    modes = { "i", "n", "v", "R" },
    refs = { "cleanup.lua:269-281", "events.md", "#169" },
  },
  safestate = {
    kind = "internal",
    keys = {},
    modes = { "n" },
    refs = { "cleanup.lua:225-248", "events.md" },
  },
  cleanup_escape = {
    kind = "internal",
    keys = {},
    modes = { "n" },
    refs = { "cleanup.lua:218-221" },
  },
  modechanged_i_to_R = {
    kind = "internal",
    keys = {},
    modes = { "R" },
    refs = { "cleanup.lua:183,207-214", "#29", "#156" },
  },
  ni_return_keep = {
    kind = "vim",
    keys = { "l", "h", "w", "A", "o", "gI" },
    modes = { "i" },
    refs = { "cleanup.lua:185,215-217", "#117", "#156" },
    notes = "1 コマンドのあと、カーソルもバッファも変わらなかったとき（ずれが無い）。",
  },
  ni_return_commit = {
    kind = "vim",
    keys = { "0", "$", "<Left>", "<Right>" },
    modes = { "i" },
    refs = { "cleanup.lua:120-147,185,215-217", "#117" },
    notes = "カーソルだけがずれたとき。pre-edit の位置に確定する。",
  },
  ni_return_drop = {
    kind = "vim",
    keys = { "x", "dd", "J" },
    modes = { "i" },
    refs = { "cleanup.lua:120-147,185,215-217", "#199" },
    notes = "カーソル以外のずれ（バッファが変わった）。読みは確定せずに捨てる。",
  },
  stale = {
    kind = "autocmd",
    keys = {},
    modes = { "i", "v" },
    refs = { "cleanup.lua:120-165,283-286", "events.md", "#8", "#12", "#61", "#66" },
    notes = "TextChangedI / TextChangedP / CursorMovedI / CompleteDone / on_bytes。",
  },
  paste = {
    kind = "input",
    keys = { "<Paste>" },
    modes = { "i" },
    refs = { "paste.lua:31-69", "#125", "#191" },
  },
  stopinsert = {
    kind = "api",
    keys = { ":stopinsert" },
    modes = { "i" },
    refs = { "cleanup.lua:187,225-248", "#70" },
  },
  insert_enter = {
    kind = "autocmd",
    keys = { "i", "a", "A", "o", "O" },
    modes = { "i" },
    refs = { "host.lua:235-244", "events.md", "#152" },
    notes = "normal から insert へ入る。keepState の one-shot があるときだけ skk を有効にする。",
  },
  register_commit = {
    kind = "key",
    keys = { "<CR>@register" },
    modes = { "c" },
    refs = { "host.lua:125-162,175-213", "events.md O12", "#189" },
  },
  register_cancel = {
    kind = "key",
    -- `@register` は cmdtype の注記。実際に打つのは <Esc> / <C-g>
    keys = { "<C-g>@register", "<Esc>@register", "<Esc>", "<C-g>" },
    modes = { "c" },
    refs = { "host.lua:197-204", "#116", "#189" },
  },
}

-- 遷移
--
-- 同じ (from, event) に複数の遷移があるのは、今の振る舞いが条件で分かれるため。
-- guard で書けない条件（辞書に候補があるか、バッファに文字があるかなど）は notes に書く。
M.transitions = {}

local function add(t)
  t.effects = t.effects or {}
  t.refs = t.refs or {}
  t.observed = t.observed or {}
  t.guard = t.guard or {}
  t.status = t.status or "unknown"
  M.transitions[#M.transitions + 1] = t
end

-- 有効化・無効化
add({
  id = "t.N_OFF.enable",
  from = "N_OFF", event = "enable", to = "I_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "main.lua:101-125" }, observed = { "O-enable" },
  notes = "元のマッピングを退避してから、skkeleton のマッピングを張る。",
})
add({
  id = "t.I_OFF.enable",
  from = "I_OFF", event = "enable", to = "I_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "main.lua:101-125" }, observed = { "O-enable-insert" },
})
add({
  id = "t.N_OFF.toggle",
  from = "N_OFF", event = "toggle", to = "I_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "unknown", refs = { "main.lua:169-175" },
  notes = "events.md O15 は API の観測で、キー列では toggle を再生できない。",
})
-- insert で有効のまま enable を呼ぶ（<Plug>(skkeleton-enable) を押す）
add({
  id = "t.I_DIRECT.enable",
  from = "I_DIRECT", event = "enable", to = "I_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "main.lua:101-125", "06 の観測 P.t.I_DIRECT.enable" },
  notes = "有効なまま enable を呼んでも、direct のまま（06 の観測）。マッピングを張り直す。",
})
add({
  id = "t.I_ROMAJI.enable",
  from = "I_ROMAJI", event = "enable", to = "I_DIRECT",
  effects = { "drop", "save_mapping", "install_mapping", "reset_state", "clear_extmark" },
  status = "gap", refs = { "main.lua:101-125", "#210", "06 の観測 P.t.I_ROMAJI.enable" },
  notes = "変換中に enable を呼ぶと、打ちかけのローマ字が確定せずに消える（#210）。",
})
add({
  id = "t.I_POINT.enable",
  from = "I_POINT", event = "enable", to = "I_DIRECT",
  effects = { "drop", "save_mapping", "install_mapping", "reset_state", "clear_extmark" },
  status = "gap", refs = { "main.lua:101-125", "#210", "06 の観測 P.t.I_POINT.enable" },
  notes = "変換中に enable を呼ぶと、読みが確定せずに消える（#210）。",
})
add({
  id = "t.I_SELECT.enable",
  from = "I_SELECT", event = "enable", to = "I_DIRECT",
  effects = { "drop", "save_mapping", "install_mapping", "reset_state", "clear_extmark" },
  status = "gap", refs = { "main.lua:101-125", "#210", "06 の観測 P.t.I_SELECT.enable" },
  notes = "候補を選んでいる途中に enable を呼ぶと、候補が確定せずに消える（#210）。",
})
add({
  id = "t.I_OFF.toggle",
  from = "I_OFF", event = "toggle", to = "I_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "main.lua:169-175" },
})
add({
  id = "t.I_DIRECT.toggle",
  from = "I_DIRECT", event = "toggle", to = "I_OFF",
  effects = { "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "main.lua:169-175", "function/disable.lua" },
})
add({
  id = "t.I_ROMAJI.toggle",
  from = "I_ROMAJI", event = "toggle", to = "I_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "main.lua:169-175", "function/disable.lua" },
})
add({
  id = "t.I_POINT.toggle",
  from = "I_POINT", event = "toggle", to = "I_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "main.lua:169-175", "function/disable.lua" },
})
add({
  id = "t.I_SELECT.toggle",
  from = "I_SELECT", event = "toggle", to = "I_OFF",
  effects = { "commit_candidate", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "main.lua:169-175", "function/disable.lua" },
})
add({
  id = "t.I_DIRECT.disable",
  from = "I_DIRECT", event = "disable", to = "I_OFF",
  effects = { "restore_mapping", "reset_state", "clear_extmark" },
  status = "unknown", refs = { "main.lua:129-139", "function/disable.lua:13-18" },
  notes = "events.md O15 は API の観測で、キー列では disable を再生できない。",
})
add({
  id = "t.I_ROMAJI.disable",
  from = "I_ROMAJI", event = "disable", to = "I_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "main.lua:129-139", "function/disable.lua:13-18" },
})
add({
  id = "t.I_POINT.disable",
  from = "I_POINT", event = "disable", to = "I_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "unknown", refs = { "main.lua:129-139", "function/disable.lua:13-18" },
  notes = "events.md O15 は API の観測で、キー列では disable を再生できない。",
})
add({
  id = "t.I_SELECT.disable",
  from = "I_SELECT", event = "disable", to = "I_OFF",
  effects = { "commit_candidate", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "main.lua:129-139", "function/disable.lua:13-18" },
})
add({
  id = "t.NI_POINT.disable",
  from = "NI_POINT", event = "disable", to = "I_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "unknown", refs = { "main.lua:129-139" },
})

-- Escape（キー）と片付け
add({
  id = "t.I_DIRECT.esc",
  from = "I_DIRECT", event = "esc", to = "I_ESCAPE",
  guard = { { "config.keepState", "=", false } },
  effects = { "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "cleanup.lua:218-221" }, observed = { "O-esc-idle" },
})
add({
  id = "t.I_ROMAJI.esc",
  from = "I_ROMAJI", event = "esc", to = "I_ESCAPE",
  guard = { { "config.keepState", "=", false } },
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27" },
})
add({
  id = "t.I_POINT.esc",
  from = "I_POINT", event = "esc", to = "I_ESCAPE",
  guard = { { "config.keepState", "=", false } },
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27" }, observed = { "O-esc" },
})
add({
  id = "t.I_SELECT.esc",
  from = "I_SELECT", event = "esc", to = "I_ESCAPE",
  guard = { { "config.keepState", "=", false } },
  effects = { "commit_candidate", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27" }, observed = { "O-esc-select" },
})
add({
  id = "t.I_DIRECT.esc.keepstate",
  from = "I_DIRECT", event = "esc", to = "N_OFF",
  guard = { { "config.keepState", "=", true } },
  effects = { "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "host.lua:235-244", "#152" },
})
add({
  id = "t.I_ROMAJI.esc.keepstate",
  from = "I_ROMAJI", event = "esc", to = "N_OFF",
  guard = { { "config.keepState", "=", true } },
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "#152" },
})
add({
  id = "t.I_POINT.esc.keepstate",
  from = "I_POINT", event = "esc", to = "N_OFF",
  guard = { { "config.keepState", "=", true } },
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "#152" },
})
add({
  id = "t.I_SELECT.esc.keepstate",
  from = "I_SELECT", event = "esc", to = "N_OFF",
  guard = { { "config.keepState", "=", true } },
  effects = { "commit_candidate", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "#152" },
})
add({
  id = "t.I_ESCAPE.cleanup",
  from = "I_ESCAPE", event = "cleanup_escape", to = "N_OFF",
  effects = { "reset_state" },
  status = "ok", refs = { "cleanup.lua:218-221" },
  notes = "state.type が escape のときの ModeChanged の分岐。pre-edit はすでに無い。",
})
add({
  id = "t.N_OFF.insert_enter.keepstate",
  from = "N_OFF", event = "insert_enter", to = "I_DIRECT",
  guard = { { "config.keepState", "=", true } },
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "host.lua:235-244", "#152" }, observed = { "O152" },
  notes = "buffer ローカルの one-shot InsertEnter。keepState のときは、次に insert へ入ったとき 1 回だけ有効化する。"
    .. "N_KEEP はクラスにせず、この guard で表す（作者の判断 3）。",
})
add({
  id = "t.N_OFF.insert_enter",
  from = "N_OFF", event = "insert_enter", to = "I_OFF",
  guard = { { "config.keepState", "=", false } },
  effects = { "pass_key" },
  status = "ok", refs = { "events.md O1" }, observed = { "O-esc-then-i" },
})
add({
  id = "t.I_OFF.esc",
  from = "I_OFF", event = "esc", to = "N_OFF",
  effects = { "pass_key" },
  status = "unknown", refs = { "Vim 本体" },
  notes = "insert で無効のときの <Esc>。今の観測では、i で入ったあとの <Esc> を取っていない。",
})
add({
  id = "t.R_OFF.esc",
  from = "R_OFF", event = "esc", to = "N_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "Vim 本体" },
})
add({
  id = "t.N_OFF.esc",
  from = "N_OFF", event = "esc", to = "N_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "Vim 本体" },
})
add({
  id = "t.N_OFF.insert_key",
  from = "N_OFF", event = "insert_key", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "Vim 本体", "06 の観測 P.t.N_OFF.insert_key" },
  notes = "normal の <Insert> は insert に入る（置換モードではない）。06 の観測で確かめた。"
    .. "normal の R は normal_R の遷移。",
})
add({
  id = "t.N_OFF.R",
  from = "N_OFF", event = "normal_R", to = "R_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "Vim 本体", "06 の観測 P.t.N_OFF.R" },
  notes = "normal の R は置換モードに入る。skk は無効のまま。",
})
add({
  id = "t.I_OFF.insert_key",
  from = "I_OFF", event = "insert_key", to = "R_OFF",
  effects = { "pass_key" },
  status = "unknown", refs = { "Vim 本体" },
  notes = "O-insert-twice の 2 回目の <Insert> は R_OFF からで、I_OFF からは打っていない。",
})
add({
  id = "t.R_OFF.insert_key",
  from = "R_OFF", event = "insert_key", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "#38" }, observed = { "O-insert-twice" },
})

-- insert から normal へ（<C-c> / :stopinsert / マウスで選択 / WinLeave / BufLeave）
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  local has_reading = from ~= "I_DIRECT"
  -- O-ctrlc は I_SELECT に届かない。P1 の破れ（読みを捨てる）は読みを持つ状態だけ。
  local leave_status = has_reading and "gap" or "unknown"
  add({
    id = "t." .. from .. ".ctrl_c",
    from = from, event = "ctrl_c", to = "N_WAIT",
    effects = {},
    status = "ok", refs = { "cleanup.lua:187,225-248", "#70", "#142" },
    observed = from == "I_POINT" and { "O-ctrlc" } or {},
    notes = "ModeChanged が SafeState の one-shot を作るだけ。確定は safestate の遷移で起きる。",
  })
  add({
    id = "t." .. from .. ".stopinsert",
    from = from, event = "stopinsert", to = "N_OFF",
    effects = has_reading and { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" }
      or { "reset_state", "restore_mapping", "clear_extmark" },
    status = "ok", refs = { "cleanup.lua:187,225-248", "#70" },
  })
  add({
    id = "t." .. from .. ".mouse_select",
    from = from, event = "mouse_select", to = "N_OFF",
    effects = has_reading and { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" }
      or { "reset_state", "restore_mapping", "clear_extmark" },
    status = "unknown", refs = { "cleanup.lua:179-190", "events.md O10", "events.md O18" },
    notes = "i から visual への直接の遷移（マウスで選択）。読みを確定してから無効化する。"
      .. "ドラッグでは ModeChanged の確定より前に一瞬 pre-edit が残る（O18）が、"
      .. "それは遷移の途中なので状態クラスにしない（作者の判断 10）。04 の観測はマウスを使っていない。",
  })
  add({
    id = "t." .. from .. ".winleave",
    from = from, event = "winleave", to = "N_OFF",
    effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
    status = leave_status, refs = { "cleanup.lua:269-281", "#169", "events.md O13" },
    notes = "読みを確定せずに捨てる。upstream は pre-edit が本物の文字なので残る。"
      .. "events.md O13 の観測は WinLeave そのもの（キー列は記録に無い）。",
  })
  add({
    id = "t." .. from .. ".bufleave",
    from = from, event = "bufleave", to = "N_OFF",
    effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
    status = leave_status, refs = { "cleanup.lua:269-281", "#169" },
  })
end
add({
  id = "t.N_WAIT.safestate",
  from = "N_WAIT", event = "safestate", to = "N_OFF",
  effects = { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" },
  status = "ok", refs = { "cleanup.lua:225-248" }, observed = { "O-ctrlc" },
  notes = "状態が escape のときは ModeChanged の分岐で先に片付いている（commit は起きない）。",
})

-- <Insert> による i → R
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".insert_key",
    from = from, event = "insert_key", to = "R_MID",
    effects = from == "I_SELECT" and { "commit_candidate", "clear_extmark" }
      or from ~= "I_DIRECT" and { "commit_reading", "clear_extmark" } or { "clear_extmark" },
    status = from ~= "I_SELECT" and "ok" or "unknown",
    refs = { "cleanup.lua:183,207-214", "#29", "#156" },
    observed = from == "I_POINT" and { "O-insert" } or {},
    notes = "ModeChanged の規則 2。置換モードでは確定した文字の後ろへカーソルを移す。"
      .. "O-insert は ▽ から打っていて、▼ からは打っていない。",
  })
end
add({
  id = "t.R_MID.modechanged",
  from = "R_MID", event = "modechanged_i_to_R", to = "R_OFF",
  effects = { "reset_state", "restore_mapping" },
  status = "ok", refs = { "cleanup.lua:207-214", "#156" }, observed = { "O-insert" },
})

-- <C-o> で insert-normal へ。読みを持ち越す
add({
  id = "t.I_DIRECT.ctrl_o",
  from = "I_DIRECT", event = "ctrl_o", to = "NI_DIRECT",
  effects = { "keep" },
  status = "ok", refs = { "#117" }, observed = {},
})
add({
  id = "t.I_ROMAJI.ctrl_o",
  from = "I_ROMAJI", event = "ctrl_o", to = "NI_POINT",
  effects = { "keep" },
  status = "ok", refs = { "#117", "06 の観測 P.t.I_ROMAJI.ctrl_o" },
  notes = "打ちかけ（▽k）を niI へ持ち越す（06 の観測）。NI_POINT の相は point だが、"
    .. "実際の pre-edit はローマ字の打ちかけ（▽k）。モデルは打ちかけの中身を状態に持っていない。",
})
add({
  id = "t.I_ROMAJI.ctrl_o_R",
  from = "I_ROMAJI", event = "ctrl_o_R", to = "R_OFF",
  effects = { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" },
  status = "ok", refs = { "cleanup.lua:179-190", "06 の観測 P.t.I_ROMAJI.ctrl_o_R" },
  notes = "打ちかけのローマ字をそのまま確定して（k がバッファに入る）無効化する。",
})
add({
  id = "t.I_ROMAJI.ctrl_o_v",
  from = "I_ROMAJI", event = "ctrl_o_v", to = "V_PRE_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "cleanup.lua:179-190", "06 の観測 P.t.I_ROMAJI.ctrl_o_v" },
  notes = "打ちかけ（▽k）を描いたまま visual に入る。相は point だが pre-edit はローマ字。",
})
add({
  id = "t.I_POINT.ctrl_o",
  from = "I_POINT", event = "ctrl_o", to = "NI_POINT",
  effects = { "keep" },
  status = "ok", refs = { "#117" }, observed = { "O-ctrl-o-l" },
})
add({
  id = "t.I_SELECT.ctrl_o",
  from = "I_SELECT", event = "ctrl_o", to = "NI_SELECT",
  effects = { "keep" },
  status = "ok", refs = { "#117" },
})

-- insert-normal から戻る（ModeChanged の規則 3）
for _, from in ipairs({ "NI_DIRECT", "NI_POINT", "NI_SELECT" }) do
  local commit = from == "NI_SELECT" and "commit_candidate" or from == "NI_POINT" and "commit_reading" or nil
  add({
    id = "t." .. from .. ".return_commit",
    from = from, event = "ni_return_commit", to = "I_DIRECT",
    effects = commit and { commit, "reset_state", "render" } or { "reset_state", "render" },
    status = from ~= "NI_SELECT" and "ok" or "unknown",
    refs = { "cleanup.lua:120-147,215-217", "#117" },
    observed = from == "NI_POINT" and { "O4" } or {},
    notes = "カーソルだけがずれたとき。pre-edit の位置に確定する（カーソルは動かさない）。"
      .. "O4 の <C-o>0 は niI から戻る。O-ctrl-o-l は keep の道を通るのでここでは使わない。",
  })
  add({
    id = "t." .. from .. ".return_drop",
    from = from, event = "ni_return_drop", to = "I_DIRECT",
    effects = { "drop", "reset_state", "clear_extmark", "render" },
    status = from ~= "NI_DIRECT" and "gap" or "unknown",
    refs = { "cleanup.lua:120-147,215-217", "#199" },
    observed = from == "NI_POINT" and { "O5", "O-ctrl-o-x" } or {},
    notes = "カーソル以外のずれ（バッファが変わった）。読みは確定せずに捨てる。"
      .. "O5 / O-ctrl-o-x は ▽ から打っていて、▼ からは打っていない。",
  })
end
add({
  id = "t.NI_DIRECT.return_keep",
  from = "NI_DIRECT", event = "ni_return_keep", to = "I_DIRECT",
  effects = { "keep" },
  status = "ok", refs = { "#117" },
})
add({
  id = "t.NI_POINT.return_keep",
  from = "NI_POINT", event = "ni_return_keep", to = "I_POINT",
  effects = { "keep" },
  status = "ok", refs = { "#117" }, observed = { "O-ctrl-o-l" },
  notes = "カーソルもバッファも変わらなければ、そのまま insert に戻る。",
})
add({
  id = "t.NI_SELECT.return_keep",
  from = "NI_SELECT", event = "ni_return_keep", to = "I_SELECT",
  effects = { "keep" },
  status = "ok", refs = { "#117" },
})
add({
  id = "t.NI_DIRECT.visual",
  from = "NI_DIRECT", event = "ni_v", to = "V_IDLE",
  effects = { "keep" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
  notes = "<C-o>v を direct から。visual の間は pre-edit が無く、skk は有効のまま。"
    .. "O-ctrl-o-v-direct は <C-o>v を 1 つのキーとして I_DIRECT から通るので、niI 経由は未観測。",
})
add({
  id = "t.NI_POINT.visual",
  from = "NI_POINT", event = "ni_v", to = "V_PRE_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
  notes = "MODE_TRANSITIONS が niI からの移り先を見ていないので、visual の間も pre-edit が描かれたまま残る。"
    .. "P1 などは破らない（読みは残る）。niI 経由の観測は無い。",
})
add({
  id = "t.NI_SELECT.visual",
  from = "NI_SELECT", event = "ni_v", to = "V_PRE_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
  notes = "▼ から niI を経て visual へ。pre-edit は残るが、P1 などは破らない。観測は無い。",
})
add({
  id = "t.I_DIRECT.ctrl_o_v",
  from = "I_DIRECT", event = "ctrl_o_v", to = "V_IDLE",
  effects = { "keep" },
  status = "ok", refs = { "cleanup.lua:179-190" }, observed = { "O-ctrl-o-v-direct" },
  notes = "<C-o>v は <C-o> のあと v の 2 キー。モデルでは 1 つのイベントにまとめた。",
})
add({
  id = "t.I_POINT.ctrl_o_v",
  from = "I_POINT", event = "ctrl_o_v", to = "V_PRE_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "cleanup.lua:179-190" }, observed = { "O-ctrl-o-v" },
  notes = "pre-edit が残ったまま visual に入る。読みは捨てないので P1 は破らない。",
})
add({
  id = "t.I_SELECT.ctrl_o_v",
  from = "I_SELECT", event = "ctrl_o_v", to = "V_PRE_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
  notes = "▼ から <C-o>v。pre-edit は残るが、P1 などは破らない。観測は無い。",
})
add({
  id = "t.NI_DIRECT.replace",
  from = "NI_DIRECT", event = "ni_R", to = "R_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
  notes = "O-ctrl-o-R は <C-o>R を 1 つのキーとして I_POINT から通るので、niI 経由は未観測。",
})
add({
  id = "t.NI_POINT.replace",
  from = "NI_POINT", event = "ni_R", to = "R_OFF",
  effects = { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
  notes = "O-ctrl-o-R は I_POINT から 1 キーで通る。niI 経由は未観測。"
    .. "観測では読みを確定して無効化した（data.js は pre-edit が残るとしていたが、再現しなかった）。",
})
add({
  id = "t.NI_SELECT.replace",
  from = "NI_SELECT", event = "ni_R", to = "R_OFF",
  effects = { "commit_candidate", "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
})
add({
  id = "t.I_DIRECT.ctrl_o_R",
  from = "I_DIRECT", event = "ctrl_o_R", to = "R_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "ok", refs = { "cleanup.lua:179-190" },
})
add({
  id = "t.I_POINT.ctrl_o_R",
  from = "I_POINT", event = "ctrl_o_R", to = "R_OFF",
  effects = { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" },
  status = "ok", refs = { "cleanup.lua:179-190" }, observed = { "O-ctrl-o-R" },
})
add({
  id = "t.I_SELECT.ctrl_o_R",
  from = "I_SELECT", event = "ctrl_o_R", to = "R_OFF",
  effects = { "commit_candidate", "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:179-190" },
})
add({
  id = "t.NI_POINT.winleave",
  from = "NI_POINT", event = "winleave", to = "N_OFF",
  effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
  status = "gap", refs = { "cleanup.lua:269-281", "#169" },
})
add({
  id = "t.NI_SELECT.winleave",
  from = "NI_SELECT", event = "winleave", to = "N_OFF",
  effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
  status = "gap", refs = { "cleanup.lua:269-281", "#169" },
})
add({
  id = "t.NI_DIRECT.winleave",
  from = "NI_DIRECT", event = "winleave", to = "N_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:269-281", "#169" },
  notes = "読みが無いので drop は起きない。P1 は破らない。",
})

-- visual から戻る・抜ける
add({
  id = "t.V_IDLE.esc",
  from = "V_IDLE", event = "esc", to = "I_DIRECT",
  effects = { "keep" },
  status = "ok", refs = { "cleanup.lua:192-251" }, observed = { "O-ctrl-o-v-direct-esc" },
  notes = "<C-o>v で入った visual を <Esc> で抜けると insert に戻る。skk は有効のまま。",
})
add({
  id = "t.V_PRE_POINT.esc",
  from = "V_PRE_POINT", event = "esc", to = "I_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "cleanup.lua:192-251" }, observed = { "O-ctrl-o-v-esc" },
  notes = "観測では pre-edit を保ったまま insert に戻った（data.js の「抜けると確定」は再現しなかった）。",
})
add({
  id = "t.V_PRE_SELECT.esc",
  from = "V_PRE_SELECT", event = "esc", to = "I_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "cleanup.lua:192-251" },
})
add({
  id = "t.V_PRE_POINT.winleave",
  from = "V_PRE_POINT", event = "winleave", to = "N_OFF",
  effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
  status = "gap", refs = { "cleanup.lua:269-281", "#169" },
})
add({
  id = "t.V_PRE_SELECT.winleave",
  from = "V_PRE_SELECT", event = "winleave", to = "N_OFF",
  effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
  status = "gap", refs = { "cleanup.lua:269-281", "#169" },
})
add({
  id = "t.V_IDLE.winleave",
  from = "V_IDLE", event = "winleave", to = "N_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:269-281", "#169" },
  notes = "読みが無いので drop は起きない。P1 は破らない。",
})

-- <C-o>: の戻り（cmdline の中は 07a）
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".ctrl_o_colon",
    from = from, event = "ctrl_o_colon", to = from,
    effects = { "keep", "clean_cmdline" },
    status = "ok", refs = { "cleanup.lua:254-266", "#86" },
    observed = from == "I_SELECT" and { "O-ctrl-o-colon-cr-select" }
      or from == "I_POINT" and { "O-ctrl-o-colon" }
      or {},
    notes = "<C-o>:<Esc> も <C-o>:<CR> も、戻ると pre-edit を保つ（観測）。cmdline の中は 07a。"
      .. "O-ctrl-o-colon は ▽ から、▼ からは O-ctrl-o-colon-cr-select で確かめた。",
  })
end

-- 入力の文字（kana_input）
add({
  id = "t.I_DIRECT.char.keep",
  from = "I_DIRECT", event = "char", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/input.lua:85-120" }, observed = { "O-a" },
  notes = "direct でかなテーブルの 1 打が確定する（例: a → あ）。バッファに文字が入る。",
})
add({
  id = "t.I_DIRECT.char.romaji",
  from = "I_DIRECT", event = "char", to = "I_ROMAJI",
  effects = { "feed_key", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
  notes = "ローマ字が続く（例: k）。打ちかけが pre-edit に出る。"
    .. "O-k の K はシフト付き（char_shift）なので、小文字から始まる道は観測していない。",
})
add({
  id = "t.I_ROMAJI.char.keep",
  from = "I_ROMAJI", event = "char", to = "I_ROMAJI",
  effects = { "feed_key", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.I_ROMAJI.char.commit",
  from = "I_ROMAJI", event = "char", to = "I_POINT",
  effects = { "feed_key", "render" },
  status = "ok", refs = { "function/input.lua:85-120", "06 の観測 P.t.I_ROMAJI.char.commit" },
  observed = { "O-ka" },
  notes = "打った文字がかなになって読みに入る（▽k + a → ▽か）。04 はここを I_DIRECT としていたが、"
    .. "06 の観測に合わせて I_POINT に直した。",
})
add({
  id = "t.I_POINT.char",
  from = "I_POINT", event = "char", to = "I_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/input.lua:85-120" }, observed = { "O-kan-n" },
})
add({
  id = "t.I_SELECT.char.commit",
  from = "I_SELECT", event = "char", to = "I_DIRECT",
  effects = { "commit_candidate", "feed_key", "reset_state" },
  status = "ok", refs = { "function/henkan.lua:137-162" }, observed = { "O-select-char" },
  notes = "henkan の表に無いキーは、候補を確定してから input として処理し直す。",
})
add({
  id = "t.I_SELECT.char.commit_romaji",
  from = "I_SELECT", event = "char", to = "I_ROMAJI",
  effects = { "commit_candidate", "feed_key", "render" },
  status = "unknown", refs = { "function/henkan.lua:137-162" },
})

-- シフト付きの文字（▽ を開始する）
add({
  id = "t.I_DIRECT.char_shift",
  from = "I_DIRECT", event = "char_shift", to = "I_ROMAJI",
  effects = { "render" },
  status = "ok", refs = { "function/input.lua:85-120" }, observed = { "O-k" },
  notes = "direct でシフト付きの文字は ▽ を開始する（例: K → ▽k）。",
})
add({
  id = "t.I_DIRECT.char_shift.point",
  from = "I_DIRECT", event = "char_shift", to = "I_POINT",
  effects = { "render" },
  status = "ok", refs = { "function/input.lua:85-120" },
  notes = "1 打でかなまで確定するシフト付きの文字もある。",
})
add({
  id = "t.I_ROMAJI.char_shift",
  from = "I_ROMAJI", event = "char_shift", to = "I_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.I_POINT.char_shift",
  from = "I_POINT", event = "char_shift", to = "I_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.I_SELECT.char_shift",
  from = "I_SELECT", event = "char_shift", to = "I_ROMAJI",
  effects = { "commit_candidate", "feed_key", "reset_state", "render" },
  status = "ok", refs = { "function/henkan.lua:137-162", "06 の観測 P.t.I_SELECT.char_shift" },
  notes = "候補を確定してから、シフト付きの文字を input として処理し直す（K → ▽k）。"
    .. "04 はここを I_DIRECT としていたが、06 の観測に合わせて I_ROMAJI に直した。",
})

-- 文字キーのうち、関数が割り当てられているもの
add({
  id = "t.I_DIRECT.key_X",
  from = "I_DIRECT", event = "key_X", to = "I_ROMAJI",
  effects = { "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
  notes = "input ではシフト付きの文字として ▽ を開始する。",
})
add({
  id = "t.I_POINT.key_X",
  from = "I_POINT", event = "key_X", to = "I_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.I_ROMAJI.key_l",
  from = "I_ROMAJI", event = "key_l", to = "I_OFF",
  effects = { "drop", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "keymap.lua:37", "function/disable.lua", "#67", "06 の観測 P.t.I_ROMAJI.key_l" },
  notes = "打ちかけのローマ字は確定せずに捨てる（06 の観測でバッファは空のまま）。",
})
add({
  id = "t.I_SELECT.key_l",
  from = "I_SELECT", event = "key_l", to = "I_OFF",
  effects = { "commit_candidate", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "keymap.lua:37", "function/disable.lua", "#67", "06 の観測 P.t.I_SELECT.key_l" },
  notes = "候補を確定してから無効にする（06 の観測で 缶 がバッファに入る）。",
})
add({
  id = "t.I_DIRECT.key_l",
  from = "I_DIRECT", event = "key_l", to = "I_OFF",
  effects = { "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "keymap.lua:37", "function/disable.lua", "#67" }, observed = { "O-l" },
  notes = "既定のかなテーブルのときだけ。1 打で無効になる。",
})
add({
  id = "t.I_POINT.key_l",
  from = "I_POINT", event = "key_l", to = "I_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "keymap.lua:37", "function/disable.lua", "#67" },
})
add({
  id = "t.I_DIRECT.key_q",
  from = "I_DIRECT", event = "key_q", to = "I_DIRECT",
  effects = { "render" },
  status = "ok", refs = { "keymap.lua:38" },
  notes = "かなモードをカタカナにする。状態クラスは変えない。",
})
add({
  id = "t.I_POINT.key_q",
  from = "I_POINT", event = "key_q", to = "I_DIRECT",
  effects = { "commit_reading", "render" },
  status = "ok", refs = { "keymap.lua:38", "function/mode.lua:63-84", "06 の観測 P.t.I_POINT.key_q" },
  notes = "変換中の q は、読みをカタカナにして確定する（カン がバッファに入る）。"
    .. "04 はここを I_POINT（状態は変えない）としていたが、06 の観測に合わせて直した。",
})
add({
  id = "t.I_DIRECT.key_semicolon",
  from = "I_DIRECT", event = "key_semicolon", to = "I_ROMAJI",
  effects = { "render" },
  status = "ok", refs = { "keymap.lua:39", "function/input.lua:147-", "06 の観測 P.t.I_DIRECT.key_semicolon" },
  notes = "送り仮名の入力へ。読みが空の direct では、▽ だけが描かれた状態になる（06 の観測）。"
    .. "04 はここを I_POINT としていたが、読みがまだ無いので I_ROMAJI に直した。",
})
add({
  id = "t.I_POINT.key_semicolon",
  from = "I_POINT", event = "key_semicolon", to = "I_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:39" },
})
add({
  id = "t.I_DIRECT.key_slash",
  from = "I_DIRECT", event = "key_slash", to = "I_ROMAJI",
  effects = { "render" },
  status = "ok", refs = { "keymap.lua:40", "06 の観測 P.t.I_DIRECT.key_slash" },
  notes = "abbrev モードへ。読みが空の direct では、▽ だけが描かれた状態になる（06 の観測）。"
    .. "04 はここを I_DIRECT としていたが、I_ROMAJI に直した。",
})
add({
  id = "t.I_DIRECT.key_L",
  from = "I_DIRECT", event = "key_L", to = "I_DIRECT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:41" },
})
add({
  id = "t.I_POINT.key_L",
  from = "I_POINT", event = "key_L", to = "I_DIRECT",
  effects = { "commit_reading", "render" },
  status = "ok", refs = { "keymap.lua:41", "function/mode.lua:98-111", "06 の観測 P.t.I_POINT.key_L" },
  notes = "変換中の L は、読みを確定してから全角モードに切り替える（かん がバッファに入る）。"
    .. "04 はここを I_POINT としていたが、06 の観測に合わせて直した。",
})
add({
  id = "t.I_DIRECT.key_cq",
  from = "I_DIRECT", event = "key_cq", to = "I_DIRECT",
  effects = { "render" },
  status = "ok", refs = { "keymap.lua:33" },
  notes = "半角カタカナにする（#40）。状態クラスは変えない。",
})
add({
  id = "t.I_POINT.key_cq",
  from = "I_POINT", event = "key_cq", to = "I_DIRECT",
  effects = { "commit_reading", "render" },
  status = "ok", refs = { "keymap.lua:33", "function/mode.lua:63-84", "06 の観測 P.t.I_POINT.key_cq" },
  notes = "変換中の <C-q> は、読みを半角カタカナにして確定する（ｶﾝ がバッファに入る）。"
    .. "04 はここを I_POINT としていたが、06 の観測に合わせて直した。",
})
add({
  id = "t.I_DIRECT.key_gt",
  from = "I_DIRECT", event = "key_gt", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "unknown", refs = { "keymap.lua:34" },
})
add({
  id = "t.I_POINT.key_gt",
  from = "I_POINT", event = "key_gt", to = "I_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:53", "function/input.lua:206-223" },
  notes = "接頭辞・接尾辞を付けて変換に入る。06 の観測（既定の辞書に かん> が無い）では、"
    .. "候補が無いので辞書登録のプロンプト（P_PROMPT）に入った。辞書に候補があるかを"
    .. "状態クラスに持っていないので、どちらになるかはモデルで決められない。",
})
add({
  id = "t.I_SELECT.key_gt",
  from = "I_SELECT", event = "key_gt", to = "I_SELECT",
  effects = { "keep" },
  status = "unknown", refs = { "keymap.lua:53" },
})

-- ▽ / ▼ の操作
add({
  id = "t.I_DIRECT.space",
  from = "I_DIRECT", event = "space", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/henkan.lua:21-38", "06 の観測 P.t.I_DIRECT.space" },
  notes = "読みが無い direct では、<Space> は空白をバッファに入れる（henkan_first が direct では"
    .. "kana_input に落ちる）。04 はこの遷移を書いていなかった。",
})

add({
  id = "t.I_POINT.space.select",
  from = "I_POINT", event = "space", to = "I_SELECT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/henkan.lua:21-56" }, observed = { "O-space" },
})
add({
  id = "t.I_POINT.space.register",
  from = "I_POINT", event = "space", to = "P_PROMPT_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/henkan.lua:21-56", "host.lua:175-213", "#144" },
  observed = { "O-space-no-candidate" },
  notes = "辞書に候補が無いとき。外側の pre-edit は凍結して残る。",
})
add({
  id = "t.I_SELECT.space.next",
  from = "I_SELECT", event = "space", to = "I_SELECT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/henkan.lua:90-113" }, observed = { "O-space-next" },
})
add({
  id = "t.I_SELECT.space.register",
  from = "I_SELECT", event = "space", to = "P_PROMPT_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/henkan.lua:90-113" },
  notes = "候補の最後でさらに <Space> を押したとき（register_word）。",
})
add({
  id = "t.I_SELECT.x.prev",
  from = "I_SELECT", event = "key_x", to = "I_SELECT",
  effects = { "keep", "render" },
  status = "ok", refs = { "keymap.lua:51", "function/henkan.lua:116-133" }, observed = { "O-x-prev" },
  notes = "x は henkanBackward。候補を 1 つ前へ。",
})
add({
  id = "t.I_SELECT.x.back",
  from = "I_SELECT", event = "key_x", to = "I_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "keymap.lua:51", "function/henkan.lua:116-133" }, observed = { "O-x-back" },
  notes = "最初の候補でさらに x を押すと ▽ に戻る。",
})
add({
  id = "t.I_SELECT.key_X.purge",
  from = "I_SELECT", event = "key_X", to = "I_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:52", "#129" },
})
add({
  id = "t.I_SELECT.key_X.register",
  from = "I_SELECT", event = "key_X", to = "P_PROMPT_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:52", "function/common.lua:89-" },
  notes = "06 の観測では、候補の最後で X を打っても辞書登録のプロンプトに入らなかった（I_SELECT のまま）。"
    .. "どういう条件で登録に入るかは未観測。",
})
add({
  id = "t.P_PROMPT_POINT.register_commit",
  from = "P_PROMPT_POINT", event = "register_commit", to = "I_DIRECT",
  effects = { "commit_reading", "reset_state", "render" },
  status = "unknown", refs = { "host.lua:125-162", "events.md O12" },
  notes = "語を登録して insert に戻る。読みは登録した語として辞書に入る（O12）。"
    .. "O12 はプロンプトに入るところまでで、<CR> の確定はキー列に無い。",
})
add({
  id = "t.P_PROMPT_SELECT.register_commit",
  from = "P_PROMPT_SELECT", event = "register_commit", to = "I_DIRECT",
  effects = { "commit_candidate", "reset_state", "render" },
  status = "unknown", refs = { "host.lua:125-162", "events.md O12" },
  notes = "▼ から登録したときも、候補を登録して insert に戻る。",
})
add({
  id = "t.P_PROMPT_POINT.register_cancel",
  from = "P_PROMPT_POINT", event = "register_cancel", to = "I_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "host.lua:166-169,197-204", "#116" },
  notes = "取り消して、凍結していた外側の ▽ に戻る。"
    .. "O12 はプロンプトに入るところまでで、取り消しはキー列に無い。",
})
add({
  id = "t.P_PROMPT_SELECT.register_cancel",
  from = "P_PROMPT_SELECT", event = "register_cancel", to = "I_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "host.lua:166-169,197-204", "#116" },
  notes = "取り消して、凍結していた外側の ▼ に戻る（未観測）。",
})
add({
  id = "t.P_PROMPT_POINT.winleave",
  from = "P_PROMPT_POINT", event = "winleave", to = "P_PROMPT_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "host.lua:75-92,269-281" },
  notes = "辞書登録の input() の間は外側の状態を壊さない（WinEnter でフレームのウィンドウへ戻す）。",
})
add({
  id = "t.P_PROMPT_SELECT.winleave",
  from = "P_PROMPT_SELECT", event = "winleave", to = "P_PROMPT_SELECT",
  effects = { "keep", "render" },
  status = "ok", refs = { "host.lua:75-92,269-281" },
  notes = "辞書登録の input() の間は外側の状態を壊さない（WinEnter でフレームのウィンドウへ戻す）。",
})

-- 確定・取消
add({
  id = "t.I_DIRECT.nl",
  from = "I_DIRECT", event = "nl", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/common.lua:18-45" },
})
add({
  id = "t.I_ROMAJI.nl",
  from = "I_ROMAJI", event = "nl", to = "I_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "ok", refs = { "function/common.lua:18-45" },
})
add({
  id = "t.I_POINT.nl",
  from = "I_POINT", event = "nl", to = "I_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "ok", refs = { "function/common.lua:18-45" }, observed = { "O-nl" },
})
add({
  id = "t.I_SELECT.nl",
  from = "I_SELECT", event = "nl", to = "I_DIRECT",
  effects = { "commit_candidate", "feed_key" },
  status = "ok", refs = { "function/common.lua:18-45" }, observed = { "O-space-nl" },
})
add({
  id = "t.I_DIRECT.cr",
  from = "I_DIRECT", event = "cr", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/common.lua:59-68" },
})
add({
  id = "t.I_ROMAJI.cr",
  from = "I_ROMAJI", event = "cr", to = "I_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "ok", refs = { "function/common.lua:59-68" },
})
add({
  id = "t.I_POINT.cr",
  from = "I_POINT", event = "cr", to = "I_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "ok", refs = { "function/common.lua:59-68" },
})
add({
  id = "t.I_SELECT.cr",
  from = "I_SELECT", event = "cr", to = "I_DIRECT",
  effects = { "commit_candidate", "feed_key" },
  status = "ok", refs = { "function/common.lua:59-68" },
})
add({
  id = "t.I_DIRECT.cg",
  from = "I_DIRECT", event = "cg", to = "I_DIRECT",
  effects = { "pass_key" },
  status = "ok", refs = { "keymap.lua:28" },
})
add({
  id = "t.I_ROMAJI.cg",
  from = "I_ROMAJI", event = "cg", to = "I_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "ok", refs = { "keymap.lua:28", "function/common.lua:71-86" },
})
add({
  id = "t.I_POINT.cg",
  from = "I_POINT", event = "cg", to = "I_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "ok", refs = { "keymap.lua:28", "#87" }, observed = { "O-cg" },
})
add({
  id = "t.I_SELECT.cg",
  from = "I_SELECT", event = "cg", to = "I_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "ok", refs = { "keymap.lua:28", "#87" },
})
add({
  id = "t.I_POINT.bs",
  from = "I_POINT", event = "bs", to = "I_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/input.lua:178-204" }, observed = { "O-bs" },
})
add({
  id = "t.I_POINT.bs.empty",
  from = "I_POINT", event = "bs", to = "I_ROMAJI",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/input.lua:178-204", "06 の観測 P.t.I_POINT.bs.empty" },
  notes = "読みが空になったとき。▽ だけが描かれた状態（I_ROMAJI）に戻る（06 の観測）。"
    .. "04 はここを I_DIRECT（pre-edit を消す）としていたが、観測では ▽ が残る。",
})
add({
  id = "t.I_ROMAJI.bs",
  from = "I_ROMAJI", event = "bs", to = "I_ROMAJI",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:178-204" },
})
add({
  id = "t.I_ROMAJI.bs.empty",
  from = "I_ROMAJI", event = "bs", to = "I_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "ok", refs = { "function/input.lua:178-204" },
})
add({
  id = "t.I_DIRECT.bs",
  from = "I_DIRECT", event = "bs", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/input.lua:178-204" },
  notes = "打ちかけが無いので、バッファの 1 文字を消す（ctx:kakutei('\\b')）。",
})
add({
  id = "t.I_SELECT.bs",
  from = "I_SELECT", event = "bs", to = "I_DIRECT",
  effects = { "commit_candidate", "feed_key", "reset_state" },
  status = "unknown", refs = { "function/henkan.lua:137-162" },
  notes = "候補を確定してから 1 文字消す。",
})

-- insert の制御キー（guard が確定しないもの）
local function insert_control(id, event, refs, observed, notes)
  for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
    local e, status
    if from == "I_DIRECT" then
      e = { "feed_key" }
      status = "ok"
    elseif from == "I_SELECT" then
      e = { "commit_candidate", "feed_key", "reset_state", "clear_extmark" }
      status = "unknown"
    else
      e = { "drop", "reset_state", "clear_extmark", "render" }
      status = "gap"
    end
    add({
      id = "t." .. from .. "." .. id,
      from = from, event = event, to = "I_DIRECT",
      effects = e, status = status,
      refs = refs, observed = from == "I_POINT" and observed or {},
      notes = notes,
    })
  end
end

insert_control("ctrl_r", "ctrl_r", { "keys.md §5,§6", "#8", "#12", "#20" }, { "O-ctrl-r" },
  "レジスタの内容がバッファに入り、TextChangedI が読みを捨てる。")
insert_control("ctrl_v", "ctrl_v", { "keys.md §5,§6", "#12" }, { "O-ctrl-v" },
  "文字コードを直接入れる。読みは捨てられる。")
insert_control("ctrl_k", "ctrl_k", { "keys.md §5,§6", "#12" }, { "O-ctrl-k" },
  "ダイグラフ。読みは捨てられる。")
insert_control("ctrl_t", "ctrl_t", { "keys.md §5,§6" }, { "O-ctrl-t" },
  "インデント。読みは捨てられる。")
insert_control("tab", "tab", { "keys.md §5,§6", "#12" }, { "O-tab" },
  "<Tab> は単バイトなので guard が確定しない。読みは捨てられる。")
insert_control("ctrl_w", "ctrl_w", { "keys.md §5,§6", "#8", "#12" }, { "O-ctrl-w" },
  "pre-edit はバッファに無いので、確定済みの文字が消える。読みだけのときは何も起きない（自己遷移）。")
insert_control("ctrl_u", "ctrl_u", { "keys.md §5,§6", "#8", "#12" }, { "O-ctrl-u" },
  "<C-w> と同じ。")
insert_control("ctrl_a", "ctrl_a", { "keys.md §6", "NOTES.md 未考慮 7" }, { "O-ctrl-a" },
  "E29: No inserted text yet になる（観測）。insert を抜けるかどうかは未確定。")
insert_control("ctrl_at", "ctrl_at", { "keys.md §4,§6", "#56" }, { "O-ctrl-at" },
  "guard が確定してから i_CTRL-@。確定した読みはバッファに入り、E29 で insert を抜ける（keys.md §4）。")

-- <C-w> / <C-u> で消す文字が無いときは pre-edit が残る（同じ from からの別の遷移）
for _, from in ipairs({ "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".ctrl_w.keep",
    from = from, event = "ctrl_w", to = from,
    effects = { "pass_key" },
    status = from ~= "I_SELECT" and "ok" or "unknown",
    refs = { "keys.md §6 補足" },
    observed = from == "I_POINT" and { "O-ctrl-w-empty" } or {},
    notes = "バッファに消す文字が無いので、バッファも pre-edit も変わらない。"
      .. "O-ctrl-w-empty は ▽ からで、▼ からは打っていない。",
  })
  add({
    id = "t." .. from .. ".ctrl_u.keep",
    from = from, event = "ctrl_u", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "keys.md §6 補足" },
  })
end

-- <C-y> / <C-e>（補完のメニューが出ていないときは何もしない）
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".completion_accept",
    from = from, event = "completion_accept", to = from,
    effects = { "pass_key" },
    status = from ~= "I_SELECT" and "ok" or "unknown",
    refs = { "keys.md §6" },
    observed = from == "I_POINT" and { "O-ctrl-y-e" } or {},
    notes = "補完のメニューが無いとき。pre-edit が残る（観測）。O-ctrl-y-e は ▽ から。",
  })
end

-- 補完（#190 の境界）
add({
  id = "t.I_DIRECT.completion_open",
  from = "I_DIRECT", event = "completion_open", to = "IC",
  effects = { "pass_key" },
  status = "unknown", refs = { "keys.md §5", "#190" },
  notes = "pre-edit が無いので、補完はそのまま始まる。",
})
add({
  id = "t.I_ROMAJI.completion_open",
  from = "I_ROMAJI", event = "completion_open", to = "IC",
  effects = { "drop", "clear_extmark" },
  status = "gap", refs = { "keys.md §5", "#19", "#190" },
})
add({
  id = "t.I_POINT.completion_open",
  from = "I_POINT", event = "completion_open", to = "IC",
  effects = { "drop", "clear_extmark" },
  status = "gap", refs = { "keys.md §5", "#18", "#19", "#190" }, observed = { "O-completion-open" },
  notes = "観測では pre-edit が消え、補完の候補が入った。読みは確定しない。",
})
add({
  id = "t.I_SELECT.completion_open",
  from = "I_SELECT", event = "completion_open", to = "IC",
  effects = { "drop", "clear_extmark" },
  status = "gap", refs = { "keys.md §5", "#18", "#190" },
})
add({
  id = "t.IC.completion_next",
  from = "IC", event = "completion_next", to = "IC",
  effects = { "pass_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-next" },
})
add({
  id = "t.IC.completion_accept.C-y",
  from = "IC", event = "completion_accept", to = "I_DIRECT",
  effects = { "reset_state" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-accept" },
  notes = "<C-y> は候補を受け入れる。<C-e> は取り消して元の文字に戻す。どちらも insert に戻る。",
})
add({
  id = "t.IC.esc",
  from = "IC", event = "esc", to = "N_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "ok", refs = { "cleanup.lua:192-251" }, observed = { "O-completion-esc" },
})
add({
  id = "t.IC.ctrl_c",
  from = "IC", event = "ctrl_c", to = "N_WAIT",
  effects = {},
  status = "unknown", refs = { "cleanup.lua:187" },
})
add({
  id = "t.IC.stale",
  from = "IC", event = "stale", to = "I_DIRECT",
  effects = { "reset_state" },
  status = "unknown", refs = { "cleanup.lua:283-286", "#190" },
  notes = "CompleteDone / TextChangedP でずれを見る。O16 は 04 で取っていない。",
})
add({
  id = "t.IC.winleave",
  from = "IC", event = "winleave", to = "N_OFF",
  effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:269-281", "#169" },
  notes = "読みが無い（IC）ので drop は起きない。P1 は破らない。",
})

-- guard が確定するキー・マウス・貼り付け
local function guard_event(event)
  for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
    local e = { "feed_key" }
    if from == "I_SELECT" then
      e = { "commit_candidate", "feed_key", "reset_state", "clear_extmark" }
    elseif from ~= "I_DIRECT" then
      e = { "commit_reading", "feed_key", "reset_state", "clear_extmark" }
    end
    add({
      id = "t." .. from .. "." .. event,
      from = from, event = event, to = "I_DIRECT",
      effects = e,
      status = from ~= "I_SELECT" and "ok" or "unknown",
      refs = { "guard.lua:50-85", "#56" },
      observed = from == "I_POINT" and { "O-guard" } or {},
      notes = "pre-edit を確定してから、キーを insert のまま流す。O-guard は ▽ からで、▼ からは打っていない。",
    })
  end
end
guard_event("guard_special")
add({
  id = "t.I_DIRECT.mouse_click",
  from = "I_DIRECT", event = "mouse_click", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "unknown", refs = { "#56" },
  notes = "同じウィンドウのクリック。04 の観測はマウスを使っていない。",
})
for _, from in ipairs({ "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".mouse_click",
    from = from, event = "mouse_click", to = "I_DIRECT",
    effects = from == "I_SELECT" and { "commit_candidate", "reset_state", "feed_key", "clear_extmark" }
      or { "commit_reading", "reset_state", "feed_key", "clear_extmark" },
    status = "unknown", refs = { "#56" },
    notes = "同じウィンドウのクリックはカーソルが動くので、ずれの検出で確定する。04 の観測はマウスを使っていない。",
  })
end
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".wheel",
    from = from, event = "wheel", to = from,
    effects = { "pass_key" },
    status = "unknown", refs = { "guard.lua:59-61", "keys.md §5" },
    notes = "guard は確定しない。スクロールだけなので pre-edit が残る。04 の観測は取っていない。",
  })
end
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".paste",
    from = from, event = "paste", to = "I_DIRECT",
    effects = from == "I_SELECT" and { "commit_candidate", "reset_state", "clear_extmark" }
      or from ~= "I_DIRECT" and { "commit_reading", "reset_state", "clear_extmark" }
      or { "feed_key" },
    status = "unknown", refs = { "paste.lua:31-69", "#125" },
    notes = "貼り付けの前に pre-edit を確定する（#125）。04 の観測は取っていない。",
  })
end

-- ずれの検出（autocmd）
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".stale.cursor",
    from = from, event = "stale", to = "I_DIRECT",
    guard = { { "reading", "in", { "romaji", "point", "henkan" } } },
    effects = from == "I_SELECT" and { "commit_candidate", "reset_state", "render" }
      or from == "I_DIRECT" and { "render" }
      or { "commit_reading", "reset_state", "render" },
    status = "unknown", refs = { "cleanup.lua:120-147,283-286", "#117" },
    notes = "カーソルだけがずれたとき（CursorMovedI）。pre-edit の位置に確定する。"
      .. "O4 の <C-o>0 は niI から戻る道で、CursorMovedI の観測ではない。",
  })
  add({
    id = "t." .. from .. ".stale.buffer",
    from = from, event = "stale", to = "I_DIRECT",
    guard = { { "reading", "in", { "romaji", "point", "henkan" } } },
    effects = { "drop", "reset_state", "clear_extmark", "render" },
    status = from ~= "I_DIRECT" and "gap" or "unknown",
    refs = { "cleanup.lua:120-147,283-286", "#8", "#12", "#199" },
    notes = "バッファが変わったとき（TextChangedI / on_bytes）。読みは確定せずに捨てる。"
      .. "I_DIRECT は読みが無いので P1 は破らない。",
  })
  add({
    id = "t." .. from .. ".stale.none",
    from = from, event = "stale", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "cleanup.lua:120-147" },
    notes = "ずれが無ければ何もしない。",
  })
end

-- 観測の記録（子の nvim、一時ディレクトリの辞書）
--
-- 04 の観測。1 つのキーを 1 回の入力として流し、落ち着いてから
-- 状態クラス（semantics/explore/observe.lua の classify と同じ見方）を読んだ。
-- start は N_OFF。prefix に <Plug>(skkeleton-enable) を含むものは、そこから数える。
M.observations = {
  {
    id = "O-enable",
    keys = { "<Plug>(skkeleton-enable)" },
    expect = { "I_DIRECT" },
    note = "有効化。mode=i、enabled=true、preedit=\"\"。",
  },
  {
    id = "O-l",
    keys = { "<Plug>(skkeleton-enable)", "l" },
    expect = { "I_OFF" },
    note = "既定のかなテーブルの l は disable。1 打で無効になり、insert のまま。04 では取っていない（コード読解）。",
    uncertain = true,
  },
  {
    id = "O-enable-insert",
    keys = { "<Plug>(skkeleton-enable)", "<Insert>", "<Insert>", "<Plug>(skkeleton-enable)" },
    expect = { "I_DIRECT" },
    note = "無効な insert から有効化する道。04 では取っていない（コード読解）。",
    uncertain = true,
  },
  {
    id = "O-select-char",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "a" },
    expect = { "I_DIRECT" },
    note = "▼ で候補を選ばずに文字キーを打つと、候補を確定してから入力に回る。04 では取っていない（コード読解）。",
    uncertain = true,
  },
  {
    id = "O-a",
    keys = { "<Plug>(skkeleton-enable)", "a" },
    expect = { "I_DIRECT" },
    note = "a → あ がバッファに入る（direct のまま）。",
  },
  {
    id = "O-k",
    keys = { "<Plug>(skkeleton-enable)", "K" },
    expect = { "I_ROMAJI" },
    note = "K → preedit=\"▽k\"（henkan_feed がまだ空）。",
  },
  {
    id = "O-ka",
    keys = { "<Plug>(skkeleton-enable)", "K", "a" },
    expect = { "I_POINT" },
    note = "K a → preedit=\"▽か\"。",
  },
  {
    id = "O-kan-n",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "I_POINT" },
    note = "preedit=\"▽かn\"。",
  },
  {
    id = "O-ctrl-r",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-r>a" },
    expect = { "I_DIRECT" },
    note = "レジスタ a に XYZ を入れてから。バッファは XYZ、preedit=\"\"、enabled=true。読みは捨てられた。",
  },
  {
    id = "O-ctrl-v",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-v>065" },
    expect = { "I_DIRECT" },
    note = "バッファは A。読みは捨てられた。",
  },
  {
    id = "O-ctrl-k",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-k>a:" },
    expect = { "I_DIRECT" },
    note = "バッファは ä。読みは捨てられた。",
  },
  {
    id = "O-ctrl-t",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-t>" },
    expect = { "I_DIRECT" },
    note = "バッファはタブ + 空行。読みは捨てられた。",
  },
  {
    id = "O-tab",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Tab>" },
    expect = { "I_DIRECT" },
    note = "バッファはタブだけ。読みは捨てられた（<S-Tab> は逆に確定してからタブが入る）。",
  },
  {
    id = "O-ctrl-w",
    keys = { "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<C-w>" },
    expect = { "I_DIRECT" },
    note = "バッファは空（あ も かん も残らない）。読みは捨てられた。",
  },
  {
    id = "O-ctrl-w-empty",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-w>" },
    expect = { "I_POINT" },
    note = "バッファに消す文字が無いので、pre-edit が残ったまま（keys.md §6 補足と同じ）。",
  },
  {
    id = "O-ctrl-u",
    keys = { "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<C-u>" },
    expect = { "I_DIRECT" },
    note = "バッファは空。読みは捨てられた。",
  },
  {
    id = "O-ctrl-a",
    keys = { "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<C-a>" },
    expect = { "I_DIRECT" },
    note = "E29: No inserted text yet。子は insert のまま観測できなかったので、クラスは推定。",
    uncertain = true,
  },
  {
    id = "O-ctrl-at",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-@>" },
    expect = { "I_DIRECT" },
    note = "E29。keys.md §4 では「確定してから E29 で insert を抜ける」。04 の観測では insert のまま観測できず、クラスは推定。",
    uncertain = true,
  },
  {
    id = "O-ctrl-y-e",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-y>" },
    expect = { "I_POINT" },
    note = "補完のメニューが無いので何も起きない。<C-e> も同じ。",
  },
  {
    id = "O-ctrl-o-v",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>v" },
    expect = { "V_PRE" },
    note = "mode=v、enabled=true、preedit=\"▽かn\" のまま。",
  },
  {
    id = "O-ctrl-o-v-esc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>v", "<Esc>" },
    expect = { "I_POINT" },
    note = "visual を抜けると insert に戻り、pre-edit は残る（data.js の「抜けると確定」は再現しなかった）。",
  },
  {
    id = "O-ctrl-o-v-direct",
    keys = { "<Plug>(skkeleton-enable)", "<C-o>v" },
    expect = { "V_IDLE" },
    note = "pre-edit が無い visual。mode=v、enabled=true。visual で有効な V_IDLE。",
  },
  {
    id = "O-ctrl-o-v-direct-esc",
    keys = { "<Plug>(skkeleton-enable)", "<C-o>v", "<Esc>" },
    expect = { "I_DIRECT" },
    note = "visual から insert に戻る。enabled=true のまま。",
  },
  {
    id = "O-ctrl-o-R",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>R" },
    expect = { "R_OFF" },
    note = "バッファは abcdeかんf（abcdef の 5 桁目に確定）、enabled=false。読みは確定して無効化された。",
  },
  {
    id = "O-insert",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Insert>" },
    expect = { "R_OFF" },
    note = "バッファは かん、mode=R、enabled=false。読みを確定して無効化した。",
  },
  {
    id = "O-insert-twice",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Insert>", "<Insert>" },
    expect = { "I_OFF" },
    note = "2 回目で insert に戻る。enabled=false のまま（skk は有効にならない）。",
  },
  {
    id = "O-ctrl-o-l",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "l" },
    expect = { "I_POINT" },
    note = "空行の末尾で l。カーソルが動かないので、pre-edit が残ったまま insert に戻る。",
  },
  {
    id = "O-ctrl-o-x",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "x" },
    expect = { "I_DIRECT" },
    note = "バッファの f が消えて abcde。読みは捨てられた（#199）。",
  },
  {
    id = "O-ctrl-o-colon",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>:<Esc>" },
    expect = { "I_POINT" },
    note = "pre-edit が残ったまま insert に戻る（#86）。<C-o>:<CR> も同じ（観測）。",
  },
  {
    id = "O-ctrl-o-colon-cr-select",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>:<CR>" },
    expect = { "I_SELECT" },
    note = "▼ でも <C-o>:<CR> は pre-edit を保った（data.js の「確定する」は再現しなかった）。",
  },
  {
    id = "O-esc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Esc>" },
    expect = { "N_OFF" },
    note = "バッファは かん、mode=n、enabled=false。",
  },
  {
    id = "O-esc-idle",
    keys = { "<Plug>(skkeleton-enable)", "<Esc>" },
    expect = { "N_OFF" },
    note = "pre-edit が無くても無効化する。",
  },
  {
    id = "O-esc-select",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Esc>" },
    expect = { "N_OFF" },
    note = "選択中の候補を確定して無効化する。",
  },
  {
    id = "O-esc-then-i",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Esc>", "i" },
    expect = { "I_OFF" },
    note = "i で insert に戻るが、enabled=false（keepState が既定の false のため）。",
  },
  {
    id = "O-ctrlc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-c>" },
    expect = { "N_OFF" },
    note = "SafeState で確定して無効化する。バッファは かん。",
  },
  {
    id = "O-space",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>" },
    expect = { "I_SELECT" },
    note = "preedit=\"▼缶\"。",
  },
  {
    id = "O-space-next",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Space>" },
    expect = { "I_SELECT" },
    note = "候補が次へ進む。",
  },
  {
    id = "O-space-nl",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-j>" },
    expect = { "I_DIRECT" },
    note = "候補 缶 を確定してバッファに入る。",
  },
  {
    id = "O-x-prev",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Space>", "x" },
    expect = { "I_SELECT" },
    note = "候補を 1 つ前へ（henkanBackward）。",
  },
  {
    id = "O-x-back",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "x" },
    expect = { "I_POINT" },
    note = "最初の候補で x を押すと ▽ に戻る。",
  },
  {
    id = "O-x-register-keys",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "x" },
    expect = { "I_POINT" },
    note = "上と同じ（x の行を分けて記録するため）。",
  },
  {
    id = "O-nl",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-j>" },
    expect = { "I_DIRECT" },
    note = "読み かん を確定。",
  },
  {
    id = "O-cg",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-g>" },
    expect = { "I_DIRECT" },
    note = "読みを捨てる（取り消し）。",
  },
  {
    id = "O-bs",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<BS>" },
    expect = { "I_POINT" },
    note = "読みの最後の 1 文字を削る。",
  },
  {
    id = "O-bs-empty",
    keys = { "<Plug>(skkeleton-enable)", "K", "<BS>" },
    expect = { "I_ROMAJI" },
    note = "K の打ちかけから始めると、読みはまだ無い。",
  },
  {
    id = "O-guard",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<S-Tab>" },
    expect = { "I_DIRECT" },
    note = "バッファは かん + タブ。guard が確定してからキーを流す。",
  },
  {
    id = "O-mouse",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "I_POINT" },
    note = "マウスの観測（同じウィンドウのクリック）は 04 では取っていない。events.md O10 と keys.md §5 を根拠にする。",
    uncertain = true,
  },
  {
    id = "O-wheel",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "I_POINT" },
    note = "ホイールは pre-edit が残る（keys.md §5）。04 では取っていない。",
    uncertain = true,
  },
  {
    id = "O-paste",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "I_POINT" },
    note = "貼り付けの観測は 04 では取っていない（events.md #125 の記録を使う）。",
    uncertain = true,
  },
  {
    id = "O-completion-open",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>" },
    expect = { "IC" },
    note = "complete=.,w と、上の行に あいうえお。mode=ic、preedit=\"\"、バッファに候補が入る。",
  },
  {
    id = "O-completion-next",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-n>" },
    expect = { "IC" },
    note = "候補を次へ。mode=ic のまま。",
  },
  {
    id = "O-completion-accept",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-y>" },
    expect = { "I_DIRECT" },
    note = "<C-y> で候補を受け入れて insert に戻る。",
  },
  {
    id = "O-completion-esc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<Esc>" },
    expect = { "N_OFF" },
    note = "補完のメニューを抜けて normal。enabled=false。",
  },
  {
    id = "O-completion-c-e",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-e>" },
    expect = { "I_DIRECT" },
    note = "<C-e> で候補を取り消して元の行に戻る。",
  },
  {
    id = "O-space-no-candidate",
    keys = { "<Plug>(skkeleton-enable)", "N", "u", "r", "u", "<Space>" },
    expect = { "P_PROMPT" },
    note = "辞書に ぬる が無いので辞書登録のプロンプトに入る（mode=c、cmdtype=@）。外側の pre-edit は凍結。",
  },
  {
    id = "O12",
    keys = { "<Plug>(skkeleton-enable)", "N", "u", "r", "u", "<Space>" },
    expect = { "P_PROMPT" },
    note = "events.md O12。プロンプトで <Esc> を取り消すと ▽ に戻る。",
  },
  {
    id = "O4",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "0" },
    expect = { "I_DIRECT" },
    note = "events.md O4。<C-o>0 でカーソルだけ動き、元の位置に確定する。",
    uncertain = true,
  },
  {
    id = "O5",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "x" },
    expect = { "I_DIRECT" },
    note = "events.md O5。<C-o>x でバッファが変わり、読みは捨てられる。",
    uncertain = true,
  },
  {
    id = "O13",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-w>" },
    expect = { "I_DIRECT" },
    note = "events.md O13 は WinLeave の観測。キーの列はモデルの経路を通すための近い列。",
    uncertain = true,
  },
  {
    id = "O10",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "I_POINT" },
    note = "events.md O10（マウスで visual）。04 では取っていない。",
    uncertain = true,
  },
  {
    id = "O15",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "I_POINT" },
    note = "events.md O15（API）。04 では disable / toggle の出口をコードと突き合わせただけ。",
    uncertain = true,
  },
  {
    id = "O16",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "I_POINT" },
    note = "events.md O16（CompleteDone / TextChangedP）。ずれが無ければ何もしない。",
    uncertain = true,
  },
  {
    id = "O152",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Esc>", "i" },
    expect = { "I_DIRECT" },
    config = { keepState = true },
    note = "keepState=true のときは、<Esc> のあとの最初の InsertEnter で有効に戻る（#152）。既定は false。",
    uncertain = true,
  },
}

-- NOTES（作者の手元の data.js）の再現キー列を、モデルで再生する。
-- keys は M.events の keys に出てくる表記。expect は再生したあとの状態クラス。
M.replays = {
  {
    id = "replay.ctrl-r",
    title = "Kan → <C-r>a（NOTES の大きい未考慮 1）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-r>a" },
    expect = { "I_DIRECT" },
    note = "読みは確定されずに捨てられる（バッファはレジスタの内容）。",
  },
  {
    id = "replay.ctrl-w",
    title = "a Kan → <C-w>（NOTES の大きい未考慮 3）",
    keys = { "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<C-w>" },
    expect = { "I_DIRECT" },
    note = "確定済みの あ が消え、読みも残らない。",
  },
  {
    id = "replay.ctrl-o-v",
    title = "Kan → <C-o>v → <Esc>（NOTES の大きい未考慮 4）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>v", "<Esc>" },
    expect = { "I_POINT" },
    note = "visual の間は pre-edit が描かれたまま。抜けると insert に戻り、pre-edit は残る。",
  },
  {
    id = "replay.ctrl-o-R",
    title = "Kan → <C-o>R（NOTES の大きい未考慮 4）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>R" },
    expect = { "R_OFF" },
    note = "読みを確定して無効化する（観測）。",
  },
  {
    id = "replay.insert",
    title = "Kan → <Insert>（NOTES の考慮されていたもの）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Insert>" },
    expect = { "R_OFF" },
    note = "読みを確定して無効化する（#156 と同じ）。",
  },
  {
    id = "replay.ctrl-n",
    title = "Kan → <C-n>（NOTES の大きい未考慮 6）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>" },
    expect = { "IC" },
    note = "組み込みの補完に入る。読みは捨てられる。",
  },
  {
    id = "replay.ctrl-o-l",
    title = "Kan → <C-o>l（NOTES の考慮されていたもの）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "l" },
    expect = { "I_POINT" },
    note = "カーソルが動かなければ pre-edit が残る。",
  },
  {
    id = "replay.ctrl-o-x",
    title = "Kan → <C-o>x（#199）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "x" },
    expect = { "I_DIRECT" },
    note = "バッファが変わると読みは捨てられる。",
  },
  {
    id = "replay.ctrl-o-colon",
    title = "Kan → <C-o>:<Esc>（NOTES の考慮されていたもの）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>:<Esc>" },
    expect = { "I_POINT" },
    note = "cmdline から戻っても pre-edit が残る（#86）。",
  },
  {
    id = "replay.esc",
    title = "Kan → <Esc>（考慮されていたもの）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Esc>" },
    expect = { "N_OFF" },
    note = "読みを確定して無効化する。",
  },
}

-- 対象外のもの（このモデルでは遷移にしない。理由と、扱うタスクを書く）
M.out_of_scope = {
  {
    id = "oos.cmdline",
    what = "cmdline（c / cr）の中の遷移",
    why = "07a（#187）のモデル。ここでは <C-o>: の戻り先だけを書いた。",
    refs = { "#187" },
    keys = {},
  },
  {
    id = "oos.terminal",
    what = "terminal（t / nt）の遷移",
    why = "07b（#188）。",
    refs = { "#188" },
    keys = {},
  },
  {
    id = "oos.register",
    what = "辞書登録のプロンプトの中の遷移（入力の書き換え、入れ子、履歴）",
    why = "07c（#189）。ここでは入口と出口の境界だけを書いた。",
    refs = { "#189" },
    keys = {},
  },
  {
    id = "oos.completion",
    what = "補完のメニューの中の動き（blink.cmp の accept、候補の並び）",
    why = "07d（#190）。ここでは入口と出口の境界だけを書いた。",
    refs = { "#190" },
    keys = {},
  },
  {
    id = "oos.macro",
    what = "マクロと `.` の繰り返し",
    why = "07f（#192）。",
    refs = { "#192" },
    keys = {},
  },
  {
    id = "oos.other",
    what = "貼り付け・マウス・ホイール・`.` 以外のその他の入力",
    why = "07e（#191）。貼り付けとマウスは、insert に戻る境界だけこのモデルに書いた。",
    refs = { "#191" },
    keys = {},
  },
  {
    id = "oos.mapped_keys",
    what = "g:skkeleton#mapped_keys で利用者が足すキー",
    why = "割り当てる関数しだいで、モデルのイベントが決まらない。",
    refs = { "keys.md §2" },
    keys = {},
  },
  {
    id = "oos.blink_keys",
    what = "blink.cmp のキー割り当て（<CR> を含む）",
    why = "skkeleton の外（#190、keys.md §5 補足）。eggLikeNewline の <CR> は 07d。",
    refs = { "#190" },
    keys = {},
  },
  {
    id = "oos.alt_meta",
    what = "<M-a> などの Alt / Meta 付きのキー",
    why = "端末では <Esc> と文字の 2 キーになり、1 キーの遷移として扱えない（#155）。",
    refs = { "#155" },
    keys = { "<M-a>" },
  },
  {
    id = "oos.vimleave",
    what = "VimLeavePre",
    why = "ユーザー辞書を保存するだけで、入力状態を変えない（events.md）。",
    refs = { "events.md" },
    keys = {},
  },
}

-- 完了の条件（キーとイベントの棚卸し）を機械で確かめるための一覧。
--
-- keys は keys.md §1 の 102 個（表記は keys.md に合わせる）。§2・§5 のうち
-- このモデルで扱うキーは events に入っている。
M.inventory = {
  keys = {
    -- §1 の 102 個（map.lua:13-23 の default_keys と同じ並び）
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s",
    "t", "u", "v", "w", "x", "y", "z",
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S",
    "T", "U", "V", "W", "X", "Y", "Z",
    "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    "!", "\"", "#", "$", "%", "&", "'", "(", ")",
    ",", ".", "/", ";", ":", "]", "@", "[", "-", "^", "\\",
    ">", "?", "_", "+", "*", "}", "`", "{", "=", "~",
    "<lt>", "<Bar>", "<BS>", "<C-h>", "<CR>", "<Space>", "<C-q>", "<C-j>", "<C-g>", "<Esc>",
  },
  -- 01 の表のほか、events.md と keys.md §4・§5 に出てくる、このモデルで扱うキー
  other_keys = {
    "<C-o>", "<C-c>", "<C-\\><C-n>", "<C-r>", "<C-r><C-r>", "<C-r>=", "<C-v>", "<C-k>", "<C-t>",
    "<Tab>", "<C-w>", "<C-u>", "<C-a>", "<C-@>", "<C-n>", "<C-p>", "<C-x>", "<C-x><C-n>",
    "<C-y>", "<C-e>", "<C-o>:", "<C-o>v", "<C-o>V", "<C-o>R", "<C-o><C-v>",
    "<Left>", "<Right>", "<Up>", "<Down>", "<Home>", "<End>", "<PageUp>", "<PageDown>",
    "<Del>", "<S-Tab>", "<S-Left>", "<S-Right>", "<S-Up>", "<S-Down>", "<C-Left>", "<C-Right>",
    "<F5>", "<C-.>", "<S-CR>",
    "<LeftMouse>", "<RightMouse>", "<DragRight>", "<2-LeftMouse>", "<3-LeftMouse>",
    "<ScrollWheelUp>", "<ScrollWheelDown>",
    "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-disable)", "<Plug>(skkeleton-toggle)",
    "<Paste>", "<Insert>",
  },
  -- events.md の autocmd と API のうち、i / n / v / R に関わるもの
  events = {
    { id = "ModeChanged", covered_by = {
      "cleanup_escape", "safestate", "modechanged_i_to_R", "ni_return_keep", "ni_return_commit",
      "ni_return_drop", "ctrl_o_v", "ctrl_o_R", "mouse_select", "insert_key",
    } },
    { id = "SafeState", covered_by = { "safestate" } },
    { id = "CmdlineLeave", out_of_scope = "07a（#187）" },
    { id = "WinLeave", covered_by = { "winleave" } },
    { id = "BufLeave", covered_by = { "bufleave" } },
    { id = "TextChangedI", covered_by = { "stale" } },
    { id = "TextChangedP", covered_by = { "stale" } },
    { id = "CursorMovedI", covered_by = { "stale", "mouse_click" } },
    { id = "CmdlineChanged", out_of_scope = "07a（#187）" },
    { id = "CompleteDone", covered_by = { "stale" } },
    { id = "VimLeavePre", out_of_scope = "入力状態を変えない（events.md O14）" },
    { id = "User skkeleton-handled", out_of_scope = "表示だけ（07d #190、インジケータ）" },
    { id = "User skkeleton-enable-post", out_of_scope = "表示だけ（07d #190、インジケータ）" },
    { id = "User skkeleton-disable-post", out_of_scope = "表示だけ（07d #190、インジケータ）" },
    { id = "User BlinkCmpMenuOpen", out_of_scope = "07d（#190）" },
    { id = "User BlinkCmpMenuClose", out_of_scope = "07d（#190）" },
    { id = "WinEnter", out_of_scope = "07c（#189、host.input のフレーム）" },
    { id = "CmdlineEnter", out_of_scope = "07c（#189、host.input のフレーム）" },
    { id = "InsertEnter", covered_by = { "insert_enter" } },
    { id = "enable", covered_by = { "enable" } },
    { id = "disable", covered_by = { "disable" } },
    { id = "toggle", covered_by = { "toggle" } },
    { id = "complete", out_of_scope = "07d（#190）" },
    { id = "commit_preedit", covered_by = { "guard_special" } },
    { id = "on_bytes", covered_by = { "stale" } },
    { id = "vim.on_key", covered_by = { "guard_special", "ctrl_c" } },
    { id = "vim.paste", covered_by = { "paste" } },
    { id = "render.finish", out_of_scope = "確定文字列を流したあとの描画だけ（events.md）" },
  },
}

-- 性質（GLOSSARY の P1–P15）。このモデルで決められるかどうかも書く。
-- decided = false の性質は、状態クラスに持っていない層（表示・マッピングの数・cmdline・terminal）が要る。
M.properties = {
  { id = "P1", title = "読みが黙って消えない", decided = true, kind = "no_silent_loss" },
  { id = "P2", title = "pre-edit は 1 つだけで、置き場所が正しく、中身が state と一致する", decided = false,
    why = "extmark の数と位置を状態クラスに持っていない（05 の探索器と 06 の比較で見る）。" },
  { id = "P3", title = "n / v / s / R では、状態とマッピングが元に戻っている", decided = true, kind = "return_to_normal" },
  { id = "P4", title = "cmdline / terminal を抜けたら、何も残っていない", decided = false,
    why = "cmdline は 07a（#187）、terminal は 07b（#188）。" },
  { id = "P5", title = "1 つのキーを二重に処理しない", decided = true, kind = "no_double_commit" },
  { id = "P6", title = "決定的に振る舞う（タイミングに左右されるものには印を付ける）", decided = false,
    why = "モデルの分岐はタイミングではなく、辞書・バッファ・設定という持っていない条件。"
      .. "分かれる組は検査の最後に一覧で出す。" },
  { id = "P7", title = "片付けは何度やっても同じ結果になる", decided = false,
    why = "同じ片付けを 2 度流す遷移の対を持っていない（reset_state の自己遷移を足せば見られる）。" },
  { id = "P8", title = "enable のあと disable すると元に戻る", decided = true, kind = "recoverable" },
  { id = "P9", title = "辞書登録の入れ子から漏れずに戻れる", decided = false, why = "07c（#189）。" },
  { id = "P10", title = "同じ読みを 2 度確定しない", decided = true, kind = "no_double_commit" },
  { id = "P11", title = "g:skkeleton#mode が中の状態と一致する", decided = false,
    why = "かなモード（hira / kata / ...）を状態クラスに持っていない。" },
  { id = "P12", title = "マッピングの範囲が正しい", decided = false,
    why = "マッピングの数と範囲を状態クラスに持っていない。出口の restore_mapping だけ P3 で見る。" },
  { id = "P13", title = "pending が片付く", decided = true, kind = "transient_progress" },
  { id = "P14", title = "terminal の Ctrl を正しく扱う", decided = false, why = "07b（#188）。" },
  { id = "P15", title = "state が空でないなら、pre-edit が見えている", decided = false,
    why = "表示（extmark）を状態クラスに持っていない。" },
}

-- 既知の破れ（性質の検査で出るが、issue にしてあるもの）。
-- transition は遷移の id。refs は issue。
M.known = {
  { property = "P1", transition = "t.I_ROMAJI.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_ROMAJI.completion_open", refs = { "#18", "#19", "#190" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_a", refs = { "keys.md §6" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_at", refs = { "#56", "keys.md §6" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_k", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_r", refs = { "#8", "#12", "#20" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_t", refs = { "keys.md §6" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_u", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_v", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_w", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_ROMAJI.enable", refs = { "#210" } },
  { property = "P1", transition = "t.I_ROMAJI.key_l", refs = { "#67", "06 の観測" } },
  { property = "P1", transition = "t.I_POINT.enable", refs = { "#210" } },
  { property = "P1", transition = "t.I_SELECT.enable", refs = { "#210" } },
  { property = "P1", transition = "t.I_ROMAJI.stale.buffer", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_ROMAJI.tab", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_ROMAJI.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_POINT.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_POINT.ctrl_a", refs = { "keys.md §6" } },
  { property = "P1", transition = "t.I_POINT.ctrl_at", refs = { "#56", "keys.md §6" } },
  { property = "P1", transition = "t.I_POINT.ctrl_k", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.ctrl_r", refs = { "#8", "#12", "#20" } },
  { property = "P1", transition = "t.I_POINT.ctrl_t", refs = { "keys.md §6" } },
  { property = "P1", transition = "t.I_POINT.ctrl_u", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.ctrl_v", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.ctrl_w", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.stale.buffer", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.tab", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_SELECT.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_SELECT.completion_open", refs = { "#18", "#19", "#190" } },
  { property = "P1", transition = "t.I_POINT.completion_open", refs = { "#18", "#19", "#190" } },
  { property = "P1", transition = "t.I_SELECT.stale.buffer", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_SELECT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.NI_POINT.return_drop", refs = { "#199" } },
  { property = "P1", transition = "t.NI_POINT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.NI_SELECT.return_drop", refs = { "#199" } },
  { property = "P1", transition = "t.NI_SELECT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.V_PRE_POINT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.V_PRE_SELECT.winleave", refs = { "#169" } },
}

-- 作者の判断（10 点）と、このモデルでの反映先（#204 の 2026-11-06 のコメント）
M.decisions = {
  {
    id = 1,
    title = "I_OFF（insert・無効）を足す",
    decision = "足す。無効な insert は、有効な insert と同じキーで結果が違うので分ける。",
    reflected_in = { "I_OFF" },
  },
  {
    id = 2,
    title = "V_IDLE（visual・有効・pre-edit 無し）を足す",
    decision = "足す。visual で有効のままなのは、N_OFF と戻ったあとの結果が違うので分ける。",
    reflected_in = { "V_IDLE", "O-ctrl-o-v-direct" },
  },
  {
    id = 3,
    title = "N_KEEP はクラスにしない",
    decision = "N_OFF のまま、遷移の guard の config.keepState で表す。",
    reflected_in = { "N_OFF", "t.N_OFF.insert_enter.keepstate", "t.I_DIRECT.esc.keepstate" },
  },
  {
    id = 4,
    title = "NI / V_PRE / P_PROMPT の粒度",
    decision = "人が読むクラスは 1 つのまま、抱えている相（direct / point / select）を属性で持つ。"
      .. "モデルの中で NI_POINT などに分けるのは可。仕様書では NI（point）のように書く。",
    reflected_in = { "NI_DIRECT", "NI_POINT", "NI_SELECT", "V_PRE_POINT", "V_PRE_SELECT",
      "P_PROMPT_POINT", "P_PROMPT_SELECT" },
  },
  {
    id = 5,
    title = "N_LOST は状態から外す",
    decision = "読みが消えるのは遷移の結果なので、effects の drop と P1 の破れで表す。"
      .. "GLOSSARY と events.md も合わせる。",
    reflected_in = { "M.known（P1）", "semantics/GLOSSARY.md", "semantics/inventory/events.md" },
  },
  {
    id = 6,
    title = "「ローマ字の打ちかけ」は I_ROMAJI に改名",
    decision = "pending は render.is_pending() の意味だけに使う。",
    reflected_in = { "I_ROMAJI" },
  },
  {
    id = 7,
    title = "▽ と ▽* は今はまとめる",
    decision = "06 で結果が割れたら分ける。",
    reflected_in = { "I_POINT" },
  },
  {
    id = 8,
    title = "R_MID は観測のクラスから外す",
    decision = "途中の状態（transient）としてだけ残す。",
    reflected_in = { "R_MID" },
  },
  {
    id = 9,
    title = "effects に install_mapping と save_mapping を足す",
    decision = "GLOSSARY にも足す。",
    reflected_in = { "semantics/GLOSSARY.md", "t.N_OFF.enable", "t.I_OFF.enable", "t.N_OFF.insert_enter.keepstate" },
  },
  {
    id = 10,
    title = "V_PRE の意味",
    decision = "<C-o>v で残り続ける状態の意味にする。マウスのドラッグで ModeChanged の確定より前に"
      .. "一瞬残るもの（events.md の O18）は、途中の状態として扱う。base を rebase して events.md も合わせる。",
    reflected_in = { "V_PRE_POINT", "V_PRE_SELECT", "semantics/inventory/events.md" },
  },
}


-- 06 の観測を、遷移の observed 欄に足す。04 の observed はそのまま残す。
do
  local by_transition = {}
  for _, t in ipairs(M.transitions) do
    by_transition[t.id] = t
  end
  for _, p in ipairs(M.probes or {}) do
    local t = by_transition[p.transition]
    if t then
      local seen = false
      for _, id in ipairs(t.observed) do
        if id == p.id then
          seen = true
        end
      end
      if not seen then
        t.observed[#t.observed + 1] = p.id
      end
    end
  end
end


-- 06 の観測（#186）。semantics/compare/probe.lua が、状態ごとの前置きを流してから
-- イベントのキーを 1 つ打ち、落ち着いたあとの状態クラスを読んだもの。1 行が 1 つの観測で、
-- keys を流したときに transition の遷移を通ることを model_check が確かめる。
-- 前置きは 1 キーずつに開いてある。イベントのキー（`<C-o>v` など）は events.keys と
-- 同じまとまりで書いてある。world が keepstate の観測だけ config を持つ。
M.probes = {
  { id = "P.t.IC.completion_accept.C-y", transition = "t.IC.completion_accept.C-y", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-y>" }, expect = { "I_DIRECT" } },
  { id = "P.t.IC.completion_next", transition = "t.IC.completion_next", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-n>" }, expect = { "IC" } },
  { id = "P.t.IC.ctrl_c", transition = "t.IC.ctrl_c", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-c>" }, expect = { "N_OFF" } },
  { id = "P.t.IC.esc", transition = "t.IC.esc", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.I_DIRECT.bs", transition = "t.I_DIRECT.bs", keys = { "i", "<Plug>(skkeleton-enable)", "<BS>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.cg", transition = "t.I_DIRECT.cg", keys = { "i", "<Plug>(skkeleton-enable)", "<C-g>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.char.keep", transition = "t.I_DIRECT.char.keep", keys = { "i", "<Plug>(skkeleton-enable)", "a" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.char.romaji", transition = "t.I_DIRECT.char.romaji", keys = { "i", "<Plug>(skkeleton-enable)", "k" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_DIRECT.char_shift", transition = "t.I_DIRECT.char_shift", keys = { "i", "<Plug>(skkeleton-enable)", "K" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_DIRECT.char_shift.point", transition = "t.I_DIRECT.char_shift.point", keys = { "i", "<Plug>(skkeleton-enable)", "A" }, expect = { "I_POINT" } },
  { id = "P.t.I_DIRECT.completion_accept", transition = "t.I_DIRECT.completion_accept", keys = { "i", "<Plug>(skkeleton-enable)", "<C-y>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.completion_open", transition = "t.I_DIRECT.completion_open", keys = { "i", "<Plug>(skkeleton-enable)", "<C-n>" }, expect = { "IC" } },
  { id = "P.t.I_DIRECT.cr", transition = "t.I_DIRECT.cr", keys = { "i", "<Plug>(skkeleton-enable)", "<CR>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.ctrl_c", transition = "t.I_DIRECT.ctrl_c", keys = { "i", "<Plug>(skkeleton-enable)", "<C-c>" }, expect = { "N_OFF" } },
  { id = "P.t.I_DIRECT.ctrl_k", transition = "t.I_DIRECT.ctrl_k", keys = { "i", "<Plug>(skkeleton-enable)", "<C-k>a:" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.ctrl_o", transition = "t.I_DIRECT.ctrl_o", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>" }, expect = { "NI" } },
  { id = "P.t.I_DIRECT.ctrl_o_R", transition = "t.I_DIRECT.ctrl_o_R", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>R" }, expect = { "R_OFF" } },
  { id = "P.t.I_DIRECT.ctrl_o_colon", transition = "t.I_DIRECT.ctrl_o_colon", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>:<Esc>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.ctrl_o_v", transition = "t.I_DIRECT.ctrl_o_v", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>v" }, expect = { "V_IDLE" } },
  { id = "P.t.I_DIRECT.ctrl_r", transition = "t.I_DIRECT.ctrl_r", keys = { "i", "<Plug>(skkeleton-enable)", "<C-r>a" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.ctrl_t", transition = "t.I_DIRECT.ctrl_t", keys = { "i", "<Plug>(skkeleton-enable)", "<C-t>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.ctrl_u", transition = "t.I_DIRECT.ctrl_u", keys = { "i", "<Plug>(skkeleton-enable)", "<C-u>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.ctrl_v", transition = "t.I_DIRECT.ctrl_v", keys = { "i", "<Plug>(skkeleton-enable)", "<C-v>065" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.ctrl_w", transition = "t.I_DIRECT.ctrl_w", keys = { "i", "<Plug>(skkeleton-enable)", "<C-w>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.disable", transition = "t.I_DIRECT.disable", keys = { "i", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-disable)" }, expect = { "I_OFF" } },
  { id = "P.t.I_DIRECT.enable", transition = "t.I_DIRECT.enable", keys = { "i", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-enable)" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.esc", transition = "t.I_DIRECT.esc", keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.I_DIRECT.esc.keepstate", transition = "t.I_DIRECT.esc.keepstate", keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>" }, expect = { "N_OFF" }, config = { keepState = true } },
  { id = "P.t.I_DIRECT.guard_special", transition = "t.I_DIRECT.guard_special", keys = { "i", "<Plug>(skkeleton-enable)", "<S-Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.insert_key", transition = "t.I_DIRECT.insert_key", keys = { "i", "<Plug>(skkeleton-enable)", "<Insert>" }, expect = { "R_OFF" } },
  { id = "P.t.I_DIRECT.key_L", transition = "t.I_DIRECT.key_L", keys = { "i", "<Plug>(skkeleton-enable)", "L" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.key_X", transition = "t.I_DIRECT.key_X", keys = { "i", "<Plug>(skkeleton-enable)", "X" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_DIRECT.key_cq", transition = "t.I_DIRECT.key_cq", keys = { "i", "<Plug>(skkeleton-enable)", "<C-q>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.key_gt", transition = "t.I_DIRECT.key_gt", keys = { "i", "<Plug>(skkeleton-enable)", ">" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.key_l", transition = "t.I_DIRECT.key_l", keys = { "i", "<Plug>(skkeleton-enable)", "l" }, expect = { "I_OFF" } },
  { id = "P.t.I_DIRECT.key_q", transition = "t.I_DIRECT.key_q", keys = { "i", "<Plug>(skkeleton-enable)", "q" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.key_semicolon", transition = "t.I_DIRECT.key_semicolon", keys = { "i", "<Plug>(skkeleton-enable)", ";" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_DIRECT.key_slash", transition = "t.I_DIRECT.key_slash", keys = { "i", "<Plug>(skkeleton-enable)", "/" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_DIRECT.nl", transition = "t.I_DIRECT.nl", keys = { "i", "<Plug>(skkeleton-enable)", "<C-j>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.space", transition = "t.I_DIRECT.space", keys = { "i", "<Plug>(skkeleton-enable)", "<Space>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.tab", transition = "t.I_DIRECT.tab", keys = { "i", "<Plug>(skkeleton-enable)", "<Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_DIRECT.toggle", transition = "t.I_DIRECT.toggle", keys = { "i", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-toggle)" }, expect = { "I_OFF" } },
  { id = "P.t.I_OFF.esc", transition = "t.I_OFF.esc", keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>", "i", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.I_OFF.insert_key", transition = "t.I_OFF.insert_key", keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>", "i", "<Insert>" }, expect = { "R_OFF" } },
  { id = "P.t.I_POINT.bs", transition = "t.I_POINT.bs", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<BS>" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.bs.empty", transition = "t.I_POINT.bs.empty", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "<BS>" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_POINT.cg", transition = "t.I_POINT.cg", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-g>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.char", transition = "t.I_POINT.char", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "a" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.char_shift", transition = "t.I_POINT.char_shift", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "K" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.completion_accept", transition = "t.I_POINT.completion_accept", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-y>" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.completion_open", transition = "t.I_POINT.completion_open", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>" }, expect = { "IC" } },
  { id = "P.t.I_POINT.cr", transition = "t.I_POINT.cr", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<CR>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.ctrl_c", transition = "t.I_POINT.ctrl_c", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-c>" }, expect = { "N_OFF" } },
  { id = "P.t.I_POINT.ctrl_k", transition = "t.I_POINT.ctrl_k", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-k>a:" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.ctrl_o", transition = "t.I_POINT.ctrl_o", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>" }, expect = { "NI" } },
  { id = "P.t.I_POINT.ctrl_o_R", transition = "t.I_POINT.ctrl_o_R", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>R" }, expect = { "R_OFF" } },
  { id = "P.t.I_POINT.ctrl_o_colon", transition = "t.I_POINT.ctrl_o_colon", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>:<Esc>" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.ctrl_o_v", transition = "t.I_POINT.ctrl_o_v", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>v" }, expect = { "V_PRE" } },
  { id = "P.t.I_POINT.ctrl_r", transition = "t.I_POINT.ctrl_r", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-r>a" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.ctrl_t", transition = "t.I_POINT.ctrl_t", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-t>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.ctrl_u", transition = "t.I_POINT.ctrl_u", keys = { "i", "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<C-u>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.ctrl_u.keep", transition = "t.I_POINT.ctrl_u.keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-u>" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.ctrl_v", transition = "t.I_POINT.ctrl_v", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-v>065" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.ctrl_w", transition = "t.I_POINT.ctrl_w", keys = { "i", "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<C-w>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.ctrl_w.keep", transition = "t.I_POINT.ctrl_w.keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-w>" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.disable", transition = "t.I_POINT.disable", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Plug>(skkeleton-disable)" }, expect = { "I_OFF" } },
  { id = "P.t.I_POINT.enable", transition = "t.I_POINT.enable", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Plug>(skkeleton-enable)" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.esc", transition = "t.I_POINT.esc", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.I_POINT.esc.keepstate", transition = "t.I_POINT.esc.keepstate", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Esc>" }, expect = { "N_OFF" }, config = { keepState = true } },
  { id = "P.t.I_POINT.guard_special", transition = "t.I_POINT.guard_special", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<S-Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.insert_key", transition = "t.I_POINT.insert_key", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Insert>" }, expect = { "R_OFF" } },
  { id = "P.t.I_POINT.key_L", transition = "t.I_POINT.key_L", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "L" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.key_X", transition = "t.I_POINT.key_X", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "X" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.key_cq", transition = "t.I_POINT.key_cq", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-q>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.key_l", transition = "t.I_POINT.key_l", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "l" }, expect = { "I_OFF" } },
  { id = "P.t.I_POINT.key_q", transition = "t.I_POINT.key_q", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "q" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.key_semicolon", transition = "t.I_POINT.key_semicolon", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", ";" }, expect = { "I_POINT" } },
  { id = "P.t.I_POINT.nl", transition = "t.I_POINT.nl", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-j>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.space.register", transition = "t.I_POINT.space.register", keys = { "i", "<Plug>(skkeleton-enable)", "N", "u", "r", "u", "<Space>" }, expect = { "P_PROMPT" } },
  { id = "P.t.I_POINT.space.select", transition = "t.I_POINT.space.select", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>" }, expect = { "I_SELECT" } },
  { id = "P.t.I_POINT.tab", transition = "t.I_POINT.tab", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_POINT.toggle", transition = "t.I_POINT.toggle", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Plug>(skkeleton-toggle)" }, expect = { "I_OFF" } },
  { id = "P.t.I_ROMAJI.bs", transition = "t.I_ROMAJI.bs", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<BS>" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_ROMAJI.bs.empty", transition = "t.I_ROMAJI.bs.empty", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<BS>", "<BS>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.cg", transition = "t.I_ROMAJI.cg", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-g>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.char.commit", transition = "t.I_ROMAJI.char.commit", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a" }, expect = { "I_POINT" } },
  { id = "P.t.I_ROMAJI.char.keep", transition = "t.I_ROMAJI.char.keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<BS>", "k" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_ROMAJI.char_shift", transition = "t.I_ROMAJI.char_shift", keys = { "i", "<Plug>(skkeleton-enable)", "K", "K" }, expect = { "I_POINT" } },
  { id = "P.t.I_ROMAJI.completion_accept", transition = "t.I_ROMAJI.completion_accept", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-y>" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_ROMAJI.completion_open", transition = "t.I_ROMAJI.completion_open", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-n>" }, expect = { "IC" } },
  { id = "P.t.I_ROMAJI.cr", transition = "t.I_ROMAJI.cr", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<CR>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.ctrl_c", transition = "t.I_ROMAJI.ctrl_c", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-c>" }, expect = { "N_OFF" } },
  { id = "P.t.I_ROMAJI.ctrl_k", transition = "t.I_ROMAJI.ctrl_k", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-k>a:" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.ctrl_o", transition = "t.I_ROMAJI.ctrl_o", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-o>" }, expect = { "NI" } },
  { id = "P.t.I_ROMAJI.ctrl_o_R", transition = "t.I_ROMAJI.ctrl_o_R", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-o>R" }, expect = { "R_OFF" } },
  { id = "P.t.I_ROMAJI.ctrl_o_colon", transition = "t.I_ROMAJI.ctrl_o_colon", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-o>:<Esc>" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_ROMAJI.ctrl_o_v", transition = "t.I_ROMAJI.ctrl_o_v", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-o>v" }, expect = { "V_PRE" } },
  { id = "P.t.I_ROMAJI.ctrl_r", transition = "t.I_ROMAJI.ctrl_r", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-r>a" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.ctrl_t", transition = "t.I_ROMAJI.ctrl_t", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-t>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.ctrl_u", transition = "t.I_ROMAJI.ctrl_u", keys = { "i", "<Plug>(skkeleton-enable)", "a", "K", "<C-u>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.ctrl_u.keep", transition = "t.I_ROMAJI.ctrl_u.keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-u>" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_ROMAJI.ctrl_v", transition = "t.I_ROMAJI.ctrl_v", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-v>065" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.ctrl_w", transition = "t.I_ROMAJI.ctrl_w", keys = { "i", "<Plug>(skkeleton-enable)", "a", "K", "<C-w>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.ctrl_w.keep", transition = "t.I_ROMAJI.ctrl_w.keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-w>" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_ROMAJI.disable", transition = "t.I_ROMAJI.disable", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<Plug>(skkeleton-disable)" }, expect = { "I_OFF" } },
  { id = "P.t.I_ROMAJI.enable", transition = "t.I_ROMAJI.enable", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<Plug>(skkeleton-enable)" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.esc", transition = "t.I_ROMAJI.esc", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.I_ROMAJI.esc.keepstate", transition = "t.I_ROMAJI.esc.keepstate", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<Esc>" }, expect = { "N_OFF" }, config = { keepState = true } },
  { id = "P.t.I_ROMAJI.guard_special", transition = "t.I_ROMAJI.guard_special", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<S-Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.insert_key", transition = "t.I_ROMAJI.insert_key", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<Insert>" }, expect = { "R_OFF" } },
  { id = "P.t.I_ROMAJI.key_l", transition = "t.I_ROMAJI.key_l", keys = { "i", "<Plug>(skkeleton-enable)", "K", "l" }, expect = { "I_OFF" } },
  { id = "P.t.I_ROMAJI.nl", transition = "t.I_ROMAJI.nl", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<C-j>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.tab", transition = "t.I_ROMAJI.tab", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_ROMAJI.toggle", transition = "t.I_ROMAJI.toggle", keys = { "i", "<Plug>(skkeleton-enable)", "K", "<Plug>(skkeleton-toggle)" }, expect = { "I_OFF" } },
  { id = "P.t.I_SELECT.bs", transition = "t.I_SELECT.bs", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<BS>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.cg", transition = "t.I_SELECT.cg", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-g>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.char.commit", transition = "t.I_SELECT.char.commit", keys = { "i", "<Plug>(skkeleton-enable)", "N", "i", "h", "o", "n", "<Space>", "a" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.char.commit_romaji", transition = "t.I_SELECT.char.commit_romaji", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "z" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_SELECT.char_shift", transition = "t.I_SELECT.char_shift", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "K" }, expect = { "I_ROMAJI" } },
  { id = "P.t.I_SELECT.completion_accept", transition = "t.I_SELECT.completion_accept", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-y>" }, expect = { "I_SELECT" } },
  { id = "P.t.I_SELECT.completion_open", transition = "t.I_SELECT.completion_open", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-n>" }, expect = { "IC" } },
  { id = "P.t.I_SELECT.cr", transition = "t.I_SELECT.cr", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<CR>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.ctrl_c", transition = "t.I_SELECT.ctrl_c", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-c>" }, expect = { "N_OFF" } },
  { id = "P.t.I_SELECT.ctrl_k", transition = "t.I_SELECT.ctrl_k", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-k>a:" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.ctrl_o", transition = "t.I_SELECT.ctrl_o", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>" }, expect = { "NI" } },
  { id = "P.t.I_SELECT.ctrl_o_R", transition = "t.I_SELECT.ctrl_o_R", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>R" }, expect = { "R_OFF" } },
  { id = "P.t.I_SELECT.ctrl_o_colon", transition = "t.I_SELECT.ctrl_o_colon", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>:<Esc>" }, expect = { "I_SELECT" } },
  { id = "P.t.I_SELECT.ctrl_o_v", transition = "t.I_SELECT.ctrl_o_v", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>v" }, expect = { "V_PRE" } },
  { id = "P.t.I_SELECT.ctrl_r", transition = "t.I_SELECT.ctrl_r", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-r>a" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.ctrl_t", transition = "t.I_SELECT.ctrl_t", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-t>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.ctrl_u", transition = "t.I_SELECT.ctrl_u", keys = { "i", "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<Space>", "<C-u>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.ctrl_u.keep", transition = "t.I_SELECT.ctrl_u.keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-u>" }, expect = { "I_SELECT" } },
  { id = "P.t.I_SELECT.ctrl_v", transition = "t.I_SELECT.ctrl_v", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-v>065" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.ctrl_w", transition = "t.I_SELECT.ctrl_w", keys = { "i", "<Plug>(skkeleton-enable)", "a", "K", "a", "n", "<Space>", "<C-w>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.ctrl_w.keep", transition = "t.I_SELECT.ctrl_w.keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-w>" }, expect = { "I_SELECT" } },
  { id = "P.t.I_SELECT.disable", transition = "t.I_SELECT.disable", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Plug>(skkeleton-disable)" }, expect = { "I_OFF" } },
  { id = "P.t.I_SELECT.enable", transition = "t.I_SELECT.enable", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Plug>(skkeleton-enable)" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.esc", transition = "t.I_SELECT.esc", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.I_SELECT.esc.keepstate", transition = "t.I_SELECT.esc.keepstate", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Esc>" }, expect = { "N_OFF" }, config = { keepState = true } },
  { id = "P.t.I_SELECT.guard_special", transition = "t.I_SELECT.guard_special", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<S-Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.insert_key", transition = "t.I_SELECT.insert_key", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Insert>" }, expect = { "R_OFF" } },
  { id = "P.t.I_SELECT.key_X.purge", transition = "t.I_SELECT.key_X.purge", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "X" }, expect = { "I_SELECT" } },
  { id = "P.t.I_SELECT.key_l", transition = "t.I_SELECT.key_l", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "l" }, expect = { "I_OFF" } },
  { id = "P.t.I_SELECT.nl", transition = "t.I_SELECT.nl", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-j>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.space.next", transition = "t.I_SELECT.space.next", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Space>" }, expect = { "I_SELECT" } },
  { id = "P.t.I_SELECT.space.register", transition = "t.I_SELECT.space.register", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Space>", "<Space>", "<Space>", "<Space>", "<Space>" }, expect = { "P_PROMPT" } },
  { id = "P.t.I_SELECT.tab", transition = "t.I_SELECT.tab", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Tab>" }, expect = { "I_DIRECT" } },
  { id = "P.t.I_SELECT.toggle", transition = "t.I_SELECT.toggle", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Plug>(skkeleton-toggle)" }, expect = { "I_OFF" } },
  { id = "P.t.I_SELECT.x.back", transition = "t.I_SELECT.x.back", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "x" }, expect = { "I_POINT" } },
  { id = "P.t.I_SELECT.x.prev", transition = "t.I_SELECT.x.prev", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Space>", "x" }, expect = { "I_SELECT" } },
  { id = "P.t.NI_DIRECT.replace", transition = "t.NI_DIRECT.replace", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>", "R" }, expect = { "R_OFF" } },
  { id = "P.t.NI_DIRECT.return_commit", transition = "t.NI_DIRECT.return_commit", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>", "0" }, expect = { "I_DIRECT" } },
  { id = "P.t.NI_DIRECT.return_drop", transition = "t.NI_DIRECT.return_drop", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>", "x" }, expect = { "I_DIRECT" } },
  { id = "P.t.NI_DIRECT.return_keep", transition = "t.NI_DIRECT.return_keep", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>", "l" }, expect = { "I_DIRECT" } },
  { id = "P.t.NI_DIRECT.visual", transition = "t.NI_DIRECT.visual", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>", "v" }, expect = { "V_IDLE" } },
  { id = "P.t.NI_POINT.disable", transition = "t.NI_POINT.disable", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "<Plug>(skkeleton-disable)" }, expect = { "I_OFF" } },
  { id = "P.t.NI_POINT.replace", transition = "t.NI_POINT.replace", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "R" }, expect = { "R_OFF" } },
  { id = "P.t.NI_POINT.return_commit", transition = "t.NI_POINT.return_commit", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "0" }, expect = { "I_DIRECT" } },
  { id = "P.t.NI_POINT.return_drop", transition = "t.NI_POINT.return_drop", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "x" }, expect = { "I_DIRECT" } },
  { id = "P.t.NI_POINT.return_keep", transition = "t.NI_POINT.return_keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "l" }, expect = { "I_POINT" } },
  { id = "P.t.NI_POINT.visual", transition = "t.NI_POINT.visual", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "v" }, expect = { "V_PRE" } },
  { id = "P.t.NI_SELECT.replace", transition = "t.NI_SELECT.replace", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>", "R" }, expect = { "R_OFF" } },
  { id = "P.t.NI_SELECT.return_commit", transition = "t.NI_SELECT.return_commit", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>", "0" }, expect = { "I_DIRECT" } },
  { id = "P.t.NI_SELECT.return_drop", transition = "t.NI_SELECT.return_drop", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>", "x" }, expect = { "I_DIRECT" } },
  { id = "P.t.NI_SELECT.return_keep", transition = "t.NI_SELECT.return_keep", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>", "l" }, expect = { "I_SELECT" } },
  { id = "P.t.NI_SELECT.visual", transition = "t.NI_SELECT.visual", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>", "v" }, expect = { "V_PRE" } },
  { id = "P.t.N_OFF.R", transition = "t.N_OFF.R", keys = { "R" }, expect = { "R_OFF" } },
  { id = "P.t.N_OFF.esc", transition = "t.N_OFF.esc", keys = { "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.N_OFF.insert_key", transition = "t.N_OFF.insert_key", keys = { "<Insert>" }, expect = { "I_OFF" } },
  { id = "P.t.P_PROMPT_POINT.register_cancel", transition = "t.P_PROMPT_POINT.register_cancel", keys = { "i", "<Plug>(skkeleton-enable)", "N", "u", "r", "u", "<Space>", "<Esc>" }, expect = { "I_POINT" } },
  { id = "P.t.P_PROMPT_SELECT.register_cancel", transition = "t.P_PROMPT_SELECT.register_cancel", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Space>", "<Space>", "<Space>", "<Space>", "<Space>", "<Esc>" }, expect = { "I_SELECT" } },
  { id = "P.t.R_OFF.esc", transition = "t.R_OFF.esc", keys = { "i", "<Plug>(skkeleton-enable)", "<Insert>", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.R_OFF.insert_key", transition = "t.R_OFF.insert_key", keys = { "i", "<Plug>(skkeleton-enable)", "<Insert>", "<Insert>" }, expect = { "I_OFF" } },
  { id = "P.t.V_IDLE.esc", transition = "t.V_IDLE.esc", keys = { "i", "<Plug>(skkeleton-enable)", "<C-o>", "v", "<Esc>" }, expect = { "I_DIRECT" } },
  { id = "P.t.V_PRE_POINT.esc", transition = "t.V_PRE_POINT.esc", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>", "v", "<Esc>" }, expect = { "I_POINT" } },
  { id = "P.t.V_PRE_SELECT.esc", transition = "t.V_PRE_SELECT.esc", keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-o>", "v", "<Esc>" }, expect = { "I_SELECT" } },
}

-- 06 の観測を、遷移の observed 欄に足す。04 の observed はそのまま残す。
do
  local by_transition = {}
  for _, t in ipairs(M.transitions) do
    by_transition[t.id] = t
  end
  for _, p in ipairs(M.probes or {}) do
    local t = by_transition[p.transition]
    if t then
      local seen = false
      for _, id in ipairs(t.observed) do
        if id == p.id then
          seen = true
        end
      end
      if not seen then
        t.observed[#t.observed + 1] = p.id
      end
    end
  end
end

return M

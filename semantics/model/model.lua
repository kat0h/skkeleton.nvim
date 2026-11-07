-- insert / normal / visual / replace / terminal の状態機械のモデル（#184、terminal は #188、
-- マクロと `.` は #192、親は #179）
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
--   キーでないイベント（User イベントや autocmd）は、観測の keys に "@イベント名" と書いて、
--   その位置で起こす（例: "@blink_refresh"）。07d の blink.cmp のメニューはキーではなく
--   User skkeleton-handled で開くので、この書き方を使う。
--
-- 使い方:
--   nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua
--   nvim --headless -u NONE -i NONE -l semantics/model/model_check.lua --verbose

local M = {}

M.issue = 184
M.parent = 179
M.scope = "insert / normal / visual / replace / terminal（Vim のモード i / n / v・s / R / t・nt）と、"
  .. "組み込み・blink.cmp の補完、貼り付け・マウス・ホイール・WinLeave / BufLeave・"
  .. "skkeleton が奪わないキー（#191）、マクロ（q 記録・@ 実行）と `.`（#192）"
M.sources = {
  "semantics/GLOSSARY.md",
  "semantics/inventory/keys.md（#181）",
  "semantics/inventory/events.md（#182）",
  "semantics/issues.md（#183）",
  "lua/skkeleton/map.lua、keymap.lua、guard.lua、cleanup.lua、paste.lua、function/",
  "lua/skkeleton/render.lua、render/cmdline.lua、preedit.lua（terminal の pre-edit、#188）",
  "lua/skkeleton/completion/init.lua、completion/blink.lua（#190）",
  "semantics/explore/explore.lua の terminal プロファイル（#188 の観測）",
  "semantics/explore/observations/misc.jsonl（#191）",
  "semantics/explore/repeat.lua、semantics/explore/observations/repeat.jsonl（#192）",
  "lua/skkeleton/render.lua の feed（#36 の修正）",
  "状態遷移図の下書き（作者の手元の data.js。18 状態・49 遷移）",
}

-- 設定。guard から config.<名前> で引く。model_check の --config で上書きできる
M.config = {
  keepState = false,
  -- blink.cmp の eggLikeNewline。真ならメニューで選んだ候補を <CR> で確定する
  eggLikeNewline = false,
}

-- 解析の開始状態。BFS はここから広げる
M.initial = { "N_OFF" }

-- 状態クラス
--
-- class は人が読む状態クラス。観測（semantics/explore/observe.lua の classify）が
-- 返す名前と違うときは notes に書く。
-- 内部で分けた状態（NI_POINT など）は、class にまとめ先を書く。
-- aspect はクラスの中の相や補完の種類を内部で分ける名前。NI / V_PRE / P_PROMPT は
-- direct / point / select を、IC は builtin / waiting-direct / waiting-romaji / waiting-point /
-- waiting-select / blink-point を、I_OFF は buffer-menu を持つ。
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
    notes = "▽ と ▽* はまとめた。06 の観測で `a` は I_POINT と I_SELECT、`<Space>` は I_SELECT と P_PROMPT に割れ、"
      .. "作者の判断 7 の条件が成立した。分ける作業は #194 と #193 で扱う。",
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
    aspect = "builtin",
    layer = "Vim のモードが ic（組み込み補完のメニュー）。pre-edit は消えている",
    vim_mode = "ic",
    enabled = true,
    phase = "input:direct",
    reading = "none",
    preedit = "none",
    menu = "builtin",
    label = "completion（組み込み）",
    refs = { "#18", "#19", "#45", "#190", "keys.md §5", "events.md O16" },
    notes = "組み込みの補完。▽ から <C-n> で入ると、その時点で pre-edit（extmark）が消える（#190 の観測）。"
      .. "人の読むクラスでは、補完のメニューが開いているあいだは pre-edit が無い。",
  },
  IX_DIRECT = {
    class = "IC",
    aspect = "waiting-direct",
    layer = "Vim のモードが ix（<C-x> のあと、補完の種類のキー待ち）。読みは無い",
    vim_mode = "ix",
    enabled = true,
    phase = "input:direct",
    reading = "none",
    preedit = "none",
    menu = "waiting",
    transient = true,
    reachable = true,
    label = "completion（キー待ち・direct）",
    refs = { "keys.md §5", "#190" },
    notes = "<C-x> は次のキーで補完の種類を選ぶ。この状態はその 1 キーのあいだだけ。",
  },
  IX_ROMAJI = {
    class = "IC",
    aspect = "waiting-romaji",
    layer = "Vim のモードが ix。ローマ字の打ちかけを抱えたまま",
    vim_mode = "ix",
    enabled = true,
    phase = "input:direct",
    reading = "romaji",
    preedit = "romaji",
    menu = "waiting",
    transient = true,
    reachable = true,
    label = "completion（キー待ち・打ちかけ）",
    refs = { "keys.md §5", "#190" },
  },
  IX_POINT = {
    class = "IC",
    aspect = "waiting-point",
    layer = "Vim のモードが ix。▽ を抱えたまま",
    vim_mode = "ix",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "point",
    preedit = "point",
    menu = "waiting",
    transient = true,
    reachable = true,
    label = "completion（キー待ち・▽）",
    refs = { "keys.md §5", "#190" },
    notes = "<C-x> の時点では pre-edit は消えない（観測）。次の <C-n> などで補完が始まると消える。",
  },
  IX_SELECT = {
    class = "IC",
    aspect = "waiting-select",
    layer = "Vim のモードが ix。▼ を抱えたまま",
    vim_mode = "ix",
    enabled = true,
    phase = "henkan",
    reading = "henkan",
    preedit = "henkan",
    menu = "waiting",
    transient = true,
    reachable = true,
    label = "completion（キー待ち・▼）",
    refs = { "keys.md §5", "#190" },
  },
  I_BLINK_POINT = {
    class = "IC",
    aspect = "blink-point",
    layer = "Vim のモードは i のまま。blink.cmp のメニューが開いていて、▽ の読みを抱えたまま",
    vim_mode = "i",
    enabled = true,
    phase = "input:okurinasi",
    reading = "point",
    preedit = "point",
    menu = "blink",
    reachable = "unknown",
    label = "completion（blink・▽）",
    refs = { "#24", "#143", "#174", "#190", "completion/init.lua:246-273" },
    notes = "人が読むクラスは IC（組み込みと同じ補完）。blink は Vim のモードを変えないので、"
      .. "pre-edit は残ったままメニューが出る。状態は User skkeleton-handled の refresh で開き、"
      .. "User BlinkCmpMenuClose / skkeleton-enable-post / disable-post で閉じる（キーではない）。",
  },
  I_OFF_MENU = {
    class = "I_OFF",
    aspect = "buffer-menu",
    layer = "Vim のモードが i、skkeleton は無効。blink.cmp の buffer 補完のメニューが開いている",
    vim_mode = "i",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    menu = "buffer",
    reachable = "unknown",
    label = "insert（無効・buffer 補完）",
    refs = { "#24", "completion/init.lua:135-142" },
    notes = "無効のあいだに出る blink の buffer 補完のメニュー（#24）。"
      .. "skkeleton の状態ではないが、有効化したときに閉じるかどうかが結果を分けるので状態にした。",
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
    refs = { "host.lua:235-244", "#152", "#192" },
    notes = "keepState の one-shot 待ちは人から見たクラスを分けない（作者の判断 3）。"
      .. "07f で `.` と `@a` の観測を取ったところ、one-shot を使い切ったあとの insert は"
      .. "有効にならないので、内部だけ N_KEEP に分けた（class は N_OFF のまま）。"
      .. "マクロの記録中も内部だけ N_REC に分ける（class は N_OFF のまま）。",
  },
  N_KEEP = {
    class = "N_OFF",
    layer = "Vim のモードが n、skkeleton は無効で、keepState の one-shot が残っている",
    vim_mode = "n",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "normal（keepState の one-shot 待ち）",
    refs = { "host.lua:235-244", "#152", "#192" },
    notes = "人の読むクラスは N_OFF（作者の判断 3）。07f で `.` が InsertEnter を起こして"
      .. "one-shot を使い切ることを観測したので、内部だけ分けた（class は N_OFF のまま）。"
      .. "one-shot は同じバッファの次の InsertEnter で 1 回だけ使う。",
  },
  N_REC = {
    class = "N_OFF",
    layer = "Vim のモードが n、skkeleton は無効で、マクロを記録している",
    vim_mode = "n",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "normal（マクロ記録中）",
    refs = { "#36", "#192" },
    notes = "人の読むクラスは N_OFF。記録中かどうかは観測の状態クラスに出ないので分けない。"
      .. "記録は insert をまたいで続くが、そのあいだの skk の状態は記録の有無で変わらない。"
      .. "insert から戻ると N_OFF になるので、`q` は N_OFF からも開始と停止の両方を許す（分かれる組）。",
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
  -- terminal（t / nt）。#188（07b）。人が読むクラスは T_DIRECT / T_POINT / T_NORMAL の 3 つで、
  -- 有効・無効、打ちかけ・▽・▼ の相、nt で抱えている読みはモデルの中で分ける
  -- （作者の判断 4・cmdline の 07a と同じ考え）。観測（observe.classify）は t の有効・無効を
  -- 区別しない（t で pre-edit が無ければ T_DIRECT）ので、T_OFF / T_ESCAPE の class は T_DIRECT。
  T_OFF = {
    class = "T_DIRECT",
    layer = "Vim のモードが t、skkeleton は無効（terminal を開いただけ、または disable した）",
    vim_mode = "t",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "terminal（無効）",
    refs = { "map.lua:113-139", "plugin/skkeleton.lua:20-24", "keys.md §4", "#188" },
    notes = "terminal を開いただけの状態と、disable した状態。t のマッピングは無いので、"
      .. "キーはそのままジョブへ渡る。",
  },
  T_ESCAPE = {
    class = "T_DIRECT",
    layer = "Vim のモードが t のまま、マップされた <Esc> のあと（state.type は escape）",
    vim_mode = "t",
    enabled = false,
    phase = "escape",
    reading = "none",
    preedit = "none",
    reachable = true,
    label = "terminal（escape の片付け待ち）",
    refs = { "function/disable.lua:21-27", "cleanup.lua:218-248", "keys.md §4", "#188" },
    notes = "t の <Esc> はマップされた escape で、読みを確定して無効になり、端末へ Esc を流す。"
      .. "insert と違い ModeChanged は起きない（t のまま）ので、state.type は escape のまま残る。"
      .. "<C-\\><C-n> で nt へ移るときに ModeChanged の分岐で reset される。"
      .. "キーのあとの観測は T_DIRECT になるので、クラスは T_DIRECT にする。",
  },
  T_DIRECT = {
    class = "T_DIRECT",
    layer = "Vim のモードが t、skk が有効で pre-edit が無い",
    vim_mode = "t",
    enabled = true,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "terminal（pre-edit 無し）",
    refs = { "render.lua:395-425", "render.lua:91-97" },
  },
  T_ROMAJI = {
    class = "T_POINT",
    aspect = "romaji",
    layer = "Vim のモードが t、ローマ字の打ちかけ（state.feed）を端末の行に書いている",
    vim_mode = "t",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "romaji",
    preedit = "romaji",
    label = "terminal（打ちかけ）",
    refs = { "state.lua", "render.lua:395-425" },
    notes = "観測は pre-edit の有無だけを見るので、class は T_POINT。"
      .. "端末の行には marker と打ちかけの文字（▽k など）が本物の文字として残る。",
  },
  T_POINT = {
    class = "T_POINT",
    aspect = "point",
    layer = "Vim のモードが t、▽ / ▽* を端末の行に書いている",
    vim_mode = "t",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "point",
    preedit = "point",
    label = "terminal（▽）",
    refs = { "render.lua:395-425", "function/input.lua" },
  },
  T_SELECT = {
    class = "T_POINT",
    aspect = "select",
    layer = "Vim のモードが t、▼ を端末の行に書いている",
    vim_mode = "t",
    enabled = true,
    phase = "henkan",
    reading = "henkan",
    preedit = "henkan",
    label = "terminal（▼）",
    refs = { "render.lua:395-425", "function/henkan.lua" },
    notes = "観測は ▽ と ▼ を分けないので、class は T_POINT。",
  },
  T_NORMAL_DIRECT = {
    class = "T_NORMAL",
    aspect = "direct",
    layer = "Vim のモードが nt（terminal-normal）、skk は有効のまま、読みは無い",
    vim_mode = "nt",
    enabled = true,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "terminal-normal（読み無し）",
    refs = { "cleanup.lua:218-248", "tests/test_e2e_cmdline.lua:147-172", "#74" },
    notes = "ModeChanged の safe_reset は、nvim_get_mode() が nt のあいだ何もしない（cleanup.lua:229-238）。"
      .. "t のマッピングは置かれたまま。i / a / I / A で t に戻る。",
  },
  T_NORMAL_ROMAJI = {
    class = "T_NORMAL",
    aspect = "romaji",
    layer = "Vim のモードが nt、打ちかけを端末の行に残したまま",
    vim_mode = "nt",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "romaji",
    preedit = "romaji",
    label = "terminal-normal（打ちかけを抱える）",
    refs = { "cleanup.lua:218-248", "#74" },
  },
  T_NORMAL_POINT = {
    class = "T_NORMAL",
    aspect = "point",
    layer = "Vim のモードが nt、▽ を端末の行に残したまま",
    vim_mode = "nt",
    enabled = true,
    phase = "input:okurinasi|okuriari",
    reading = "point",
    preedit = "point",
    label = "terminal-normal（▽ を抱える）",
    refs = { "cleanup.lua:218-248", "#74" },
    notes = "t の pre-edit は端末の行の本物の文字なので、nt でもそのまま見えている。"
      .. "i で t に戻ると、その続きから打てる（#74 の直し）。",
  },
  T_NORMAL_SELECT = {
    class = "T_NORMAL",
    aspect = "select",
    layer = "Vim のモードが nt、▼ を端末の行に残したまま",
    vim_mode = "nt",
    enabled = true,
    phase = "henkan",
    reading = "henkan",
    preedit = "henkan",
    label = "terminal-normal（▼ を抱える）",
    refs = { "cleanup.lua:218-248", "#74" },
  },
  T_NORMAL_OFF = {
    class = "T_NORMAL",
    layer = "Vim のモードが nt、skk は無効",
    vim_mode = "nt",
    enabled = false,
    phase = "input",
    reading = "none",
    preedit = "none",
    label = "terminal-normal（無効）",
    refs = { "cleanup.lua:218-248", "tests/test_e2e_cmdline.lua:147-172" },
    notes = "disable したあと、または <Esc>（escape）から nt へ移った状態。"
      .. "i で t に戻っても skk は無効のまま（T_OFF）。",
  },
}

-- イベント
--
-- kind: key（キー）/ autocmd（Vim のイベント）/ api（skkeleton の関数）/ input（キー以外の入力）/
--       internal（キーの処理の途中で走る片付け）
-- keys: 棚卸し（#181）の表記。イベントが 1 つのキーでないとき（<C-o>v など）はまとめた表記を書く。
-- modes: このモデルで扱う Vim のモード。c は 07a、t は 07b（#188）で足した。
M.events = {
  enable = {
    kind = "api",
    keys = { "<Plug>(skkeleton-enable)", "skkeleton.enable()" },
    modes = { "i", "n", "t" },
    refs = { "main.lua:101-125", "plugin/skkeleton.lua:20-24", "events.md O15" },
  },
  disable = {
    kind = "api",
    keys = { "<Plug>(skkeleton-disable)", "skkeleton.disable()" },
    modes = { "i", "t" },
    refs = { "main.lua:129-139", "function/disable.lua:13-18", "events.md O15" },
  },
  toggle = {
    kind = "api",
    keys = { "<Plug>(skkeleton-toggle)", "skkeleton.toggle()" },
    modes = { "i", "n", "t" },
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
    modes = { "i", "t" },
    refs = { "keymap.lua:23-56,64-88", "function/input.lua:85-120", "keys.md §1,§3" },
    notes = "l q ; / L > X は、それぞれ別のイベントにした（関数が割り当てられているため）。",
  },
  char_shift = {
    kind = "key",
    keys = {
      "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "M", "N", "O", "P", "Q", "R",
      "S", "T", "U", "V", "W", "Y", "Z",
    },
    modes = { "i", "t" },
    refs = { "function/input.lua:85-120", "keys.md §1" },
    notes = "シフト付きの文字。direct では ▽ を開始する（かなテーブルに単独の項目が無いとき）。",
  },
  key_x = {
    kind = "key",
    keys = { "x" },
    modes = { "i", "t" },
    refs = { "keymap.lua:51", "function/henkan.lua:116-133" },
    notes = "input では文字。henkan では候補を 1 つ前へ（henkanBackward）。",
  },
  key_X = {
    kind = "key",
    keys = { "X" },
    modes = { "i", "t" },
    refs = { "keymap.lua:52", "function/common.lua:89-", "keys.md §3" },
    notes = "input では文字（▽ を開始）。henkan では候補の削除（purgeCandidate）。",
  },
  key_L = {
    kind = "key",
    keys = { "L" },
    modes = { "i", "t" },
    refs = { "keymap.lua:41", "function/mode.lua" },
  },
  key_l = {
    kind = "key",
    keys = { "l" },
    modes = { "i", "t" },
    refs = { "keymap.lua:37", "#67", "#87" },
    notes = "既定のかなテーブルのときだけ disable を呼ぶ。",
  },
  key_q = {
    kind = "key",
    keys = { "q" },
    modes = { "i", "t" },
    refs = { "keymap.lua:38", "function/mode.lua" },
  },
  key_semicolon = {
    kind = "key",
    keys = { ";" },
    modes = { "i", "t" },
    refs = { "keymap.lua:39", "function/input.lua:147-" },
  },
  key_slash = {
    kind = "key",
    keys = { "/" },
    modes = { "i", "t" },
    refs = { "keymap.lua:40", "function/mode.lua" },
  },
  key_gt = {
    kind = "key",
    keys = { ">" },
    modes = { "i", "t" },
    refs = { "keymap.lua:34,53", "function/input.lua:206-223" },
    notes = "input では接頭辞・接尾辞、henkan では送り仮名（suffix）。",
  },
  key_cq = {
    kind = "key",
    keys = { "<C-q>" },
    modes = { "i", "t" },
    refs = { "keymap.lua:33", "function/mode.lua" },
  },
  bs = {
    kind = "key",
    keys = { "<BS>", "<C-h>" },
    modes = { "i", "t" },
    refs = { "keymap.lua:27,29", "function/input.lua:178-204", "keys.md §1" },
    notes = "<C-h> は <bs> に正規化され、keymap.lua:29 の <c-h> の行は引かれない。",
  },
  cr = {
    kind = "key",
    keys = { "<CR>" },
    modes = { "i", "t" },
    refs = { "keymap.lua:30,48", "function/common.lua:59-68" },
  },
  space = {
    kind = "key",
    keys = { "<Space>" },
    modes = { "i", "t" },
    refs = { "keymap.lua:35,50", "function/henkan.lua:21-56,90-113" },
  },
  nl = {
    kind = "key",
    keys = { "<C-j>" },
    modes = { "i", "t" },
    refs = { "keymap.lua:32,49", "function/common.lua:18-45" },
  },
  cg = {
    kind = "key",
    keys = { "<C-g>" },
    modes = { "i", "t" },
    refs = { "keymap.lua:28,47", "function/common.lua:71-86", "#87" },
  },
  esc = {
    kind = "key",
    keys = { "<Esc>", "<C-[>" },
    modes = { "i", "n", "v", "R", "ic", "t" },
    refs = { "keymap.lua:31", "function/disable.lua:21-27", "cleanup.lua:192-251", "#86" },
    notes = "insert では keymap の escape。cmdline から visual へ戻るときなどは ModeChanged の規則 5。",
  },
  insert_key = {
    kind = "key",
    keys = { "<Insert>" },
    modes = { "i", "R", "t" },
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
    modes = { "i", "t" },
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
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#8", "#12", "#20" },
    notes = "レジスタの中身を入れる・式の結果を入れる。guard は確定しないので、"
      .. "バッファが変わったあとの TextChangedI が読みを捨てる。",
  },
  ctrl_v = {
    kind = "key",
    keys = { "<C-v>", "<C-v>065" },
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#12" },
  },
  ctrl_k = {
    kind = "key",
    keys = { "<C-k>", "<C-k>a:" },
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#12" },
  },
  ctrl_t = {
    kind = "key",
    keys = { "<C-t>" },
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §5,§6" },
  },
  tab = {
    kind = "key",
    keys = { "<Tab>" },
    modes = { "i", "t" },
    refs = { "guard.lua:89-96", "keys.md §5,§6", "#12" },
    notes = "<S-Tab> は termcap なので guard が確定する。guard_special のほう。",
  },
  ctrl_w = {
    kind = "key",
    keys = { "<C-w>" },
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#8", "#12" },
  },
  ctrl_u = {
    kind = "key",
    keys = { "<C-u>" },
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §5,§6", "#8", "#12" },
  },
  ctrl_a = {
    kind = "key",
    keys = { "<C-a>" },
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §6", "NOTES.md 未考慮 7" },
  },
  ctrl_at = {
    kind = "key",
    keys = { "<C-@>" },
    modes = { "i", "t" },
    refs = { "guard.lua:62-65", "keys.md §4,§6", "#56" },
  },
  completion_open = {
    kind = "key",
    keys = { "<C-n>", "<C-p>", "<C-x><C-n>" },
    modes = { "i", "t" },
    refs = { "guard.lua:78-80", "keys.md §5", "#18", "#19", "#45", "#190" },
    notes = "<C-n> / <C-p> はそのまま補完を始め、<C-x><C-n> は <C-x> のあとに始める。"
      .. "▽ や ▼ から始めると、その時点で pre-edit が消える（P1 の破れ）。",
  },
  completion_key = {
    kind = "key",
    keys = { "<C-x>" },
    modes = { "i", "ic", "t" },
    refs = { "keys.md §5", "#190" },
    notes = "補完の種類を選ぶキー待ち（モード ix）。pre-edit はこの時点では消えない。",
  },
  completion_next = {
    kind = "key",
    keys = { "<C-n>", "<C-p>" },
    modes = { "i", "ic" },
    refs = { "keys.md §5", "#190", "blink.cmp keymap super-tab" },
    notes = "ic では候補を次／前へ。ix では補完を始める。blink のメニューでは <C-n> / <C-p> も選択を動かす。",
  },
  completion_accept = {
    kind = "key",
    keys = { "<C-y>" },
    modes = { "i", "ic", "t" },
    refs = { "keys.md §6", "#19", "#190" },
    notes = "補完の候補を確定する。<C-e> は取り消しなので completion_cancel に分けた。",
  },
  completion_cancel = {
    kind = "key",
    keys = { "<C-e>" },
    modes = { "i", "ic" },
    refs = { "keys.md §6", "#19", "#190" },
    notes = "補完の候補を取り消す。メニューが出ていないときは何もしない（観測）。",
  },
  completion_newline = {
    kind = "key",
    keys = { "<CR>" },
    modes = { "i", "ic" },
    refs = { "keys.md §6", "#190", "doc/skkeleton.txt:516-518" },
    notes = "組み込みの補完では選んだ候補を確定して改行する。blink では eggLikeNewline のときだけ候補を確定する。",
  },
  completion_tab = {
    kind = "key",
    keys = { "<Tab>", "<S-Tab>" },
    modes = { "i", "ic" },
    refs = { "keys.md §5", "#190", "blink.cmp keymap super-tab" },
    notes = "組み込みの補完では <Tab> が候補を確定する。blink の super-tab では <Tab> が選んだ候補を確定する。",
  },
  blink_refresh = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "completion/init.lua:128-134,246-273", "#24", "#143", "#174", "#190" },
    notes = "User skkeleton-handled。▽ の読みが変わったときに blink のメニューを開く／開き直す。"
      .. "読みが minLength 未満か、▽ でなければ閉じる。ユーザーの設定の blink が要る。",
  },
  blink_menu_open = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "completion/init.lua:143-151", "#143", "#174", "#190" },
    notes = "User BlinkCmpMenuOpen。▽ の入力中なら、メニューをカーソルに揃える（align_to = cursor）。",
  },
  blink_menu_close = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "completion/init.lua:152-158", "#143", "#174", "#190" },
    notes = "User BlinkCmpMenuClose。align_to を元に戻す。",
  },
  blink_hide = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "completion/init.lua:135-142", "#24", "#190" },
    notes = "User skkeleton-enable-post / skkeleton-disable-post。"
      .. "skkeleton が開いたものではないメニューも閉じる。",
  },
  blink_commit = {
    kind = "api",
    keys = { "completion.confirm" },
    modes = { "i" },
    refs = { "completion/init.lua:221-226", "main.lua:205-236", "#190" },
    notes = "blink の source の execute が選んだ語で確定する。main.complete が読みを捨てて語を流す。",
  },
  buffer_menu_open = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "completion/init.lua:143-158", "#24", "#190" },
    notes = "blink の buffer 補完のメニューが開く。skkeleton が無効でも出る。",
  },
  buffer_menu_close = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "completion/init.lua:135-158", "#24", "#190" },
    notes = "blink の buffer 補完のメニューが閉じる。",
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
    modes = { "i", "t" },
    refs = { "guard.lua:22-37,50-85", "keys.md §4", "#56" },
    notes = "guard が pre-edit を確定してから、キーを流し直す。",
  },
  mouse_click = {
    kind = "input",
    keys = { "<LeftMouse>", "<RightMouse>" },
    modes = { "i" },
    refs = { "cleanup.lua:120-160,269-281", "keys.md §5", "#56", "#191" },
    notes = "同じウィンドウのクリック。カーソルが動いたときだけ CursorMovedI が読みを確定する。"
      .. "別のウィンドウのクリックは mouse_click_other。",
  },
  mouse_click_other = {
    kind = "input",
    keys = { "<LeftMouse>", "<RightMouse>" },
    modes = { "i", "v" },
    refs = { "cleanup.lua:269-281", "#169", "#191" },
    notes = "別のウィンドウへのクリック。WinLeave が走り、読みを確定せずに捨てる（#169）。",
  },
  mouse_select = {
    kind = "input",
    keys = { "<2-LeftMouse>", "<3-LeftMouse>", "<DragRight>" },
    modes = { "i" },
    refs = { "cleanup.lua:179-190,207-214", "events.md O10", "events.md O18", "#47", "#191" },
    notes = "ダブルクリック・ドラッグで visual / select に入る。"
      .. "ダブルクリックは 1 回目の押下の CursorMovedI が先に確定する。"
      .. "ドラッグでは ModeChanged の時点で pre-edit が残る（O18）。",
  },
  wheel = {
    kind = "input",
    keys = { "<ScrollWheelUp>", "<ScrollWheelDown>" },
    modes = { "i" },
    refs = { "guard.lua:59-61", "keys.md §5", "#191" },
    notes = "スクロールはカーソルを動かさないので、guard もずれの検出も確定しない。",
  },
  winleave = {
    kind = "autocmd",
    keys = {},
    modes = { "i", "n", "v", "R" },
    refs = { "cleanup.lua:269-281", "events.md", "#46", "#169", "#191" },
    notes = "読みを確定せずに捨てる。insert のまま無効になる（I_OFF）。",
  },
  bufleave = {
    kind = "autocmd",
    keys = {},
    modes = { "i", "n", "v", "R" },
    refs = { "cleanup.lua:269-281", "events.md", "#169", "#191" },
    notes = "読みを確定せずに捨てる。insert のまま無効になる（I_OFF）。",
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
    notes = "TextChangedI / CursorMovedI / on_bytes。",
  },
  text_changed_p = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "cleanup.lua:150-165,283-286", "events.md O16", "#19", "#190" },
    notes = "補完のメニューが出ているあいだに候補やバッファが変わると来る。check_stale は mode が i / c でなければ何もしない。",
  },
  complete_done = {
    kind = "autocmd",
    keys = {},
    modes = { "i" },
    refs = { "cleanup.lua:150-165,283-286", "events.md O16", "#19", "#190" },
    notes = "組み込みの補完が終わったときに来る。この時点ではもう insert に戻っていることが多い。",
  },
  paste = {
    kind = "input",
    keys = { "<Paste>" },
    modes = { "i" },
    refs = { "paste.lua:31-69", "#57", "#125", "#191" },
    notes = "vim.paste。最初のチャンク（phase が -1 / 1 / nil）でだけ pre-edit を確定し、"
      .. "そのあと元の vim.paste に渡す。2 つ目以降のチャンクでは確定しない（観測）。",
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
  macro_record_start = {
    kind = "key",
    keys = { "qa" },
    modes = { "n" },
    refs = { "Vim 本体（q のコマンド）", "#36", "#192" },
    notes = "normal の `q{reg}`。レジスタは a だけを対象にする（#36 の再現と観測が a）。"
      .. "skk のマッピングは normal に無いので、Vim が記録を始める。",
  },
  macro_record_stop = {
    kind = "key",
    keys = { "q" },
    modes = { "n" },
    refs = { "Vim 本体（q のコマンド）", "#36", "#192" },
    notes = "記録中の `q`。記録を止めるだけで、skk の状態は変えない。",
  },
  macro_replay = {
    kind = "key",
    keys = { "@a", "3@a" },
    modes = { "n" },
    refs = { "Vim 本体（@ のコマンド）", "#36", "#152", "#192" },
    notes = "レジスタ a のマクロを再生する。記録されたキーを Vim が流し直すので、"
      .. "中に toggle や insert があれば skk の状態も動く。",
  },
  dot_repeat = {
    kind = "key",
    keys = { "." },
    modes = { "n" },
    refs = { "Vim 本体（. のコマンド）", "#36", "#152", "#192" },
    notes = "直前の変更を繰り返す。変更が insert なら InsertEnter を起こす（#152）。",
  },
  normal_motion = {
    kind = "key",
    keys = { "j", "k", "h", "l", "0", "$", "G", "j0", "3G0" },
    modes = { "n" },
    refs = { "Vim 本体（normal の移動）", "#192" },
    notes = "マクロの再生や `.` の前後で使う移動。skk の状態は変えない。",
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
  -- terminal（t / nt）。#188（07b）
  --
  -- t でも、map.lua が置いた 102 個のキーは char や esc などの同じイベントで扱う
  -- （キーマップは Vim のモードで分かれるだけで、keymap の処理は同じ）。
  -- ここに足すのは、terminal にだけあるイベントと、nt のキー。
  term_open = {
    kind = "api",
    keys = { ":terminal", "vim.cmd('terminal')" },
    modes = { "n" },
    refs = { "explore.lua の terminal プロファイル", "keys.md §5", "#188" },
    notes = "normal から terminal を開くと Vim のモードが t になり、skk は無効のまま（T_OFF）。"
      .. "探索器の terminal プロファイルは `terminal cat` を実行して同じ所まで進める。",
  },
  t_normal = {
    kind = "key",
    keys = { "<C-\\><C-n>" },
    modes = { "t" },
    refs = { "guard.lua:114-124,154-163", "cleanup.lua:218-248", "tests/test_e2e_cmdline.lua:147-172", "#74" },
    notes = "terminal から terminal-normal（nt）へ抜ける。guard は pre-edit を確定せずに通す（#74）。",
  },
  nt_insert = {
    kind = "key",
    keys = { "i", "a", "I", "A" },
    modes = { "nt" },
    refs = { "tests/test_e2e_cmdline.lua:147-172", "#74" },
    notes = "terminal-normal から terminal（t）へ戻る。skk は有効のままで、読みと pre-edit も残る。",
  },
  nt_edit = {
    kind = "key",
    keys = { "x", "X", "dd", "J", "o", "O", "u", "U", "R", "p", "P", "." },
    modes = { "nt" },
    refs = { "keys.md §5", "#188" },
    notes = "terminal のバッファは nomodifiable なので、編集は E21 で何も変わらない（x / dd / J / o / u / R）。"
      .. "レジスタが空の p / P と、直前の変更が無い . は何も起きない。",
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
  effects = { "save_mapping", "install_mapping", "reset_state", "hide_completion" },
  status = "ok", refs = { "main.lua:101-125" }, observed = { "O-enable" },
  notes = "元のマッピングを退避してから、skkeleton のマッピングを張る。",
})
add({
  id = "t.I_OFF.enable",
  from = "I_OFF", event = "enable", to = "I_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state", "hide_completion" },
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
  from = "I_DIRECT", event = "esc", to = "N_KEEP",
  guard = { { "config.keepState", "=", true } },
  effects = { "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "host.lua:235-244", "#152" },
})
add({
  id = "t.I_ROMAJI.esc.keepstate",
  from = "I_ROMAJI", event = "esc", to = "N_KEEP",
  guard = { { "config.keepState", "=", true } },
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "#152" },
})
add({
  id = "t.I_POINT.esc.keepstate",
  from = "I_POINT", event = "esc", to = "N_KEEP",
  guard = { { "config.keepState", "=", true } },
  effects = { "commit_reading", "restore_mapping", "reset_state", "clear_extmark" },
  status = "ok", refs = { "function/disable.lua:21-27", "#152" },
})
add({
  id = "t.I_SELECT.esc.keepstate",
  from = "I_SELECT", event = "esc", to = "N_KEEP",
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
  id = "t.N_KEEP.insert_enter.keepstate",
  from = "N_KEEP",
  event = "insert_enter",
  to = "I_DIRECT",
  guard = { { "config.keepState", "=", true } },
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok",
  refs = { "host.lua:235-244", "#152", "#192" },
  observed = { "O152" },
  notes = "buffer ローカルの one-shot InsertEnter。one-shot が残っている間だけ、"
    .. "次の insert で 1 回有効化する。使ったら N_OFF に戻る（クラスは N_OFF のまま）。",
})
add({
  id = "t.N_KEEP.insert_enter",
  from = "N_KEEP",
  event = "insert_enter",
  to = "I_OFF",
  effects = { "pass_key" },
  status = "ok",
  refs = { "host.lua:235-244", "#152" },
  notes = "one-shot が残っていても keepState が偽なら有効化しない（N_KEEP は config が真のときだけ届く）。",
})
add({
  id = "t.N_OFF.insert_enter",
  from = "N_OFF",
  event = "insert_enter",
  to = "I_OFF",
  effects = { "pass_key" },
  status = "ok",
  refs = { "events.md O1" },
  observed = { "O-esc-then-i" },
  notes = "one-shot が無いときの insert。keepState が真でも、skk の <Esc> のあとでなければ有効化しない（#152）。",
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

-- keepState の one-shot 待ち（#152、#192）
add({
  id = "t.N_KEEP.esc",
  from = "N_KEEP",
  event = "esc",
  to = "N_KEEP",
  effects = { "pass_key" },
  status = "unknown",
  refs = { "Vim 本体", "#152" },
  notes = "normal の <Esc> は one-shot を使わない（次の InsertEnter まで残る）。",
})
add({
  id = "t.N_KEEP.normal_motion",
  from = "N_KEEP",
  event = "normal_motion",
  to = "N_KEEP",
  effects = { "pass_key" },
  status = "unknown",
  refs = { "Vim 本体", "#152" },
  notes = "normal の移動は InsertEnter を起こさないので、one-shot は残る。",
})
add({
  id = "t.N_KEEP.dot",
  from = "N_KEEP",
  event = "dot_repeat",
  to = "N_OFF",
  effects = { "feed_key", "pass_key" },
  status = "ok",
  refs = { "Vim 本体（. のコマンド）", "#152", "#192" },
  observed = { "O-dot-keepstate" },
  notes = "`.` は直前の変更を繰り返す。変更が insert なら InsertEnter を起こし、"
    .. "one-shot を使い切る（#152 の観測）。使ったあとの insert は有効にならない。",
})
add({
  id = "t.N_KEEP.macro_record_stop",
  from = "N_KEEP",
  event = "macro_record_stop",
  to = "N_KEEP",
  status = "ok",
  refs = { "Vim 本体（q のコマンド）", "#152", "#192" },
  observed = { "O-macro-keepstate" },
  notes = "insert を経由して normal に戻ったあとの `q`。one-shot は `q` では使わないので残る。",
})
add({
  id = "t.N_KEEP.macro_replay",
  from = "N_KEEP",
  event = "macro_replay",
  to = "N_KEEP",
  guard = { { "config.keepState", "=", true } },
  effects = { "feed_key", "pass_key" },
  status = "ok",
  refs = { "Vim 本体（@ のコマンド）", "#152", "#192" },
  observed = { "O-macro-keepstate" },
  notes = "マクロは normal の `q` で止めるので、最後に insert を抜ける <Esc> を含む。"
    .. "その <Esc> が再生され、keepState の one-shot がまた残る（観測）。",
})

-- マクロの記録と再生、`.` の繰り返し（#192）
add({
  id = "t.N_OFF.macro_record_start",
  from = "N_OFF",
  event = "macro_record_start",
  to = "N_REC",
  status = "ok",
  refs = { "Vim 本体（q のコマンド）", "#192" },
  observed = { "O-macro-record" },
  notes = "記録を始める。skk の状態は変えない。",
})
add({
  id = "t.N_REC.macro_record_stop",
  from = "N_REC",
  event = "macro_record_stop",
  to = "N_OFF",
  status = "ok",
  refs = { "Vim 本体（q のコマンド）", "#192" },
  observed = { "O-macro-normal" },
  notes = "記録を止める。skk の状態は変えない。",
})
add({
  id = "t.N_OFF.macro_record_stop",
  from = "N_OFF",
  event = "macro_record_stop",
  to = "N_OFF",
  status = "ok",
  refs = { "Vim 本体（q のコマンド）", "#36", "#192" },
  observed = { "O36" },
  notes = "insert を経由して normal に戻ったあとの `q`。記録中かどうかは観測の状態クラスに"
    .. "出ないので、N_OFF からの `q` は開始（N_REC）と停止（N_OFF）の両方を許す。"
    .. "分かれる組として出る。",
})
add({
  id = "t.N_REC.insert_enter",
  from = "N_REC",
  event = "insert_enter",
  to = "I_OFF",
  effects = { "pass_key" },
  status = "ok",
  refs = { "Vim 本体", "#36", "#192" },
  notes = "記録中の insert は、記録していないときと同じく skk は無効のまま。"
    .. "記録は insert をまたいで続くが、モデルは insert の中の記録の有無を持たない。",
})
add({
  id = "t.N_REC.esc",
  from = "N_REC",
  event = "esc",
  to = "N_REC",
  effects = { "pass_key" },
  status = "unknown",
  refs = { "Vim 本体", "#192" },
})
add({
  id = "t.N_REC.normal_motion",
  from = "N_REC",
  event = "normal_motion",
  to = "N_REC",
  effects = { "pass_key" },
  status = "ok",
  refs = { "Vim 本体", "#192" },
  observed = { "O-macro-normal" },
  notes = "記録中の移動はレジスタに入る。skk の状態は変えない。",
})
add({
  id = "t.N_REC.dot",
  from = "N_REC",
  event = "dot_repeat",
  to = "N_REC",
  effects = { "feed_key", "pass_key" },
  status = "unknown",
  refs = { "Vim 本体", "#192" },
  notes = "記録中の `.` はレジスタに入り、その場でも繰り返す。"
    .. "繰り返しの途中の状態はモデルに持たない。",
})
add({
  id = "t.N_REC.macro_replay",
  from = "N_REC",
  event = "macro_replay",
  to = "N_REC",
  effects = { "feed_key", "pass_key" },
  status = "unknown",
  refs = { "Vim 本体", "#192" },
  notes = "記録中の `@a` はレジスタに入り、その場でも再生する。入れ子の再生は対象外。",
})
add({
  id = "t.N_OFF.normal_motion",
  from = "N_OFF",
  event = "normal_motion",
  to = "N_OFF",
  effects = { "pass_key" },
  status = "ok",
  refs = { "Vim 本体", "#192" },
  observed = { "O36" },
  notes = "normal の移動。skk の状態は変えない。",
})
add({
  id = "t.N_OFF.dot",
  from = "N_OFF",
  event = "dot_repeat",
  to = "N_OFF",
  effects = { "feed_key", "pass_key" },
  status = "ok",
  refs = { "Vim 本体（. のコマンド）", "#192" },
  observed = { "O-dot", "O-dot-henkan" },
  notes = "直前の変更を繰り返す。変更が insert なら、もう一度 insert して確定し、normal に戻る。",
})
add({
  id = "t.N_OFF.macro_replay",
  from = "N_OFF",
  event = "macro_replay",
  to = "N_OFF",
  guard = { { "config.keepState", "=", false } },
  effects = { "feed_key", "pass_key" },
  status = "ok",
  refs = { "Vim 本体（@ のコマンド）", "#36", "#192" },
  observed = { "O36" },
  notes = "記録したキーを流し直す。マクロは normal の `q` で止めるので、最後は normal に戻る。",
})
add({
  id = "t.N_OFF.macro_replay.keepstate",
  from = "N_OFF",
  event = "macro_replay",
  to = "N_KEEP",
  guard = { { "config.keepState", "=", true } },
  effects = { "feed_key", "pass_key" },
  status = "ok",
  refs = { "Vim 本体（@ のコマンド）", "#152", "#192" },
  observed = { "O-macro-replay-off" },
  notes = "insert を含むマクロの再生の最後の <Esc> で、keepState の one-shot がまた残る（観測）。"
    .. "normal だけのマクロでは残らないが、レジスタの中身を状態に持たないので分けない。",
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
  local select_status = from == "I_ROMAJI" and "unknown" or "ok"
  add({
    id = "t." .. from .. ".mouse_select",
    from = from, event = "mouse_select", to = "N_OFF",
    effects = from == "I_SELECT" and { "commit_candidate", "reset_state", "restore_mapping", "clear_extmark" }
      or has_reading and { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" }
      or { "reset_state", "restore_mapping", "clear_extmark" },
    status = select_status,
    refs = { "cleanup.lua:179-190,207-214", "events.md O10", "events.md O18", "#47", "#191" },
    notes = "i から visual / select への直接の遷移（ダブルクリック・ドラッグ）。"
      .. "読みを確定してから無効化する。ドラッグでは ModeChanged の確定より前に一瞬 pre-edit が残る（O18）が、"
      .. "それは遷移の途中なので状態クラスにしない（作者の判断 10）。"
      .. "観測は semantics/explore/observations/misc.jsonl（I_DIRECT / I_POINT / I_SELECT は実測、I_ROMAJI は未観測）。",
  })
  add({
    id = "t." .. from .. ".winleave",
    from = from, event = "winleave", to = "I_OFF",
    effects = has_reading and { "drop", "reset_state", "restore_mapping", "clear_extmark" }
      or { "reset_state", "restore_mapping", "clear_extmark" },
    status = leave_status, refs = { "cleanup.lua:269-281", "#169", "#191", "events.md O13" },
    notes = "読みを確定せずに捨てる。insert に戻ったまま無効になる（I_OFF）。"
      .. "観測: 別ウィンドウのクリック（misc.jsonl の mouse.otherwin.point）、`:new`、`:wincmd w`。"
      .. "upstream は pre-edit が本物の文字なので残る。",
  })
  add({
    id = "t." .. from .. ".bufleave",
    from = from, event = "bufleave", to = "I_OFF",
    effects = has_reading and { "drop", "reset_state", "restore_mapping", "clear_extmark" }
      or { "reset_state", "restore_mapping", "clear_extmark" },
    status = leave_status, refs = { "cleanup.lua:269-281", "#169", "#191" },
    notes = "読みを確定せずに捨てる。insert に戻ったまま無効になる（I_OFF）。"
      .. "観測: 別のバッファへ `:buffer`（misc.jsonl の bufleave.point）。",
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
add({
  id = "t.V_IDLE.bufleave",
  from = "V_IDLE", event = "bufleave", to = "N_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:269-281", "#169" },
})
for _, from in ipairs({ "V_PRE_POINT", "V_PRE_SELECT" }) do
  add({
    id = "t." .. from .. ".bufleave",
    from = from, event = "bufleave", to = "N_OFF",
    effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
    status = "gap", refs = { "cleanup.lua:269-281", "#169", "#191" },
    notes = "読みを確定せずに捨てる。観測では切り替え後に mode が niI で無効になった（NI_OFF はモデルに無い）。",
  })
end
for _, from in ipairs({ "NI_DIRECT", "NI_POINT", "NI_SELECT" }) do
  add({
    id = "t." .. from .. ".bufleave",
    from = from, event = "bufleave", to = "N_OFF",
    effects = from == "NI_DIRECT" and { "reset_state", "restore_mapping", "clear_extmark" }
      or { "drop", "reset_state", "restore_mapping", "clear_extmark" },
    status = from == "NI_DIRECT" and "unknown" or "gap",
    refs = { "cleanup.lua:269-281", "#169", "#191" },
    notes = "観測では切り替え後に mode が niI で無効になった（NI_OFF はモデルに無い）。",
  })
end
add({
  id = "t.I_OFF.winleave",
  from = "I_OFF", event = "winleave", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "cleanup.lua:269-281", "#191" },
  notes = "無効な insert では状態を変えない。",
})
add({
  id = "t.I_OFF.bufleave",
  from = "I_OFF", event = "bufleave", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "cleanup.lua:269-281", "#191" },
})
add({
  id = "t.IC.bufleave",
  from = "IC", event = "bufleave", to = "N_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:269-281", "#169" },
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
  "前に挿入した文字があれば、その文字が入り、TextChangedI が読みを捨てる。"
  .. "無ければ E29 で何も起きない（下の ctrl_a.e29）。")

-- 前に挿入した文字が無いときの <C-a>。E29 で何も変わらず、読みが残る（観測）
for _, from in ipairs({ "I_ROMAJI", "I_POINT" }) do
  add({
    id = "t." .. from .. ".ctrl_a.e29",
    from = from, event = "ctrl_a", to = from,
    effects = { "pass_key" },
    status = from == "I_POINT" and "ok" or "unknown",
    refs = { "keys.md §6", "#191" },
    observed = from == "I_POINT" and { "O-ctrl-a-e29" } or {},
    notes = "E29: No inserted text yet。バッファも pre-edit も変わらない（観測: misc.jsonl の ctrl-a.empty）。"
      .. "E29 の扱いは #179 の「ここでは決めないこと」。",
  })
end

-- <C-@>。guard が読みを確定してから i_CTRL-@ に渡り、E29 で insert を抜ける（keys.md §4）
local ctrl_at_observed = {
  I_DIRECT = { "O-ctrl-at-direct" },
  I_ROMAJI = { "O-ctrl-at-romaji" },
  I_POINT = { "O-ctrl-at-point" },
  I_SELECT = { "O-ctrl-at-select" },
  I_OFF = { "O-ctrl-at-off" },
}
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT", "I_OFF" }) do
  local commit = from == "I_SELECT" and "commit_candidate"
    or from ~= "I_DIRECT" and from ~= "I_OFF" and "commit_reading"
    or nil
  local effects = { "reset_state", "restore_mapping", "clear_extmark", "feed_key" }
  if commit then
    table.insert(effects, 1, commit)
  end
  add({
    id = "t." .. from .. ".ctrl_at",
    from = from, event = "ctrl_at", to = "N_OFF",
    effects = effects,
    status = "ok", refs = { "keys.md §4,§6", "#56", "#191" },
    observed = ctrl_at_observed[from],
    notes = "guard が pre-edit を確定してから i_CTRL-@ に渡り、E29 で insert を抜けて無効になる。"
      .. "読みが無いときも insert を抜ける。E29 の扱いは #179 の「ここでは決めないこと」。",
  })
end

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
  add({
    id = "t." .. from .. ".completion_cancel",
    from = from, event = "completion_cancel", to = from,
    effects = { "pass_key" },
    status = "ok",
    refs = { "keys.md §6", "#190" },
    notes = "補完のメニューが無いときの <C-e>。Neovim の i_CTRL-E に落ちて、pre-edit は残る（#19 の再現の最後）。",
  })
end

-- 補完（#190）
--
-- 組み込みの補完（ic）は、<C-n> / <C-p> で入った時点で pre-edit が消える（#190 の観測）。
-- <C-x> はモード ix のキー待ちになり、この時点では pre-edit が残る。
-- blink.cmp は Vim のモードを変えずにメニューを出すので、IC（point）のままキーで結果が分かれる。
add({
  id = "t.I_DIRECT.completion_open",
  from = "I_DIRECT", event = "completion_open", to = "IC",
  effects = { "pass_key" },
  status = "ok", refs = { "keys.md §5", "#190" }, observed = { "O-completion-direct" },
  notes = "pre-edit が無いので、補完はそのまま始まる。",
})
add({
  id = "t.I_ROMAJI.completion_open",
  from = "I_ROMAJI", event = "completion_open", to = "IC",
  effects = { "drop", "clear_extmark", "reset_state" },
  status = "gap", refs = { "keys.md §5", "#19", "#190" }, observed = { "O-completion-romaji" },
  notes = "観測では打ちかけ（▽k）が消えて補完の候補が入った。読みは確定しない。",
})
add({
  id = "t.I_POINT.completion_open",
  from = "I_POINT", event = "completion_open", to = "IC",
  effects = { "drop", "clear_extmark", "reset_state" },
  status = "gap", refs = { "keys.md §5", "#18", "#19", "#190" }, observed = { "O-completion-open" },
  notes = "観測では pre-edit が消え、補完の候補が入った。読みは確定しない。",
})
add({
  id = "t.I_SELECT.completion_open",
  from = "I_SELECT", event = "completion_open", to = "IC",
  effects = { "drop", "clear_extmark", "reset_state" },
  status = "gap", refs = { "keys.md §5", "#18", "#190" }, observed = { "O-completion-select" },
  notes = "観測では ▼ の候補が消え、補完の候補が入った。候補は確定しない。",
})

-- <C-x> のキー待ち（モード ix）
add({
  id = "t.I_DIRECT.completion_key",
  from = "I_DIRECT", event = "completion_key", to = "IX_DIRECT",
  effects = { "keep" },
  status = "ok", refs = { "keys.md §5", "#190" },
  notes = "pre-edit が無いので、そのままキー待ちになる。",
})
add({
  id = "t.I_ROMAJI.completion_key",
  from = "I_ROMAJI", event = "completion_key", to = "IX_ROMAJI",
  effects = { "keep" },
  status = "ok", refs = { "keys.md §5", "#190" }, observed = { "O-completion-x-romaji" },
})
add({
  id = "t.I_POINT.completion_key",
  from = "I_POINT", event = "completion_key", to = "IX_POINT",
  effects = { "keep" },
  status = "ok", refs = { "keys.md §5", "#190" }, observed = { "O-completion-x" },
  notes = "観測では pre-edit が残ったままモード ix になった。",
})
add({
  id = "t.I_SELECT.completion_key",
  from = "I_SELECT", event = "completion_key", to = "IX_SELECT",
  effects = { "keep" },
  status = "unknown", refs = { "keys.md §5", "#190" },
})
add({
  id = "t.IC.completion_key",
  from = "IC", event = "completion_key", to = "IX_DIRECT",
  effects = { "pass_key" },
  status = "ok", refs = { "keys.md §5", "#190" }, observed = { "O-completion-x-after" },
  notes = "補完の候補が入ったあとに <C-x>。pre-edit は無いので、そのままキー待ちになる。",
})
for _, from in ipairs({ "IX_DIRECT", "IX_ROMAJI", "IX_POINT", "IX_SELECT" }) do
  local reading = from ~= "IX_DIRECT"
  add({
    id = "t." .. from .. ".completion_next",
    from = from, event = "completion_next", to = "IC",
    effects = reading and { "drop", "clear_extmark", "reset_state" } or { "pass_key" },
    status = reading and "gap" or "ok",
    refs = { "keys.md §5", "#190" },
    observed = (from == "IX_POINT" and { "O-completion-x-n" })
      or (from == "IX_ROMAJI" and { "O-completion-x-n-romaji" })
      or {},
    notes = reading and "観測では打ちかけ／▽／▼ が消えて補完の候補が入った。読みは確定しない。"
      or "読みが無いので、そのまま補完が始まる。",
  })
  add({
    id = "t." .. from .. ".esc",
    from = from, event = "esc", to = "N_OFF",
    effects = reading and { "commit_reading", "reset_state", "restore_mapping", "clear_extmark" }
      or { "reset_state", "restore_mapping", "clear_extmark" },
    status = "ok", refs = { "function/disable.lua:21-27", "#190" },
    observed = (from == "IX_POINT" and { "O-completion-x-esc" })
      or (from == "IX_ROMAJI" and { "O-completion-x-esc-romaji" })
      or {},
  })
  add({
    id = "t." .. from .. ".ctrl_c",
    from = from, event = "ctrl_c", to = "N_WAIT",
    effects = {},
    status = "ok", refs = { "cleanup.lua:187,225-248", "#70", "#142" },
    observed = (from == "IX_POINT" and { "O-completion-x-ctrlc" })
      or (from == "IX_ROMAJI" and { "O-completion-x-ctrlc-romaji" })
      or {},
    notes = "SafeState の one-shot を作るだけ。確定は safestate の遷移で起きる。",
  })
end

-- 組み込みの補完（ic）の中
add({
  id = "t.IC.completion_next",
  from = "IC", event = "completion_next", to = "IC",
  effects = { "pass_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-next" },
})
add({
  id = "t.IC.completion_accept.C-y",
  from = "IC", event = "completion_accept", to = "I_DIRECT",
  effects = { "pass_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-accept" },
  notes = "<C-y> は候補を受け入れる。pre-edit は無いので、そのまま insert に戻る。",
})
add({
  id = "t.IC.completion_cancel.C-e",
  from = "IC", event = "completion_cancel", to = "I_DIRECT",
  effects = { "pass_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-c-e" },
  notes = "<C-e> は候補を取り消して元の文字に戻す。",
})
add({
  id = "t.IC.completion_newline",
  from = "IC", event = "completion_newline", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-cr" },
  notes = "観測では候補を確定して改行した（バッファに候補 + 空行）。",
})
add({
  id = "t.IC.completion_tab",
  from = "IC", event = "completion_tab", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-tab" },
  notes = "観測では候補を確定してタブを入れた。",
})
add({
  id = "t.IC.char",
  from = "IC", event = "char", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-char" },
  notes = "候補を確定してから、その文字を入れる。",
})
add({
  id = "t.IC.char_shift",
  from = "IC", event = "char_shift", to = "I_ROMAJI",
  effects = { "feed_key", "render" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-shift" },
  notes = "観測では補完が終わり、シフト付きの文字で ▽ を開始した。",
})
add({
  id = "t.IC.bs",
  from = "IC", event = "bs", to = "IC",
  effects = { "pass_key" },
  status = "ok", refs = { "#190" }, observed = { "O-completion-bs" },
  notes = "候補の最後の 1 文字を消す。補完は続く。",
})
add({
  id = "t.IC.key_q",
  from = "IC", event = "key_q", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "unknown", refs = { "#190", "#174" },
  notes = "組み込みの補完では q は文字として入る（blink のときはカタカナで確定する）。",
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
  status = "ok", refs = { "cleanup.lua:187" }, observed = { "O-completion-ctrlc" },
  notes = "SafeState で insert を抜ける。",
})
add({
  id = "t.IC.text_changed_p",
  from = "IC", event = "text_changed_p", to = "IC",
  effects = { "pass_key" },
  status = "ok", refs = { "cleanup.lua:150-165,283-286", "#190" },
  notes = "check_stale は mode が i / c でないので何もしない（観測でも pre-edit は無いまま）。",
})
add({
  id = "t.IC.complete_done",
  from = "IC", event = "complete_done", to = "I_DIRECT",
  effects = { "reset_state" },
  status = "unknown", refs = { "cleanup.lua:150-165,283-286", "#190" },
  notes = "補完が終わったあとの CompleteDone。この時点ではもう insert に戻っていることが多い。",
})
add({
  id = "t.IC.winleave",
  from = "IC", event = "winleave", to = "N_OFF",
  effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
  status = "unknown", refs = { "cleanup.lua:269-281", "#169" },
  notes = "読みが無い（IC）ので drop は起きない。P1 は破らない。",
})

-- blink.cmp のメニュー（User イベントで開閉する）
add({
  id = "t.I_POINT.blink_refresh",
  from = "I_POINT", event = "blink_refresh", to = "I_BLINK_POINT",
  effects = { "keep", "show_completion", "render" },
  status = "ok", refs = { "completion/init.lua:246-273", "#24", "#143", "#174" },
  notes = "読みが minLength 以上なら、blink が skkeleton の source でメニューを開く。",
})
add({
  id = "t.I_BLINK_POINT.blink_refresh",
  from = "I_BLINK_POINT", event = "blink_refresh", to = "I_BLINK_POINT",
  effects = { "keep", "show_completion", "render" },
  status = "ok", refs = { "completion/init.lua:246-273", "#143", "#174" },
  notes = "読みが変わるとメニューを開き直す。",
})
add({
  id = "t.I_BLINK_POINT.blink_menu_open",
  from = "I_BLINK_POINT", event = "blink_menu_open", to = "I_BLINK_POINT",
  effects = { "keep", "show_completion" },
  status = "ok", refs = { "completion/init.lua:143-151", "#143", "#174" },
  notes = "メニューをカーソルに揃える（align_to = cursor）。",
})
add({
  id = "t.I_POINT.blink_menu_open",
  from = "I_POINT", event = "blink_menu_open", to = "I_BLINK_POINT",
  effects = { "keep", "show_completion" },
  status = "ok", refs = { "completion/init.lua:143-151", "#143", "#174" },
  notes = "blink の auto_show が先にメニューを開く道。",
})
add({
  id = "t.I_BLINK_POINT.blink_menu_close",
  from = "I_BLINK_POINT", event = "blink_menu_close", to = "I_POINT",
  effects = { "keep", "hide_completion" },
  status = "ok", refs = { "completion/init.lua:152-158", "#143", "#174" },
})
add({
  id = "t.I_BLINK_POINT.blink_hide",
  from = "I_BLINK_POINT", event = "blink_hide", to = "I_POINT",
  effects = { "keep", "hide_completion" },
  status = "ok", refs = { "completion/init.lua:135-142", "#24" },
})
add({
  id = "t.I_OFF.blink_hide",
  from = "I_OFF", event = "blink_hide", to = "I_OFF",
  effects = { "hide_completion" },
  status = "ok", refs = { "completion/init.lua:135-142", "#24" },
  notes = "有効化・無効化のときに、skkeleton が開いたものではないメニューも閉じる。",
})
add({
  id = "t.N_OFF.blink_hide",
  from = "N_OFF", event = "blink_hide", to = "N_OFF",
  effects = { "hide_completion" },
  status = "ok", refs = { "completion/init.lua:135-142", "#24" },
})
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".blink_refresh",
    from = from, event = "blink_refresh", to = from,
    effects = { "hide_completion" },
    status = "ok", refs = { "completion/init.lua:246-273", "#24" },
    notes = "▽ の入力中でないので、blink のメニューは開かない（開いていれば閉じる）。",
  })
end

-- blink のメニューの中のキー
add({
  id = "t.I_BLINK_POINT.completion_next",
  from = "I_BLINK_POINT", event = "completion_next", to = "I_BLINK_POINT",
  effects = { "pass_key", "keep" },
  status = "ok", refs = { "#190", "blink.cmp keymap super-tab" }, observed = { "O-blink-next" },
  notes = "<C-n> / <C-p> は選択を動かす。読みは残る。",
})
add({
  id = "t.I_BLINK_POINT.completion_accept",
  from = "I_BLINK_POINT", event = "completion_accept", to = "I_BLINK_POINT",
  effects = { "pass_key", "keep" },
  status = "unknown", refs = { "#190" },
  notes = "<C-y> は blink の既定のキーマップには無い。Neovim の i_CTRL-Y に落ちる（未観測）。",
})
add({
  id = "t.I_BLINK_POINT.completion_tab.tab",
  from = "I_BLINK_POINT", event = "completion_tab", to = "I_DIRECT",
  effects = { "commit_candidate", "reset_state", "hide_completion" },
  status = "ok", refs = { "#190", "blink.cmp keymap super-tab" }, observed = { "O-blink-tab" },
  notes = "super-tab の <Tab>（select_and_accept）。観測では候補 漢字 を確定した。",
})
add({
  id = "t.I_BLINK_POINT.completion_tab.s-tab",
  from = "I_BLINK_POINT", event = "completion_tab", to = "I_DIRECT",
  effects = { "commit_reading", "feed_key", "reset_state", "clear_extmark", "hide_completion" },
  status = "ok", refs = { "#190", "blink.cmp keymap super-tab" }, observed = { "O-blink-s-tab" },
  notes = "super-tab の <S-Tab> はメニューを選ばずに fallback し、guard が読みを確定してからタブを流す。",
})
add({
  id = "t.I_BLINK_POINT.completion_newline.accept",
  from = "I_BLINK_POINT", event = "completion_newline", to = "I_DIRECT",
  guard = { { "config.eggLikeNewline", "=", true } },
  effects = { "commit_candidate", "reset_state", "hide_completion" },
  status = "unknown", refs = { "main.lua:84-87", "doc/skkeleton.txt:516-518", "#190" },
  notes = "eggLikeNewline = true のときの <CR>。選んだ候補で確定する（未観測）。",
})
add({
  id = "t.I_BLINK_POINT.completion_newline.newline",
  from = "I_BLINK_POINT", event = "completion_newline", to = "I_DIRECT",
  guard = { { "config.eggLikeNewline", "=", false } },
  effects = { "commit_reading", "feed_key", "reset_state", "clear_extmark", "hide_completion" },
  status = "ok", refs = { "main.lua:84-87", "#190" }, observed = { "O-blink-cr" },
  notes = "既定（eggLikeNewline = false）では blink は <CR> を取らず、guard が読みを確定して改行する。",
})
add({
  id = "t.I_BLINK_POINT.completion_cancel",
  from = "I_BLINK_POINT", event = "completion_cancel", to = "I_POINT",
  effects = { "keep", "hide_completion" },
  status = "ok", refs = { "#190", "blink.cmp keymap super-tab" }, observed = { "O-blink-c-e" },
  notes = "<C-e> はメニューを閉じる。読みと pre-edit は残る。",
})
add({
  id = "t.I_BLINK_POINT.char",
  from = "I_BLINK_POINT", event = "char", to = "I_POINT",
  effects = { "feed_key", "render" },
  status = "unknown", refs = { "#190" }, observed = { "O-blink-char" },
  notes = "観測では読みに足されて I_POINT に戻り、メニューは閉じていた。読み直しは次の refresh で開く（タイミング次第）。",
})
add({
  id = "t.I_BLINK_POINT.bs",
  from = "I_BLINK_POINT", event = "bs", to = "I_BLINK_POINT",
  effects = { "pass_key", "keep", "render" },
  status = "ok", refs = { "#190" }, observed = { "O-blink-bs" },
  notes = "読みの最後の 1 文字を削る。メニューは開いたまま。",
})
add({
  id = "t.I_BLINK_POINT.space",
  from = "I_BLINK_POINT", event = "space", to = "I_SELECT",
  effects = { "keep", "render", "hide_completion" },
  status = "ok", refs = { "#190" }, observed = { "O-blink-space" },
  notes = "▽ から ▼ へ。blink のメニューは閉じる。",
})
add({
  id = "t.I_BLINK_POINT.key_q",
  from = "I_BLINK_POINT", event = "key_q", to = "I_DIRECT",
  effects = { "commit_reading", "reset_state", "hide_completion" },
  status = "ok", refs = { "#174", "#190" }, observed = { "O-blink-q" },
  notes = "カタカナにして確定する（観測では カンジ がバッファに入った）。",
})
add({
  id = "t.I_BLINK_POINT.cg",
  from = "I_BLINK_POINT", event = "cg", to = "I_DIRECT",
  effects = { "cancel", "reset_state", "hide_completion" },
  status = "ok", refs = { "#190" }, observed = { "O-blink-cg" },
  notes = "読みを取り消して無効化しない（insert のまま）。",
})
add({
  id = "t.I_BLINK_POINT.esc",
  from = "I_BLINK_POINT", event = "esc", to = "N_OFF",
  effects = { "commit_reading", "reset_state", "restore_mapping", "clear_extmark", "hide_completion" },
  status = "ok", refs = { "#190" }, observed = { "O-blink-esc" },
})
add({
  id = "t.I_BLINK_POINT.ctrl_c",
  from = "I_BLINK_POINT", event = "ctrl_c", to = "N_WAIT",
  effects = { "hide_completion" },
  status = "ok", refs = { "cleanup.lua:187,225-248", "#70", "#142" }, observed = { "O-blink-ctrlc" },
  notes = "SafeState で読みを確定して無効化する。",
})
add({
  id = "t.I_BLINK_POINT.ctrl_w",
  from = "I_BLINK_POINT", event = "ctrl_w", to = "I_DIRECT",
  effects = { "drop", "reset_state", "clear_extmark", "hide_completion" },
  status = "gap", refs = { "#8", "#12", "#190" }, observed = { "O-blink-ctrl-w" },
  notes = "読みを捨てる（P1 の破れ）。",
})
add({
  id = "t.I_BLINK_POINT.guard_special",
  from = "I_BLINK_POINT", event = "guard_special", to = "I_DIRECT",
  effects = { "commit_reading", "feed_key", "reset_state", "clear_extmark", "hide_completion" },
  status = "ok", refs = { "guard.lua:50-85", "#56", "#190" }, observed = { "O-blink-left" },
  notes = "guard が読みを確定してから、キーを流す。",
})
add({
  id = "t.I_BLINK_POINT.ctrl_o",
  from = "I_BLINK_POINT", event = "ctrl_o", to = "NI_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "#117", "#190" }, observed = { "O-blink-ctrl-o" },
  notes = "観測ではメニューが開いたまま niI に入り、pre-edit も残った。",
})
add({
  id = "t.I_BLINK_POINT.blink_commit",
  from = "I_BLINK_POINT", event = "blink_commit", to = "I_DIRECT",
  effects = { "commit_candidate", "reset_state", "hide_completion" },
  status = "ok", refs = { "completion/init.lua:221-226", "#190" },
  notes = "blink の source の execute が選んだ語で確定する。",
})
add({
  id = "t.I_BLINK_POINT.winleave",
  from = "I_BLINK_POINT", event = "winleave", to = "N_OFF",
  effects = { "drop", "reset_state", "restore_mapping", "clear_extmark", "hide_completion" },
  status = "gap", refs = { "cleanup.lua:269-281", "#169" },
  notes = "読みを確定しないで捨てる（P1 の破れ、#169）。",
})

-- 無効のあいだに出る blink の buffer 補完（#24）
add({
  id = "t.I_OFF.buffer_menu_open",
  from = "I_OFF", event = "buffer_menu_open", to = "I_OFF_MENU",
  effects = { "show_completion" },
  status = "unknown", refs = { "#24", "completion/init.lua:143-158" },
  notes = "無効でも blink の buffer source がメニューを出す。",
})
add({
  id = "t.I_OFF_MENU.buffer_menu_close",
  from = "I_OFF_MENU", event = "buffer_menu_close", to = "I_OFF",
  effects = { "hide_completion" },
  status = "unknown", refs = { "#24", "completion/init.lua:143-158" },
})
add({
  id = "t.I_OFF_MENU.enable",
  from = "I_OFF_MENU", event = "enable", to = "I_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state", "hide_completion" },
  status = "ok", refs = { "main.lua:101-125", "completion/init.lua:135-142", "#24" },
  observed = { "O-blink-buffer-24" },
  notes = "有効化のあとの skkeleton-enable-post で、buffer のメニューも閉じる（#24 の直し）。",
})
add({
  id = "t.I_OFF_MENU.blink_hide",
  from = "I_OFF_MENU", event = "blink_hide", to = "I_OFF",
  effects = { "hide_completion" },
  status = "ok", refs = { "#24" },
})
add({
  id = "t.I_OFF_MENU.esc",
  from = "I_OFF_MENU", event = "esc", to = "N_OFF",
  effects = { "pass_key", "hide_completion" },
  status = "unknown", refs = { "Vim 本体", "#24" },
})

-- guard が確定するキー・マウス・ホイール・貼り付け（#56、#125、#169、#191）
local function guard_event(event)
  local guard_observed = {
    I_DIRECT = { "O-guard-direct" },
    I_ROMAJI = { "O-guard-romaji" },
    I_POINT = {
      "O-guard-cdot", "O-guard-f5", "O-guard-s-cr", "O-guard-left", "O-guard-c-left",
      "O-guard-s-up", "O-guard-s-f1",
    },
    I_SELECT = { "O-guard-select" },
  }
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
      status = "ok",
      refs = { "guard.lua:50-85,174-188", "#56", "#191" },
      observed = guard_observed[from],
      notes = "pre-edit があるときは、確定してからキーを insert のまま流す。"
        .. "pre-edit が無い（I_DIRECT）ときは何もせずに流す。"
        .. "観測: <C-.> / <F5> / <S-CR> / <Left> / <C-Left> / <S-Up> / <S-F1>（misc.jsonl）。"
    })
  end
end
guard_event("guard_special")
add({
  id = "t.I_OFF.guard_special",
  from = "I_OFF", event = "guard_special", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:174-188", "#191" },
  notes = "無効な insert では guard は何もせず、キーはそのまま Neovim に渡る。",
})

-- 同じウィンドウのクリック。カーソルが動いたときだけ確定する
add({
  id = "t.I_DIRECT.mouse_click",
  from = "I_DIRECT", event = "mouse_click", to = "I_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "cleanup.lua:120-160", "#56", "#191" },
  notes = "読みが無いので、カーソルが動いても何も確定しない。",
})
add({
  id = "t.I_OFF.mouse_click",
  from = "I_OFF", event = "mouse_click", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "#191" },
  notes = "無効な insert ではクリックは Neovim のカーソル移動だけ。",
})
add({
  id = "t.N_OFF.mouse_click",
  from = "N_OFF", event = "mouse_click", to = "N_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "Vim 本体", "#47", "#191" },
  notes = "normal のクリックは Neovim のカーソル移動だけ。#47 の再現の最後のクリック。",
})
for _, from in ipairs({ "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  local commit = from == "I_SELECT" and "commit_candidate" or "commit_reading"
  add({
    id = "t." .. from .. ".mouse_click",
    from = from, event = "mouse_click", to = "I_DIRECT",
    effects = { commit, "reset_state", "feed_key", "clear_extmark" },
    status = "ok", refs = { "cleanup.lua:120-160", "#56", "#191" },
    notes = "同じウィンドウのクリックでカーソルが動くと、CursorMovedI のずれの検出が読みを確定する。"
      .. "観測: misc.jsonl の mouse.click.left.*。",
  })
  add({
    id = "t." .. from .. ".mouse_click.keep",
    from = from, event = "mouse_click", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "cleanup.lua:120-160", "#191" },
    notes = "同じ位置のクリックではカーソルが動かず、ずれの検出が走らないので pre-edit が残る。"
      .. "観測: misc.jsonl の mouse.click.end（I_POINT）。",
  })
end

-- 別のウィンドウのクリック（WinLeave）
for _, from in ipairs({ "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".mouse_click_other",
    from = from, event = "mouse_click_other", to = "I_OFF",
    effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
    status = "gap", refs = { "cleanup.lua:269-281", "#169", "#191" },
    notes = "別のウィンドウをクリックすると WinLeave が走り、読みを確定せずに捨てる（#169）。"
      .. "insert に戻ったまま無効になる。観測: misc.jsonl の mouse.otherwin.*。",
  })
end
add({
  id = "t.I_DIRECT.mouse_click_other",
  from = "I_DIRECT", event = "mouse_click_other", to = "I_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "ok", refs = { "cleanup.lua:269-281", "#191" },
  notes = "読みが無いので drop は起きない。insert に戻ったまま無効になる。",
})
add({
  id = "t.I_OFF.mouse_click_other",
  from = "I_OFF", event = "mouse_click_other", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "#191" },
})
for _, from in ipairs({ "V_PRE_POINT", "V_PRE_SELECT" }) do
  add({
    id = "t." .. from .. ".mouse_click_other",
    from = from, event = "mouse_click_other", to = "I_OFF",
    effects = { "drop", "reset_state", "restore_mapping", "clear_extmark" },
    status = "gap", refs = { "cleanup.lua:269-281", "#47", "#169", "#191" },
    notes = "visual のときに別のウィンドウをクリックすると、WinLeave が読みを捨てて無効にする。"
      .. "観測: misc.jsonl の winleave.visual.mouse。",
  })
end

-- ダブルクリック・ドラッグ（visual / select へ）
add({
  id = "t.I_OFF.mouse_select",
  from = "I_OFF", event = "mouse_select", to = "N_OFF",
  effects = { "reset_state", "restore_mapping", "clear_extmark" },
  status = "ok", refs = { "cleanup.lua:179-190,207-214", "#191" },
  notes = "無効な insert からでも、マウスで選択すると visual に入り、無効のまま。"
    .. "観測: misc.jsonl の mouse.dclick.off。",
})

-- ホイール。スクロールだけなので確定しない
local wheel_observed = { I_POINT = { "O-wheel-point" } }
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".wheel",
    from = from, event = "wheel", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "guard.lua:59-61", "keys.md §5", "#191" },
    observed = wheel_observed[from],
    notes = "guard は確定しない。スクロールはカーソルを動かさないので、pre-edit が残る。"
      .. "観測: misc.jsonl の mouse.wheel.*。",
  })
end
add({
  id = "t.I_OFF.wheel",
  from = "I_OFF", event = "wheel", to = "I_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:59-61", "#191" },
})

-- 貼り付け。最初のチャンクでだけ確定する（#125）
local paste_observed = {
  I_DIRECT = { "O-paste-direct" },
  I_ROMAJI = { "O-paste-romaji" },
  I_POINT = { "O-paste-point" },
  I_SELECT = { "O-paste-select" },
}
for _, from in ipairs({ "I_DIRECT", "I_ROMAJI", "I_POINT", "I_SELECT" }) do
  add({
    id = "t." .. from .. ".paste",
    from = from, event = "paste", to = "I_DIRECT",
    effects = from == "I_SELECT" and { "commit_candidate", "reset_state", "clear_extmark", "feed_key" }
      or from ~= "I_DIRECT" and { "commit_reading", "reset_state", "clear_extmark", "feed_key" }
      or { "feed_key" },
    status = "ok", refs = { "paste.lua:31-69", "#57", "#125", "#191" },
    observed = paste_observed[from],
    notes = "最初のチャンクで pre-edit を確定してから、元の vim.paste に渡す（#125）。"
      .. "2 つ目以降のチャンクでは確定しない（観測: paste.chunks）。"
      .. "読みがローマ字の打ちかけだけのときは、そのままの文字（k など）を確定する。",
  })
end
add({
  id = "t.I_OFF.paste",
  from = "I_OFF", event = "paste", to = "I_OFF",
  effects = { "feed_key" },
  status = "ok", refs = { "paste.lua:31-69", "#191" },
  notes = "無効な insert では、貼り付けはバッファを書き換えるだけ。",
})

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

-- terminal（t / nt）。#188（07b）
--
-- 観測は semantics/explore/explore.lua の terminal プロファイル（`terminal cat`、子の nvim、
-- 一時ディレクトリの辞書、HISTFILE=/dev/null）で取った。t では pre-edit を本物の文字として
-- ジョブへ流し、BS で消して書き直すので、端末の行には書き直しの BS が ^H として残る。
--
-- t のキーは、マップされた 102 個なら insert と同じイベント（char / esc / space など）で扱う。
-- ここに書くのは、terminal にだけある道と、t / nt の移り変わり。
local T_ON = { "T_DIRECT", "T_ROMAJI", "T_POINT", "T_SELECT" }
local T_NORMAL = {
  T_DIRECT = "T_NORMAL_DIRECT",
  T_ROMAJI = "T_NORMAL_ROMAJI",
  T_POINT = "T_NORMAL_POINT",
  T_SELECT = "T_NORMAL_SELECT",
}

-- normal から terminal を開く
add({
  id = "t.N_OFF.term_open",
  from = "N_OFF", event = "term_open", to = "T_OFF",
  effects = { "pass_key" },
  status = "ok", refs = { "explore.lua の terminal プロファイル", "keys.md §5" },
  notes = "terminal を開くと Vim のモードは t で、skk は無効のまま（T_OFF）。"
    .. "探索器の terminal プロファイルでは `terminal cat` を実行してから enable する。",
})

-- 有効化・無効化
add({
  id = "t.T_OFF.enable",
  from = "T_OFF", event = "enable", to = "T_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "main.lua:101-125" }, observed = { "O-t-enable" },
  notes = "t で有効化すると、t のマッピングが張られる。",
})
add({
  id = "t.T_OFF.toggle",
  from = "T_OFF", event = "toggle", to = "T_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "main.lua:169-175" }, observed = { "O-t-toggle-on" },
  notes = "無効なので enable 側。`<Plug>(skkeleton-toggle)` はキー列で再生できる。",
})
add({
  id = "t.T_ESCAPE.enable",
  from = "T_ESCAPE", event = "enable", to = "T_DIRECT",
  effects = { "save_mapping", "install_mapping", "reset_state" },
  status = "ok", refs = { "main.lua:101-125" }, observed = { "O-t-esc-enable" },
  notes = "state.type が escape でも、<Plug> からの enable は Context を作り直す。",
})
for _, from in ipairs(T_ON) do
  local commit = from == "T_SELECT" and "commit_candidate" or from ~= "T_DIRECT" and "commit_reading" or nil
  local obs_disable = ({ T_DIRECT = { "O-t-disable-direct" }, T_POINT = { "O-t-disable" } })[from] or {}
  local obs_toggle = ({ T_DIRECT = { "O-t-toggle-off-direct" }, T_POINT = { "O-t-toggle-off" } })[from] or {}
  local obs_esc = ({
    T_DIRECT = { "O-t-esc-direct" },
    T_ROMAJI = { "O-t-romaji-esc" },
    T_POINT = { "O-t-esc" },
    T_SELECT = { "O-t-select-esc" },
  })[from] or {}
  add({
    id = "t." .. from .. ".disable",
    from = from, event = "disable", to = "T_OFF",
    effects = commit and { commit, "restore_mapping", "reset_state" } or { "restore_mapping", "reset_state" },
    status = "ok", refs = { "main.lua:129-139", "function/disable.lua:13-18" },
    observed = obs_disable,
    notes = "読みがあれば確定してから無効にする。t のまま。",
  })
  add({
    id = "t." .. from .. ".toggle",
    from = from, event = "toggle", to = "T_OFF",
    effects = commit and { commit, "restore_mapping", "reset_state" } or { "restore_mapping", "reset_state" },
    status = "ok", refs = { "main.lua:169-175", "function/disable.lua:13-18" },
    observed = obs_toggle,
  })
  add({
    id = "t." .. from .. ".esc",
    from = from, event = "esc", to = "T_ESCAPE",
    effects = commit and { commit, "restore_mapping", "reset_state", "feed_key" }
      or { "restore_mapping", "reset_state", "feed_key" },
    status = "ok", refs = { "function/disable.lua:21-27", "function/common.lua:59-68" },
    observed = obs_esc,
    notes = "読みを確定して無効にし、端末へ Esc を流す。ModeChanged は起きないので state.type は escape のまま（T_ESCAPE）。",
  })
end

-- terminal → terminal-normal（<C-\><C-n>）。読みと pre-edit を持ち越す（#74）
for _, from in ipairs(T_ON) do
  local obs_nt = ({
    T_DIRECT = { "O-t-nt-direct" },
    T_ROMAJI = { "O-t-romaji-nt" },
    T_POINT = { "O-t-nt" },
    T_SELECT = { "O-t-select-nt" },
  })[from] or {}
  add({
    id = "t." .. from .. ".t_normal",
    from = from, event = "t_normal", to = T_NORMAL[from],
    effects = { "keep" },
    status = "ok", refs = { "guard.lua:114-124,154-163", "cleanup.lua:218-248", "#74" },
    observed = obs_nt,
    notes = "guard は pre-edit を確定せずに通す。ModeChanged の safe_reset は nt のあいだ何もしない。"
      .. "端末の行には pre-edit の文字が残ったまま。",
  })
end
add({
  id = "t.T_OFF.t_normal",
  from = "T_OFF", event = "t_normal", to = "T_NORMAL_OFF",
  effects = {},
  status = "ok", refs = { "guard.lua:114-124,154-163", "cleanup.lua:218-248" }, observed = { "O-t-disable-nt" },
})
add({
  id = "t.T_ESCAPE.t_normal",
  from = "T_ESCAPE", event = "t_normal", to = "T_NORMAL_OFF",
  effects = { "reset_state" },
  status = "ok", refs = { "cleanup.lua:218-221" }, observed = { "O-t-esc-nt" },
  notes = "state.type が escape なので、ModeChanged の分岐でその場で reset する。",
})

-- terminal-normal → terminal（i / a / I / A）。読みと pre-edit が残っている
for _, from in ipairs(T_ON) do
  local obs_back = ({
    T_DIRECT = { "O-t-nt-direct-back" },
    T_ROMAJI = { "O-t-romaji-nt-back" },
    T_POINT = { "O-t-nt-back" },
    T_SELECT = { "O-t-select-nt-back" },
  })[from] or {}
  add({
    id = "t." .. T_NORMAL[from] .. ".nt_insert",
    from = T_NORMAL[from], event = "nt_insert", to = from,
    effects = from == "T_DIRECT" and {} or { "keep" },
    status = "ok", refs = { "tests/test_e2e_cmdline.lua:147-172", "#74" },
    observed = obs_back,
    notes = "nt から t に戻る。読みは捨てずに続きから打てる。",
  })
end
add({
  id = "t.T_NORMAL_OFF.nt_insert",
  from = "T_NORMAL_OFF", event = "nt_insert", to = "T_OFF",
  effects = {},
  status = "ok", refs = { "tests/test_e2e_cmdline.lua:147-172" }, observed = { "O-t-disable-nt-back" },
  notes = "skk が無効のまま t に戻る。",
})
-- nt で端末のバッファを編集するキー（nomodifiable なので E21、状態は変わらない）
for _, from in ipairs({ "T_NORMAL_DIRECT", "T_NORMAL_ROMAJI", "T_NORMAL_POINT", "T_NORMAL_SELECT", "T_NORMAL_OFF" }) do
  add({
    id = "t." .. from .. ".nt_edit",
    from = from, event = "nt_edit", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "keys.md §5", "#188" },
    observed = from == "T_NORMAL_POINT" and { "O-t-nt-edit" } or {},
    notes = "terminal のバッファは nomodifiable。x / dd / J / o / u / R は E21 になり、何も変わらない。"
      .. "p / P / . は何もしない。",
  })
  add({
    id = "t." .. from .. ".t_normal_again",
    from = from, event = "t_normal", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "Vim 本体" },
    observed = from == "T_NORMAL_POINT" and { "O-t-nt-again" } or {},
    notes = "nt で <C-\\><C-n> を押しても何も起きない。",
  })
  add({
    id = "t." .. from .. ".esc",
    from = from, event = "esc", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "Vim 本体" },
    observed = from == "T_NORMAL_POINT" and { "O-t-nt-esc" } or {},
    notes = "nt の <Esc> は normal の <Esc>。skk は何もしない。",
  })
  add({
    id = "t." .. from .. ".ctrl_c",
    from = from, event = "ctrl_c", to = from,
    effects = { "pass_key" },
    status = "ok", refs = { "Vim 本体" },
    observed = from == "T_NORMAL_POINT" and { "O-t-nt-ctrl-c" } or {},
  })
end

-- 無効な terminal（T_OFF / T_ESCAPE）では、キーはジョブへそのまま渡る
local T_PASS_EVENTS = {
  "char", "char_shift", "key_x", "key_X", "key_L", "key_l", "key_q", "key_semicolon", "key_slash",
  "key_gt", "key_cq", "bs", "cr", "space", "nl", "cg", "esc", "insert_key", "ctrl_o", "ctrl_r",
  "ctrl_v", "ctrl_k", "ctrl_t", "tab", "ctrl_w", "ctrl_u", "ctrl_a", "ctrl_at", "completion_open",
  "completion_accept", "guard_special",
}
for _, from in ipairs({ "T_OFF", "T_ESCAPE" }) do
  for _, event in ipairs(T_PASS_EVENTS) do
    local observed
    if from == "T_OFF" and event == "char" then
      observed = { "O-t-off-char" }
    elseif from == "T_ESCAPE" and event == "char" then
      observed = { "O-t-esc-char" }
    elseif from == "T_ESCAPE" and event == "ctrl_a" then
      observed = { "O-t-esc-ctrl-a" }
    end
    add({
      id = "t." .. from .. "." .. event,
      from = from, event = event, to = from,
      effects = { "pass_key" },
      status = observed and "ok" or "unknown",
      refs = { "guard.lua:139-189", "keys.md §4" },
      observed = observed or {},
      notes = "skk が無効なので、キーは端末のジョブへそのまま渡る。確定はしない。",
    })
  end
end

-- t・有効で pre-edit が無い（T_DIRECT）
add({
  id = "t.T_DIRECT.char.keep",
  from = "T_DIRECT", event = "char", to = "T_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/input.lua:85-120" }, observed = { "O-t-a" },
  notes = "direct でかなテーブルの 1 打が確定する（例: a → あ）。端末のジョブへ流れる。",
})
add({
  id = "t.T_DIRECT.char.romaji",
  from = "T_DIRECT", event = "char", to = "T_ROMAJI",
  effects = { "feed_key", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
  notes = "ローマ字が続く（例: k）。端末の行に打ちかけを書く。",
})
add({
  id = "t.T_DIRECT.char_shift",
  from = "T_DIRECT", event = "char_shift", to = "T_ROMAJI",
  effects = { "render" },
  status = "ok", refs = { "function/input.lua:85-120" }, observed = { "O-t-k" },
})
add({
  id = "t.T_DIRECT.char_shift.point",
  from = "T_DIRECT", event = "char_shift", to = "T_POINT",
  effects = { "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.T_DIRECT.key_X",
  from = "T_DIRECT", event = "key_X", to = "T_ROMAJI",
  effects = { "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.T_DIRECT.key_l",
  from = "T_DIRECT", event = "key_l", to = "T_OFF",
  effects = { "restore_mapping", "reset_state" },
  status = "ok", refs = { "keymap.lua:37", "function/disable.lua", "#67" },
  notes = "既定のかなテーブルのときだけ。t のまま無効になる。",
})
add({
  id = "t.T_DIRECT.key_q",
  from = "T_DIRECT", event = "key_q", to = "T_DIRECT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:38" },
  notes = "かなモードをカタカナにする。クラスは変えない（P11 の外）。",
})
add({
  id = "t.T_DIRECT.key_semicolon",
  from = "T_DIRECT", event = "key_semicolon", to = "T_ROMAJI",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:39", "function/input.lua:147-" },
  notes = "送り仮名の入力へ。",
})
add({
  id = "t.T_DIRECT.key_slash",
  from = "T_DIRECT", event = "key_slash", to = "T_DIRECT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:40" },
  notes = "abbrev モードへ。クラスは変えない。",
})
add({
  id = "t.T_DIRECT.key_L",
  from = "T_DIRECT", event = "key_L", to = "T_DIRECT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:41" },
})
add({
  id = "t.T_DIRECT.key_cq",
  from = "T_DIRECT", event = "key_cq", to = "T_DIRECT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:33" },
  notes = "半角カタカナにする。読みが無いのでクラスは変えない。",
})
add({
  id = "t.T_DIRECT.key_gt",
  from = "T_DIRECT", event = "key_gt", to = "T_DIRECT",
  effects = { "feed_key" },
  status = "unknown", refs = { "keymap.lua:34" },
})
add({
  id = "t.T_DIRECT.space",
  from = "T_DIRECT", event = "space", to = "T_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/henkan.lua:21-56" }, observed = { "O-t-space" },
  notes = "読みが無いので、<Space> はジョブへそのまま渡る（端末の行に空白が入る）。",
})
add({
  id = "t.T_DIRECT.bs",
  from = "T_DIRECT", event = "bs", to = "T_DIRECT",
  effects = { "feed_key" },
  status = "unknown", refs = { "function/input.lua:178-204" },
  notes = "打ちかけが無いので、端末の 1 文字を消す。",
})
add({
  id = "t.T_DIRECT.cr",
  from = "T_DIRECT", event = "cr", to = "T_DIRECT",
  effects = { "feed_key" },
  status = "unknown", refs = { "function/common.lua:59-68" },
})
add({
  id = "t.T_DIRECT.nl",
  from = "T_DIRECT", event = "nl", to = "T_DIRECT",
  effects = {},
  status = "unknown", refs = { "function/common.lua:18-45" },
  notes = "確定する読みが無いので、何も流さない。",
})
add({
  id = "t.T_DIRECT.cg",
  from = "T_DIRECT", event = "cg", to = "T_DIRECT",
  effects = {},
  status = "unknown", refs = { "keymap.lua:28" },
})
add({
  id = "t.T_DIRECT.insert_key",
  from = "T_DIRECT", event = "insert_key", to = "T_DIRECT",
  effects = { "pass_key" },
  status = "unknown", refs = { "guard.lua:15-16,143-145" },
  notes = "guard は <Insert> で確定しない。t ではジョブへそのまま渡る。",
})
add({
  id = "t.T_DIRECT.ctrl_c",
  from = "T_DIRECT", event = "ctrl_c", to = "T_DIRECT",
  effects = { "pass_key" },
  status = "unknown", refs = { "guard.lua:89-112" },
})
add({
  id = "t.T_DIRECT.ctrl_o",
  from = "T_DIRECT", event = "ctrl_o", to = "T_DIRECT",
  effects = { "pass_key" },
  status = "unknown", refs = { "guard.lua:89-112" },
  notes = "t の <C-o> は insert-normal ではなく、ジョブへ渡る（tty の C-o）。",
})
add({
  id = "t.T_DIRECT.ctrl_r",
  from = "T_DIRECT", event = "ctrl_r", to = "T_DIRECT",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:89-112" }, observed = { "O-t-ctrl-r-direct" },
})
add({
  id = "t.T_DIRECT.ctrl_a",
  from = "T_DIRECT", event = "ctrl_a", to = "T_DIRECT",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:89-112" }, observed = { "O-t-ctrl-a-direct" },
})
for _, event in ipairs({ "ctrl_v", "ctrl_k", "ctrl_t", "tab", "ctrl_w", "ctrl_u", "ctrl_at", "completion_open", "completion_accept", "guard_special" }) do
  add({
    id = "t.T_DIRECT." .. event,
    from = "T_DIRECT", event = event, to = "T_DIRECT",
    effects = { "pass_key" },
    status = "unknown", refs = { "guard.lua:89-112", "keys.md §4" },
  })
end

-- t・有効で打ちかけがある（T_ROMAJI）
add({
  id = "t.T_ROMAJI.char.keep",
  from = "T_ROMAJI", event = "char", to = "T_ROMAJI",
  effects = { "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.T_ROMAJI.char.commit",
  from = "T_ROMAJI", event = "char", to = "T_DIRECT",
  effects = { "feed_key" },
  status = "ok", refs = { "function/input.lua:85-120" }, observed = { "O-t-ka" },
  notes = "打ちかけがかなに解決して確定する（k → a で か）。",
})
add({
  id = "t.T_ROMAJI.char_shift",
  from = "T_ROMAJI", event = "char_shift", to = "T_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.T_ROMAJI.key_X",
  from = "T_ROMAJI", event = "key_X", to = "T_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.T_ROMAJI.key_l",
  from = "T_ROMAJI", event = "key_l", to = "T_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state" },
  status = "unknown", refs = { "keymap.lua:37", "function/disable.lua", "#67" },
})
add({
  id = "t.T_ROMAJI.key_q",
  from = "T_ROMAJI", event = "key_q", to = "T_ROMAJI",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:38" },
})
add({
  id = "t.T_ROMAJI.key_semicolon",
  from = "T_ROMAJI", event = "key_semicolon", to = "T_POINT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:39" },
})
add({
  id = "t.T_ROMAJI.key_slash",
  from = "T_ROMAJI", event = "key_slash", to = "T_ROMAJI",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:40" },
})
add({
  id = "t.T_ROMAJI.key_L",
  from = "T_ROMAJI", event = "key_L", to = "T_ROMAJI",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:41" },
})
add({
  id = "t.T_ROMAJI.key_cq",
  from = "T_ROMAJI", event = "key_cq", to = "T_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "unknown", refs = { "keymap.lua:33" },
  notes = "半角カタカナにして確定する。",
})
add({
  id = "t.T_ROMAJI.key_gt",
  from = "T_ROMAJI", event = "key_gt", to = "T_POINT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:34" },
})
add({
  id = "t.T_ROMAJI.space",
  from = "T_ROMAJI", event = "space", to = "T_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/henkan.lua:21-56" },
  notes = "打ちかけを解決して変換に入る。",
})
add({
  id = "t.T_ROMAJI.bs",
  from = "T_ROMAJI", event = "bs", to = "T_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/input.lua:178-204" }, observed = { "O-t-romaji-bs" },
  notes = "打ちかけの 1 文字を削る。▽ だけになり、クラスは T_POINT（観測）。"
    .. "もう一度 <BS> を押すと T_DIRECT になる（T_POINT.bs.empty の道）。",
})
add({
  id = "t.T_ROMAJI.cr",
  from = "T_ROMAJI", event = "cr", to = "T_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "unknown", refs = { "function/common.lua:59-68" },
})
add({
  id = "t.T_ROMAJI.nl",
  from = "T_ROMAJI", event = "nl", to = "T_DIRECT",
  effects = { "commit_reading" },
  status = "unknown", refs = { "function/common.lua:18-45" },
})
add({
  id = "t.T_ROMAJI.cg",
  from = "T_ROMAJI", event = "cg", to = "T_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "unknown", refs = { "keymap.lua:28", "function/common.lua:71-86" },
})
add({
  id = "t.T_ROMAJI.insert_key",
  from = "T_ROMAJI", event = "insert_key", to = "T_ROMAJI",
  effects = { "pass_key" },
  status = "unknown", refs = { "guard.lua:15-16,143-145" },
})
add({
  id = "t.T_ROMAJI.tab",
  from = "T_ROMAJI", event = "tab", to = "T_ROMAJI",
  effects = { "pass_key" },
  status = "unknown", refs = { "guard.lua:89-96" },
})
add({
  id = "t.T_ROMAJI.ctrl_c",
  from = "T_ROMAJI", event = "ctrl_c", to = "T_DIRECT",
  effects = { "commit_reading", "pass_key" },
  status = "unknown", refs = { "guard.lua:89-112" },
})
add({
  id = "t.T_ROMAJI.ctrl_o",
  from = "T_ROMAJI", event = "ctrl_o", to = "T_DIRECT",
  effects = { "commit_reading", "pass_key" },
  status = "unknown", refs = { "guard.lua:89-112" },
})
add({
  id = "t.T_ROMAJI.ctrl_a",
  from = "T_ROMAJI", event = "ctrl_a", to = "T_DIRECT",
  effects = { "commit_reading", "pass_key" },
  status = "ok", refs = { "guard.lua:89-112" }, observed = { "O-t-romaji-ctrl-a" },
})
for _, event in ipairs({ "ctrl_r", "ctrl_v", "ctrl_k", "ctrl_t", "ctrl_w", "ctrl_u", "ctrl_at", "completion_open", "completion_accept", "guard_special" }) do
  add({
    id = "t.T_ROMAJI." .. event,
    from = "T_ROMAJI", event = event, to = "T_DIRECT",
    effects = { "commit_reading", "pass_key" },
    status = "unknown", refs = { "guard.lua:89-112", "keys.md §4" },
  })
end

-- t・有効で ▽（T_POINT）
add({
  id = "t.T_POINT.char",
  from = "T_POINT", event = "char", to = "T_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/input.lua:85-120" }, observed = { "O-t-kan-n" },
})
add({
  id = "t.T_POINT.char_shift",
  from = "T_POINT", event = "char_shift", to = "T_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.T_POINT.key_X",
  from = "T_POINT", event = "key_X", to = "T_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "function/input.lua:85-120" },
})
add({
  id = "t.T_POINT.key_l",
  from = "T_POINT", event = "key_l", to = "T_OFF",
  effects = { "commit_reading", "restore_mapping", "reset_state" },
  status = "unknown", refs = { "keymap.lua:37", "function/disable.lua", "#67" },
})
add({
  id = "t.T_POINT.key_q",
  from = "T_POINT", event = "key_q", to = "T_POINT",
  effects = { "render" },
  status = "unknown", refs = { "keymap.lua:38" },
})
add({
  id = "t.T_POINT.key_semicolon",
  from = "T_POINT", event = "key_semicolon", to = "T_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:39" },
})
add({
  id = "t.T_POINT.key_slash",
  from = "T_POINT", event = "key_slash", to = "T_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:40" },
})
add({
  id = "t.T_POINT.key_L",
  from = "T_POINT", event = "key_L", to = "T_POINT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:41" },
})
add({
  id = "t.T_POINT.key_gt",
  from = "T_POINT", event = "key_gt", to = "T_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:53", "function/input.lua:206-223" },
})
add({
  id = "t.T_POINT.key_cq",
  from = "T_POINT", event = "key_cq", to = "T_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "ok", refs = { "keymap.lua:33" }, observed = { "O-t-cq" },
  notes = "半角カタカナにして確定する（観測では ｶﾝ）。",
})
add({
  id = "t.T_POINT.space.select",
  from = "T_POINT", event = "space", to = "T_SELECT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/henkan.lua:21-56" }, observed = { "O-t-select" },
})
add({
  id = "t.T_POINT.bs",
  from = "T_POINT", event = "bs", to = "T_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/input.lua:178-204" }, observed = { "O-t-bs" },
})
add({
  id = "t.T_POINT.bs.empty",
  from = "T_POINT", event = "bs", to = "T_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "ok", refs = { "function/input.lua:178-204" }, observed = { "O-t-bs-empty" },
  notes = "読みが空になったとき。",
})
add({
  id = "t.T_POINT.cr",
  from = "T_POINT", event = "cr", to = "T_DIRECT",
  effects = { "commit_reading", "feed_key" },
  status = "ok", refs = { "function/common.lua:59-68" }, observed = { "O-t-cr" },
})
add({
  id = "t.T_POINT.nl",
  from = "T_POINT", event = "nl", to = "T_DIRECT",
  effects = { "commit_reading" },
  status = "ok", refs = { "function/common.lua:18-45" }, observed = { "O-t-nl" },
})
add({
  id = "t.T_POINT.cg",
  from = "T_POINT", event = "cg", to = "T_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "ok", refs = { "keymap.lua:28", "#87" }, observed = { "O-t-cg" },
})
add({
  id = "t.T_POINT.insert_key",
  from = "T_POINT", event = "insert_key", to = "T_POINT",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:15-16,143-145" }, observed = { "O-t-insert" },
  notes = "guard は <Insert> で確定しない。t ではエスケープシーケンスがジョブへ渡る。",
})
add({
  id = "t.T_POINT.tab",
  from = "T_POINT", event = "tab", to = "T_POINT",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:89-96" }, observed = { "O-t-tab" },
  notes = "<Tab> は skk 自身の書き直しに使う制御バイトなので、guard は確定しない（読みは残る）。",
})
add({
  id = "t.T_POINT.ctrl_c",
  from = "T_POINT", event = "ctrl_c", to = "T_DIRECT",
  effects = { "commit_reading", "pass_key" },
  status = "ok", refs = { "guard.lua:89-112" }, observed = { "O-t-ctrlc" },
  notes = "確定してからジョブへ <C-c>（SIGINT）。t のままで、skk は有効のまま。",
})
add({
  id = "t.T_POINT.ctrl_o",
  from = "T_POINT", event = "ctrl_o", to = "T_DIRECT",
  effects = { "commit_reading", "pass_key" },
  status = "ok", refs = { "guard.lua:89-112" }, observed = { "O-t-ctrl-o" },
})
for _, event in ipairs({ "ctrl_r", "ctrl_v", "ctrl_k", "ctrl_t", "ctrl_w", "ctrl_u", "ctrl_a", "ctrl_at", "completion_open", "completion_accept", "guard_special" }) do
  local observed = ({
    ctrl_r = { "O-t-ctrl-r" },
    ctrl_w = { "O-t-ctrl-w" },
    ctrl_u = { "O-t-ctrl-u" },
    ctrl_a = { "O-t-ctrl-a" },
    ctrl_at = { "O-t-ctrl-at" },
    ctrl_v = { "O-t-ctrl-v" },
    ctrl_k = { "O-t-ctrl-k" },
    ctrl_t = { "O-t-ctrl-t" },
    completion_open = { "O-t-ctrl-n" },
    completion_accept = { "O-t-ctrl-y" },
    guard_special = { "O-t-guard" },
  })[event] or {}
  add({
    id = "t.T_POINT." .. event,
    from = "T_POINT", event = event, to = "T_DIRECT",
    effects = { "commit_reading", "pass_key" },
    status = #observed > 0 and "ok" or "unknown", refs = { "guard.lua:89-112", "keys.md §4" },
    observed = observed,
    notes = "ジョブに渡す前に pre-edit を確定する（#121）。",
  })
end

-- t・有効で ▼（T_SELECT）
add({
  id = "t.T_SELECT.char.commit",
  from = "T_SELECT", event = "char", to = "T_DIRECT",
  effects = { "commit_candidate", "feed_key", "reset_state" },
  status = "unknown", refs = { "function/henkan.lua:137-162" },
  notes = "henkan の表に無いキーは、候補を確定してから input として処理し直す。",
})
add({
  id = "t.T_SELECT.char.commit_romaji",
  from = "T_SELECT", event = "char", to = "T_ROMAJI",
  effects = { "commit_candidate", "feed_key", "render" },
  status = "unknown", refs = { "function/henkan.lua:137-162" },
})
add({
  id = "t.T_SELECT.char_shift",
  from = "T_SELECT", event = "char_shift", to = "T_DIRECT",
  effects = { "commit_candidate", "feed_key", "reset_state" },
  status = "unknown", refs = { "function/henkan.lua:137-162" },
})
add({
  id = "t.T_SELECT.key_x.back",
  from = "T_SELECT", event = "key_x", to = "T_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "keymap.lua:51", "function/henkan.lua:116-133" }, observed = { "O-t-select-x" },
  notes = "x は henkanBackward。最初の候補で押すと ▽ に戻る（観測: ▼缶 → ▽かん）。",
})
add({
  id = "t.T_SELECT.key_x.prev",
  from = "T_SELECT", event = "key_x", to = "T_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:51", "function/henkan.lua:116-133" },
})
add({
  id = "t.T_SELECT.key_X",
  from = "T_SELECT", event = "key_X", to = "T_SELECT",
  effects = { "keep", "render" },
  status = "unknown", refs = { "keymap.lua:52", "#129" },
})
add({
  id = "t.T_SELECT.key_l",
  from = "T_SELECT", event = "key_l", to = "T_OFF",
  effects = { "commit_candidate", "restore_mapping", "reset_state" },
  status = "unknown", refs = { "keymap.lua:37", "function/disable.lua", "#67" },
})
add({
  id = "t.T_SELECT.key_q",
  from = "T_SELECT", event = "key_q", to = "T_SELECT",
  effects = { "keep" },
  status = "unknown", refs = { "keymap.lua:38" },
})
add({
  id = "t.T_SELECT.key_semicolon",
  from = "T_SELECT", event = "key_semicolon", to = "T_SELECT",
  effects = { "keep" },
  status = "unknown", refs = { "keymap.lua:39" },
})
add({
  id = "t.T_SELECT.key_slash",
  from = "T_SELECT", event = "key_slash", to = "T_SELECT",
  effects = { "keep" },
  status = "unknown", refs = { "keymap.lua:40" },
})
add({
  id = "t.T_SELECT.key_L",
  from = "T_SELECT", event = "key_L", to = "T_SELECT",
  effects = { "keep" },
  status = "unknown", refs = { "keymap.lua:41" },
})
add({
  id = "t.T_SELECT.key_gt",
  from = "T_SELECT", event = "key_gt", to = "T_POINT",
  effects = { "keep", "render" },
  status = "ok", refs = { "keymap.lua:53" }, observed = { "O-t-select-gt" },
  notes = "▼ から > を押すと、▽> に戻る（観測）。接尾辞の入力を続ける。",
})
add({
  id = "t.T_SELECT.key_cq",
  from = "T_SELECT", event = "key_cq", to = "T_DIRECT",
  effects = { "commit_candidate", "feed_key" },
  status = "unknown", refs = { "keymap.lua:33" },
})
add({
  id = "t.T_SELECT.space.next",
  from = "T_SELECT", event = "space", to = "T_SELECT",
  effects = { "keep", "render" },
  status = "ok", refs = { "function/henkan.lua:90-113" }, observed = { "O-t-select-next" },
})
add({
  id = "t.T_SELECT.bs",
  from = "T_SELECT", event = "bs", to = "T_DIRECT",
  effects = { "commit_candidate", "feed_key", "reset_state" },
  status = "ok", refs = { "function/henkan.lua:137-162" }, observed = { "O-t-select-bs" },
  notes = "候補を確定してから 1 文字消す。",
})
add({
  id = "t.T_SELECT.cr",
  from = "T_SELECT", event = "cr", to = "T_DIRECT",
  effects = { "commit_candidate", "feed_key" },
  status = "ok", refs = { "function/common.lua:59-68" }, observed = { "O-t-select-cr" },
})
add({
  id = "t.T_SELECT.nl",
  from = "T_SELECT", event = "nl", to = "T_DIRECT",
  effects = { "commit_candidate" },
  status = "ok", refs = { "function/common.lua:18-45" }, observed = { "O-t-select-nl" },
})
add({
  id = "t.T_SELECT.cg",
  from = "T_SELECT", event = "cg", to = "T_DIRECT",
  effects = { "cancel", "reset_state" },
  status = "unknown", refs = { "keymap.lua:28", "#87" },
})
add({
  id = "t.T_SELECT.insert_key",
  from = "T_SELECT", event = "insert_key", to = "T_SELECT",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:15-16,143-145" }, observed = { "O-t-select-insert" },
})
add({
  id = "t.T_SELECT.tab",
  from = "T_SELECT", event = "tab", to = "T_SELECT",
  effects = { "pass_key" },
  status = "ok", refs = { "guard.lua:89-96" }, observed = { "O-t-select-tab" },
})
add({
  id = "t.T_SELECT.ctrl_c",
  from = "T_SELECT", event = "ctrl_c", to = "T_DIRECT",
  effects = { "commit_candidate", "pass_key" },
  status = "ok", refs = { "guard.lua:89-112" }, observed = { "O-t-select-ctrlc" },
})
add({
  id = "t.T_SELECT.ctrl_a",
  from = "T_SELECT", event = "ctrl_a", to = "T_DIRECT",
  effects = { "commit_candidate", "pass_key" },
  status = "ok", refs = { "guard.lua:89-112" }, observed = { "O-t-select-ctrl-a" },
  notes = "▼ でも、ジョブに渡す前に候補を確定する（#121）。",
})
for _, event in ipairs({ "ctrl_r", "ctrl_v", "ctrl_k", "ctrl_t", "ctrl_w", "ctrl_u", "ctrl_at", "ctrl_o", "completion_open", "completion_accept", "guard_special" }) do
  add({
    id = "t.T_SELECT." .. event,
    from = "T_SELECT", event = event, to = "T_DIRECT",
    effects = { "commit_candidate", "pass_key" },
    status = "unknown", refs = { "guard.lua:89-112", "keys.md §4" },
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
    id = "O-completion-direct",
    keys = { "<Plug>(skkeleton-enable)", "<C-n>" },
    expect = { "IC" },
    note = "pre-edit が無い状態から <C-n>。補完のモード ic に入る（観測）。",
  },
  {
    id = "O-completion-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<C-n>" },
    expect = { "IC" },
    note = "打ちかけ ▽k から <C-n>。pre-edit が消えて ic になる（観測。#19）。",
  },
  {
    id = "O-completion-select",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-n>" },
    expect = { "IC" },
    note = "▼ から <C-n>。候補が消えて ic になる（観測）。",
  },
  {
    id = "O-completion-x",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-x>" },
    expect = { "IC" },
    note = "<C-x> はモード ix のキー待ち。pre-edit は残る（観測）。",
  },
  {
    id = "O-completion-x-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<C-x>" },
    expect = { "IC" },
    note = "▽k から <C-x>。pre-edit は残る（観測）。",
  },
  {
    id = "O-completion-x-n",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-x>", "<C-n>" },
    expect = { "IC" },
    note = "<C-x><C-n> で補完が始まる。pre-edit はこの時点で消える（観測）。",
  },
  {
    id = "O-completion-x-n-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<C-x>", "<C-n>" },
    expect = { "IC" },
    note = "▽k から <C-x><C-n>。pre-edit は消える（観測）。",
  },
  {
    id = "O-completion-x-esc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-x>", "<Esc>" },
    expect = { "N_OFF" },
    note = "<C-x> のキー待ちで <Esc>。読みを確定して無効化する（観測）。",
  },
  {
    id = "O-completion-x-esc-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<C-x>", "<Esc>" },
    expect = { "N_OFF" },
    note = "▽k から <C-x><Esc>。無効化する（観測は未取得。コード読解）。",
    uncertain = true,
  },
  {
    id = "O-completion-x-ctrlc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-x>", "<C-c>" },
    expect = { "N_OFF" },
    note = "<C-x> のキー待ちで <C-c>。SafeState で読みを確定して無効化する（観測）。",
  },
  {
    id = "O-completion-x-ctrlc-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<C-x>", "<C-c>" },
    expect = { "N_OFF" },
    note = "▽k から <C-x><C-c>。無効化する（観測は未取得。コード読解）。",
    uncertain = true,
  },
  {
    id = "O-completion-x-after",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-x>" },
    expect = { "IC" },
    note = "補完のあとに <C-x>。モード ix に入る（観測）。",
  },
  {
    id = "O-completion-accept-c-y",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-y>" },
    expect = { "I_DIRECT" },
    note = "<C-y> で候補を受け入れる。",
  },
  {
    id = "O-completion-cr",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<CR>" },
    expect = { "I_DIRECT" },
    note = "<CR> で候補を受け入れて改行する（観測。バッファに候補 + 空行）。",
  },
  {
    id = "O-completion-tab",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<Tab>" },
    expect = { "I_DIRECT" },
    note = "<Tab> で候補を受け入れてタブを入れる（観測）。",
  },
  {
    id = "O-completion-char",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "a" },
    expect = { "I_DIRECT" },
    note = "候補を確定してから文字を入れる（観測）。",
  },
  {
    id = "O-completion-shift",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "R" },
    expect = { "I_ROMAJI" },
    note = "補完が終わり、シフト付きの文字で ▽ を始める（観測）。",
  },
  {
    id = "O-completion-bs",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<BS>" },
    expect = { "IC" },
    note = "<BS> は候補の最後の 1 文字を消す。補完は続く（観測）。",
  },
  {
    id = "O-completion-ctrlc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "<C-c>" },
    expect = { "N_OFF" },
    note = "<C-c> で insert を抜け、SafeState で無効になる（観測）。",
  },
  {
    id = "O-blink-open",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh" },
    expect = { "IC" },
    note = "blink.cmp。▽かんj でメニューが開く。pre-edit は残る（観測）。",
  },
  {
    id = "O-blink-next",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<C-n>" },
    expect = { "IC" },
    note = "blink のメニューで <C-n>。選択が次へ動く（観測）。",
  },
  {
    id = "O-blink-tab",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<Tab>" },
    expect = { "I_DIRECT" },
    note = "super-tab の <Tab> で候補 漢字 を確定する（観測）。",
  },
  {
    id = "O-blink-s-tab",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<S-Tab>" },
    expect = { "I_DIRECT" },
    note = "<S-Tab> は fallback して、guard が読みを確定してからタブを流す（観測）。",
  },
  {
    id = "O-blink-cr",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<CR>" },
    expect = { "I_DIRECT" },
    config = { eggLikeNewline = false },
    note = "eggLikeNewline = false の <CR>。読みを確定して改行する（観測）。",
  },
  {
    id = "O-blink-c-e",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<C-e>" },
    expect = { "I_POINT" },
    note = "<C-e> でメニューを閉じる。pre-edit は残る（観測）。",
  },
  {
    id = "O-blink-cg",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<C-g>" },
    expect = { "I_DIRECT" },
    note = "<C-g> で読みを取り消す。insert のまま（観測）。",
  },
  {
    id = "O-blink-space",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<Space>" },
    expect = { "I_SELECT" },
    note = "<Space> で ▼ に入る。メニューは閉じる（観測）。",
  },
  {
    id = "O-blink-bs",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<BS>" },
    expect = { "IC" },
    note = "<BS> で読みの最後の 1 文字を削る。メニューは開いたまま（観測）。",
  },
  {
    id = "O-blink-char",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "a" },
    expect = { "I_POINT" },
    note = "読みに足すと I_POINT に戻り、メニューは閉じていた（観測。開き直しはタイミング次第）。",
  },
  {
    id = "O-blink-q",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "i", "@blink_refresh", "q" },
    expect = { "I_DIRECT" },
    note = "blink のメニューが出ているときに q。カタカナで確定する（#174 の再現、観測）。",
  },
  {
    id = "O-blink-esc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<Esc>" },
    expect = { "N_OFF" },
    note = "<Esc> で読みを確定して無効化する（観測）。",
  },
  {
    id = "O-blink-ctrlc",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<C-c>" },
    expect = { "N_OFF" },
    note = "<C-c> で insert を抜け、SafeState で無効になる（観測）。",
  },
  {
    id = "O-blink-ctrl-w",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<C-w>" },
    expect = { "I_DIRECT" },
    note = "<C-w> で読みを捨てる（観測。P1 の破れ）。",
  },
  {
    id = "O-blink-left",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<Left>" },
    expect = { "I_DIRECT" },
    note = "guard が読みを確定してから <Left> を流す（観測）。",
  },
  {
    id = "O-blink-ctrl-o",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "@blink_refresh", "<C-o>" },
    expect = { "NI" },
    note = "<C-o> で niI に入る。メニューと pre-edit は残る（観測）。",
  },
  {
    id = "O-blink-buffer-24",
    keys = { "<Plug>(skkeleton-enable)", "<Insert>", "<Insert>", "@buffer_menu_open", "<Plug>(skkeleton-enable)" },
    expect = { "I_DIRECT" },
    note = "無効のあいだに出た buffer のメニューは、有効化のあとに閉じる（#24 の直し。観測は blink_buffer プロファイル）。",
    uncertain = true,
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
  -- terminal（t / nt）。#188（07b）。
  -- 子の nvim で `terminal cat` を開いてから skk を有効にし、1 つのキーを 1 回の入力として流した。
  -- 端末の行の pre-edit は本物の文字で、書き直しの BS は ^H として残る。
  {
    id = "O-t-enable",
    keys = { ":terminal", "<Plug>(skkeleton-enable)" },
    expect = { "T_DIRECT" },
    note = "terminal で有効化。mode=t、enabled=true、preedit=\"\"。t のマッピングが 102 個。",
  },
  {
    id = "O-t-toggle-on",
    keys = { ":terminal", "<Plug>(skkeleton-toggle)" },
    expect = { "T_DIRECT" },
    note = "無効な terminal での toggle は有効化（main.lua:169-175）。",
  },
  {
    id = "O-t-a",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "a" },
    expect = { "T_DIRECT" },
    note = "a → あ が端末のジョブへ流れる（direct のまま）。",
  },
  {
    id = "O-t-k",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K" },
    expect = { "T_POINT" },
    note = "K → 端末の行に ▽k。g:state.phase は input:okurinasi、henkanFeed は空。",
  },
  {
    id = "O-t-ka",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a" },
    expect = { "T_POINT" },
    note = "K a → ▽か。打ちかけが解決して読みになる。",
  },
  {
    id = "O-t-kan-n",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n" },
    expect = { "T_POINT" },
    note = "▽かn。端末の行は ▽k^H^H▽かn。",
  },
  {
    id = "O-t-select",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>" },
    expect = { "T_POINT" },
    note = "▽かn → ▼缶。観測のクラスは pre-edit の有無だけなので T_POINT のまま。",
  },
  {
    id = "O-t-select-next",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Space>" },
    expect = { "T_POINT" },
    note = "▼缶 → ▼感。候補が進む。",
  },
  {
    id = "O-t-space",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Space>" },
    expect = { "T_DIRECT" },
    note = "読みが無いので、<Space> は端末のジョブへそのまま渡る。",
  },
  {
    id = "O-t-bs",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<BS>" },
    expect = { "T_POINT" },
    note = "▽かn → ▽か。読みの最後の 1 文字を削る。",
  },
  {
    id = "O-t-bs-direct",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<BS>" },
    expect = { "T_DIRECT" },
    note = "読みが無いので、<BS> はジョブへ流れて 1 文字消す（端末の行は ^H）。<C-h> も同じ。",
  },
  {
    id = "O-t-bs-empty",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<BS>", "<BS>", "<BS>" },
    expect = { "T_DIRECT" },
    note = "▽かn → ▽か → ▽ → 空。読みが空になったら direct に戻る。",
  },
  {
    id = "O-t-romaji-bs",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<BS>" },
    expect = { "T_POINT" },
    note = "打ちかけ k を消すと、▽ だけが残る（クラスは pre-edit があるので T_POINT）。",
  },
  {
    id = "O-t-romaji-bs-empty",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<BS>", "<BS>" },
    expect = { "T_DIRECT" },
    note = "▽ も消すと direct に戻る。",
  },
  {
    id = "O-t-romaji-ctrl-a",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<C-a>" },
    expect = { "T_DIRECT" },
    note = "打ちかけ k をそのまま確定してから ^A をジョブへ渡す（端末の行は k^A）。",
  },
  {
    id = "O-t-romaji-esc",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<Esc>" },
    expect = { "T_DIRECT" },
    note = "打ちかけ k を確定して無効になり、端末へ Esc を流す。",
  },
  {
    id = "O-t-romaji-nt",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "打ちかけを抱えたまま nt へ。",
  },
  {
    id = "O-t-romaji-nt-back",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<C-\\><C-n>", "i" },
    expect = { "T_POINT" },
    note = "nt から戻ると打ちかけの続きから打てる。",
  },
  {
    id = "O-t-nt-direct-back",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<C-\\><C-n>", "i" },
    expect = { "T_DIRECT" },
    note = "読みが無いまま nt から t に戻る。",
  },
  {
    id = "O-t-select-x",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "x" },
    expect = { "T_POINT" },
    note = "▼缶 で x を押すと ▽かん に戻る。",
  },
  {
    id = "O-t-select-gt",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", ">" },
    expect = { "T_POINT" },
    note = "▼缶 で > を押すと ▽> になる。",
  },
  {
    id = "O-t-select-bs",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<BS>" },
    expect = { "T_DIRECT" },
    note = "候補 缶 を確定してから 1 文字消す。",
  },
  {
    id = "O-t-select-insert",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Insert>" },
    expect = { "T_POINT" },
    note = "<Insert> は guard が確定しないので、エスケープシーケンスがジョブへ渡る。",
  },
  {
    id = "O-t-select-tab",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Tab>" },
    expect = { "T_POINT" },
    note = "<Tab> は guard が確定しない。▼缶 が残る。",
  },
  {
    id = "O-t-cr",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<CR>" },
    expect = { "T_DIRECT" },
    note = "かん を確定して改行する。端末の行は ▽かん になり、カーソルは次の行へ。",
  },
  {
    id = "O-t-nl",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-j>" },
    expect = { "T_DIRECT" },
    note = "かん を確定する（改行はしない）。",
  },
  {
    id = "O-t-cg",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-g>" },
    expect = { "T_DIRECT" },
    note = "読みを取り消す。端末の行の pre-edit は BS で消える。",
  },
  {
    id = "O-t-cq",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-q>" },
    expect = { "T_DIRECT" },
    note = "半角カタカナ ｶﾝ にして確定する。skk は有効のまま。",
  },
  {
    id = "O-t-ctrl-a-direct",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<C-a>" },
    expect = { "T_DIRECT" },
    note = "読みが無いので、^A はそのままジョブへ渡る（pre-edit が無いので確定しない）。",
  },
  {
    id = "O-t-ctrl-r-direct",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<C-r>" },
    expect = { "T_DIRECT" },
    note = "読みが無いので、^R はそのままジョブへ渡る。",
  },
  {
    id = "O-t-ctrl-a",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-a>" },
    expect = { "T_DIRECT" },
    note = "#121。かん を確定してから ^A をジョブへ渡す。pre-edit は空、有効のまま。",
  },
  {
    id = "O-t-ctrl-r",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-r>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^R をジョブへ渡す。",
  },
  {
    id = "O-t-ctrl-w",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-w>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^W（tty の単語削除）をジョブへ渡す。",
  },
  {
    id = "O-t-ctrl-u",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-u>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^U（tty の行削除）をジョブへ渡す。",
  },
  {
    id = "O-t-ctrl-n",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^N をジョブへ渡す（terminal では補完にならない）。",
  },
  {
    id = "O-t-ctrl-y",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-y>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^Y をジョブへ渡す。",
  },
  {
    id = "O-t-ctrl-at",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-@>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから NUL をジョブへ渡す（insert の E29 は起きない）。",
  },
  {
    id = "O-t-ctrl-o",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-o>" },
    expect = { "T_DIRECT" },
    note = "t の <C-o> は insert-normal ではない。かん を確定して ^O をジョブへ渡す。",
  },
  {
    id = "O-t-ctrl-v",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-v>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^V をジョブへ渡す。",
  },
  {
    id = "O-t-ctrl-k",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-k>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^K をジョブへ渡す。",
  },
  {
    id = "O-t-ctrl-t",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-t>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^T をジョブへ渡す。",
  },
  {
    id = "O-t-ctrlc",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-c>" },
    expect = { "T_DIRECT" },
    note = "かん を確定してから ^C をジョブへ渡す。t のままで skk は有効のまま。猫（cat）は 130 で終わる。",
  },
  {
    id = "O-t-guard",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Left>" },
    expect = { "T_DIRECT" },
    note = "guard が かん を確定してから <Left> をジョブへ渡す。",
  },
  {
    id = "O-t-tab",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Tab>" },
    expect = { "T_POINT" },
    note = "<Tab> は skk 自身の書き直しと区別できないので guard は確定しない。読みが残る。",
  },
  {
    id = "O-t-insert",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Insert>" },
    expect = { "T_POINT" },
    note = "guard は <Insert> で確定しない。エスケープシーケンスがジョブへ渡り、読みは残る。",
  },
  {
    id = "O-t-esc",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Esc>" },
    expect = { "T_DIRECT" },
    note = "かん を確定して無効になり、端末へ Esc を流す。t のままで state.type は escape。"
      .. "観測のクラスは pre-edit が無いので T_DIRECT。",
  },
  {
    id = "O-t-esc-direct",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Esc>" },
    expect = { "T_DIRECT" },
    note = "読みが無い <Esc>。端末へ Esc を流し、無効になる。",
  },
  {
    id = "O-t-esc-char",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Esc>", "a" },
    expect = { "T_DIRECT" },
    note = "無効なので a はジョブへ渡る（端末の行は ^[a）。",
  },
  {
    id = "O-t-esc-ctrl-a",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Esc>", "<C-a>" },
    expect = { "T_DIRECT" },
    note = "無効なので ^A はジョブへ渡る。確定は起きない。",
  },
  {
    id = "O-t-esc-nt",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Esc>", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "escape のまま nt へ移ると、ModeChanged の分岐でその場で reset する（phase=input）。",
  },
  {
    id = "O-t-esc-enable",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Esc>", "<Plug>(skkeleton-enable)" },
    expect = { "T_DIRECT" },
    note = "escape のあとでも、<Plug> からの enable は Context を作り直して有効になる。",
  },
  {
    id = "O-t-disable",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Plug>(skkeleton-disable)" },
    expect = { "T_DIRECT" },
    note = "かん を確定して無効になる。t のまま。",
  },
  {
    id = "O-t-disable-direct",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-disable)" },
    expect = { "T_DIRECT" },
    note = "読みが無い disable。t のまま無効になる。",
  },
  {
    id = "O-t-disable-nt",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-disable)", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "無効のまま nt へ。",
  },
  {
    id = "O-t-disable-nt-back",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-disable)", "<C-\\><C-n>", "i" },
    expect = { "T_DIRECT" },
    note = "nt から t へ戻っても無効のまま。a はジョブへ渡る。",
  },
  {
    id = "O-t-off-char",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-disable)", "a" },
    expect = { "T_DIRECT" },
    note = "無効なので a はジョブへ渡る（端末の行に a）。",
  },
  {
    id = "O-t-toggle-off",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Plug>(skkeleton-toggle)" },
    expect = { "T_DIRECT" },
    note = "有効なときの toggle は disable。かん を確定して無効になる。",
  },
  {
    id = "O-t-toggle-off-direct",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<Plug>(skkeleton-toggle)" },
    expect = { "T_DIRECT" },
    note = "読みが無い toggle（disable）。",
  },
  {
    id = "O-t-nt",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "nt へ移っても、enabled は true で pre-edit（▽かn）と読みが残る（#74 の直し）。",
  },
  {
    id = "O-t-nt-direct",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "読みが無いまま nt へ。enabled は true。",
  },
  {
    id = "O-t-nt-back",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-\\><C-n>", "i" },
    expect = { "T_POINT" },
    note = "nt から i で t に戻ると、▽かn の続きから打てる。",
  },
  {
    id = "O-t-nt-again",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-\\><C-n>", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "nt で <C-\\><C-n> を押しても何も起きない。",
  },
  {
    id = "O-t-nt-esc",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-\\><C-n>", "<Esc>" },
    expect = { "T_NORMAL" },
    note = "nt の <Esc> は normal の <Esc>。skk は何もしない。",
  },
  {
    id = "O-t-nt-ctrl-c",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-\\><C-n>", "<C-c>" },
    expect = { "T_NORMAL" },
    note = "nt の <C-c> は何もしない。",
  },
  {
    id = "O-t-nt-edit",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-\\><C-n>", "x" },
    expect = { "T_NORMAL" },
    note = "terminal のバッファは nomodifiable。x は E21 になり、状態は変わらない。",
    uncertain = true,
  },
  {
    id = "O-t-select-nt",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "▼ を抱えたまま nt へ。",
  },
  {
    id = "O-t-select-nt-back",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-\\><C-n>", "i" },
    expect = { "T_POINT" },
    note = "nt から戻ると ▼ の続きから選べる。",
  },
  {
    id = "O-t-select-ctrl-a",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-a>" },
    expect = { "T_DIRECT" },
    note = "▼ でも、ジョブへ <C-a> を渡す前に候補（缶）を確定する（#121）。",
  },
  {
    id = "O-t-select-esc",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Esc>" },
    expect = { "T_DIRECT" },
    note = "候補を確定して無効になり、端末へ Esc を流す。",
  },
  {
    id = "O-t-select-ctrlc",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-c>" },
    expect = { "T_DIRECT" },
    note = "候補を確定してから ^C をジョブへ渡す。",
  },
  {
    id = "O-t-select-cr",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<CR>" },
    expect = { "T_DIRECT" },
    note = "候補 缶 を確定して改行する。",
  },
  {
    id = "O-t-select-nl",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-j>" },
    expect = { "T_DIRECT" },
    note = "候補 缶 を確定する。",
  },
  -- 貼り付け（#57、#125）。実際の観測は semantics/explore/observations/misc.jsonl
  {
    id = "O-paste-direct",
    keys = { "<Plug>(skkeleton-enable)", "<Paste>" },
    expect = { "I_DIRECT" },
    note = "読みが無いので、貼り付けはそのままバッファに入る（PASTED）。",
  },
  {
    id = "O-paste-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<Paste>" },
    expect = { "I_DIRECT" },
    note = "▽k（ローマ字の打ちかけ）を k として確定してから PASTED を貼る。",
  },
  {
    id = "O-paste-point",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Paste>" },
    expect = { "I_DIRECT" },
    note = "▽かn を かん として確定してから PASTED を貼る（#125）。",
  },
  {
    id = "O-paste-select",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Paste>" },
    expect = { "I_DIRECT" },
    note = "▼缶 の候補 缶 を確定してから PASTED を貼る。",
  },
  {
    id = "O-ctrl-at-direct",
    keys = { "<Plug>(skkeleton-enable)", "<C-@>" },
    expect = { "N_OFF" },
    note = "読みが無いときも、E29 で insert を抜けて無効になる。",
  },
  {
    id = "O-ctrl-at-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<C-@>" },
    expect = { "N_OFF" },
    note = "▽k を k として確定してから、E29 で insert を抜ける。",
  },
  {
    id = "O-ctrl-at-point",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-@>" },
    expect = { "N_OFF" },
    note = "▽かn を かん として確定してから、E29 で insert を抜ける。",
  },
  {
    id = "O-ctrl-at-select",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-@>" },
    expect = { "N_OFF" },
    note = "▼缶 の候補 缶 を確定してから、E29 で insert を抜ける。",
  },
  {
    id = "O-ctrl-at-off",
    keys = { "i", "<C-@>" },
    expect = { "N_OFF" },
    config = { keepState = false },
    note = "無効な insert でも、E29 で insert を抜ける。",
  },
  {
    id = "O-ctrl-a-e29",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-a>" },
    expect = { "I_POINT" },
    note = "前に挿入した文字が無いときの <C-a> は E29 で、pre-edit が残る。",
  },
  -- guard が確定するキー（#56）
  {
    id = "O-guard-direct",
    keys = { "<Plug>(skkeleton-enable)", "<C-.>" },
    expect = { "I_DIRECT" },
    note = "pre-edit が無いので、guard は何もせずに . を入れる。",
  },
  {
    id = "O-guard-romaji",
    keys = { "<Plug>(skkeleton-enable)", "K", "<C-.>" },
    expect = { "I_DIRECT" },
    note = "▽k を k として確定してから . を入れる。",
  },
  {
    id = "O-guard-cdot",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-.>" },
    expect = { "I_DIRECT" },
    note = "▽かn を かん として確定してから . を入れる。",
  },
  {
    id = "O-guard-f5",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<F5>" },
    expect = { "I_DIRECT" },
    note = "確定してから <F5> を流す。",
  },
  {
    id = "O-guard-s-cr",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<S-CR>" },
    expect = { "I_DIRECT" },
    note = "確定してから <S-CR> を流す。",
  },
  {
    id = "O-guard-left",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Left>" },
    expect = { "I_DIRECT" },
    note = "確定してからカーソルを動かす。",
  },
  {
    id = "O-guard-c-left",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-Left>" },
    expect = { "I_DIRECT" },
    note = "確定してからカーソルを動かす。",
  },
  {
    id = "O-guard-s-up",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<S-Up>" },
    expect = { "I_DIRECT" },
    note = "確定してからカーソルを動かす。",
  },
  {
    id = "O-guard-s-f1",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<S-F1>" },
    expect = { "I_DIRECT" },
    note = "確定してから <S-F1> を流す。",
  },
  {
    id = "O-guard-select",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Left>" },
    expect = { "I_DIRECT" },
    note = "▼缶 の候補 缶 を確定してからカーソルを動かす。",
  },
  {
    id = "O-wheel-point",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<ScrollWheelUp>" },
    expect = { "I_POINT" },
    note = "スクロールは確定せず、pre-edit が残る。",
  },
  -- マクロと `.`（#192）。子の nvim に打鍵を流し、repeat.jsonl に残した観測。
  {
    id = "O-macro-record",
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      "q",
    },
    expect = { "N_OFF" },
    note = "q で記録を始め、insert で変換して確定し、q で止める。レジスタ a には打ったキーだけが入り、"
      .. "確定した文字や render.finish は入らない（#36）。",
  },
  {
    id = "O-macro-normal",
    keys = { "qa", "j", "q" },
    expect = { "N_OFF" },
    note = "normal の移動だけを記録する。移動はレジスタに入り、skk の状態は変わらない。",
  },
  {
    id = "O36",
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      "q",
      "j",
      "@a",
    },
    expect = { "N_OFF" },
    note = "#36 の再現キー列（insert のマクロを記録して @a で再生する）。"
      .. "今の実装では 2 行目にも 缶 が入る。",
  },
  {
    id = "O-macro-count",
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "k",
      "a",
      "n",
      "<C-j>",
      "<Esc>",
      "j0",
      "q",
      "3@a",
    },
    expect = { "N_OFF" },
    note = "3@a で 3 回再生する。",
  },
  {
    id = "O-dot",
    keys = { "A", "<Plug>(skkeleton-enable)", "k", "a", "n", "<C-j>", "<Esc>", "j0", "." },
    expect = { "N_OFF" },
    note = "insert で確定したあとの `.`。直前の変更（insert と確定）を繰り返す。",
  },
  {
    id = "O-dot-henkan",
    keys = {
      "A",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      "j0",
      ".",
    },
    expect = { "N_OFF" },
    note = "変換して確定した insert の `.`。",
  },
  {
    id = "O-dot-keepstate",
    config = { keepState = true },
    keys = {
      "i",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      ".",
      "a",
    },
    expect = { "I_OFF" },
    note = "#152。keepState の one-shot があるとき、`.` が InsertEnter を起こして one-shot を使い切る。"
      .. "そのあとの `a` は skk を有効にしない。",
  },
  {
    id = "O-macro-replay-keepstate",
    config = { keepState = true },
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      "q",
      "j",
      "@a",
    },
    expect = { "N_OFF" },
    note = "keepState が真のとき、記録したマクロの再生の最後の <Esc> で one-shot がまた残る。",
  },
  {
    id = "O-macro-replay-off",
    config = { keepState = true },
    keys = { "qa", "j", "q", "j", "@a" },
    expect = { "N_OFF" },
    note = "one-shot が無いときの @a。normal だけのマクロなので、再生の最後に <Esc> は無い。",
  },
  {
    id = "O-macro-keepstate",
    config = { keepState = true },
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      "q",
      "i",
      "<Plug>(skkeleton-enable)",
      "<Esc>",
      "j",
      "@a",
      "a",
    },
    expect = { "I_DIRECT" },
    note = "#152。one-shot があるときの @a のあと、次の insert も有効になる（再生の最後の <Esc> が one-shot を残す）。",
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
  {
    id = "replay.completion-19",
    title = "#19: Kan → <C-n> → R → <C-e>",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-n>", "R", "<C-e>" },
    expect = { "I_ROMAJI" },
    note = "#19 の再現列。今の振る舞いでは <C-n> の時点で pre-edit が消える（P1 の破れ、"
      .. "t.I_POINT.completion_open）。行のずれそのものは表示の層なので、状態クラスには出ない。",
  },
  {
    id = "replay.completion-24",
    title = "#24: 無効の buffer メニュー → 有効化",
    keys = {
      "<Plug>(skkeleton-enable)", "<Insert>", "<Insert>", "@buffer_menu_open",
      "<Plug>(skkeleton-enable)",
    },
    expect = { "I_DIRECT" },
    note = "#24 の再現列（利用者の <C-j> は <Plug>(skkeleton-enable) で代用）。"
      .. "有効化のあとの skkeleton-enable-post が buffer のメニューも閉じる。",
  },
  {
    id = "replay.completion-143",
    title = "#143: 行末で Kanji → blink のメニュー",
    keys = { "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "i", "@blink_refresh" },
    expect = { "IC" },
    note = "#143 / #149 の再現列のうち、モデルで表せる部分。メニューの画面の位置は oos.blink_position で扱う。",
  },
  {
    id = "replay.completion-174",
    title = "#174: Kanji → q（blink のメニュー）",
    keys = {
      "i", "<Plug>(skkeleton-enable)", "K", "a", "n", "j", "i", "@blink_refresh", "q",
    },
    expect = { "I_DIRECT" },
    note = "#174 の再現列。issue は Henkan と q だが、この辞書には へんかん の候補が無いので、"
      .. "同じ形の Kanji で観測した。q でカタカナ カンジ を確定し、メニューは閉じた。"
      .. "一瞬の位置のずれは表示の層（oos.blink_position）。",
  },
  -- terminal（#74 / #121）。`#term` は terminal プロファイルで `terminal cat` を開いたところ。
  {
    id = "replay.t74",
    title = "#74 terminal で <C-\\><C-n>",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<C-\\><C-n>" },
    expect = { "T_NORMAL" },
    note = "直したあとは state を捨てない。nt で enabled=true、pre-edit と読みが残る。",
  },
  {
    id = "replay.t74-back",
    title = "#74 nt から i で戻る",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<C-\\><C-n>", "i" },
    expect = { "T_POINT" },
    note = "▽k の続きから打てる。",
  },
  {
    id = "replay.t74-cr",
    title = "#74 nt から戻って <CR>",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<C-\\><C-n>", "i", "<CR>" },
    expect = { "T_DIRECT" },
    note = "▽k は k として確定し、改行がジョブへ渡る（▽k がそのままシェルへ渡る道ではない）。",
  },
  {
    id = "replay.t121",
    title = "#121 terminal で <C-a>",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-a>" },
    expect = { "T_DIRECT" },
    note = "ジョブへ <C-a> を渡す前に かん を確定する。P14。",
  },
  {
    id = "replay.t121-ka",
    title = "#121 <C-a> のあと続けて打つ",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "a", "n", "<C-a>", "k", "a" },
    expect = { "T_POINT" },
    note = "確定したあとに新しい読み（▽か）を打てる。",
  },
  {
    id = "replay.t121-romaji",
    title = "#121 打ちかけの途中で <C-a>",
    keys = { ":terminal", "<Plug>(skkeleton-enable)", "K", "<C-a>" },
    expect = { "T_DIRECT" },
    note = "打ちかけ k を確定してから ^A を渡す。",
  },
  {
    id = "replay.paste.point",
    title = "Kan → <Paste>（#125）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Paste>" },
    expect = { "I_DIRECT" },
    note = "貼る前に かん を確定し、かんPASTED になる。",
  },
  {
    id = "replay.paste.select",
    title = "Kan<Space> → <Paste>（#125）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<Paste>" },
    expect = { "I_DIRECT" },
    note = "貼る前に 缶 を確定し、缶PASTED になる。",
  },
  {
    id = "replay.paste.57",
    title = "kakiku → <Paste> → ka → <Esc>（#57）",
    keys = { "<Plug>(skkeleton-enable)", "k", "a", "k", "i", "k", "u", "<Paste>", "k", "a", "<Esc>" },
    expect = { "N_OFF" },
    note = "undo のまとまりはモデルの性質の外。観測では u 1 回で貼り付け以降だけが戻る。",
  },
  {
    id = "replay.mouse.otherwin",
    title = "Kan → 別のウィンドウをクリック（#169）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<LeftMouse>" },
    expect = { "I_OFF" },
    note = "WinLeave が読みを捨てる（gap）。同じウィンドウのクリックの道もモデルにはある。",
  },
  {
    id = "replay.mouse.select",
    title = "Kan → ダブルクリック（#47）",
    keys = { "<Plug>(skkeleton-enable)", "K", "a", "n", "<2-LeftMouse>" },
    expect = { "N_OFF" },
    note = "visual に入って無効になる。インジケータの位置は表示の層（対象外）。",
  },
  {
    id = "replay.mouse.47",
    title = "別ウィンドウのクリック → ドラッグ → クリック（#47）",
    keys = { "<Plug>(skkeleton-enable)", "<LeftMouse>", "<DragRight>", "<LeftMouse>" },
    expect = { "N_OFF" },
    note = "マウスの遷移だけを再生する。インジケータの位置は表示の層なので対象外。",
  },
  {
    id = "replay.macro",
    title = "#36 のマクロ（qa A ... q → @a）",
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      "q",
      "j",
      "@a",
    },
    expect = { "N_OFF" },
    note = "insert のマクロを記録して再生する。",
  },
  {
    id = "replay.dot",
    title = "insert のあとの `.`",
    keys = { "A", "<Plug>(skkeleton-enable)", "K", "a", "n", "<Space>", "<C-j>", "<Esc>", "j0", "." },
    expect = { "N_OFF" },
    note = "直前の変更を繰り返す。",
  },
  {
    id = "replay.dot.keepstate",
    title = "#152（`.` が keepState の one-shot を使い切る）",
    config = { keepState = true },
    keys = {
      "i",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      ".",
      "a",
    },
    expect = { "I_OFF" },
    note = "`.` のあとの insert は skk を有効にしない。",
  },
  {
    id = "replay.macro.keepstate",
    title = "keepState と @a（再生の最後の <Esc> が one-shot を残す）",
    config = { keepState = true },
    keys = {
      "qa",
      "A",
      "<Plug>(skkeleton-enable)",
      "K",
      "a",
      "n",
      "<Space>",
      "<C-j>",
      "<Esc>",
      "q",
      "i",
      "<Plug>(skkeleton-enable)",
      "<Esc>",
      "j",
      "@a",
      "a",
    },
    expect = { "I_DIRECT" },
    note = "one-shot があるときの @a のあと、次の insert も有効になる。",
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
    id = "oos.terminal_register",
    what = "terminal から辞書登録のプロンプトへ入る道（候補の無い読みで <Space> など）",
    why = "07c（#189）。入口の外側の pre-edit は凍結して残るが、中と戻り先は 07c。",
    refs = { "#189" },
    keys = {},
  },
  {
    id = "oos.terminal_visual",
    what = "terminal-normal から visual / select へ入る道（v / V）",
    why = "07e（#191）。visual の V_PRE は insert から入る道を前提にしているので、"
      .. "terminal からの道はここでは足さない（観測では v で V_PRE になった）。",
    refs = { "#191" },
    keys = {},
  },
  {
    id = "oos.terminal_cmdline",
    what = "terminal-normal から cmdline へ入る道（`:`）と、そこから terminal を抜ける道",
    why = "07a（#187）。terminal-normal → cmdline のときに skk の状態は c のクラスで観測される。",
    refs = { "#187" },
    keys = {},
  },
  {
    id = "oos.terminal_leave",
    what = "terminal を完全に抜ける道（:hide / :q / ウィンドウを閉じる）",
    why = "cmdline・ウィンドウ操作は 07a / 07e。nt → n で skk は無効になり状態も捨てるが、"
      .. "端末の行に本物の文字として残っている読みは消えない（端末の表示層の話）。",
    refs = { "#187", "#191" },
    keys = {},
  },
  {
    id = "oos.terminal_mouse",
    what = "terminal のマウス・ホイール",
    why = "07e（#191）。観測では t のホイールで Vim のモードが nt に変わった（pre-edit は残る）。",
    refs = { "#191" },
    keys = {},
  },
  {
    id = "oos.terminal_control_other",
    what = "terminal のその他の単バイト制御（<C-b> <C-f> <C-l> <C-s> <C-z> など）",
    why = "guard.lua:89-112 の同じ道（確定してからジョブへ渡す）なので、"
      .. "代表の <C-a> / <C-r> / <C-w> / <C-u> / <C-n> / <C-y> だけ遷移にした。",
    refs = { "guard.lua:89-112", "keys.md §4" },
    keys = {},
  },
  {
    id = "oos.terminal_insert_job",
    what = "terminal でジョブが終了したあと（<C-c> で cat が 130 で終わるなど）",
    why = "cat の終了は端末のジョブの話で、skk の状態は t のまま。"
      .. "シェルでは <C-c> はジョブを止めるだけで端末は続く。",
    refs = { "keys.md §4" },
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
    what = "補完の候補の並び・絞り込み・メニューの描画",
    why = "状態機械ではなく、辞書と blink の表示の話。候補の確定・取消は 07d（#190）で遷移にした。",
    refs = { "#190", "#159" },
    keys = {},
  },
  {
    id = "oos.native_completion",
    what = "completefunc / <C-x><C-u> の組み込み補完（#45）",
    why = "実装から消えている（#69 で補完は blink.cmp だけ）。Vim の completefunc を利用者が"
      .. "自前でつないだ場合の動きは skkeleton の状態機械ではない。",
    refs = { "#45", "#69" },
    keys = { "<C-x><C-u>" },
  },
  {
    id = "oos.blink_position",
    what = "blink.cmp のメニューの画面の位置（#143、#174）",
    why = "状態クラスに画面の位置を持っていない。観測の JSONL で menu の row / col を取り、"
      .. "いまは pre-edit の近くに出ることを確かめた。位置そのものは P2 / P15 の表示の層。",
    refs = { "#143", "#174", "#190" },
    keys = {},
  },
  {
    id = "oos.buffer_completion",
    what = "無効のあいだの blink.cmp の buffer 補完の候補（#24）",
    why = "候補は blink の buffer source が作る。ここではメニューが開いている状態（I_OFF_MENU）と、"
      .. "有効化・無効化で閉じる遷移だけを書いた。",
    refs = { "#24", "#190" },
    keys = {},
  },
  {
    id = "oos.macro_register",
    what = "マクロのレジスタに入るキーの種類（skk が流したキー・render.finish が混ざるか）",
    why = "レジスタの中身は状態クラスに持っていない。07f で repeat.jsonl に記録した。"
      .. "insert では #36 の修正で混ざらない。cmdline と terminal では混ざり、再生すると"
      .. "エラーになる（#214）。",
    refs = { "#36", "#192", "#214" },
    keys = {},
  },
  {
    id = "oos.repeat_undo",
    what = "マクロの再生と `.` の undo の単位",
    why = "undo の区切りは状態クラスに持っていない。07f の観測では、skk の確定ごとに"
      .. "`<C-g>u` の区切りがあり、`u` 1 回で確定 1 つぶんが戻った（#57、#158）。",
    refs = { "#36", "#57", "#152", "#158", "#192" },
    keys = {},
  },
  {
    id = "oos.macro_nested",
    what = "記録中の再生（入れ子の @）と、記録中の insert の中の状態",
    why = "記録中かどうかは観測の状態クラスに出ない（N_REC の class は N_OFF）。"
      .. "記録は insert をまたいで続くが、insert の中の skk の状態は記録の有無で変わらない。",
    refs = { "#192" },
    keys = {},
  },
  {
    id = "oos.cmdline_winleave",
    what = "#46 の cmdline 中の WinLeave",
    why = "cmdline（c / cr）の状態は 07a（#187）。このモデルは insert / normal / visual / replace だけを書いている。",
    refs = { "#46", "#187" },
    keys = { "<Cmd>wincmd w<CR>" },
  },
  {
    id = "oos.mouse_position",
    what = "#47 のインジケータの位置（visual から insert に戻ったとき）",
    why = "表示（インジケータ）の位置は P2 / P15 の層で、このモデルの状態クラスには持っていない。"
      .. "マウスの遷移そのものは mouse_click / mouse_select に書いた。",
    refs = { "#47" },
    keys = { "<ClickOtherWin>", "<DragRight>", "<ClickLine3>" },
  },
  {
    id = "oos.paste_undo",
    what = "#57 の貼り付けの undo のまとまり",
    why = "undo の区切りは P1–P15 の外。貼り付けの遷移と、貼る前の確定は paste に書いた。"
      .. "観測では u 1 回で貼り付け以降だけが戻り、打った読みは残る。",
    refs = { "#57" },
    keys = { "<Paste>" },
  },
  {
    id = "oos.mouse_coords",
    what = "マウスの座標（どの列をクリックしたか）と、確定した文字の置き場所",
    why = "ダブルクリックでは、確定した読みがクリックした位置に入る（観測）。"
      .. "文字の位置は状態クラスに持っていない（P2 の層）。",
    refs = { "#47", "#191" },
    keys = { "<2-LeftMouse>" },
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
    what = "blink.cmp が skkeleton の外で持つキー（snippet の移動など）",
    why = "利用者の blink のキーマップしだい。skkeleton が関わる <Tab> / <CR> は 07d（#190）で遷移にした。",
    refs = { "#190", "blink.cmp keymap super-tab" },
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
      "ni_return_drop", "ctrl_o_v", "ctrl_o_R", "mouse_select", "insert_key", "t_normal",
    } },
    { id = "SafeState", covered_by = { "safestate" } },
    { id = "CmdlineLeave", out_of_scope = "07a（#187）" },
    { id = "WinLeave", covered_by = { "winleave" } },
    { id = "BufLeave", covered_by = { "bufleave" } },
    { id = "TextChangedI", covered_by = { "stale" } },
    { id = "TextChangedP", covered_by = { "text_changed_p" } },
    { id = "CursorMovedI", covered_by = { "stale", "mouse_click" } },
    { id = "CmdlineChanged", out_of_scope = "07a（#187）" },
    { id = "CompleteDone", covered_by = { "complete_done" } },
    { id = "VimLeavePre", out_of_scope = "入力状態を変えない（events.md O14）" },
    { id = "User skkeleton-handled", covered_by = { "blink_refresh" } },
    { id = "User skkeleton-enable-post", covered_by = { "blink_hide" } },
    { id = "User skkeleton-disable-post", covered_by = { "blink_hide" } },
    { id = "User BlinkCmpMenuOpen", covered_by = { "blink_menu_open" } },
    { id = "User BlinkCmpMenuClose", covered_by = { "blink_menu_close" } },
    { id = "WinEnter", out_of_scope = "07c（#189、host.input のフレーム）" },
    { id = "CmdlineEnter", out_of_scope = "07c（#189、host.input のフレーム）" },
    { id = "InsertEnter", covered_by = { "insert_enter" } },
    { id = "enable", covered_by = { "enable" } },
    { id = "disable", covered_by = { "disable" } },
    { id = "toggle", covered_by = { "toggle" } },
    { id = "complete", covered_by = { "blink_commit" } },
    { id = "commit_preedit", covered_by = { "guard_special" } },
    { id = "on_bytes", covered_by = { "stale" } },
    { id = "vim.on_key", covered_by = { "guard_special", "ctrl_c" } },
    { id = "vim.paste", covered_by = { "paste" } },
    { id = "render.finish", out_of_scope = "確定文字列を流したあとの描画だけ（events.md）" },
  },
}

-- 性質（GLOSSARY の P1–P15）。このモデルで決められるかどうかも書く。
-- decided = false の性質は、状態クラスに持っていない層（表示・マッピングの数・cmdline）が要る。
M.properties = {
  { id = "P1", title = "読みが黙って消えない", decided = true, kind = "no_silent_loss" },
  { id = "P2", title = "pre-edit は 1 つだけで、置き場所が正しく、中身が state と一致する", decided = false,
    why = "extmark の数と位置を状態クラスに持っていない（05 の探索器と 06 の比較で見る）。"
      .. "07d で blink.cmp のメニューの位置も観測の JSONL に残した。" },
  { id = "P3", title = "n / v / s / R では、状態とマッピングが元に戻っている", decided = true, kind = "return_to_normal" },
  { id = "P4", title = "cmdline / terminal を抜けたら、何も残っていない", decided = true,
    kind = "terminal_normal_keep",
    why = "terminal は 07b（#188）で決めた。t の pre-edit は端末の行に本物の文字として書くので、"
      .. "t → nt で「何も残らない」ようにはできない（#74 の直しは、状態を捨てずに残す側）。"
      .. "ここでは P4 の terminal 側を「t → nt → t で、読みと pre-edit が保たれる」と読み、"
      .. "nt を経ても読みが消えないことを検査する。cmdline は 07a（#187）。" },
  { id = "P5", title = "1 つのキーを二重に処理しない", decided = true, kind = "no_double_commit" },
  { id = "P6", title = "決定的に振る舞う（タイミングに左右されるものには印を付ける）", decided = false,
    why = "モデルの分岐はタイミングではなく、辞書・バッファ・設定という持っていない条件。"
      .. "分かれる組は検査の最後に一覧で出す。blink.cmp のメニューは User skkeleton-handled のあとに"
      .. "タイマーで開くので、同じキー列でも観測の時点で開いていないことがある（07d）。" },
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
  { id = "P14", title = "terminal の Ctrl を正しく扱う", decided = true,
    kind = "terminal_ctrl_commit",
    why = "07b（#188）。terminal でジョブへ渡すキー（pass_key）は、読みを確定してから渡す（#121）。"
      .. "guard の own_output と <C-\\><C-n> は確定しない。" },
  { id = "P15", title = "state が空でないなら、pre-edit が見えている", decided = false,
    why = "表示（extmark）を状態クラスに持っていない。補完のメニューだけが開いている状態は"
      .. "pre-edit が無いので、この性質の対象外（07d）。" },
}

-- 既知の破れ（性質の検査で出るが、issue にしてあるもの）。
-- transition は遷移の id。refs は issue。
M.known = {
  { property = "P1", transition = "t.I_ROMAJI.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_ROMAJI.completion_open", refs = { "#18", "#19", "#190" } },
  { property = "P1", transition = "t.I_ROMAJI.ctrl_a", refs = { "keys.md §6" } },
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
  { property = "P1", transition = "t.I_ROMAJI.mouse_click_other", refs = { "#169" } },
  { property = "P1", transition = "t.I_POINT.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_POINT.ctrl_a", refs = { "keys.md §6" } },
  { property = "P1", transition = "t.I_POINT.ctrl_k", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.ctrl_r", refs = { "#8", "#12", "#20" } },
  { property = "P1", transition = "t.I_POINT.ctrl_t", refs = { "keys.md §6" } },
  { property = "P1", transition = "t.I_POINT.ctrl_u", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.ctrl_v", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.ctrl_w", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.stale.buffer", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.tab", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_POINT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_POINT.mouse_click_other", refs = { "#169" } },
  { property = "P1", transition = "t.I_SELECT.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_SELECT.completion_open", refs = { "#18", "#19", "#190" } },
  { property = "P1", transition = "t.IX_ROMAJI.completion_next", refs = { "#19", "#190" } },
  { property = "P1", transition = "t.IX_POINT.completion_next", refs = { "#19", "#190" } },
  { property = "P1", transition = "t.IX_SELECT.completion_next", refs = { "#19", "#190" } },
  { property = "P1", transition = "t.I_BLINK_POINT.ctrl_w", refs = { "#8", "#12", "#190" } },
  { property = "P1", transition = "t.I_BLINK_POINT.winleave", refs = { "#169", "#190" } },
  { property = "P1", transition = "t.I_POINT.completion_open", refs = { "#18", "#19", "#190" } },
  { property = "P1", transition = "t.I_SELECT.stale.buffer", refs = { "#8", "#12" } },
  { property = "P1", transition = "t.I_SELECT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.I_SELECT.mouse_click_other", refs = { "#169" } },
  { property = "P1", transition = "t.NI_POINT.return_drop", refs = { "#199" } },
  { property = "P1", transition = "t.NI_POINT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.NI_SELECT.return_drop", refs = { "#199" } },
  { property = "P1", transition = "t.NI_SELECT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.V_PRE_POINT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.V_PRE_POINT.mouse_click_other", refs = { "#47", "#169" } },
  { property = "P1", transition = "t.V_PRE_SELECT.winleave", refs = { "#169" } },
  { property = "P1", transition = "t.V_PRE_SELECT.mouse_click_other", refs = { "#47", "#169" } },
  { property = "P1", transition = "t.NI_POINT.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.NI_SELECT.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.V_PRE_POINT.bufleave", refs = { "#169" } },
  { property = "P1", transition = "t.V_PRE_SELECT.bufleave", refs = { "#169" } },
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
      "P_PROMPT_POINT", "P_PROMPT_SELECT", "T_ROMAJI", "T_POINT", "T_SELECT",
      "T_NORMAL_ROMAJI", "T_NORMAL_POINT", "T_NORMAL_SELECT" },
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
  { id = "P.t.I_OFF.ctrl_at", transition = "t.I_OFF.ctrl_at", keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>", "i", "<C-@>" }, expect = { "N_OFF" } },
  { id = "P.t.I_OFF.esc", transition = "t.I_OFF.esc", keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>", "i", "<Esc>" }, expect = { "N_OFF" } },
  { id = "P.t.I_OFF.guard_special", transition = "t.I_OFF.guard_special", keys = { "i", "<Plug>(skkeleton-enable)", "<Esc>", "i", "<S-Tab>" }, expect = { "I_OFF" } },
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

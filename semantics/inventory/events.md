# autocmd と API の棚卸し（task-02）

親の issue は #179、この表の issue は #182。キー以外のイベント（autocmd、API）で skkeleton の状態が変わる道を、「今の」振る舞いとして並べます。望ましい振る舞いは決めません。

対象は `formal-semantics` の `ac567ab`（scaffold のマージ後）です。行番号はこの時点のものです。

## この表の読み方

- 用語は `semantics/GLOSSARY.md` に合わせます。この表で使う状態クラスは、次の動きで見分けます。
- effects は用語集の動詞を使います。用語集に無い効果は、関数名を添えて書きます。
- 「印」の `timing` は、`vim.schedule`、タイマー、`SafeState` に頼るため、同じキー列でも実行の順番で結果が変わりうる箇所です。
- 「観測」は、この文書の末尾の O 番号です。コードを読んだだけの行には観測番号がありません。

### 状態クラス

| クラス | 見分け方 |
|---|---|
| N_OFF | Vim のモードが n。`g:skkeleton#enabled` が偽で、state は input:direct、pre-edit は無い。`keepState` の one-shot 待ちもこのクラスのまま、遷移の guard（`config.keepState`）で表す |
| N_WAIT | Vim のモードが n。`ModeChanged` が作った `SafeState` の one-shot がまだ残っている |
| V_PRE | Vim のモードが v / s。`<C-o>v` で visual / select に入ったあと、pre-edit が描かれたまま残り続ける。抱えている相（point / select）は属性で持つ |
| V_IDLE | Vim のモードが v / s。skkeleton は有効で pre-edit は無い（direct から `<C-o>v`） |
| I_OFF | Vim のモードが i。skkeleton は無効（`<Esc>` のあと `i`、`<Insert>` を 2 回、`l` キー） |
| I_DIRECT | Vim のモードが i。state は input:direct（かなを直接書く。`▽` は無い） |
| I_POINT | Vim のモードが i。state は input:okurinasi（`▽...`） |
| I_SELECT | Vim のモードが i。state は henkan（`▼...`） |
| I_ESCAPE | state.type が escape。マップされた `<Esc>` のあと、`ModeChanged` か `SafeState` の片付けが終わるまで（insert に戻ったあとに残る場合も含む） |
| I_ROMAJI | ローマ字の打ちかけ（`state.feed`）がある。`pending` は `render.is_pending()` の意味だけに使う |
| NI | Vim のモードが ni（`<C-o>` の insert-normal）。抱えている相（direct / point / select）は属性で持つ |
| IC | insert の補完（モード `ic`、blink.cmp のメニュー）。blink.cmp が無い環境では観測していない（unknown） |
| R_OFF | Vim のモードが R で、skkeleton は無効 |
| C_DIRECT | Vim のモードが c。cmdline に pre-edit は無い |
| C_POINT | Vim のモードが c。cmdline に pre-edit（`▽` / `▼`）が本物の文字として書かれ、`cmdline.remember()` が覚えている |
| C_REPLACE | Vim のモードが c。書いた pre-edit と今の cmdline がずれている（`cmdline.is_stale()` が真）。`CmdlineChanged` の掃除の対象 |
| P_PROMPT | `host.is_in_input()` が真。辞書登録の `input()` のプロンプトの中。外側の相（point / select）は属性で持つ |
| T_DIRECT / T_POINT / T_NORMAL | terminal（t / nt）。今回の観測の外（#188） |

`R_MID` はクラスにしない。`<Insert>` による insert と replace の移り変わりの途中の状態（transient）としてだけ扱う。マウスのドラッグで `ModeChanged` の確定より前に一瞬 pre-edit が残るもの（O18）も、状態ではなく遷移の途中として扱う。

## 登録される autocmd の全体

コード上の `nvim_create_autocmd` の呼び出しは 14 か所です。`setup()`、有効化、インジケータ有効の状態で 33 個の autocmd が登録されます（`skkeleton-internal` 10、`skkeleton-completion` 5、`skkeleton-indicator` 18）。このほかに、動的に作られるものが 4 個あります（`SafeState`、`WinEnter`、`CmdlineEnter`、`InsertEnter`）。動的なものは一時的にしか存在しないので、同時に 37 個になるとは限りません。

| # | グループ | イベント | 作る場所 | いつ作るか |
|---|---|---|---|---|
| 1 | `skkeleton-internal` | `ModeChanged` | `lua/skkeleton/cleanup.lua:192-251` | 最初の `main.init()` |
| 2 | `skkeleton-internal` | `SafeState`（one-shot） | `lua/skkeleton/cleanup.lua:225-248` | `ModeChanged` の `safe_reset` のたび |
| 3 | `skkeleton-internal` | `CmdlineLeave` | `lua/skkeleton/cleanup.lua:254-266` | 最初の `main.init()` |
| 4 | `skkeleton-internal` | `WinLeave`、`BufLeave` | `lua/skkeleton/cleanup.lua:269-281` | 最初の `main.init()` |
| 5 | `skkeleton-internal` | `TextChangedI`、`TextChangedP`、`CursorMovedI`、`CmdlineChanged`、`CompleteDone` | `lua/skkeleton/cleanup.lua:283-286` | 最初の `main.init()` |
| 6 | `skkeleton-internal` | `VimLeavePre` | `lua/skkeleton/cleanup.lua:288-293` | 最初の `main.init()` |
| 7 | `skkeleton-completion` | `User skkeleton-handled` | `lua/skkeleton/completion/init.lua:128-134` | `setup()` |
| 8 | `skkeleton-completion` | `User skkeleton-enable-post`、`skkeleton-disable-post` | `lua/skkeleton/completion/init.lua:135-142` | `setup()` |
| 9 | `skkeleton-completion` | `User BlinkCmpMenuOpen` | `lua/skkeleton/completion/init.lua:143-151` | `setup()` |
| 10 | `skkeleton-completion` | `User BlinkCmpMenuClose` | `lua/skkeleton/completion/init.lua:152-158` | `setup()` |
| 11 | `skkeleton-indicator` | 18 個（下の「インジケータ」） | `lua/skkeleton/indicator/indicator.lua:30-50` | インジケータの `setup()` |
| 12 | `skkeleton-host-input` | `WinEnter` | `lua/skkeleton/host.lua:75-92` | `host.input()` のフレームを作るとき |
| 13 | （グループ無し） | `CmdlineEnter`（one-shot） | `lua/skkeleton/host.lua:194-204` | `host.input()` のたび |
| 14 | `skkeleton` | `InsertEnter`（buffer、one-shot） | `lua/skkeleton/host.lua:235-244` | `keepState` で `<Esc>` したとき |

## ModeChanged（`cleanup.lua`）

`ModeChanged` は `v:event.old_mode` と `v:event.new_mode` を見ます（192–206 行）。`old_mode` の先頭が `c` なら、先に `clean_history()` で `:`、`/`、`@` の履歴からマーカーを消します（197–199 行）。そのあと `MODE_TRANSITIONS`（179–190 行）を上から順に見て、最初に当たった規則の `action` を使います（200–206 行）。どの規則にも当たらなければ何もしません。

| # | from（`old_mode`） | to（`new_mode`） | action | 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|---|---|---|---|
| 1 | `^i` | `^[vV\022sS\019]` | `reset` | I_DIRECT / I_POINT / I_SELECT / IC → N_OFF（visual は途中） | `host.is_in_input()` が偽なら、`commit_preedit()`（カーソルは動かさない）、`reset_state`、`restore_mapping`（`host.disable()`。中で `clear_extmark`、popup close、completion hide もする）。pre-edit が無くても `reset_state` と `restore_mapping` はする | 181、207–214 行 | O10 |
| 2 | `^i` | `^R` | `reset` | I_DIRECT / I_POINT / I_SELECT → R_MID | `host.is_in_input()` が偽なら、`commit_preedit("insert")`（カーソルを確定文字の後ろへ）、`reset_state`、`restore_mapping` | 183、207–214 行 | O3 |
| 3 | `^ni` | `^i` | `stale` | NI → I_DIRECT / I_POINT | `reset_if_stale("i")`。カーソルだけがずれていれば `commit_preedit()`、それ以外はずれなら `drop`（読みは確定しない）、`clear_extmark`、`reset_state`、`render`。`restore_mapping` はしない（有効なまま） | 185、215–217 行 | O4、O5 |
| 4 | `.*` | `^n` | `safe_reset` | すべて → N_OFF / N_WAIT | state が escape で `host.is_in_input()` が偽なら、その場で `reset_state`（218–221 行）。そうでなければ `SafeState` の one-shot を作る（225–248 行）。one-shot は、そのときのモードが i / c / t でなく、ni / nt でもなく、`host.is_in_input()` でもないときに、`old_mode` の先頭が `i` なら `commit_preedit("normal")` をして `reset_state`、`restore_mapping`（224、230–246 行） | 187、218–248 行 | timing |
| 5 | `^c` | `^[^ictn]` | `safe_reset` | C_DIRECT / C_POINT / C_REPLACE → N_OFF / R_OFF（visual / R は途中。operator-pending の `no` は先に規則 4 が当たる） | 規則 4 の `safe_reset` と同じ分岐（state が escape ならその場で `reset_state`、そうでなければ `SafeState` の one-shot。`commit` は偽） | 189、218–248 行 | timing、O11 |

補足:

- 規則は「先頭一致」で、`find` のパターンです。`^i` は `i`、`ic`、`ix` に当たり、`^ni` は `niI` などに当たります。規則 1 と 2 は同じ `action == "reset"` の処理を通り、`new_mode` の先頭が `R` のときだけ `commit_preedit("insert")` にします（211 行）。規則 1 の遷移先は v / s なので、規則 1 ではカーソルを動かしません。
- 規則 4 は「`n` へ移るすべて」に当たるので、v / s / R / t などから n へ戻るときも one-shot を作ります。`commit` は `old_mode` の先頭が `i` のときだけ真です（224 行）。
- `SafeState` の one-shot は、その間にモードが変わると、callback の先頭のモード判定で何もせず終わります（230–239 行）。この判定は `vim.fn.mode()` ではなく `nvim_get_mode()` を使います（229 行。`nt` を `n` と返すため）。
- `skkeleton-internal` の `ModeChanged` が `action == "reset"` で `host.disable()` を呼ぶと、`User skkeleton-disable-pre` / `skkeleton-mode-changed` / `skkeleton-disable-post` が出ます（`host.lua` 22–37 行）。
- `clean_history()` は `ModeChanged` の先頭で `:`、`/`、`@` を掃除し、`CmdlineLeave` では `v:event.cmdtype` の履歴も加えて掃除します（`cleanup.lua` 94–102、197–199、260–264 行）。

## SafeState（one-shot）

`ModeChanged` の `safe_reset`（規則 4・5）が作る one-shot の autocmd です（`cleanup.lua` 225–248 行）。作るときに `old_mode` の先頭が `i` かどうかを `commit` として覚えます（224 行）。

| 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|
| N_WAIT → N_OFF | 呼ばれた時点のモードが i / c / t でなく、`ni` / `nt` でもなく、`host.is_in_input()` でもないなら、`commit` が真のときだけ `commit_preedit("normal")`（カーソルを確定文字の末尾へ）、`reset_state`、`restore_mapping`。それ以外は何もしない | `cleanup.lua:224-248` | timing、O2、O9 |

`SafeState` は one-shot なので 1 回で消えます。その間にモードが変わると、callback の先頭のモード判定で何もせず終わります（230–239 行）。`commit` が偽の道（規則 5、v / R などから n へ戻るとき）では、確定はせずに `reset_state` と `restore_mapping` だけをします。

## ずれの検出（`cleanup.lua` の `check_stale`）

`TextChangedI`、`TextChangedP`、`CursorMovedI`、`CmdlineChanged`、`CompleteDone` の 5 つは、同じ `check_stale` を呼びます（283–286 行）。`check_stale` は、無効、`handling_depth > host.in_input_depth()`、`render.is_pending()`、モードが i / c 以外のどれかなら何もせずに返ります（150–159 行）。そうでなければ `reset_if_stale(vm)` を呼び、cmdline で片付け残しがあれば `cmdline.clean()` をもう一度試します（160–164 行）。

`reset_if_stale(vm)`（120–147 行）は、pre-edit がバッファやカーソルとずれていなければ何もしません（126–128 行）。ずれていて、カーソルだけが動いたときは `commit_preedit()` で元の位置に確定します（129–132 行）。それ以外のずれでは、`clear_extmark`、cmdline なら `clean_cmdline`、`reset_state`、`render`、`User skkeleton-handled` をして、読みは確定しません（133–141 行）。

`render.is_stale` が見るもの（`render.lua` 269–302 行）は、`on_bytes` で立つ `mark_bytes_changed`、`ctx.vim_mode` と今のモードの違い、cmdline なら `cmdline.is_stale`、insert なら extmark とカーソルの位置、行の文字列です。`render.is_cursor_only_stale`（309–330 行）は、insert で、`on_bytes` の印が無く、extmark の位置と行がそのままで、カーソルだけが違うときだけ真になります。

| イベント | 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|---|
| `CursorMovedI` | I_DIRECT / I_POINT / I_SELECT | ずれていれば `reset_if_stale`。カーソルだけなら `commit_reading`（元の位置）、それ以外は `drop` + `clear_extmark` + `reset_state` + `render` | `cleanup.lua:120-147, 283-286` | O4、O16 |
| `TextChangedI` | I_DIRECT / I_POINT / I_SELECT | 同上。バッファの変更は `on_bytes`（下）でも拾う | `cleanup.lua:120-147, 283-286` | O6 |
| `TextChangedP` | I_DIRECT / I_POINT / I_SELECT（補完の popup 中） | 同上 | `cleanup.lua:120-147, 283-286` | O16（イベントを直接起こして確認） |
| `CompleteDone` | I_DIRECT / I_POINT / I_SELECT（補完の直後） | 同上 | `cleanup.lua:120-147, 283-286` | O16（同上） |
| `CmdlineChanged` | C_POINT → C_REPLACE | cmdline のときは `cmdline.is_stale` でずれを見る。ずれていれば `clean_cmdline`、`clear_extmark`、`reset_state`、`render`（C_REPLACE から C_DIRECT に戻る） | `cleanup.lua:120-147, 283-286`、`render.lua:280-281`、`render/cmdline.lua:93-99` | O7 |

`CmdlineChanged` の片付けは `cmdline.clean()` です（`render/cmdline.lua:111-157`）。覚えている pre-edit（`cmdline.remember`、75–88 行）を、cmdline の今の文字列から探して取り除き、`cmdline.reset()`（160–162 行）で記録を捨てます。見つからないときは記録を残し、次の `CmdlineChanged` でもう一度試します（156 行）。`CmdlineLeave` で記録を捨てます（`cleanup.lua` 168–172 行）。

## autocmd ではないが、同じ片付けを呼ぶ道

| 道 | 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|---|
| バッファの `on_bytes`（pre-edit の行が書き換わったとき） | I_DIRECT / I_POINT / I_SELECT | pre-edit の行が変わると `mark_bytes_changed` を立て、`vim.schedule` で `check_stale()` を呼ぶ。カーソルだけのずれではないので、読みは `drop` される | `render.lua:172-199`、`cleanup.lua:150-165` | timing、O6 |
| `vim.on_key`（`guard.attach`） | I_DIRECT / I_POINT / I_SELECT、C_DIRECT / C_POINT、T_DIRECT / T_POINT | マップされずに素通りした物理の特殊キーで、pre-edit を確定してからキーを流す。キーの棚卸しは #181 | `guard.lua:139-194`、`cleanup.lua:295` | キーの表（#181） |
| `vim.paste` の包み | I_DIRECT / I_POINT / I_SELECT | 貼り付けの前に pre-edit を確定して流す（#125）。バッファの文字を直接書く | `paste.lua:31-69` | イベントではない（#191） |
| `render.finish()` の `User skkeleton-handled` | 確定待ち（`render.is_pending()`。クラスではない） | 確定文字列を流したあとの描画を終える | `render.lua:388-406` | timing（`feed_key` のあと） |

## CmdlineLeave

`CmdlineLeave` は、cmdline を抜けるときに `drop_cmdline_preedit()`（168–172 行）で `clean_cmdline`、記録の `reset`、`g:skkeleton#state.preedit` の消去をします（257 行）。続けて `update_state_variable()`（259 行）で今の Context の値を入れ直し、`clean_history(cmdtype)` をその場で 1 回（260–261 行）、`vim.schedule` でもう 1 回呼びます（262–264 行）。

| 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|
| C_DIRECT / C_POINT / C_REPLACE / P_PROMPT | `clean_cmdline`、`g:skkeleton#state.preedit` を空にする（`clear_preedit_state`）、`clean_history`（`:`, `/`, `@`, cmdtype）。辞書登録のプロンプト中でも同じ処理をする | `cleanup.lua:168-172, 254-266` | timing（2 回目の履歴掃除）、O8、O9、O12 |

`P_PROMPT` のときの `CmdlineLeave` は、`host.input()` の中の cmdline を抜けるときに来ます（cmdtype は `@`）。`host.pop_input_frame()` のあとに `map.map()` と `User skkeleton-enable-post` があるので、外側の状態に戻ります（`host.lua` 125–162 行）。

## WinLeave / BufLeave

`WinLeave` と `BufLeave` は同じ callback です（`cleanup.lua` 269–281 行）。`host.is_in_input()` が真なら何もしません（272–274 行。辞書登録の `input()` の間は外側の状態を壊さない）。偽なら、cmdline 中は `drop_cmdline_preedit()`（275–277 行）、そのあと `reset_state` と `restore_mapping`（`host.disable()`）をします（278–279 行）。

| 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|
| すべて（ただし `host.is_in_input()` の間は除く） | cmdline なら `clean_cmdline`。そのあと `reset_state` を常にし、`restore_mapping` は有効なときだけ（`host.disable()` は無効ならすぐ返る）。読みは確定しない（`drop`）。バッファの文字は変えない | `cleanup.lua:269-281`、`host.lua:22-25` | O13（`new`、`enew` で確かめた）。同じ形の報告が #169 |

## VimLeavePre

`VimLeavePre` は `require("skkeleton").save_user_dict()` を呼ぶだけです（`cleanup.lua` 288–293 行、`init.lua` 121–126 行）。状態の片付けも pre-edit の確定もしません。

| 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|
| すべて（終了時） | `store.library():save()`（ユーザー辞書と補完ランクの保存） | `cleanup.lua:288-293`、`init.lua:121-126` | O14 |

## main.lua の API

API はすべて `M.handle(func, opts)` を通ります（146–184 行）。`handle` は先に `M.init()`（必要なら `cleanup.setup()`）、`render.is_pending()` なら `render.clear()`、`popup.close()`、`cleanup.reset_if_stale(short)` をしてから、`func` ごとの処理に進みます（150–178 行）。終わったあとに `g:skkeleton#state` を更新し、`render.update()` を呼びます（179–183 行）。

| API | 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|---|
| `enable`（`handle("enable")`、`init.lua` 23–25 行） | N_OFF / I_DIRECT / C_DIRECT / C_POINT | `R` では何もせず notify（`main.lua` 103–106 行）。state が input:direct でなく `opts.key` があれば、キーをそのまま流す（107–110 行）。そうでなければ `kana.set_current`、`reset_state`（`store.init_context()`）、`vim_mode` の記録、`User skkeleton-enable-pre`、`map.save_options()`、`map.map()`（マッピングを張る）、`g:skkeleton#enabled = true`、`store.variables.last_mode` のモード関数、`User skkeleton-enable-post`（111–124 行） | `main.lua:101-125`、`host.lua:14-19` | O15 |
| `disable`（`handle("disable")`、`init.lua` 27–29 行） | I_DIRECT / I_POINT / I_SELECT / NI / C_DIRECT / C_POINT | state が input でないか input:direct でなく、`opts.key` があればキーを流す（`main.lua` 132–136 行）。そうでなければ `function/disable.lua` の `disable` で、`commit_reading` / `commit_candidate`（`common.kakutei`）、`restore_mapping`（`host.disable()`。`User skkeleton-disable-pre`、`map.restore()`、`map.restore_options()`、`g:skkeleton#mode = ""`、`User skkeleton-mode-changed`、`User skkeleton-disable-post`、`g:skkeleton#enabled = false`、`clear_extmark`、popup close、completion hide）、`reset_state`（`state.initialize`） | `main.lua:129-139`、`function/disable.lua:13-18`、`host.lua:22-37` | O15、O2 |
| `toggle`（`handle("toggle")`、`init.lua` 31–33 行） | すべて | `g:skkeleton#mode == ""` か `g:skkeleton#enabled` が偽なら `enable`、そうでなければ `disable`（`main.lua` 169–175 行）。判断は公開している変数だけでする | `main.lua:169-175` | O15 |
| `complete`（`handle` ではなく `main.complete`。`init.lua` 132–134 行 → `completion.confirm`） | I_POINT | `popup.close()`、`ctx.vim_mode` の記録、`initialize_state_with_abbrev(ctx, { "converter", "table" })`（変換中の状態を捨てる）、選んだ語をユーザー辞書に登録して `last_candidate` に入れる、`candidate.modify` と `converter`、`ctx:kakutei_with_undo_point(text)`、`g:skkeleton#state` の更新、`render` | `main.lua:205-236`、`completion/init.lua:221-226` | O15 |
| `commit_preedit`（`main.commit_preedit`） | I_POINT / I_SELECT | `common.kakutei`、`popup.close()`、`g:skkeleton#state`、`render`（`guard` と `paste` から呼ぶ） | `main.lua:187-199` | — |

`completion.confirm` は `can_complete()`（skkeleton が有効、insert、input:okurinasi、読みが空でない）が偽なら何もしません（`completion/init.lua` 161–179、221–226 行）。blink.cmp の menu で選んで `<CR>` を押したときは、`handle_keys` が `completion.accept_selected()` を先に試します（`main.lua` 84–87 行、`completion/init.lua` 278–312 行）。

## 辞書登録（`host.input()`）の autocmd

`host.input()` は、辞書登録のプロンプトの間だけ `WinEnter` と `CmdlineEnter` を作ります。`InsertEnter` は `keepState` の経路（`function/disable.lua` の `escape`）で作られます。

| autocmd | 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|---|
| `WinEnter`（`skkeleton-host-input`） | P_PROMPT | `vim.schedule` の中で、スタックの一番上のフレームが自分のままで、cmdwin でもなく、今のウィンドウが違えば、フレームのウィンドウへ戻す。フレームを pop すると `nvim_clear_autocmds` で消す | `host.lua:70-93, 125-138` | timing、O12 |
| `CmdlineEnter`（one-shot） | P_PROMPT | `map.map()` をして、`<Esc>`、`<C-g>`、`<C-c>` を `host.cancel_input()`（取り消しの印を書いて `<CR>`）に差し替える | `host.lua:194-204`、`host.lua:166-169` | O12 |
| `InsertEnter`（`keepState` のときだけ） | N_OFF（次に insert へ入るとき） | `keepState` で `<Esc>` したときに、その buffer の次の `InsertEnter` で `main.handle("enable")` を 1 回だけ呼ぶ | `host.lua:235-244`、`function/disable.lua:21-27` | O13 |

`host.input()` の中では、`store.init_context()` と `g:skkeleton#state = { phase = "input", henkanFeed = "", preedit = "" }` をしてから `vim.fn.input(prompt)` に入ります（190–205 行）。外側の pre-edit は `render.freeze()` で残したまま見せ、取り消しなら `render.thaw()`、登録するなら `render.unfreeze()` で戻します（182–213 行）。pop すると、退避した Context とモードに戻して `map.map()` と `User skkeleton-enable-post` をします（125–162 行）。

## 補完（blink.cmp）の User イベント

blink.cmp が無い環境では、7–10 の autocmd は登録されるが callback の中身は動きません（`get_blink()` が nil）。入力状態は変えません。

| イベント | 効く状態 | 何をするか | 根拠 | 印・観測 |
|---|---|---|---|---|
| `User skkeleton-handled` | I_POINT / I_SELECT | `completion.refresh()`。有効で、input:okurinasi で、読みが `minLength` 以上なら blink のメニューを開く／開き直す。そうでなければ閉じる | `completion/init.lua:128-134, 246-273` | IC は unknown |
| `User skkeleton-enable-post`、`skkeleton-disable-post` | すべて | `completion.hide(true)` で、skkeleton が開いたものではないメニューも閉じる | `completion/init.lua:135-142, 93-105` | 同上 |
| `User BlinkCmpMenuOpen` | IC | 有効で input:okurinasi なら、メニューの `align_to` を一時的に `cursor` にする（#143、#174） | `completion/init.lua:143-151, 69-79` | 同上 |
| `User BlinkCmpMenuClose` | IC | `align_to` を元に戻す | `completion/init.lua:152-158, 81-91` | 同上 |

## インジケータ（`skkeleton-indicator`）

インジケータは `g:skkeleton#enabled`、`g:skkeleton#mode`、`g:skkeleton#state` と `User` イベントだけを読み、入力状態は変えません（`indicator/indicator.lua` 30–50 行）。18 個の autocmd は 1 か所のループで作ります。

| イベント | パターン | 何をするか | 根拠 |
|---|---|---|---|
| `InsertEnter` | `*` | 表示を開く | `indicator.lua:31, 234-238` |
| `InsertLeave` | `*` | 表示を閉じる | `indicator.lua:32, 343-355` |
| `CursorMovedI` | `*` | 表示の位置を合わせる | `indicator.lua:33, 275-288` |
| `CmdlineEnter` | `*` | cmdline 用に表示を開く | `indicator.lua:34, 239-243` |
| `CmdlineLeave` | `*` | cmdline 用の表示を閉じる | `indicator.lua:35, 245-252` |
| `CmdlineChanged` | `*` | cmdline 用の表示を更新する | `indicator.lua:36, 254-259` |
| `TextChangedI`、`TextChangedP` | `*` | 表示を更新する | `indicator.lua:37-38, 261-266` |
| `WinScrolled`、`WinResized`、`WinLeave` | `*` | 表示を閉じる | `indicator.lua:39, 343-355` |
| `ModeChanged` | `*` | モードが変わったら表示を更新する | `indicator.lua:40, 290-311` |
| `User skkeleton-handled` | `skkeleton-handled` | 表示を更新する | `indicator.lua:41, 268-273` |
| `User skkeleton-mode-changed`、`skkeleton-disable-post`、`skkeleton-enable-post` | 各パターン | 表示を更新する | `indicator.lua:42-44, 313-341` |
| `OptionSet` | `background` | 色を読み直す | `indicator.lua:45, 364-372` |
| `ColorScheme` | `*` | 色を読み直す | `indicator.lua:46, 364-372` |

## 観測

Neovim 0.11.6 の headless で、一時ディレクトリの辞書だけを使い、`indicator = false`、`completion = { enabled = false }`（blink.cmp 無し）で観測しました。キーは別の nvim から `--remote-send` で送り、`g:skkeleton#enabled`、`g:skkeleton#mode`、`g:skkeleton#state`、バッファ、カーソル、`:autocmd` の一覧を `--remote-expr` で読みました。辞書登録と `keepState` の観測では、その設定を足しています。

### O1. insert の `▽` で `<Esc>`

`i`、有効化、`;ka`、`<Esc>`。

- 前: モード i、enabled=true、`g:skkeleton#state` は phase=input:okurinasi、preedit=▽か。
- 後: モード n、enabled=false、`g:skkeleton#mode`=""、preedit=""、バッファは `か`、カーソルは `{ 1, 0 }`。
- `<Esc>` のときの `ModeChanged` は 1 回だけ（old=i、new=n）。規則 4 の「state が escape」の分岐で、その場で `reset_state`。この分岐は `SafeState` を作らない（`cleanup.lua` 218–221 行）。

### O2. `<C-c>` で insert を抜ける

`i`、有効化、`;ka`、`<C-c>`。

- 後: モード n、enabled=false、バッファは `か`、カーソルは `{ 1, 0 }`。
- `ModeChanged`（i→n、規則 4、old の先頭が i）のあと、`SafeState` の one-shot が `commit_preedit("normal")`、`reset_state`、`disable` をした。`User skkeleton-disable-pre`、`skkeleton-mode-changed`、`skkeleton-disable-post` が出た。

### O3. `<Insert>` で置換モードへ

`i`、有効化、`;ka`、`<Insert>`。

- 後: モード R、enabled=false、バッファは `か`、カーソルは `{ 1, 3 }`（確定文字の後ろ）。
- `ModeChanged`（i→R、規則 2）で `commit_preedit("insert")`、`reset_state`、`disable`。

### O4. `<C-o>` のあと、normal のコマンドでカーソルだけ動かす

行 `abc` の末尾で insert（`A`）、有効化、`;ka`、`<C-o>`、`0`。

- 前: preedit=▽か、カーソル `{ 1, 3 }`。
- 後: モード i に戻り、enabled=true、バッファは `abcか`（pre-edit の位置に `か` が確定）、カーソルは `0` で移った先の `{ 1, 0 }`、preedit=""。
- `ModeChanged` の `niI`→`i`（規則 3）で `reset_if_stale("i")`。カーソルだけのずれだったので `commit_preedit()`（カーソルは動かさない）。`disable` はしない。

### O5. `<C-o>x` でバッファの文字を消す

行 `abc` の末尾で insert（`A`）、有効化、`;ka`、`<C-o>`、`x`。

- 前: preedit=▽か、カーソル `{ 1, 3 }`。
- 後: モード i、enabled=true、バッファは `ab`（`x` が `c` を消した）、カーソルは `{ 1, 2 }`、preedit=""。読み `か` はどこにも残らない。
- 途中の `ModeChanged` は `niI`→`no`、`no`→`niI`、`niI`→`i`。最後の `niI`→`i` が規則 3 に当たり、`reset_if_stale("i")` が `drop` した（カーソルだけのずれではないため）。同じ形を #199 に書いた。

### O6. 外からバッファを書き換える

行 `abc` の末尾で insert（`A`）、有効化、`;ka`、`nvim_buf_set_text(0, 0, 3, 0, 3, { "X" })`。

- 後: バッファは `abcX`、カーソルは `{ 1, 3 }`、preedit=""、enabled=true、phase=input。
- `on_bytes` が `mark_bytes_changed` を立て、`vim.schedule` の `check_stale` が `drop` した。`TextChangedI` はそのあとに来て、そのときにはもう preedit が無い。

### O7. cmdline の `▽` で `<C-u>`

normal で `:`、cmdline で有効化、`;ka`、`<C-u>`。

- 前: モード c、cmdline は `▽か`、preedit=▽か。
- 後: モード c、enabled=true、`g:skkeleton#mode`="hira"、cmdline は空（`getcmdline()`=""、`getcmdpos()`=1）、preedit=""。
- `CmdlineChanged` ごとに `check_stale` が走り、`<C-u>` のあとに `cmdline.clean()` が pre-edit を取り除いた。

### O8. cmdline の `▽` で `<Esc>`

normal で `:`、cmdline で有効化、`;ka`、`<Esc>`。

- 後: モード n、enabled=false、preedit=""、`: ` の履歴は `か`（マーカーは消えている）。
- `<Esc>` は cmdline のマッピングで `escape` を呼び、読みを確定して `disable` した（`function/disable.lua` 21–27 行）。`CmdlineLeave` が履歴を掃除し、`ModeChanged`（c→n）の規則 4 の「state が escape」の分岐で `reset_state`。

### O9. cmdline の `▽` で `<C-c>`

normal で `:`、cmdline で有効化、`;ka`、`<C-c>`。

- 後: モード n、enabled=false、preedit=""、`: ` の履歴は空（マーカーを含む項目ごと消えた）。
- `CmdlineLeave` が `clean_cmdline` と cmdline の記録の `reset` をし、`ModeChanged`（c→n）の規則 4 の one-shot が `reset_state` と `disable` をした。

### O10. insert からマウスで visual へ

行 `hello world` の末尾で insert、有効化、`;kanji`、`set mouse=a` でダブルクリック。

- 前: モード i、preedit=▽かんじ。
- 後: モード v、enabled=false、バッファは `hello worldかんじ`、preedit=""。
- 1 回目の押下でカーソルが動き、`CursorMovedI` の `reset_if_stale` が先に `commit_preedit()` をした（この時点ではまだ enabled=true）。そのあとの `ModeChanged`（i→v、規則 1）は、確定する pre-edit がもう無い状態で `reset_state` と `disable` をした。
- 押下でカーソルが動かないときは、`ModeChanged`（i→v、規則 1）の時点で pre-edit が残っている。ドラッグ（押下・移動・離す）では、`ModeChanged` の `commit_preedit()`（カーソルは動かさない）が確定し、そのあと `reset_state` と `disable` をした（別の観測）。
- pre-edit が無いときも同じダブルクリックで i→v になり、enabled=false になった。

### O11. visual から入った cmdline で有効化して `<Esc>`

行 `ab cd` で `v/`、cmdline で有効化、`;ka`、`<Esc>`。

- 後: モード v に戻り、enabled=false、preedit=""、phase=input。
- `CmdlineLeave` と `ModeChanged`（c→v、規則 5）の「state が escape」の分岐で `reset_state`。

### O12. 辞書登録のプロンプト

insert で有効化、`;nuru`、`<Space>`（辞書に候補が無い読み）。

- プロンプト中: モード c、`getcmdtype()` は `@`、enabled=true、`g:skkeleton#state` は preedit="" の仮の値。外側の pre-edit `▽ぬる` は extmark で残ったまま。
- `skkeleton-host-input` に `WinEnter` が 1 つ登録され、`split` してもフレームのウィンドウに戻った。
- プロンプトで `<Esc>` を取り消すと、モード i に戻り、enabled=true、preedit=▽ぬる。`CmdlineLeave`（cmdtype=`@`）が履歴の `@` を掃除した。
- プロンプトで `tesuto` と打つと cmdline は `てすと` になり、`<CR>` で `ぬる` の語として確定してユーザー辞書に `ぬる /てすと/` が書かれた。確定したあとはモード i、enabled=true、preedit=""。

### O13. `new` でウィンドウを移る

insert で有効化、`;ka`、`vim.cmd("new")`。

- 後: モード i、enabled=false、新しいバッファは空（元のバッファにも `か` は入らない）、preedit=""。
- `WinLeave` が `reset_state` と `disable` をし、読みは確定しない。`BufLeave` も来るが、そのときにはもう無効なので `disable` は何もしない（`host.lua` 23–25 行）。

### O14. 終了

insert で有効化、`;ka`、`qa!`。

- `VimLeavePre` が来て、`Library:save()` が呼ばれた（偽の Library の `save` を包んで確認）。
- 状態の片付けはされない（`g:skkeleton#state.preedit` は `▽か` のまま）。

### O15. API

- `disable`（pre-edit が `▽か`）: バッファに `か` が確定し、モード i のまま、enabled=false、`g:skkeleton#mode`=""、preedit=""、カーソルは `{ 1, 3 }`。
- `toggle`（無効から）: enabled=true、`g:skkeleton#mode`="hira"。
- `toggle`（有効から、pre-edit 無し）: enabled=false。
- `complete("かん", "漢字", "okurinasi")`（pre-edit が `▽かn`）: バッファに `漢字`、preedit=""、enabled=true、`g:skkeleton#mode`="hira"。`get_henkan_result("okurinasi", "かん")` の先頭が `漢字` になった（ユーザー辞書に登録された）。

### O16. `CompleteDone` と `TextChangedP` の handler

`eventignore` で `CursorMovedI` を止めたままカーソルだけを動かして pre-edit をずらし、`nvim_exec_autocmds("CompleteDone", {})` を起こすと、`check_stale` が走って読みが元の位置に確定した（`abかc`、preedit=""、enabled=true）。`TextChangedP` でも同じだった。どちらのイベントも、ずれが無ければ何もしない。

### O17. 登録一覧

`nvim_create_autocmd` を包んで呼び出しを記録し、`setup()` と有効化のあとに `nvim_get_autocmds` で `skkeleton-*` のグループを読むと、33 個（`skkeleton-internal` 10、`skkeleton-completion` 5、`skkeleton-indicator` 18）だった。辞書登録の `input()` の間は `skkeleton-host-input` に `WinEnter` が 1 つ増え、`keepState` の `<Esc>` のあとは `skkeleton` に `InsertEnter` が 1 つ増えた。

### O18. 検算（ダブルクリックとドラッグ、`<C-o>x`、`enew`）

- ダブルクリック（`set mouse=a`、`hello world` の末尾で `;kanji`）: `CursorMovedI` のあとに `ModeChanged`（i→v）が来た。`CursorMovedI` の時点（skel の callback のあと）には pre-edit は空だった。確定は 1 回目の押下の `CursorMovedI` で起き、`ModeChanged` では確定する pre-edit がもう無い。
- ドラッグ（押下・移動・離す）: skel の `ModeChanged` callback より前に読むと、i→v の時点で pre-edit がまだ `▽かんじ` だった。そのあと確定して disabled になった。
- `<C-o>x`（`abc` の末尾で `Kan`、pre-edit は `▽かn`）: バッファは `ab`、preedit=""、enabled=true。読みは確定しない。
- `enew`（`one` の行で `Kan`）: 元のバッファは `one` のまま。enabled=false、preedit=""。
- `nvim_get_autocmds` で数えると、常設は 33 個（internal 10、completion 5、indicator 18）。`SafeState`、`WinEnter`、`CmdlineEnter`、`InsertEnter` は動的で、同時に 4 つそろうとは限らない。

## 今の振る舞いのまとめ

- 読みが確定する道は、`<Esc>`（キーの処理）、`commit_preedit` を呼ぶ道（規則 1・2、規則 3 のカーソルだけのずれ、SafeState の one-shot で old が i のとき）、`disable` API です。
- 読みが `drop` される道は、`WinLeave` / `BufLeave`（#169）、`ModeChanged` の規則 3 でカーソル以外のずれがあるとき（`<C-o>x`、外部からの変更。 #199）、`TextChangedI` などの `check_stale` でカーソル以外のずれがあるときです。
- `SafeState` に頼る道（規則 4・5）は、`vim.schedule` ではありませんが、`SafeState` が来るまで状態が残ります。`ModeChanged` の callback の中では、`SafeState` の one-shot を作るだけで、確定と初期化はしません。
- 表示だけの autocmd（補完、インジケータ）は、入力状態を変えません。
- `CmdlineLeave` と `ModeChanged`（old が c）は、履歴からマーカーを消します。`CmdlineLeave` の 2 回目は `vim.schedule` です。
- 辞書登録の `input()` の中では、`g:skkeleton#state` は仮の値（preedit=""）になります。外側の pre-edit は extmark で残ります。

## この表に入れないもの

- キーそのもの（どのキーを skkeleton が受けるか）は #181。
- terminal（t / nt）の状態機械は #188。今回の観測は insert・normal・visual・cmdline だけです。
- 補完メニューの中の動き（blink.cmp の accept など）は #190。この環境には blink.cmp が無いので、`IC` は unknown のままです。
- マクロと `.` は #192、貼り付け・マウス・ホイールは #191。
- 辞書 DB の非同期の構築（`dictionary/db.lua` の `run_async`、`vim.defer_fn`、`vim.schedule`）は入力状態を変えないので入れていません。
- インジケータのフェードアウトのタイマー（`indicator.lua` 120–134 行）は表示だけです。

## 未観測・決めていないこと

- `IC`（補完のメニューが開いている状態）と、その中の `CompleteDone` / `TextChangedP` は blink.cmp が無いため観測していません。
- `R_MID`（`<Insert>` による i→R の移り変わりの途中）は観測で作れませんでした。遷移の途中の状態としてだけ扱います。`N_LOST` はクラスにせず、読みが消える遷移を P1 の破れとして扱います。
- `V_PRE` は `<C-o>v` のあと pre-edit が残り続ける状態です（O-ctrl-o-v）。ダブルクリックでは 1 回目の押下の `CursorMovedI` が先に確定するため、`ModeChanged` の時点で pre-edit は空でした。ドラッグでは `ModeChanged` の時点で残っていましたが、これは遷移の途中として扱います（O18）。
- upstream（denops 版）との比較はしていません。この表は Lua 版のコードと観測だけです。

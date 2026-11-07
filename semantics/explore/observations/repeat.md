# マクロと `.` の観測（#192 / 07f）

`repeat.jsonl` は、`semantics/explore/repeat.lua` で取った観測です（15 件）。1 行が 1 つのキー列で、前後の状態クラス（`semantics/GLOSSARY.md`）と、レジスタ `a` / `.`、undo の各段階のバッファを残しています。

子の nvim は `tests/helpers.lua` の `e2e_set`（一時ディレクトリの辞書、`HISTFILE=/dev/null`、インジケータは無効）です。マクロの記録は normal のキーなので、`qa` と `@a` はキー列として流しています。

```sh
flock /tmp/heavy.lock timeout 900 nvim --headless -u NONE -i NONE -l semantics/explore/repeat.lua
```

`05` の探索器でも同じキー列を流せます。`qa` と `@a` は次の文字を待つので、`explore.lua` では 1 回で送るトークン（`raw`）にしています。

```sh
nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua \
  --replay 'qa,A,<Plug>(skkeleton-enable),Kan<Space>,<C-j>,<Esc>,q,j,@a' --profile macro

flock /tmp/heavy.lock timeout 600 nvim --headless -u NONE -i NONE \
  -l semantics/explore/explore.lua --bfs --profile macro --depth 3 --max-sequences 200
```

`macro` プロファイルの幅優先は、200 遷移を広げて 914 行を観測し、状態クラスは 6 種類（`I_DIRECT`、`I_OFF`、`I_POINT`、`I_ROMAJI`、`I_SELECT`、`N_OFF`）になりました。記録中と one-shot 待ちは状態クラスに出ないので、探索の状態の鍵に `reg_recording()` と `reg_executing()` を足しています。

## 観測

| # | シナリオ | キー列 | 前 | 後 | モデルの遷移 |
| ---: | --- | --- | --- | --- | --- |
| 1 | `macro.record.insert` | `qa` `A` enable `Kan<Space><C-j>` `<Esc>` `q` | N_OFF | N_OFF | `t.N_OFF.macro_record_start` など |
| 2 | `macro.replay.insert` | 1 のあと `j` `@a` | N_OFF | N_OFF | `t.N_OFF.macro_replay` |
| 3 | `macro.replay.count` | `qa` `A` enable `kan<C-j>` `<Esc>` `j0` `q` `3@a` | N_OFF | N_OFF | `t.N_OFF.macro_replay` |
| 4 | `macro.replay.normal` | `qa` `j` `q` `j` `@a` | N_OFF | N_OFF | `t.N_REC.normal_motion`、`t.N_REC.macro_record_stop` |
| 5 | `dot.insert` | `A` enable `kan<C-j>` `<Esc>` `j0` `.` | N_OFF | N_OFF | `t.N_OFF.dot` |
| 6 | `dot.henkan` | `A` enable `Kan<Space><C-j>` `<Esc>` `j0` `.` | N_OFF | N_OFF | `t.N_OFF.dot` |
| 7 | `dot.twice` | 5 のあと `j0` `.` | N_OFF | N_OFF | `t.N_OFF.dot` |
| 8 | `undo.replay` | 2 回確定するマクロを `@a`、そのあと `u` 3 回 | N_OFF | N_OFF | `t.N_OFF.macro_replay` |
| 9 | `undo.dot` | 2 回確定する insert を `.`、そのあと `u` 3 回 | N_OFF | N_OFF | `t.N_OFF.dot` |
| 10 | `keepstate.dot` | keepState で insert のあと `<Esc>` `.` `a` | N_OFF | I_OFF | `t.N_KEEP.dot`、`t.N_OFF.insert_enter` |
| 11 | `keepstate.dot.empty` | keepState で空の insert のあと `<Esc>` `.` `a` | N_OFF | I_OFF | `t.N_KEEP.dot` |
| 12 | `keepstate.replay` | keepState で記録し、one-shot があるとき `@a` のあと `a` | N_OFF | I_DIRECT | `t.N_KEEP.macro_replay` |
| 13 | `cmdline.record` | `qa` `:` `<C-j>` `Kan<C-j>` `<Esc>` `q` | N_OFF | N_OFF | `N_OFF`（既知の不具合 #214） |
| 14 | `cmdline.replay` | 13 のあと `j` `@a` | N_OFF | N_OFF | `N_OFF`（既知の不具合 #214） |
| 15 | `terminal.record` | terminal で `qa` … `q` | T_DIRECT | T_NORMAL | `T_NORMAL`（既知の不具合 #214） |

「後」は観測した状態クラスです。13–15 は `△`（既知の不具合 #214）にしています。

## 分かったこと（モデルと観測の差）

1. **insert のマクロは、打ったキーだけがレジスタに入る（#36 の修正後）。** `qa A enable Kan<Space><C-j> <Esc> q` のレジスタ `a` は `A<80><fd>S(skkeleton-enable)Kan <80><fc>\4J\27` のような打鍵だけで、`缶` や `render.finish` は入りません。`@a` で 2 行目にも `缶` が入り、normal に戻ります（`macro.replay.insert`）。

2. **`.` は直前の変更を繰り返し、normal に戻る。** insert で確定したあとの `.` は、もう一度 insert して同じ読みを確定します（`dot.insert`、`dot.henkan`）。2 回続けても同じです（`dot.twice`）。状態クラスは N_OFF のままです。

3. **keepState の one-shot は `.` が使い切る（#152）。** `<Esc>` のあと `.` が InsertEnter を起こすので、そのあとの `a` は skk を有効にしません（`keepstate.dot`、`keepstate.dot.empty`）。モデルでは one-shot 待ちを内部状態 N_KEEP に分けました（クラスは N_OFF のまま）。

4. **`@a` は再生の最後の `<Esc>` で one-shot を残す。** keepState で one-shot があるとき、insert を含むマクロを `@a` で再生すると、再生の最後の `<Esc>` がまた one-shot を残します。そのあとの `a` は skk を有効にします（`keepstate.replay`）。normal の移動だけのマクロには `<Esc>` が無いので、one-shot は残りません。レジスタの中身を状態クラスに持たないので、モデルはこの 2 つを分けません。

5. **undo の区切りは skk の確定ごと。** `@a` でも `.` でも、`u` 1 回で戻るのは確定 1 つぶん（`<C-g>u` の区切り）です。マクロの再生全体を 1 つの undo にはしていません（`undo.replay`、`undo.dot`）。#57 と #158 で受け入れた区切りと同じで、undo は状態クラスに持っていないので `oos.repeat_undo` にしました。

6. **cmdline と terminal では、skk が流したキーがレジスタに混ざる（#214）。** cmdline で skk を有効にして記録すると、レジスタに `▽k`、BS、`<Cmd>lua require('skkeleton.render').finish()<CR>` が入ります。`@a` で再生すると `E492: Not an editor command: かん` になります（`cmdline.replay`）。terminal でも `▽か` と `finish()` が入ります（`terminal.record`。再生は未確認）。insert では #36 の修正で混ざらないので、`render.lua` の `feed` が cmdline / terminal で `t` を残していることによると見ています。issue #214 にしました。

## 過去の issue との対応

| issue | 状態 | このモデルでの扱い |
| ---: | --- | --- |
| #36 | CLOSED | insert のマクロは打ったキーだけが入る（`c78b2e7`）。`replay.macro` で再現キー列を流す |
| #57 | CLOSED | undo の区切りは `oos.repeat_undo`（`undo.replay` / `undo.dot` で観測） |
| #152 | CLOSED | `.` が InsertEnter を起こして one-shot を使い切る。`t.N_KEEP.dot` と `O-dot-keepstate` で表した |
| #214 | OPEN | cmdline / terminal のマクロのレジスタに skk の出力が混ざる（07f で見つけた別 issue） |

## モデルに足したもの

- 状態: `N_REC`（記録中）と `N_KEEP`（keepState の one-shot 待ち）。どちらも人の読むクラスは N_OFF で、内部だけ分けています。記録中かどうかは状態クラスに出ず、one-shot 待ちは次の insert の結果で分かれます。
- イベント: `macro_record_start`（`qa`）、`macro_record_stop`（`q`）、`macro_replay`（`@a`、`3@a`）、`dot_repeat`（`.`）、`normal_motion`（`j` など）。
- 遷移: 上のイベントの N_OFF / N_REC / N_KEEP の組。`I_*.esc.keepstate` の戻り先を N_OFF から N_KEEP に変え、`N_OFF.insert_enter.keepstate` を `N_KEEP.insert_enter.keepstate` に移しました。
- 観測: `O-macro-record`、`O-macro-normal`、`O36`、`O-macro-count`、`O-dot`、`O-dot-henkan`、`O-dot-keepstate`、`O-macro-replay-off`、`O-macro-replay-keepstate`、`O-macro-keepstate`。
- 再現: `replay.macro`、`replay.dot`、`replay.dot.keepstate`、`replay.macro.keepstate`。
- 対象外: `oos.macro_register`、`oos.repeat_undo`、`oos.macro_nested`。07e の `oos.macro` は消しました。

## 掘り残し

- 記録中かどうかは観測の状態クラスに出ません。insert をまたぐ記録は、戻ったあとの `q` を開始と停止の両方として許しています（`t.N_OFF.macro_record_stop` と `t.N_OFF.macro_record_start` の分かれる組）。記録を状態クラスに上げるかは、観測で結果が割れてから決めます。
- レジスタ `a` 以外のレジスタは観測していません。#36 の再現と観測が `a` だけなので、モデルも `a` だけを対象にしています。
- terminal で記録したマクロの再生は、端末のジョブを開き直す必要があり、まだ試していません。レジスタの混入だけを #214 に書きました。
- `.` が繰り返す「直前の変更」の中身（insert か delete か）は状態クラスに持っていません。insert の `.` だけを観測しました。

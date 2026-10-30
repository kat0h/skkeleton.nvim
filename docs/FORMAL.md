# 表示とモードの行き来を、モデル検査の考え方で確かめる（PoC）

pre-edit の位置、インジケータの位置、モードを行き来したあとの片付けのような、表示のずれのバグを、キー列を手で書かずに見つけるための試みです。`tests/formal/` にあります。

## 考え方

TLA+ の TLC のようなモデル検査を、仕様のモデルではなく実装そのものに当てはめています。

- **状態**: 子の nvim を 1 キーごとに落ち着かせて取った観測です（`observe.lua`）。skkeleton の内部の状態に加えて、画面の文字（`screenstring()`）、端末のカーソル、浮動ウィンドウの位置、バッファローカルのマッピング、バッファとウィンドウの数を取ります。
- **遷移**: キーを 1 つ流すことです。キーの集合は `check.lua` の `ALPHABET` で決めます。深いところへ 1 手で行けるように、`Kan` と `<Space>` 4 回もそれぞれ 1 つの遷移として扱います（マクロ遷移）。
- **初期状態**: insert モードで、カーソルが行頭・行の途中・行末の 3 つです（TLA+ の `Init`）。
- **性質**（`spec.lua`）
  - 不変条件: 1 つの観測で成り立つべきことです。「pre-edit の extmark は全バッファで高々 1 つで、カーソル位置にある」「画面の行は、バッファのカーソルの位置に pre-edit を差し込んだものと一致し、端末のカーソルは pre-edit の直後にある」「インジケータは pre-edit の直後にある」「normal に戻ったら状態・`'textwidth'`・マッピングが元に戻っている」「ウィンドウとバッファが漏れない」など。
  - 遷移の性質（TLA+ の action）: 1 キーの前後の組で成り立つべきことです。「skkeleton が処理しないキーでバッファやカーソルが動いたら、pre-edit を捨てる」（#8 の型）、「確定した文字はカーソルの位置に入り、前後の文字を変えない」など。
  - 2 手以上をまたぐ性質: 履歴を持って確かめます。「辞書登録を取り消すと、登録に入る前の行・カーソル・pre-edit に戻る」（d5fc182 の型）。
- **探索**: 観測を抽象化し（モード、有効か、skkeleton の状態、pre-edit の長さ、popup、カーソルが行のどこにあるか、など）、同じ抽象状態は 1 度しか広げない幅優先探索をします。幅優先なので、見つかった反例は最短のキー列です。深い状態にはランダムなキー列で届かせ、違反したキー列を ddmin で縮めます。

## 使い方

```sh
make verify ARGS="--depth 5 --jobs 8"            # 幅優先（深さ 5 で約 30 秒）
make verify ARGS="--random 2000 --length 30"     # ランダムなキー列 2000 本（約 1 分）
make verify ARGS="--keys '#eol,<C-j>,K,K,<Space>,<Esc>'"   # 1 本を流して、キーごとの観測と違反を出す
make verify ARGS="--list-mutations"              # 直したバグを戻す変異の一覧
make verify ARGS="--depth 5 --mutate no-stale-check"
```

`make test` には入れていません。

## 確かめたこと

直したバグを子の nvim の中に戻す変異（`--mutate`）を 7 種類作り、どれも深さ 5 までの探索で、3〜6 キーの反例として見つかりました。

| 変異 | 戻したバグ | 反例 |
| --- | --- | --- |
| `indicator-ignores-preedit` | #6 インジケータが pre-edit に置いていかれる | `#eol <C-j> K` |
| `no-stale-check` | #8 変換中の `<C-u>` などで pre-edit が残る | `#mid <C-j> A <C-w>` |
| `no-winleave-reset` | ウィンドウを移ると状態が残る | `#eol <C-j> <Cmd>wincmd w<CR>` |
| `no-normal-reset` | normal に戻っても無効にならない | `#bol <C-j> <Esc>` |
| `popup-leaks` | 229f6be popup のバッファが漏れる | `#eol <C-j> Kan <Space> <Space>×4 <C-g>` |
| `restore-loses-user-map` | 229f6be 利用者のマッピングが消える | `#bol <C-j> <C-j>` |
| `textwidth-not-restored` | `'textwidth'` を戻し忘れる | `#bol <C-j> <Esc>` |

d5fc182（行末で辞書登録を取り消すとカーソルが 1 文字左にずれる）は、修正前のコードでも headless の子ではずれが出ず、この方法では見つけられませんでした。上流で足したテストも修正前のコードで失敗しないので、実際の端末でだけ起きるものと考えられます。

## 見つかったもの（すべて修正済み）

探索で見つかり修正したバグは以下の 4 件です。

1. 辞書登録の欄で ▽ を入力中に `<Left>`・`<C-w>` などで cmdline を動かしてから確定すると、▽ ごと語として登録・確定される。例: `A <Space> A <Left> <CR>` でバッファに `▽あ` が入る。upstream でも同じになる（`tests/diff` の driver で確かめた）。→ `render.lua` で cmdline の pre-edit 範囲を記録し、ずれを検出した際（`CmdlineChanged` および次のキー処理時）に `setcmdline()` で残存 pre-edit を取り除くよう修正。
2. 辞書登録の `input()` の途中でウィンドウを移ると（`<Cmd>` のマッピングなど）、`WinLeave` の autocmd が状態を作り直してマッピングを外す。取り消すと移った先のバッファで pre-edit が戻り、確定すると ▽ ごと登録・確定される。→ `host.input()` 中は `WinLeave` の初期化をスキップし、元のウィンドウを維持するよう修正。
3. 候補一覧で、ページに無い選択キーを押すと、一覧の状態のまま popup だけ閉じる。upstream も同じ動き。→ `henkan.lua` でページ範囲外の選択キーが押された際にも `show_candidates()` を呼んで popup を維持するよう修正。
4. ウィンドウを移ったあと `g:skkeleton#state` に古い値が残る。→ `main.lua` の `reset()` でも `update_state_variable()` を呼ぶよう修正。

## 確かめていないこと

- 子の nvim は headless で、画面は 80×24 です。端末やフォント、`ambiwidth` によるずれは見ていません。
- 補完（blink.cmp）、terminal モード、折り返しのある長い行、複数行にまたがる操作は、キーの集合と初期状態に入れていません。
- 性質は人が書いたものなので、書いていない性質の破れは見つかりません。今回も、はじめに書いた性質のいくつかが仕様の誤りによる偽の反例を出し、直しました（`alwaysShown`、cmdline からの登録、`'smarttab'` の `<BS>`、タブの表示など）。

# 表示とモードの行き来を、モデル検査の考え方で確かめる（PoC）

pre-edit の位置、インジケータの位置、モードを行き来したあとの片付けのような、表示のずれのバグを、キー列を手で書かずに見つけるための試みです。`tests/formal/` にあります。

## 考え方

TLA+ の TLC のようなモデル検査を、仕様のモデルではなく実装そのものに当てはめています。

- **状態**: 子の nvim を 1 キーごとに落ち着かせて取った観測です（`observe.lua`）。skkeleton の内部の状態に加えて、画面の文字（`screenstring()`）、カーソルの画面上の位置、浮動ウィンドウの位置と中身、バッファローカルのマッピング、バッファとウィンドウの数、cmdline を取ります。
- **遷移**: キーを 1 つ流すことです。深いところへ 1 手で行けるように、`Kan` や `<Space>` 4 回もそれぞれ 1 つの遷移として扱います（マクロ遷移）。
- **プロファイル**（`profiles.lua`）: 設定、キーの集合、初期状態（TLA+ の `Init`）、辞書の組です。`make verify ARGS=--list-profiles` で一覧が出ます。

  | プロファイル | 調べること |
  | --- | --- |
  | `default` | 既定の設定で、入力・変換・編集キー・モードとウィンドウの行き来 |
  | `modes` | 入力モードの切り替え（`q`、`<C-q>`、`L`、`l`、`/`）と送り仮名・数値変換 |
  | `config` | eggLikeNewline・keepState・keepMode・別のマーカー・`showCandidatesCount = 1` |
  | `edge` | 画面の右端と下端で、popup とインジケータが画面に収まり、カーソルを隠さない |
  | `cmdline` | コマンドライン（`:`）の中での入力・変換・取り消し |
  | `styles`、`rounded`、`minimal` | インジケータの style（#9）と popup の枠（#10） |
  | `misc` | `<C-o>`・`<C-r>=`・`<C-v>`・`<C-n>` の補完・`o`/`O`・`R`（置換）・`X`（候補の削除） |
  | `terminal` | terminal モードでの入力・変換・抜け方 |
  | `blink` | blink.cmp の補完（利用者の設定と同じ super-tab、auto_insert） |
  | `wrap` | 折り返しのある長い行と全角の行で、pre-edit・インジケータ・popup が折り返しをまたぐ |
  | `okuri` | 送り仮名・数値変換・abbrev 変換 |

- **性質**（`spec.lua`）
  - 不変条件: 1 つの観測で成り立つべきことです。「pre-edit の extmark は全バッファで高々 1 つで、カーソル位置にある」「画面の行は、バッファのカーソルの位置に pre-edit を差し込んだものと一致する」「インジケータは pre-edit の直後にあり、今のモードの文字列を出す」「popup の中身は今のページの候補」「float は画面に収まり、カーソルを隠さない」「cmdline のカーソルの前は pre-edit で終わり、マーカーを残さない」「normal に戻ったら状態・`'textwidth'`・マッピングが元に戻っている」「ウィンドウとバッファが漏れない」など。
  - 遷移の性質（TLA+ の action）: 1 キーの前後の組で成り立つべきことです。「skkeleton が処理しないキーでバッファやカーソルが動いたら、pre-edit を捨てる」（#8 の型）、「確定した文字はカーソルの位置に入り、前後の文字を変えない」など。
  - 2 手以上をまたぐ性質: 履歴を持って確かめます。「辞書登録を取り消すと、登録に入る前の行・カーソル・pre-edit に戻る」（d5fc182 の型）、「keepState なら、insert に戻ると抜ける前のモードで有効になる」。
- **探索**: 観測を抽象化し（モード、有効か、skkeleton の状態、pre-edit の長さ、popup、カーソルが行のどこにあるか、など）、同じ抽象状態は 1 度しか広げない幅優先探索をします。幅優先なので、見つかった反例は最短のキー列です。深い状態にはランダムなキー列で届かせ、違反したキー列を ddmin で縮めます。
- **本物の端末**（`tui.lua`）: tmux の中で TUI の nvim を動かし、tmux の `cursor_x`・`cursor_y` と `capture-pane` を正解にして確かめます。headless の子の `screencol()` は、枠つきの float が出ていると正しい値を返さないので、そこは端末で確かめます。
- **upstream との見比べ**（`upstream.lua`）: 見つけた反例のキー列を、Lua 版と denops 版の両方に流して見比べます。denops 版は起動に時間がかかるので、探索には入れず、反例を確かめるときだけ使います。

## 使い方

```sh
make verify ARGS="--profile misc --depth 5"              # 幅優先。並列数の既定はコア数 − 2（深さ 5 で 30 秒〜1 分）
make verify ARGS="--random 2000 --length 30"             # ランダムなキー列 2000 本（約 1 分）
make verify ARGS="--keys '#eol,<C-j>,K,K,<Space>,<Esc>'" # 1 本を流して、キーごとの観測と違反を出す
make verify ARGS="--list-profiles"
make verify ARGS="--list-mutations"                      # 直したバグを戻す変異の一覧
make verify ARGS="--depth 5 --mutate no-stale-check"

# 本物の端末（tmux が要る）
nvim --headless -u NONE -i NONE -l tests/formal/tui.lua --profile edge --keys '#right,Kan'
# upstream（deno と denops.vim が要る）
nvim --headless -u NONE -i NONE -l tests/formal/upstream.lua 'A<Space>A<Left><CR><C-g>'
```

`--keys` の先頭の `#mid` などは初期状態の名前です。`make test` には入れていません。

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

d5fc182（行末で辞書登録を取り消すとカーソルが 1 文字左にずれる）は、修正前のコードでも、headless の子と tmux の中の TUI のどちらでも、ずれが出ませんでした。上流で足したテストも修正前のコードで失敗しないので、利用者の設定によって起きるものと考えられます。この方法では、検査の設定に無いものは見つけられません。

## 見つかったもの

#12〜#24 を issue にしました（#20 と #22 は別のセッションが立てたもの）。直していないものは、`spec.lua` の `M.known` に理由と一緒に書き、探索を続けられるようにしています。upstream にもあるものには `upstream` ラベルを付けています。

| issue | 内容 | upstream | 状態 |
| --- | --- | --- | --- |
| #12 | 辞書登録の欄でカーソルを動かすと、▽ ごと語が登録・確定される。cmdline のずれを次のキーまで見つけない | 同じ | 修正済み（`render.lua` で cmdline の pre-edit の範囲を覚え、ずれたら `setcmdline()` で取り除く） |
| #13 | 辞書登録の途中でウィンドウを移ると、状態とマッピングが外れる | — | 修正済み（`host.input()` の最中は `WinLeave` で初期化しない） |
| #14 | 候補一覧で、ページに無い選択キーを押すと popup だけ消える | 同じ動き | 修正済み（`show_candidates()` を呼び直す） |
| #15 | ウィンドウを移ったあと `g:skkeleton#state` に古い値が残る | 同じ動き | 修正済み（`reset()` で `update_state_variable()` を呼ぶ） |
| #16 | 枠つきのインジケータが、画面の右端でカーソルと打った文字を隠す | skkeleton_indicator.nvim も同じ | 未修正 |
| #17 | `<C-r>=` で式を入れて戻ると、インジケータが消えたままになる | — | 未修正 |
| #18 | 補完で候補が入ると、インジケータが元の位置に残る | 未確認 | 未修正 |
| #19 | ▽ の入力中に補完を入れたり取り消したりすると、pre-edit が行の途中に描かれる | —（upstream は pre-edit をバッファに書く） | 未修正 |
| #21 | pre-edit が画面の次の行へ折り返すと、インジケータが前の行の右端に残る | 無い | 未修正 |
| #23 | カーソルの直後にタブがあると、インジケータがタブの後ろに出る | skkeleton_indicator.nvim も同じ | 未修正 |
| #24 | blink.cmp: 有効にしても、無効のときに出ていた buffer の補完のメニューが残る | —（upstream は別のプラグインで連携する） | 未修正 |

## 確かめていないこと

- 端末やフォント、`ambiwidth` によるずれ。子の nvim は 80×24 です。
- blink.cmp と nvim-cmp の補完、折り返しのある長い行、複数行にまたがる操作。
- 性質は人が書いたものなので、書いていない性質の破れは見つかりません。今回も、はじめに書いた性質のいくつかが仕様の誤りによる偽の反例を出し、直しました（`alwaysShown`、cmdline からの登録、`'smarttab'` の `<BS>`、タブの表示、枠つきインジケータの位置など）。

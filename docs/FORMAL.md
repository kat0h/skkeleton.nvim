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
  | `steal` | Vim のモードの移り方（`<C-[>`、`<C-\><C-n>`、`<C-o>`、`<Insert>`、visual 経由）と、カーソルやウィンドウを奪う操作（タイマー、浮動ウィンドウ、マウス、スクロール、画面の幅） |
  | `options` | 表示に関わるオプション（`number`・`cmdheight=0`・`nowrap`・`ambiwidth=double`・`list`・`virtualedit`） |
  | `noindicator` | インジケータを切ったもの（原因の切り分け用） |

  どのプロファイルのキーの集合にも `<C-c>` が入っています。`,` を含む操作には、`<ClickL2>`・`<StealCursor>`・`<WheelDown>` などの別名（`profiles.lua` の `M.aliases`）を付けて、`--keys` に書けるようにしています。

- **性質**（`spec.lua`）
  - 不変条件: 1 つの観測で成り立つべきことです。「pre-edit の extmark は全バッファで高々 1 つで、カーソル位置にある」「画面の行は、バッファのカーソルの位置に pre-edit を差し込んだものと一致する」「インジケータは pre-edit の直後にあり、今のモードの文字列を出す」「popup の中身は今のページの候補」「float は画面に収まり、カーソルを隠さない」「cmdline のカーソルの前は pre-edit で終わり、マーカーを残さない」「normal に戻ったら状態・`'textwidth'`・マッピングが元に戻っている」「ウィンドウとバッファが漏れない」など。
  - 遷移の性質（TLA+ の action）: 1 キーの前後の組で成り立つべきことです。「skkeleton が処理しないキーでバッファやカーソルが動いたら、pre-edit を捨てる」（#8 の型）、「確定した文字はカーソルの位置に入り、前後の文字を変えない」など。
  - 2 手以上をまたぐ性質: 履歴を持って確かめます。「辞書登録を取り消すと、登録に入る前の行・カーソル・pre-edit に戻る」（d5fc182 の型）、「keepState なら、skkeleton の `<Esc>` で抜けたあと同じバッファで insert に戻ると有効になる」。
  - upstream の issue から作った性質: `g:skkeleton#mode` は内部のモードと同じ（upstream #69）、disable-post は無効になったときだけ（#130）、モードが変わったら mode-changed が来る（#43）、`<C-j>` で有効・無効が切り替わる（#4・#45）。
- **探索**: 観測を抽象化し（モード、有効か、skkeleton の状態、pre-edit の長さ、popup、カーソルが行のどこにあるか、など）、同じ抽象状態は 1 度しか広げない幅優先探索をします。幅優先なので、見つかった反例は最短のキー列です。深い状態には、ランダムなキー列か、カバレッジを手がかりにしたファジング（`--fuzz`。「状態→キー→状態」の辺に新しく届いたキー列をコーパスに取り、まれな辺に届いたものほど伸ばす。1 本ごとにキーの集合と設定をランダムに絞るスウォームつき）で届かせ、違反したキー列を ddmin で縮めます。
- **同じところを何度も調べない**: 幅優先の結果は、プロファイル・深さ・コードのハッシュを鍵に `.tests/formal-cache/` に覚え、同じなら流しません。ファジングはコーパスを引き継いで前回の続きから流します。
- **本物の端末**（`tui.lua`）: tmux の中で TUI の nvim を動かし、tmux の `cursor_x`・`cursor_y` と `capture-pane` を正解にして確かめます。headless の子の `screencol()` は、枠つきの float が出ていると正しい値を返さないので、そこは端末で確かめます。
- **入力エンジンだけの検査**（`core.lua`）: nvim の子を使わず、同じプロセスの中で core を動かします。本物のキーの振り分け（`keymap.handle_key`）を通し、UI へ出るところ（`host`）だけを差し替えます。1 キーが数十マイクロ秒で済むので、深さ 12 の幅優先や、30 キーの列を 10 万本流すランダム探索が十数秒で終わります。cmdline と terminal で使う「BS で消して書き直す」出力を仮想の行に当て、行がいつも「確定した文字列 + pre-edit」になること、確定した文字列が `<BS>` のほかで縮んだり書き換わったりしないこと、マーカーが入らないこと、状態が整っていること（▼ なら候補があり番号が範囲内、など）を確かめます。
- **ちらつき**（`tui.lua --flicker`、#25）: 本物の端末に出たフレーム（同期出力 `ESC[?2026h`〜`ESC[?2026l`）を 1 キーごとに数え、各フレームの終わりのカーソル位置を小さな端末のまねで追います。最後のカーソル位置と違うところで終わったフレームを「寄り道」として出し、同じキー列を素の nvim でも流して、skkeleton のせいで増えたものだけを残します。
- **録画**（`tui.lua --record`）: 1 キーごとの本物の画面を asciinema の形式で書き出します。画面の下に何手目か・キー列・違反を出します。agg で GIF にして、`formal-recordings` ブランチに置き、issue に貼っています。
- **upstream との見比べ**（`upstream.lua`）: 見つけた反例のキー列を、Lua 版と denops 版の両方に流して見比べます。denops 版は起動に時間がかかるので、探索には入れず、反例を確かめるときだけ使います。

## 使い方

```sh
make verify ARGS="--profile misc --depth 5"              # 幅優先。並列数の既定はコア数 − 2（深さ 5 で 30 秒〜1 分）
make verify ARGS="--random 2000 --length 30"             # ランダムなキー列 2000 本（約 1 分）
make verify ARGS="--profile steal --fuzz 200 --seed-depth 2"  # 幅優先の深さ 2 を種にしたファジング（前回の続きから）
make verify ARGS="--profile options --config '{ keepState = true }' --keys '#list,<C-j>,n'"  # ファジングの反例を設定つきで再生
make verify ARGS="--keys '#eol,<C-j>,K,K,<Space>,<Esc>'" # 1 本を流して、キーごとの観測と違反を出す
make verify ARGS="--list-profiles"
make verify ARGS="--list-mutations"                      # 直したバグを戻す変異の一覧
make verify ARGS="--depth 5 --mutate no-stale-check"

# 入力エンジンだけ（速い）
nvim --headless -u NONE -i NONE -l tests/formal/core.lua --depth 12 --max-states 20000
nvim --headless -u NONE -i NONE -l tests/formal/core.lua --random 100000 --length 30
nvim --headless -u NONE -i NONE -l tests/formal/core.lua --config '{eggLikeNewline=true}' --random 50000
# 本物の端末（tmux が要る）
nvim --headless -u NONE -i NONE -l tests/formal/tui.lua --profile edge --keys '#right,Kan'
nvim --headless -u NONE -i NONE -l tests/formal/tui.lua --flicker --keys '#mid,<Esc>,:,<BS>'      # ちらつき
nvim --headless -u NONE -i NONE -l tests/formal/tui.lua --keys '#mid,<C-c>' --record out.cast      # 録画
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

モデル検査で見つけたものは issue にしています（#12〜#35。#20 と #22 は別のセッションが立てたもの、#25 は検査の提案、#33 は設計の記録）。開いている issue の型は `spec.lua` の `M.known` に理由と一緒に書き、探索を続けられるようにしています。upstream にもあるものには `upstream` ラベルを付け、ほとんどの issue に再現の GIF を付けています。

一覧と今の状態は `gh issue list -R kat0h/skkeleton.nvim --state all` で見られます。根本から直すには設計を変える必要がありそうな型（モードの行き来の片付け、pre-edit の出し方、インジケータの更新）は、#33 にまとめています。

## 確かめていないこと

- 端末やフォントによるずれ。子の nvim と tmux は 80×24 です（`ambiwidth=double` は `options` で試しています）。
- nvim-cmp の補完、複数行にまたがる操作、マクロ（`q`・`@`）、ユーザーの設定に依存するもの（d5fc182 の型）。
- 性質は人が書いたものなので、書いていない性質の破れは見つかりません。今回も、はじめに書いた性質のいくつかが仕様の誤りによる偽の反例を出し、直しました（`alwaysShown`、cmdline からの登録、`'smarttab'` の `<BS>`、タブの表示、枠つきインジケータの位置など）。

# モデル検査の手引き

skkeleton.nvim のバグの多くは、モデル検査で見つけています。このリポジトリで初めて作業する人やエージェントが、検査を流し、結果を仕分け、issue にして直すまでを、一通りできるように書きました。道具の細かい説明（プロファイルの一覧、性質の一覧、オプション）は、`poc/formal-ui` ブランチの `docs/FORMAL.md` にあります。

Neovim のモードと skkeleton の状態を合わせた「今の」振る舞いを、状態機械として書き出した仕様書は、`formal-semantics` ブランチの [`semantics/STATE_MACHINE.md`](https://github.com/kat0h/skkeleton.nvim/blob/formal-semantics/semantics/STATE_MACHINE.md) にあります（#179）。この仕様書は `semantics/model/model.lua` から生成するもので、モデルと生成の道具も同じブランチにあります。main には写しを置いていません（写すと更新されない文書になり、すぐ実際の振る舞いとずれるため）。用語と性質 P1–P15 の一覧は `semantics/GLOSSARY.md` にあります。

## なぜやるのか

skkeleton の不具合は、決まった形で出ることが多いです。たとえば次のようなものです。

- Vim のモードを行き来したあとの片付け漏れ（`<C-c>` で抜ける、`<C-o>`、visual を経由する、マウス、辞書登録の入れ子など）
- pre-edit（`▽かん` など）とバッファのずれ
- cmdline や terminal での表示の崩れ

こうした不具合は、キーの組み合わせが多すぎて、手で書いたテストではなかなか見つかりません。そこで、キー列を機械に作らせて、どの状態でも守られるべき決まり（性質）が破れないかを調べます。

## 考え方

TLA+ の TLC のようなモデル検査を、仕様のモデルではなく、実装そのものに当てています。

- 状態：子の nvim を 1 キーごとに落ち着かせて取った観測です。skkeleton の内部の状態、画面の文字、カーソルの画面上の位置、浮動ウィンドウ、マッピング、cmdline などです。
- 遷移：キーを 1 つ送ることです。`Kan` のように、よく使う並びは 1 つの遷移としてまとめてあります。
- プロファイル：設定、送るキーの集合、初期状態、辞書の組です。`default`、`cmdline`、`terminal`、`register`（辞書登録）、`blink`（補完）、`unmapped`（skkeleton が奪わない特殊キー）などがあります。
- 性質：破れたらバグとみなす決まりです。次の 3 種類があります。
  - 1 つの状態で成り立つもの（不変条件）：「pre-edit はカーソルの位置に 1 つだけ」「normal に戻ったら状態とマッピングが元に戻っている」など
  - 1 キーの前後で成り立つもの：「確定した文字はカーソルの位置に入り、前後の文字を変えない」など
  - 何手かをまたいで成り立つもの：「辞書登録を取り消すと、登録に入る前に戻る」など
- **探索**
  - 幅優先：同じ状態は 1 度しか広げないので、見つかる反例はいちばん短いキー列になります。
  - ランダムとファジング：深いところへ届かせるために使います。ファジングは新しい遷移に届いたキー列を伸ばしていきます。
  - 縮小：反例が見つかったら、ddmin で短く縮めます。
- 既知（`M.known`）：開いている issue の反例は `spec.lua` の `M.known` に理由と issue の番号を付けて書きます。こうしておくと、同じバグで探索が止まりません。
- 回帰（`regressions.lua`）：issue にした反例は全部 `regressions.lua` に残し、`--regress` で流し直します。結果は 3 通りです。
  - `✓`：直っている
  - `△`：既知で、まだ直していない
  - `✗`：直ったはずなのに戻った

ほかにも、次の検査があります。

- `core.lua`：入力エンジンだけを同じプロセスで動かす、速い検査です。変成テスト（`--metamorphic`）、insert と cmdline の比較（`--differential`）もここにあります。
- `dict.lua`、`jisyo.lua`：辞書の検査です。
- `tui.lua`：tmux の中の本物の端末で確かめます。`--record` で録画し、`--flicker` でちらつきを数えます。
- `upstream.lua`：同じキー列を Lua 版と denops 版に流して、並べて比べます。
- main の `make difftest`：upstream との差分テストです。

## 道具の置き場所

モデル検査の道具は main ではなく `poc/formal-ui` ブランチにあります。

- ブランチの中身：main の全部に、`tests/formal/`、`docs/FORMAL.md`、`Makefile` の `verify` を足したものです。
- main の取り込み：`tests/formal/ops/sync.sh` で行います。検査の道具は `poc/formal-ui` の側を残します。
- main への取り込み：検査の道具を main に入れることはしません。

作業するときは、`poc/formal-ui` の作業ツリーを作ります。

```sh
git fetch origin
git worktree add ../skkeleton.nvim-formal poc/formal-ui
cd ../skkeleton.nvim-formal
export MINI_PATH=<mini.nvim のディレクトリ>   # 無ければ make test が .tests/mini.nvim に clone する
```

`tui.lua` には tmux が要ります。`upstream.lua` と `make difftest` には、deno と denops.vim と upstream の skkeleton が要ります。

## 作業の手順

1. main を取り込む：`tests/formal/ops/sync.sh` を流します。このスクリプトがすることは次のとおりです。
   - main を取り込んで `make test` を流し、`poc/formal-ui` に push する。
   - 閉じた issue の既知の項目を、`spec.lua` から外す。
   - `core.lua` と `dict.lua` に残っている閉じた issue を知らせる。こちらは手で外す。
   - `--regress` を流す。

   このスクリプトはコミットと push をします。ほかの人と同じ作業ツリーを使っているときは、誰が流すかを決めておいてください。
2. 回帰を見る：`--regress` の `✗` はまず調べます。
3. プロファイルを回す：`tests/formal/ops/rotate.sh 3` を流します。いちばん長く調べていないプロファイルから 3 つ選んで、幅優先とファジングを流します。続けて、入力エンジンと辞書の速い検査も流します。
4. **反例を仕分ける**（下の「仕分け」）。
5. issue にする：新しいバグなら issue を立てます。閉じた issue の残りなら、その issue を開き直してコメントします。
   - `M.known` に項目を足し、`regressions.lua` に反例を足します。
   - 再現の GIF は `tests/formal/ops/attach.sh <番号> <tui.lua の引数>` で作り、`formal-recordings` に置いて issue に貼ります。
6. 直す：main の側で直して、回帰テストを足します（[AGENTS.md](../AGENTS.md)）。その場しのぎでしか直せなければ、#33 に書きます。
7. 確かめる：直したら 1 の `sync.sh` を流し、`--regress` で `✓` になるのを確かめます。

定常の作業を任せるときの細かい決まりは、`poc/formal-ui` の `tests/formal/ops/HANDOVER.md` にあります。

## 仕分け

反例が出たら、1 件ずつ次の順で見ます。

1. **再現するか**
   - コマンド：`make verify ARGS="--profile <p> [--config '<設定>'] --keys '<キー列>'"`
   - キーごとの観測と、破れた性質が出ます。再現しなければ、タイミングの揺れとして記録だけします。
2. **本物の端末でも起きるか**
   - コマンド：`nvim --headless -u NONE -i NONE -l tests/formal/tui.lua --profile <p> --keys '<キー列>'`
   - headless の子の観測（`screencol()` など）が正しくない場面があるので、端末で確かめます。
3. **upstream でも起きるか**
   - コマンド：`nvim --headless -u NONE -i NONE -l tests/formal/upstream.lua '<キー列>'`
   - 起きれば `upstream` ラベルを付けます。upstream と違う動きなら、どちらが正しいかを考えます。
4. **検査の誤りか、本物のバグか**
   - 性質の書き方が間違っていて、正しい動きを違反と判定していることがあります。そのときは `spec.lua` の性質を直し、直した理由をコメントに書きます。
   - 迷ったら upstream の動きに合わせます。
5. **既知か**
   - `M.known` と、開いている issue に、同じ型のものがあるかを見ます。

## 気を付けること

- 並列の数：コア数 − 2 までにします（`make verify` は既定でそうなります）。重い検査を同時に 2 つ流さないでください。長いものには `timeout` を付けます。
- 待ち方：ほかの検査が終わるのを待つときに、`pgrep -f 'tests/formal/check.lua'` は使いません。待つループのコマンドの文字列にも当たってしまいます。代わりに `ps -o args= -C nvim | grep -c 'tests/formal/check.lua'` を使います。
- `--config` の書き方：Lua の表の形で渡します（`'{ keepState = true }'`）。
- 子の nvim の分け方：子の nvim は使う人の環境から切り離してあります。たとえば辞書は一時ディレクトリに置き、クリップボードはいつも `PASTED` を返す偽物にし（`vim.g.clipboard = false` では Wayland のクリップボードを読んでしまう）、terminal のシェルの履歴は `/dev/null` に書きます。新しいプロファイルを足すときも、使う人のファイルや履歴やクリップボードに触らないようにしてください。検査の出力に手元の文字（`PASTED` 以外のクリップボードの中身など）が出てきたら、どこかで切り離しが抜けています。
- 検査の結果の使い方：性質は人が書いたものです。書いていない性質の破れは見つかりません。新しい種類のバグを直したら、その型を性質として足せるかを考えてください。
- キャッシュ：幅優先の結果は、プロファイル、深さ、設定、コードのハッシュを鍵にして `.tests/formal-cache/` に覚えます。コードが同じなら、もう一度は流しません。

## 開いてから閉じた issue（記録）

検査の観測だけで issue を立て、あとで本物の画面では再現しなかったことがあります。同じ失敗を繰り返さないために残します。

### #149 blink.cmp のメニュー位置（2026-11-03）

- ヘッドレスの子で `is_menu_visible()` が true、`nvim_win_get_position()` が `(1,1)` になったため、「変換のあとにメニューが行頭に出る」という issue を立てました。
- 同じキー列を `tui.lua`（tmux の本物の端末）で流すと、メニューは描かれませんでした。利用者の設定の nvim（blink.cmp + skkeleton.nvim）でも、メニューは pre-edit の近く（9 列目・36 列目）に出て、行頭ではありませんでした。
- ヘッドレスでは、blink の auto_show が開いたメニューのウィンドウが存在しても、画面には描かれていないことがあります。ウィンドウの位置だけを「画面に出ている」とみなしたのが誤りでした。
- 検査は、skkeleton の `refresh` が `blink.show` を呼んで開いたメニューだけを位置の対象にしました。auto_show の経路は、本物の端末で再現したときに別の性質として足します。

この失敗から、issue を立てる前に次を確かめます。

1. ヘッドレスの観測だけで issue にしない。まず `tui.lua` で同じキー列を流し、本物の画面を見る。
2. 浮動ウィンドウは、`is_menu_visible()` や `nvim_win_get_position()` だけで「画面に出ている」と判断しない。`tui.lua` の画面、できれば利用者の設定の nvim でも見る。
3. 利用者の設定（blink.cmp など）で変わる動きは、その設定でも試す。
4. 検査の誤りだったら、`spec.lua` の性質を直し、issue を閉じた理由と再現しなかった手順を #147 に書く。

検査の性質を直した例も残します。

- 辞書登録の間は、外側の pre-edit が見えているのが正しい（upstream も同じ）。`disabled:` の性質は登録中を除外し、登録中の表示は `register:` の性質で見る。
- 登録を開く `<Space>` は、打ちかけのローマ字をかなに直すことがある。`before_register` の文字列と厳密に比べるのは `feed` が空のときだけにする。
- 折り返さない長い行は、端末のスクロールで `<Esc>` の基準がずれる。カーソルの性質では、画面の性質と同じように長い行を外す。
- `<StealCursor>` や `<StealFloat>` のようにタイマーでカーソルやウィンドウを奪う操作は、画面の行の比較から外す（pre-edit の extmark があることだけを見る）。

### #152 keepState と #155 `<M-a>`（2026-11-03）

どちらも検査の誤りで、issue を閉じました。

- #152: `keepState` は「skkeleton の `<Esc>` のあと、同じバッファの次の `InsertEnter` で有効に戻す」ものです。`<Esc>` のあとの `.`（直前の入力の繰り返し）が一度目の insert でこれを使い切るため、そのあとの `<C-k>a:` は keepState の対象外です。`.` のあとの keepState を性質から外しました。
- #155: `<M-a>` は端末では `<Esc>` と `a` の 2 キーで、1 つの遷移の中で一時的に disable/enable します。`event: disable-post` は 1 キーの遷移を前提にしているので、`<M-...>` の別名は対象外にしました。利用者に見える不具合は確認できませんでした。

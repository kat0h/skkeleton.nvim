# skkeleton.nvim の開発の決まり

このリポジトリで作業する人とエージェント向けの決まりです。作業を始める前に読んでください。設計は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) に、モデル検査は [docs/MODEL_CHECKING.md](docs/MODEL_CHECKING.md) に書いてあります。

## 作業を始める前に

1. 設計の記録の issue #33 を読む。

   ```sh
   gh issue view 33 -R kat0h/skkeleton.nvim --comments
   ```

   打ち消し線で消してある項目は、別の issue になったものです。項目の後ろの番号の issue を見てください。
2. 開いている issue を見て、同じ話の issue が無いかを確かめる。

   ```sh
   gh issue list -R kat0h/skkeleton.nvim --state open
   ```

3. `git fetch origin` をして、`git log origin/main` で最近の変更を見る。

## 方針

- **upstream に合わせる。** 入力の仕組みは [skkeleton](https://github.com/vim-skk/skkeleton)（denops 版、以下 upstream）の移植です。動きに迷ったら upstream に合わせます。わざと変えたところは `tests/diff/known.lua` に理由と一緒に書きます。
- **互換のためのコードは書かない。** 今の利用者は作者だけです。設定や API を変えるときは、古い書き方を受け付ける処理、移し替え、警告を足さずに、古い道を消してください。
- **差分を小さくする。** 足すより消す方を選びます。使っていない機能は残しません。作者が使っていないものは、壊れても気づけないからです。nvim-cmp と組み込みの補完をやめたのもこの理由です（#69）。
- **インジケータは本体から切り離す。** 本体は公開した状態（`g:skkeleton#mode`、`g:skkeleton#enabled`、`g:skkeleton#state`）と `User` イベントだけを出します。インジケータはそれだけを読み、`skkeleton.render` などの本体の中を `require` しません。本体からインジケータを呼ぶのは `setup` だけにします（#63）。
- **決めることがあれば、自分で決めない。** 直し方が 2 つ以上あって、使う人から見た動きが変わるときは、issue に選択肢を書いて作者に聞いてください。

## その場しのぎでしか直せないとき

バグを直すときに、根本から直すには設計を大きく変える必要があり、今はその場しのぎでしか直せないことがあります。読みにくくなったコードを、すぐには直せないこともあります。そのときは、直したうえで **issue #33 にコメントで書き残してください。** 書くのは次のことです。

- どこを、どうその場しのぎで直したか（ファイルと行、コミット）
- なぜ根本から直せなかったか
- 同じ形の原因から出た issue の番号
- 根本から直すならどうするかの案

同じ形の原因が #33 にもう書いてあれば、新しく書かずに、その項目に issue の番号を書き足します。#33 の項目を別の issue にしたら、#33 のその項目を打ち消し線で消して、その issue の番号を付けます。

## issue

- issue は kat0h/skkeleton.nvim にだけ立てます。upstream（vim-skk/skkeleton など）には立てません。
- 題は、何が起きるかがわかる日本語の文にします。
- バグの本文には起きること、再現の手順とコマンド、原因の見当（ファイルと行）、直し方の案を書きます。モデル検査で見つけたものは、検査を再生するコマンドも書きます（[docs/MODEL_CHECKING.md](docs/MODEL_CHECKING.md)）。
- 同じことが upstream でも起きると確かめられたときだけ、`upstream` ラベルを付けます。確かめていなければ、本文にそう書きます。
- ラベル：バグは `bug`、改良は `enhancement`、作者に決めてほしいことは `question`。

## GitHub（gh コマンド）

`gh` コマンドが使えます。認証は済んでいて、`git push` も `gh` の認証（HTTPS）で通ります。リポジトリは `-R kat0h/skkeleton.nvim` で指定します。

```sh
gh issue view 33 -R kat0h/skkeleton.nvim --comments     # issue を読む
gh issue list -R kat0h/skkeleton.nvim --state open       # 開いている issue
gh issue create -R kat0h/skkeleton.nvim -t "題" -F body.md -l bug   # issue を立てる
gh issue comment 12 -R kat0h/skkeleton.nvim -F comment.md            # コメントする
gh issue reopen 12 -R kat0h/skkeleton.nvim                           # 開き直す
gh pr create -R kat0h/skkeleton.nvim -B main -H <ブランチ> -t "題" -F body.md
gh pr view 76 -R kat0h/skkeleton.nvim                    # PR を読む（gh pr diff で差分）
gh pr checks 76 -R kat0h/skkeleton.nvim --watch          # CI を待つ
gh run view <run の番号> -R kat0h/skkeleton.nvim --log-failed   # 落ちた CI のログ
```

- 本文は、文字列で渡さずにファイルに書いて `-F` で渡します。引用符や改行が崩れないようにするためです。
- 本文に `@名前` を書くと、その人に通知が届きます。人を呼ぶとき以外は、`@` を書かないか、バッククォートで囲みます。
- 書き込む（issue、コメント、PR、ラベル）のは kat0h/skkeleton.nvim だけです。upstream（vim-skk/skkeleton など）には書き込みません。
- PR のマージは作者が行います（「git」の節）。

## コード

- Neovim 専用で、純粋な Lua です。FFI や外部コマンドには頼りません。
- upstream から移したファイルは、先頭に移植元と著作権とライセンスを書きます（`LICENSES/README.md` の形）。ほかの zlib のプロジェクト（skkelua.nvim など）のコードを写すときも同じです。考え方を借りるだけなら要りません。
- SKK-JISYO などの辞書（GPL）や npm のパッケージのコードは、リポジトリに入れません。
- コードのコメントは日本語で、処理の意図を短く書きます。
- 整形は stylua です（`make fmt`、`make lint`）。

## テスト

- 直したら `make test` と `make lint` を通します。CI は Neovim の stable と nightly で `make test` を流します。
- バグを直したら、そのバグの回帰テストを `tests/` に足します。足したテストは直す前のコードでは落ち、直したあとのコードでは通ることを確かめてください。
- 動きを変えない作り直しで、既存のテストの期待値を変えないと通らないときは、動きが変わっているということです。そこで止めて、何がどう変わるかを issue に書いてください。
- テストは `tests/test_<領域>.lua` に置きます。config やかなテーブルのようなモジュールの状態を変えるテストは、`require("helpers").child_set()` で子の nvim を使い、ケースごとに分けます。辞書のテストデータは `tests/testdata/` にあります。
- テストと検査では、一時ディレクトリの辞書だけを使います。`~/.skkeleton`、`~/.cache/skk.db` など、使う人の辞書やデータには触りません。シェルを起動するテストは `HISTFILE=/dev/null` にし、使う人のシェルの履歴に書かないようにします。
- upstream との差分テストは `make difftest` です（deno と denops.vim が要ります）。違いが出たら、Lua 版の不具合か、わざと変えたところかを分け、わざとなら `tests/diff/known.lua` に書きます。
- Neovim nightly だけで動きが違うことがあります。そのときは Neovim の変更を探して、テストを機能があるかどうかで分けます。たとえば nightly では `input()` の中から cmdline window を開けなくなりました（`tests/test_e2e_dictionary.lua` の #54 のテスト）。

## git

- コミットのメッセージは英語の Conventional Commits（`fix(input): ...`、`refactor(render): ...`、`test: ...`、`docs: ...`）で書きます。issue を閉じるなら本文に `Closes #番号`、関係するだけなら `Refs #番号` を書きます。
- push は HTTPS で行います。force push はしません。
- バグを直したら、テストを通したうえで main に直接 push してかまいません。大きな作り直しや、決めることを含む変更は PR にします。PR のマージは作者が行います。マージ済みのブランチは消します。

## 同時に作業するとき

複数の人やエージェントが、同じリポジトリで同時に作業しています。ぶつからないように、次のことを守ってください。

- **自分の作業ツリーで作業する。** 作業を始めるときに、`git worktree add` で自分の作業ツリーを作ります。置き場所はリポジトリの中の `.claude/worktrees/<作業者>-<内容>`（たとえば `.claude/worktrees/opencode-fix74`）にします。

  ```sh
  git fetch origin
  git worktree add -b fix/terminal-normal .claude/worktrees/opencode-fix74 origin/main
  ```

  ブランチの名前は `<種類>/<内容>`（「ブランチ」の節）にします。同じブランチを 2 つの作業ツリーでチェックアウトすることはできないので、ブランチも人ごとに分けます。
- **リポジトリの最上位（main の作業ツリー）では作業しない。** そこは `git pull` で最新にしておくだけの場所にします。ファイルを変えたり、ブランチを切り替えたりしないでください。
- **ほかの人の作業ツリーに触らない。** ファイルを変える、checkout する、コミットする、のどれもしません。
- **`git stash` を使わない。** stash の置き場所はすべての作業ツリーで共有なので、ほかの人の stash を取り出してしまいます。作業を一時的によけたいときは、作業用のコミットを作ります。
- **push の前に main を取り込む。** main に push する前に `git pull --rebase origin main` をして、テストを流し直します。自分が書いていない変更がコミットに混ざっていないかを、`git status` と `git diff --cached` で確かめます。
- **重い処理は全員で同時に 1 つまで。** 並列の上限（コア数 − 2）は 1 人ぶんの上限です。`make verify` や `make difftest` を流す前に、`ps -o args= -C nvim | grep -c -E 'tests/(formal|diff)'` が 0 であることを確かめます（「重い処理」の節）。
- **終わったら片付ける。** `git worktree remove .claude/worktrees/<名前>` で作業ツリーを消し、マージ済みのブランチを消します。
- `.tests/`（mini.nvim、テストのキャッシュ、検査の結果）は作業ツリーごとにできるので、ほかの人の結果は混ざりません。テストの辞書や tmux のセッションも、一時ディレクトリや PID で分かれています。

## ブランチ

- `main`：プラグインの本体とテスト。
- `poc/formal-ui`：モデル検査の道具（`tests/formal/`、`docs/FORMAL.md`）。main は取り込みますが、main には戻しません（[docs/MODEL_CHECKING.md](docs/MODEL_CHECKING.md)）。
- `formal-recordings`：issue に貼る再現の GIF の置き場です。main とは履歴がつながっていません。消さないでください。
- `feat/*`、`fix/*`、`test/*`、`docs/*`、`chore/*`：PR のための作業ブランチ。

## 書く日本語

README、ヘルプ、issue、PR、コメントの日本語は、読む人に要ることだけを飾らずに書きます。「〜を行う」「〜を実現する」のような硬い言い方や、宣伝のような書き方はしません。upstream（skkeleton、denops）を下げる比べ方（「Deno が要らない」など）は書きません。リポジトリに入れる文章には、手元のパスや環境の細かいこと（ユーザー名、ホームディレクトリなど）を書きません。

## 重い処理

モデル検査や差分テストのような重い処理は、並列をコア数 − 2 までにします（`make verify` は既定でそうなります）。重いものは、ほかの人の分も含めて同時に 1 つまでにします。長く動くものには `timeout` を付けます。

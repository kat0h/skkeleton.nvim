# モデル検査の定常作業の引き継ぎ

skkeleton.nvim（Neovim の SKK、純 Lua）のモデル検査を、決まった手順で流して結果を報告してもらうための書類です。検査の道具の説明は `docs/FORMAL.md` にあります。

## 役割の分け方（いちばん大事）

検査の道具（`poc/formal-ui`）は **手元だけ** で扱います。`poc/formal-ui` からブランチが分かれないようにするためです。一方、プラグインのバグの直しは、main に push してかまいません。

### 検査（この worktree、`poc/formal-ui`）
- してよいこと
  - この worktree で検査を流す
  - 結果と、検査の直し方の案を `.tests/formal-ops/`（git に入らない）にファイルで書く
- しないこと
  - この worktree での `git commit`、`git push`、`git merge`、`git checkout`、`git stash`
  - この worktree の追跡されているファイル（`tests/formal/`、`docs/FORMAL.md`、`Makefile` など）を書き換えること。`spec.lua` などの直しは、diff のファイルにして出すだけにする
  - `tests/formal/ops/sync.sh` と `tests/formal/ops/attach.sh` を動かすこと（どちらも `poc/formal-ui` にコミットして push する。こちらで動かす）

### バグの直し（main に push してよい）
検査で見つけたバグ（区分が「新しいバグ」か「閉じた issue の残り」のもの）は、自分で直して main に push してかまいません。

- **作業場所**：main のツリー（`/home/kat0h/ghq/github.com/kat0h/skkeleton.nvim`）は agy が使っているので、触らない。直すための worktree を 1 つ作り、そこで作業する。
  ```sh
  git -C /home/kat0h/ghq/github.com/kat0h/skkeleton.nvim fetch origin
  git -C /home/kat0h/ghq/github.com/kat0h/skkeleton.nvim worktree add --detach /home/kat0h/ghq/github.com/kat0h/skkeleton.nvim/.claude/worktrees/opencode-fix origin/main
  ```
  2 回目からは、その worktree で `git fetch origin && git switch --detach origin/main` をしてから始める。
- **直すもの**：`lua/`、`plugin/`、`tests/`（`tests/formal/` を除く）、`doc/`。直したら、そのバグの回帰テストを `tests/` に足す。
- **確かめること**：直した worktree で `make test` と `make lint` を通す。整形には `/home/kat0h/ghq/github.com/kat0h/skkeleton.nvim/.tests/bin/stylua` を使う。足した回帰テストが、直す前の版では落ちて、直したあとでは通ることも確かめる。検査の worktree の `lua/` は古いままなので、モデル検査での確かめ直し（`--regress`）は、push のあとに引き継ぎ元が `sync.sh` で取り込んでから行う。
- **コミット**：メッセージは英語の conventional commits（`fix(...): ...`）にする。issue があれば本文に `Closes #番号`（閉じた issue の残りなら `Refs #番号`）を書く。issue が無い新しいバグなら、`.tests/formal-ops/issues/` の下書きのファイル名を本文に書く。
- **push**：`git push origin HEAD:main`（HTTPS）。先に agy の push があって通らなければ、`git pull --rebase origin main` をして、テストを流し直してから push する。force push はしない。
- **直さずに止めるもの**：直すのに「どちらにするか」を決める必要があるもの、使う人から見た動きが変わるもの、`lua/` を大きく作り直すもの。これは issue の下書きに選択肢を書くだけにする。
- **互換**：互換のためのコードや警告は足さない。差分は小さくする。

### GitHub
- issue を立てること、コメント、ラベル、PR はしない。issue は下書きをファイルで出す。コミットの `Closes` で issue が閉じるのはかまわない。

取り込み、`poc/formal-ui` へのコミット、issue を立てることは、引き継ぎ元（Claude Code）が報告を読んでから行います。

## 決まり

- **触らないもの**：`~/.skkeleton`、`~/.cache/skk.db`、`~/.bash_history` には触らない。検査は一時ディレクトリの辞書だけを使う。
- **CPU**：並列はコア数 − 2 までにする（`make verify` は既定でそうなる）。重い検査を同時に 2 つ流さない。
- **時間切れ**：長く動くものには `timeout` を付ける。ops のスクリプトには付けてある。
- **ほかの検査の確かめ方**：動いているかを見るときは `pgrep -f` を使わない。待ちのループ自身の文字列に当たってしまう。代わりに `ps -o args= -C nvim | grep -c 'tests/formal/check.lua'` を使う。
- **`--config` の書き方**：Lua の表の形（`'{keepState=true}'`）で渡す。JSON の形では通らない。
- **書く日本語**：利用者に要ることだけを飾らずに書く。upstream（denops 版 skkeleton）を下げる比べ方は書かない。
- **重点**：入力エンジン、変換、辞書、辞書登録、cmdline と terminal の pre-edit、補完。インジケータの不具合は追わない（利用者の判断）。

## 毎回の手順

作業はすべてこの worktree で行います。

```sh
cd /home/kat0h/ghq/github.com/kat0h/skkeleton.nvim/.claude/worktrees/formal-ui
```

1. **今の版を確かめる**
   - `git log --oneline -1` と `git status --short` を記録する。
   - 未コミットの変更が `.tests/` 以外にあったら、そこで止めて報告する。
2. **回帰の見張り**
   - コマンド：`timeout 900 nvim --headless -u NONE -i NONE -l tests/formal/check.lua --regress`
   - これまでの反例（`tests/formal/regressions.lua`）を全部流し直す。
   - `✗` は、直したはずのバグが戻ったか、まだ直っていない（issue が開いている）かのどちらか。
3. **プロファイルを回す**
   - コマンド：`tests/formal/ops/rotate.sh 3`
   - いちばん長く調べていないプロファイルから 3 つ選び、幅優先（深さ 4）とファジングを流す。
   - 続けて、入力エンジン（`core.lua`）、辞書（`dict.lua`）、SKK-JISYO（`jisyo.lua`）の速い検査を流す。
   - 結果は `.tests/formal-ops/runs.log` に溜まる。
4. **反例を仕分ける**（`✗` や `△` が出たら、1 件ずつ下の「仕分け」をする）
5. **報告を書く**（下の「報告」の形で）

## nightly で流す（週に 1 回）

- `tests/formal/ops/nightly.sh` を流します。nightly の nvim を `$W/.tests/nvim-nightly` にダウンロードし、全プロファイルを深さ 2 で短く流したあと、`core.lua`・`dict.lua`・`jisyo.lua` の速い検査も流します。`~/.local` などには入れません。
- `NVIM_DIR=/path/to/nvim-dir` を指定すると、その `bin/nvim` を使います（stable で流し方を試すとき）。
- `NVIM=/path/to/nvim` は `run.sh`・`make verify`・`rotate.sh`・`attach.sh` の nvim を切り替えます。`Makefile` の `NVIM` も同じです。
- stable では出ずに nightly だけで出た違反は、Neovim の変更を探して issue に書きます（AGENTS.md の「テスト」の節）。

## 開いてから閉じた issue（記録）

- **#149（blink.cmp のメニュー位置）**: ヘッドレスの子で `is_menu_visible()` が true、`nvim_win_get_position()` が `(1,1)` だったため issue を立てましたが、`tui.lua` の本物の端末と利用者の設定の nvim では、メニューは pre-edit の近くに出て行頭ではありませんでした。ヘッドレスではウィンドウがあっても描かれていないことがあります。
- 浮動ウィンドウの位置の違反は、ヘッドレスの観測だけで issue にしないでください。`tui.lua` の画面（できれば利用者の設定の nvim）で確かめてから issue にします。詳しくは main の `docs/MODEL_CHECKING.md` の「開いてから閉じた issue」に書きました。

## 仕分け

1. **再現するか**
   - 再生のコマンド：`make verify ARGS="--profile <p> [--config '<設定>'] --keys '<キー列>'"`
   - 再現しなければ、タイミングの件として記録だけする。
2. **本物の端末で確かめる**：`timeout 300 nvim --headless -u NONE -i NONE -l tests/formal/tui.lua --profile <p> --keys '<キー列>'`（tmux が要る）
3. **既知のものかを見る**
   - `tests/formal/spec.lua` の `M.known`、`core.lua` と `dict.lua` の既知の絞り込みに、同じ issue があるかを見る。
   - その issue の状態は `gh issue view <番号> -R kat0h/skkeleton.nvim` で見る（読むだけ）。
4. **検査の誤りか、本物のバグか**
   - 迷ったら upstream と比べる。upstream のコードは `~/.local/share/nvim/lazy/skkeleton/` にある。
   - 動きを見比べるには `timeout 300 nvim --headless -u NONE -i NONE -l tests/formal/upstream.lua '<キー列>'` を使う（deno と denops.vim が要る）。
   - upstream で同じことが起きたかも書く。
5. **結果を書き分ける**
   - 検査の誤り：`spec.lua` の直し方を diff にして `.tests/formal-ops/patches/` に置く。理由もコメントに書く。
   - 閉じた issue の残り：その番号と、開き直す理由を書く。
   - 新しいバグ：issue の下書きを `.tests/formal-ops/issues/` に置く（形は下）。

## 今の重点（2026-11-02）

agy（直す係）が、使う人から見た動きを変えない約束で、次の作り直しを main に入れました。

- #61：pre-edit のずれを見つける処理を 1 か所にまとめた（1cadb8e）
- #66：`on_bytes` でバッファの書き換えを受ける（9dbc735）
- #62：モードの移り変わりの後片付けを、`ModeChanged` 1 か所と表にまとめた（34d4647）
- #58・#64：補完の候補作りと判定をまとめた（d721076）

**作り直しの前に通っていた性質や反例が、作り直しのあとで落ちたら、それは作り直しで入ったバグの見込みが高い**です。その場合は、どのコミットで落ち始めたかを `git log` の版で書いてください。特に見てほしいのは次のプロファイルです。

- `cmdline`、`terminal`、`register`、`regcmd`、`modes`、`misc`：#61、#62 に関係する
- `blink`：#58・#64 に関係する（nvim-cmp と組み込み補完はやめた。#69）
- `undo`、`macro`：#66 に関係する

### 最初に仕分けてほしいもの（c88679c の `--regress` で出たもの）

1. **#12（mouse）**：`#mid <Esc> : <C-j> Kan <RightClickMid>`
   - cmdline で ▽ を打ちかけのまま中クリックで貼ると、`▽別かn` のように ▽ が cmdline に残る。
   - #12 は閉じている。#12 の残りか、#61 の作り直しで戻ったのかを見分けてほしい。
   - 見分け方：#61 の前の版（1cadb8e の 1 つ前）の `lua/` で流す。その版は `git show <版>:lua/...` で読むだけにし、ツリーは書き換えない。どうしても動かして比べるときは、`git archive <版> | tar -x -C .tests/formal-ops/old` で別の場所に展開して比べる。
2. **#54（register）**：`#mid <C-j> A <Space> <C-f>`
   - 辞書登録の欄で `<C-f>` を押すと、`g:skkeleton#state` の henkanFeed が `あ` のまま残り、状態とずれる。
   - #54 は閉じている。#54 の残りとして、開き直しの理由を書いてほしい。
3. **閉じた issue の既知の絞り込みが残っている**：
   - 残っている場所：`core.lua` の #42 #43 #49、`dict.lua` の #37 #49 #50 #53。
   - 外す diff を `patches/` に置く。外したあとに `--regress` か、それぞれの検査を流し、通るか（✓）を書く。✗ なら開き直しの理由を書く。

中クリックの貼り付けは、子の nvim のクリップボードを、いつも `PASTED` を返す偽物に替えてあります（`vim.g.clipboard = false` では Wayland のクリップボードを読んでしまった）。検査の結果に `PASTED` 以外の手元の文字が出てきたら、流すのを止めて報告してください。

ひとつ気になっていることがあります。e91f913 で、「cmdline window の中では normal でも enabled」を違反として扱わないように緩めました。#54 が直ったので、緩める前の性質に戻して通るかを試し、結果を報告してください。試すときは手元で書き換えて流し、終わったら `git checkout -- tests/formal/spec.lua` で元に戻してください。戻せる差分は diff にして `patches/` に置いてください。

## 報告

`.tests/formal-ops/report-YYYYMMDD-HHMM.md` に、次の順で書きます。

1. **版**：`poc/formal-ui` の HEAD と、取り込まれている main の版
2. **流したもの**：コマンド、何件・何状態見たか、かかった時間
3. **結果の一覧**：見つけたものごとに 1 行。区分（新しいバグ / 閉じた issue の残り / 既知 / 検査の誤り / タイミング）、プロファイル、キー列、関係しそうな issue
4. **置いたファイル**：`issues/` と `patches/` に置いたもの
5. **push した直し**：main のコミット（版と題）と、直した反例

## issue の下書きの形

ファイル名は `.tests/formal-ops/issues/<短い名前>.md` です。1 行目に題を書き、題は中身のある日本語の文にします。そのあとに次の節を書きます。

- **起きること**：手順と、見えるもの
- **再現**：`make verify ARGS=...` と `tests/formal/tui.lua ...` のコマンド
- **原因の見当**：ファイルと行
- **直し方の案**
- **upstream**：同じことが起きたか。確かめていなければ、そう書く

## 道具の早見

| やること | コマンド |
|---|---|
| プロファイルの一覧 | `nvim --headless -u NONE -i NONE -l tests/formal/check.lua --list-profiles` |
| 1 つを幅優先で | `tests/formal/ops/run.sh <label> --profile <p> --depth 4` |
| 1 つをファジングで | `tests/formal/ops/run.sh <label> --profile <p> --fuzz 200 --seed-depth 0 --length 25 --seed <数>` |
| 入力エンジンだけ（速い） | `nvim --headless -u NONE -i NONE -l tests/formal/core.lua --random 50000 --length 30 --seed <数>` |
| 変成テスト・差分 | `docs/FORMAL.md` の「使い方」 |

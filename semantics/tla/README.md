# Neovim との結合の層の TLA+（#264）

Neovim と skkeleton の結合の層を TLA+ で書いたものです。親の issue は #264 です。いまあるのは第 1 段で、P5（1 つのキーを二重に処理しない）だけを確かめます。

**TLC はまだ流していません。** 仕様は構文の検査（SANY）も通していません。下の「結果」は見込みです。

| ファイル | 中身 |
|---|---|
| `Nvim.tla` | Neovim のキーの読み方の抽象。入力の待ち行列、typebuf、feedkeys の旗、モード、続きのキーの待ち、記録に入るキー、類 |
| `Skkeleton.tla` | skkeleton の handler の抽象。マッピングの handler、guard、render の feed と finish、`ModeChanged` の反応、P5 |
| `P5_main.cfg` | いまの main の動き。P5 が通る見込み |
| `P5_before214.cfg` | #214 を直す前の動き。cmdline で反例が出る見込み |
| `P5_before36.cfg` | #36 を直す前の動き。insert で反例が出る見込み |

## 1. 第 1 段の範囲

入れたもの：

- 先行入力（入力の待ち行列と typebuf）
- `nvim_feedkeys` の旗 `n`、`i`、`t`
- `vim.on_key`（guard）
- `<Cmd>` のマッピングの形で流す `finish()`
- `ModeChanged`（モードが変わったら skkeleton が状態を捨てる、というところまで）
- モードは insert、cmdline、normal

入れていないもの（第 2 段、第 3 段）：

- `SafeState`、`vim.schedule`、`InsertLeave`
- マクロの再生（`@`、`.`）と、guard の中の再生中の分かれ道
- 辞書登録の `input()`
- terminal

## 2. #264 の前提から変えたところ

1. **記録に入るキーの列（`recording`、`rec`）を第 1 段に入れました。** #264 は、第 1 段の目標を「#36 を直す前の動きで反例が出ること」とし、マクロの記録と再生を第 2 段に置いています。しかし #36 は、流した確定文字列が記録に入って、再生で二重になる不具合です。記録を入れないと反例が出ません。そこで、Neovim が打鍵として扱ったキーの列だけを先に入れました。`q` と `@` のキー、再生の動きは入れていません。記録中かどうかは、始めに決めて変えません。
2. **P5 を 2 つの条件の組にしました。** 「handler が 2 回走らない」だけでは、第 1 段の範囲で #36 を捕まえられません。「skkeleton が流したキーが記録に入らない」を合わせました（§5）。第 2 段で再生を入れたら、後ろの条件は「再生のあとも handler と結果が 1 回ずつ」に書き直せます。
3. **先行入力を 2 本にしました。** 打ったがまだ読まれていないキーには、入力の待ち行列にあるものと、typebuf に取り込まれたものがあります。`feedkeys` が末尾に足すのは typebuf です。まとめて取り込まれたかどうかで、guard が流し直したキーと、あとから打ったキーの順番が変わります（§9 の見込み 1）。1 本にすると、この違いが出ません。
4. **cmdline の類を、insert の類から借りました。** METHOD.md の表は insert だけです。`feedkeys` の `t` が残るのは cmdline なので、cmdline を外すと `"nit"` を確かめる意味がなくなります。同じ軸の値で 6 つだけ置きました（仮定 K2）。
5. **設定を 3 つにしました。** 定数 `Variant` で、#36 の前、#214 の前、いまの main を切り替えます。直す前の動きで反例が出て、いまの動きで通ることを、同じ仕様で比べるためです。

## 3. 状態の変数

| 変数 | モジュール | 意味 |
|---|---|---|
| `inq` | Nvim | 入力の待ち行列。打ったが、まだ typebuf に取り込まれていないキー |
| `ta` | Nvim | typebuf。次に読まれるキーが先頭 |
| `mode` | Nvim | Vim のモード（`i` / `c` / `n`）。軸 M |
| `wait` | Nvim | 続きのキーを待っているか。軸 W |
| `recording` | Nvim | マクロを記録しているか |
| `rec` | Nvim | 記録に入ったキーの列 |
| `nextId` | Nvim | 次に打つキーの番号 |
| `pre` | Skkeleton | 読み（pre-edit）を抱えているか |
| `pend` | Skkeleton | render の pending。`finish` を待っているか |
| `stale` | Skkeleton | pre-edit の置き場所が、Neovim の変化でずれたか。軸 P |
| `handled` | Skkeleton | 打ったキーごとの、handler が走った回数 |

`inq`、`ta`、`rec` に入る項目は、`kind`（キー / 確定文字列 / `finish`）、`key`、`id`（もとになった打ったキーの番号）、`src`（利用者 / skkeleton）、`typed`（`t` の旗）、`remap`（`n` の旗の逆）を持ちます。`id` と `src` は検査のための印で、実装にはありません。

## 4. イベント（類）

利用者が打つキーは 6 つです。METHOD.md の類 × 経路の升から、第 1 段に関わるものの代表を選びました。類は `Nvim.tla` に、軸 M（前の文脈 → 後の文脈、`InsertLeave` が出るか）、P、W の値の組で書いてあります。

| キー | 経路 | insert での類（METHOD §6 の番号） | cmdline での類 | 選んだ理由 |
|---|---|---|---|---|
| `a` | map | 1 文字を足す（`i`→`i`、足す、なし） | 文字を足す | handler が確定文字列を `feedkeys` で流す道 |
| `CR` | map | 2 改行する（`i`→`i`、改行、なし） | 実行して抜ける（`c`→`n`） | handler がキーを流す道。cmdline では `finish` をその場で走らせる |
| `Esc` | map | 13 normal に抜ける（`i`→`n`、`InsertLeave` あり） | 捨てて抜ける（`c`→`n`） | 流した `<Esc>` で `ModeChanged` が出る |
| `Left` | guard 確定 | 7 カーソルを動かす（`i`→`i`、カーソル、なし） | カーソルを動かす | `vim.on_key` が確定して流し直す道 |
| `C-v` | guard 通す | 6 続きのキーを待つ（`i`→`i+待ち`、なし、続きを待つ） | 続きのキーを待つ | 次のキーがマッピングを通らない |
| `C-c` | guard 通す | 14 normal に抜ける（`i`→`n`、`InsertLeave` なし） | 捨てて抜ける | skkeleton を通らずに `ModeChanged` が出る |

続きを待つ文脈（`i+待ち`、`c+待ち`）では、どのキーも「21 引数を受けて足す」として扱います。normal は第 2 の環なので、どのキーも何もしません。

skkeleton が流す項目は 3 種類です。確定文字列（1 つの項目にまとめる）、キー（`<CR>`、`<Esc>`、guard が流し直したキー）、`finish`（`<Cmd>lua require('skkeleton.render').finish()<CR>`）です。

## 5. P5 の書き方

```tla
P5 ==
  \A i \in Ids :
    /\ handled[i] <= 1
    /\ \A j \in DOMAIN rec : ~(rec[j].id = i /\ rec[j].src = "skk")
```

打ったキー `i` について、skkeleton の handler（マッピングの handler か、guard の確定）が走るのは 1 回までで、`i` から skkeleton が流したキーは記録に入らない、という意味です。後ろの条件が破れると、再生のときに、打ったキーがもう一度 handler を通るうえに、流した文字列もそのまま入ります（#36）。

## 6. 抽象化の決めごと

- 1 つの action は「typebuf の先頭を 1 つ読んで、処理し終わるまで」です。handler の途中には割り込みません。
- core は 1 つの操作です。`a` を handler が受けたときの結果は、「読みを持つ（何も流さない）」か「確定して流す」かを、非決定に選びます。入力相（▽ / ▼）は分けません。
- `Variant` は `render.lua` の `feed` の旗だけを変えます。
  - `before36`：いつも `nit`
  - `before214`：insert は `ni`、cmdline は `nit`
  - `main`：insert は `ni`、cmdline は `nit`、ただし記録中は `t` を外す
- `stale` は、利用者のキーを Neovim がそのまま処理して、P が「なし」でなかったときに立ちます。次の handler が読みを捨てます（`reset_if_stale`）。置き場所の中身は持ちません。
- normal に移ると、skkeleton は読みを捨てます。normal からは戻りません。

## 7. 仮定

Neovim の動きは、ソースを読まずに仮定として書きました。確かめるテストは、どれも `tests/helpers.lua` の E2E のキー入力ドライバを使い、一時ディレクトリの辞書で動かします。外れた仮定は、仕様を直します。

### Neovim の動き

| # | 仮定 | 使っているところ | どのテストで確かめるか |
|---|---|---|---|
| N1 | typebuf が空のときだけ、入力の待ち行列から取り込む。1 個以上をまとめて取り込むことがある | `Pull` | `nvim_input("ab")` を 1 回で送る場合と、`a` の処理が終わってから `b` を送る場合で、`a` の handler の中の `getchar(1)`（先読み）が `b` を返すかどうかを見る |
| N2 | `feedkeys` の `i` は typebuf の先頭に入れ、`i` が無ければ末尾に入れる | `ConsumeMapped`、`ConsumeGuard` | typebuf に `xy` がある状態で、マッピングの中から `feedkeys("1", "ni")` と `feedkeys("2", "n")` を呼び、バッファが `1xy2` になることを見る |
| N3 | `feedkeys` の `n` のキーは、マッピングを通らない | 項目の `remap` | `a` にマッピングを置き、`feedkeys("a", "n")` でマッピングが呼ばれないことを見る |
| N4 | `t` を付けたキーは、記録中ならレジスタに入り、`vim.on_key` の `typed` が空でない。`t` が無ければ、どちらも起きない | `RecAfter`、`GuardCommits` | `qa` のあと `feedkeys("x", "nt")` と `feedkeys("y", "n")` を呼び、レジスタ `a` と、`on_key` が受けた `typed` を見る |
| N5 | `<Cmd>…<CR>` は、typebuf の中でほかのキーに割り込まれず、読まれたときに実行され、モードを変えない | `ConsumeFinish` | `feedkeys("ab<Cmd>let g:x = mode()<CR>c", "ni")` を流し、`g:x` が `i` で、バッファが `abc` になることを見る |
| N6 | `vim.on_key` は、読んだキーごとに 1 回、マッピングを当てたあとで呼ばれる。Lua の callback のマッピングが奪ったキーは擬似キーで届く | `IsMapped` と `GuardCommits` が同時に成り立たないこと | `tests/test_guard.lua` に、`a`（マッピングあり）と `<Left>`（なし）を打って `on_key` の引数を記録するケースを足す |
| N7 | `vim.on_key` が `""` を返すと、そのキーは Neovim に処理されない。記録中なら、レジスタには入る | `ConsumeGuard` | `on_key` で `<Left>` を捨て、カーソルが動かないことと、`qa` の記録に `<Left>` が入ることを見る |
| N8 | 続きを待っている間のキーは、マッピングを通らないが、`vim.on_key` には届く（METHOD.md の A2） | `IsMapped`、`GuardCommits` | `a` にマッピングを置いて `<C-v>a`、`<C-r>a`、`<C-k>a:` を打ち、マッピングが呼ばれず、`on_key` には届くことを見る |
| N9 | `ModeChanged` は、モードを変えたキーの処理の中で出る。次のキーを読むより前である | `ConsumePlain` | `ModeChanged` の autocmd と `on_key` の両方で通し番号を記録し、`<Esc>x` を 1 回で送って順番を見る |
| N10 | レジスタに入るのは、読まれた時点で打鍵として扱われたキーである。入るのは読まれたときである | `RecAfter` | N4 のテストで、`feedkeys` を呼んだ直後（読まれる前）に記録を止めたときのレジスタを見る |
| N11 | 続きを待っているときに typebuf の先頭が `<Cmd>…<CR>` だと、引数として食われて実行されない | `ConsumeFinish` の `wait` の枝 | `feedkeys("<C-v><Cmd>let g:x = 1<CR>", "ni")` のあと、`g:x` があるかを見る |
| N12 | マッピングの callback や `vim.on_key` の中から呼んだ `feedkeys` のキーは、いま処理しているキーのあとに読まれる | action を割らないこと | N2 のテストと同じ。`on_key` の中から呼ぶ場合も足す |

### skkeleton の動きの抽象

| # | 仮定 | どのテストで確かめるか |
|---|---|---|
| S1 | 経路は、`a`、`<CR>`、`<Esc>` が map、`<Left>` が guard 確定、`<C-v>` と `<C-c>` が guard 通す | skkeleton を有効にして `maparg()` を見る。`guard._is_physical_special` に各キーのバイト列を渡す（`tests/test_guard.lua`） |
| S2 | 文字キーを handler が受けた結果は、「何も流さない」か「確定文字列と `finish` を流す」のどちらかである | `tests/test_e2e_guard.lua` と同じ形で、`k`、`a`、`Ka`、`Kan<Space>a` を打ち、`on_key` に届いた流したキーの列を見る |
| S3 | 確定文字列は、何文字でも 1 つの項目として扱ってよい。文字の途中に、ほかのキーは入らない | N2、N12 が成り立てば足りる |
| S4 | モードが変わったときの反応は、その場で読みを捨てるだけで、キーを流さない | 第 2 段で `SafeState` の道を書くときに、`cleanup.lua` を読んで直す。それまでは、この抽象で P5 の反例が出たら E2E で確かめる |
| S5 | normal に抜けたあとのキーは、skkeleton に関わらない | 第 2 の環（METHOD.md §0 の 5）を作るときに外す |
| S6 | terminal を入れなくても、第 1 段の P5 の結果は変わらない | terminal は `t` をいつも付け、guard が自分の流した制御文字を見分ける（`guard.lua` の `own_output`）。第 2 段のあとで、モードに `t` を足して確かめる |

### 類

| # | 仮定 | どう確かめるか |
|---|---|---|
| K1 | METHOD.md §6 の類は、`index.txt` の説明から作った案で、キーを流して確かめていない。ここで使った 7 つの類（1、2、6、7、13、14、21）の M、P、W の値が合っている | #268 の「進め方」の 2 の道具で署名を測り、`Nvim.tla` の類の定義と比べる |
| K2 | cmdline の類は METHOD.md に表が無く、insert の類と同じ軸の値を借りた | METHOD.md §7 のとおりに cmdline の類を作り、`Nvim.tla` の `C_` の定義を置き換える |
| K3 | 続きを待つ文脈では、どのキーも「引数を受けて足す」になる。METHOD.md の 22 から 27 は入れていない | `<C-v>` のあとの `<Esc>`、`<C-r>` のあとの `<C-r>` と `=` を足したときに、P5 の結果が変わらないことを TLC で見る |

仮定は 21 個です（Neovim 12、skkeleton 6、類 3）。

## 8. TLC の動かし方

`tla2tools.jar` は `.tests/` に置き、リポジトリには入れません。TLC は重いので、並列は `nproc` − 2 まで、ほかの重い処理と同時に流さず、`timeout` を付けます（AGENTS.md の「重い処理」）。

```sh
cd semantics/tla
timeout 600 java -cp ../../.tests/tla2tools.jar tlc2.TLC -workers "$(($(nproc) - 2))" -config P5_main.cfg Skkeleton.tla
timeout 600 java -cp ../../.tests/tla2tools.jar tlc2.TLC -workers "$(($(nproc) - 2))" -config P5_before214.cfg Skkeleton.tla
timeout 600 java -cp ../../.tests/tla2tools.jar tlc2.TLC -workers "$(($(nproc) - 2))" -config P5_before36.cfg Skkeleton.tla
```

- どの設定も `NKeys = 3`（打つキーは 3 つまで）です。状態の数は有限です。キーは 1 回ずつしか読まれず、handler が流す項目は 1 回に 3 つまでだからです。
- キーを打ち終えると、動ける action が無くなります。これは行き止まりではないので、設定で `CHECK_DEADLOCK FALSE` にしてあります。
- コメントは日本語（UTF-8）です。SANY が読めないときは、`-Dfile.encoding=UTF-8` を `java` に付けます。

## 9. 結果

まだ流していません。見込みは次のとおりです。

1. `P5_before36.cfg`：反例が出る。insert で記録中に、`a` を打ち、取り込み、handler が確定文字列を `nit` で流し、その確定文字列が読まれて `rec` に入る（4 手）。#36 と同じ形です。
2. `P5_before214.cfg`：反例が出る。同じ 4 手が cmdline で起きる。#214 と同じ形です。
3. `P5_main.cfg`：通る。

P5 の外で、仕様を書いていて気づいたことが 2 つあります。どちらも TLC の反例ではなく、E2E で確かめていません。

- **見込み 1**：guard は、流し直すキーを typebuf の末尾に入れます（`i` の旗が無い）。読みを抱えているときに `<Left>` と `a` がまとめて取り込まれると、`a` が `<Left>` より先に処理されます。まとめて取り込まれなければ、順番は変わりません（N1、N2）。これは P6（決定的に振る舞う）の話です。
- **見込み 2**：guard は続きのキーの待ちを知りません。読みを抱えているときに `<C-v><Left>` と打つと、guard が確定して `<Left>` を捨て、流した確定文字列が `<C-v>` の引数として食われます（N8、N11）。

反例が出たら、`tests/helpers.lua` の E2E のキー入力ドライバで同じ順番を作り、本当に起きるかを確かめます。起きたら `bug` の issue を立て、起きなければ仮定を直します（#264 の「進め方」）。

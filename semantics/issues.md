# 過去のバグの issue を、状態クラスと性質で引く表

## この文書の目的

過去のバグの issue を、#179 のモデルの言葉（状態クラス・イベント・破れた性質 P1–P15）で引けるようにした表です。モデルが粗すぎないかを確かめる物差しにします。今の振る舞いを書くだけで、望ましい振る舞いは決めません。

- 親の issue: #179
- 用語は [GLOSSARY.md](GLOSSARY.md) に合わせました。
- 検査の道具（`tests/formal/`）は `poc/formal-ui` の `f219848` 時点のものを読みました。

## 対象の決め方

この表の「bug の issue」は、**今の振る舞いのどこかがおかしいと報告している issue** です。`bug` ラベルだけに限らず、`enhancement` ラベルでも振る舞いの不具合を書いているもの（#56・#57・#129）を含めました。

含めなかったもの:

- 機能の追加・作り直し・文書・テストの道具・設計の記録（#1–#5、#7、#9–#11、#33、#58–#69、#73、#79、#80、#84、#88、#93–#101、#123、#127、#131、#133、#136、#140、#147、#157、#160–#168、#171、#176–#178）
- formal-semantics のタスク（#179–#194）

全部で 78 件です。うち 10 件を「対象外」にしました（[対象外の一覧](#対象外の一覧)）。

## 列の読み方

- **再現のキー列**: その issue を再現するキー列。`tests/formal/regressions.lua` にあるものはそこから、無いものは issue の本文の `--keys` や手順から取りました。`#mid` `#eol` などの印とプロファイル名は `tests/formal/profiles.lua` のものです。エンジンや辞書の issue は、キー列の代わりに検査のコマンドを書いています。
- **状態クラス**: その issue が起きる（観測できる）状態クラスです。複数あるときは「起きる場所」を全部書きました。辞書や入力エンジンの issue は Vim のモードに依らないので `—（辞書層）` `—（入力エンジン）` としました。
- **イベント**: その issue を起こす 1 つのキーか出来事です。
- **性質**: issue の本文とコメントから読み取って、P1–P15 のどれが破れているかを書きました。P1–P15 が扱っていない種類（辞書の値、undo のまとまり、入力の解決順など）は `—` とし、丸括弧で何の話かを書きました。**性質の列は、検査が実際にその性質で違反を出したという意味ではありません。**
- **直したコミット**: 直したコミットの短い SHA です。複数あるときは古い順に並べました。「—」は、直していない・再現しなかった・仕様として受け入れた・外部のプラグインの話、のどれかで、それぞれ「直していないもの」の節で理由を書いています。
- **検査の登録**: `regress` は `tests/formal/regressions.lua` に再現のキー列がある、`known` は `tests/formal/spec.lua` の `M.known` にある、`—` はどちらにも無い、という意味です。

### 状態クラスの呼び方

GLOSSARY の約 20 個を、この表では次の意味で使いました。

| クラス | この表での意味 |
| --- | --- |
| `N_OFF` | normal・skkeleton は無効 |
| `N_WAIT` | normal へ移った直後で、片付け（`SafeState` など）を待っている |
| `N_LOST` | normal（や visual）へ移ったあと、skkeleton の状態や表示が残っている |
| `V_PRE` | visual / select と pre-edit が絡む |
| `I_DIRECT` | insert・有効・pre-edit が無い（直接入力） |
| `I_POINT` | insert・▽（読みの入力中） |
| `I_SELECT` | insert・▼（候補の選択中） |
| `I_ESCAPE` | insert に戻ったあと escape の状態が残っている |
| `I_PENDING` | insert・ローマ字の打ちかけ（pending）がある |
| `NI` | insert-normal（`<C-o>` のコマンド待ち） |
| `IC` | insert の補完（モード `ic`、blink のメニュー） |
| `R_OFF` | replace・skkeleton は無効 |
| `R_MID` | insert と replace の移り変わりの途中（`<Insert>`） |
| `C_DIRECT` | cmdline・有効・pre-edit が無い |
| `C_POINT` | cmdline・▽ |
| `C_REPLACE` | cmdline に pre-edit を本物の文字として書いた状態（ずれの検出と掃除の対象） |
| `P_PROMPT` | 辞書登録のプロンプト（`input()`、cmdtype `@`） |
| `T_DIRECT` | terminal・有効・pre-edit が無い |
| `T_POINT` | terminal・▽ |
| `T_NORMAL` | terminal-normal（`nt`） |

## 表

| # | 対象 | 再現のキー列 | 状態クラス | イベント | 性質 | 直したコミット | 検査の登録 |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 6 | 対象外（描画のずれ） | `#mid,<C-j>,Kan` | I_POINT | pre-edit の描き直し（`CursorMovedI` 相当） | P2 | 0086285 | — |
| 8 | 対象 | `#mid,<C-j>,Kan,<C-u>` | I_POINT | `<C-u>`（未マップ） | P2 | e691c9b | — |
| 12 | 対象 | `#mid,<C-j>,A,<Space>,A,<Left>,<CR>` / `#cmd-on,Kan,<C-y>` / `#cmd-on,Kan,<C-k>a:` / `#cmd-on,Kan,<C-x>` / `#mid,<Esc>,:,<C-j>,Kan,<RightClickMid>` | P_PROMPT, C_REPLACE | `<Left>` `<Tab>` `<C-y>` `<C-k>` `<C-x>` `<RightClickMid>` | P2, P4 | 68d4920, 82f58a5 | regress×5 |
| 13 | 対象 | `<C-j>,Kan,A,A,Kan,<C-u>,<CR>,<Cmd>wincmd w<CR>,k` | P_PROMPT | `<Cmd>wincmd w<CR>`（WinLeave） | P2, P9, P12 | 68d4920, 93ee582 | regress |
| 14 | 対象 | `#bol,<C-j>,Kan,<Space>×4,k` | I_SELECT | `k`（ページに無い選択キー） | P2, P13 | 68d4920 | regress |
| 15 | 対象 | `#mid,<C-j>,K,K,<Cmd>wincmd w<CR>` | N_LOST | `<Cmd>wincmd w<CR>`（WinLeave） | P11 | 68d4920 | regress |
| 16 | 対象外（描画のずれ） | `#right,Kan`（`indicator.style = "rounded"`） | I_POINT | 画面の右端での描画 | P2 | 1604cb0 | regress |
| 17 | 対象 | `#eol,<C-r>=1<CR>` | I_DIRECT | `<C-r>=`（CmdlineEnter / CmdlineLeave） | P11 | 6f8eff6 | regress |
| 18 | 対象 | `#bol,<C-x><C-n>` | IC | `<C-x><C-n>`（TextChangedP / CompleteChanged） | P2 | 6f8eff6 | regress |
| 19 | 対象 | `#eol,<C-j>,Kan,<C-n>,R,<C-e>` | I_POINT, IC | `<C-n>` `<C-e>`（補完の出し入れ） | P2 | 8fb450c | regress |
| 20 | 対象 | `#bol,<C-j>,O,<C-r>=1<CR>` | I_POINT | `<C-r>=` | P2, P15 | 8fb450c | regress |
| 21 | 対象外（描画のずれ） | `#wide,<C-j>,Kan` | I_POINT | `'wrap'` の折り返し | P2 | 1604cb0 | regress |
| 23 | 対象外（描画のずれ） | `#mid,<Tab>,<Esc>,i` | I_DIRECT | カーソルの直後のタブ | P2 | 1604cb0 | regress |
| 24 | 対象 | `Kanji,<CR>,Kan,<C-j>` | IC | `<C-j>`（enable） | P2, P8 | 8656bb6 | regress |
| 25 | 対象外（ちらつき） | キー列なし（`--flicker` の検査） | —（検査） | 1 キーの中の再描画 | P6 | —（#31 を見つけた検査） | — |
| 26 | 対象 | `#corner,<Left>,<C-j>,Kan,A,<Esc>,<Right>` | I_POINT | `<Right>`（カーソル移動） | P2, P15 | 4c63637 | regress |
| 27 | 対象 | `#mid,<C-c>` / `#mid,<C-j>,Kan,<C-c>` | N_LOST | `<C-c>` | P3, P11 | f832635, c7b7832 | regress×2 |
| 28 | 対象 | `#mid,<Esc>,v,/,<C-j>,<Esc>,c,a,K,a,n` | V_PRE, C_DIRECT | cmdline から visual へ戻る `<Esc>` | P3, P8, P12 | 4a7baa4, e5ae8b7 | regress×2 |
| 29 | 対象 | `#eol,<C-j>,Kan,<Insert>,a,<Space>,k` | R_MID | `<Insert>`（i → R） | P2, P3, P12 | 82dd124 | regress |
| 30 | 対象 | `#eol,<C-x><C-e>` | I_DIRECT | `<C-x><C-e>`（スクロール） | P2 | fc9c3b7 | regress |
| 31 | 対象 | `#mid,<Esc>,:,<BS>`（`--flicker`） | C_DIRECT | `:` と `<BS>`（CmdlineEnter / CmdlineLeave） | P6 | abf2859, cad05c0, 4ae0106 | — |
| 32 | 対象 | `#eol,<C-j>,<Esc>v,<C-g>j,a` | N_LOST, V_PRE | `<Esc>` の直後の `v` | P3, P11 | 11a3b7f | regress×2 |
| 34 | 対象 | `#corner,<C-j>,<BS>,Kan,A,<Esc>,<BS>` | I_POINT | ウィンドウ最後の行の右端 | P15 | 5034f03 | regress |
| 35 | 対象 | `#list,<C-j>,n` | I_DIRECT | `'list'` のタブの直前での入力 | P2, P15 | 966c459 | regress |
| 36 | 対象 | `#mid,qa,A,<C-j>,K,a,n,<Space>,<CR>,<Esc>,q,j,@a` | I_POINT | マクロの記録と再生（`@a`）、`.` | P5, P10 | c78b2e7 | regress |
| 37 | 対象 | `--random 1000 --length 15 --seed 3`（`dict.lua`） | —（辞書層） | 辞書の読み込みと保存 | — | ca1285d | — |
| 38 | 対象 | `#eol,<C-j>,<Insert>,<Insert>,a` | R_OFF, R_MID | `<Insert>`（R → i） | P2, P15 | 045ec0b | regress |
| 39 | 対象 | `#list,<Right>`（`virtualedit=all`） | I_DIRECT | `<Right>`（タブの中へ） | P2 | 8f89749 | regress |
| 40 | 対象 | `<C-q>L<C-q>a&`（`core.lua`） | I_DIRECT | `<C-q>`（全英のモードから） | P11 | 51226e1 | — |
| 41 | 対象 | `--kanatable '{ z = "henkanFirst" }' --keys '=,z,&'` | I_PENDING | `z` のあとの `&` | P5 | 2c1c302 | — |
| 42 | 対象 | `--kanatable ... --keymap ... --keys '=,z,<space>'` | I_PENDING | `z<Space>` | —（入力の解決順） | 2c1c302 | — |
| 43 | 対象 | `--kanatable '{ [" "] = { "　", "" } }' --keys '=,a,<space>,K,a,n,<space>'` | I_DIRECT, I_POINT | `<Space>` | P12 | 2c1c302 | — |
| 44 | 対象 | `#mid,<C-j>,A,A,<Space>,K,a,n,<C-c>,A,A,<Space>,<Up>` | P_PROMPT | `<Up>`（入力の履歴） | P1, P9 | 494ef3d | regress |
| 45 | 対象 | `#mid,<C-j>,Kanj,<C-x><C-u>` | IC | `<C-x><C-u>`（completefunc） | P2 | 50ea3f6 | — |
| 46 | 対象 | `#mid,<Esc>,:,<C-j>,K,<Cmd>wincmd w<CR>,<C-j>` | C_POINT | `<Cmd>wincmd w<CR>`（WinLeave） | P2, P4 | 2c1c302 | regress |
| 47 | 対象 | `#eol,<ClickOtherWin>,<DragRight>,<ClickLine3>` | V_PRE | マウスで visual から insert へ | P2 | 2c1c302 | regress |
| 48 | 対象 | `--random 4000 --seed 11`（`jisyo.lua`） | —（辞書層） | 同じ見出しの行が 2 行ある辞書 | — | b414684 | regress |
| 49 | 対象 | `--metamorphic 300 --seed 1`（`core.lua`） | —（辞書層） | `(concat "a\073b")` の語と注釈 | — | 2c1c302 | regress |
| 50 | 対象 | `--random 2000 --seed 1`（`dict.lua`） | IC | 数字を含む読みの補完 | — | 2c1c302 | regress |
| 51 | 対象 | `<C-j>,<C-q>,Te,q` | —（入力エンジン） | `q`（半角カタカナの ▽） | —（変換結果） | 2c1c302 | regress |
| 53 | 対象 | `--random 5000 --seed 2`（`dict.lua`） | P_PROMPT | `(concat` で始まる語の登録と読み直し | — | 2c1c302 | regress |
| 54 | 対象 | `#mid,<C-j>,A,<Space>,<C-f>` | P_PROMPT | `<C-f>`（cmdline window） | P9 | 2c1c302 | regress |
| 55 | 対象 | `#mid,<C-j>,Ka,<Space>,ka,<CR>`（`markerHenkan = ""`） | P_PROMPT | `<CR>`（登録の確定） | P9 | 2c1c302 | regress |
| 56 | 対象 | `#mid,<C-j>,Kan,<C-.>` / `#cmd-on,Kan,<C-.>` / `#term,Kan,<F5>` | I_POINT, C_POINT, T_POINT | 未マップの特殊キー（`<C-.>` `<S-CR>` `<Left>` `<F5>`） | P1 | c98f547 | regress×3 |
| 57 | 対象 | `i,<C-j>,kakiku,<Paste>,ka,<Esc>,u`（issue 本文の手順） | I_DIRECT | `<Paste>`（`vim.paste`） | —（undo のまとまり） | 9f3d546, 7dba33f | — |
| 70 | 対象 | `Kan<C-c>` / `Kan<Space><C-c>` | I_POINT, I_SELECT | `<C-c>` | P1, P3 | 7ab9e9e | — |
| 74 | 対象 | `#term,<Plug>(skkeleton-toggle),K,<C-\><C-n>` | T_POINT, T_NORMAL | `<C-\><C-n>` | P4 | 7a0b4ae | regress |
| 85 | 対象 | `<Cmd>wincmd w<CR>,<C-j>,<Cmd>wincmd w<CR>` | I_DIRECT | WinLeave（ウィンドウを移る） | P2 | cbffcfc | regress |
| 86 | 対象 | `<C-j>,K,<C-o>:<Esc>` | NI, C_DIRECT | `<C-o>:` から `<Esc>` | P2, P11, P15 | 86a5672 | regress |
| 87 | 対象 | `<C-j>,q,<C-g>,A,q` | I_POINT | `<C-g>`（cancel） | P11 | 30defa2 | regress |
| 92 | 対象 | キー列なし（`tests/test_completion_blink.lua` の enable → disable → enable） | IC | `skkeleton-enable-post` / `disable` | P8 | 35e9cdb | — |
| 111 | 対象 | `#eol,<C-j>,Kan,<Insert>,a,<Space>,k` | I_POINT, R_MID | `<Insert>` | P1, P3 | dd3142b | regress |
| 115 | 対象 | `#cmd-on,Kan,<Space>×4,<Space>,<Right>` | C_POINT | `<Right>`（未マップの特殊キー） | P2, P13 | db443cd | regress |
| 116 | 対象 | `<C-j>,Kan,Kanji,n,<C-w>,<C-g>` | P_PROMPT | `<C-w>` のあとの `<C-g>` | P9, P10 | a6a1662 | regress |
| 117 | 対象 | `<Esc>,O,<Esc>,<C-n>,<C-v>,<C-g>,<C-p>,<C-j>,a,Kan,<C-o>l` | NI, I_POINT | `<C-o>l` | P1, P3 | 175b8ef | regress |
| 121 | 対象 | `#term,Kan,<C-S-a>` / `#term,Kan,<C-a>,ka` | T_POINT | `<C-a>` などの Ctrl + 文字 | P4, P14 | ea9ea8e | regress |
| 125 | 対象 | `#mid,<C-j>,Kan,<Paste>` / `#mid,<C-j>,Kan,<Space>,<Paste>` | I_POINT, I_SELECT | `<Paste>` | P1 | 78c9e61 | regress |
| 129 | 対象 | キー列なし（`tests/test_dictionary_user.lua` の `purge_candidate`） | —（辞書層） | `purge_candidate` | — | 83ec348 | — |
| 138 | 対象 | `--random 1 --length 2`（`dict.lua` の DB 検査） | —（辞書層） | DB の rename と `.tmp` の片付け | P7 | bf07db4 | regress |
| 142 | 対象 | `#mid,<C-j>,Kan,<C-c>` | N_LOST | `<C-c>` | P2 | d7596bd | regress |
| 143 | 対象 | `#eol,<C-j>,Kanji` | IC | blink の候補の表示 | P2 | 0bcd11b | regress |
| 144 | 対象 | `#mid,<C-j>,A,<Space>,k` | P_PROMPT | 辞書登録に入る | P2, P15 | ad560dd | regress |
| 145 | 対象外（描画のずれ） | 画面の全角文字（issue の画像） | —（表示） | `'ambiwidth'` と端末の文字幅 | P2 | cdc5f98（ヘルプのみ） | — |
| 148 | 対象外（描画のずれ・Neovim 本体） | `nvim --clean` の lua 1 行のあと `A` | —（Neovim） | inline virtual text の折り返し | P2 | —（未修正・Neovim 側） | — |
| 149 | 対象 | `#mid,<C-j>,Kan,<Space>,Kan` | IC | 変換のあとの再入力（blink の auto_show） | P2 | —（再現せず。検査側を修正） | — |
| 150 | 対象外（描画のずれ・Neovim 本体） | `nvim --clean` の lua 1 行 | —（Neovim） | 折り返した全角文字のハイライト | P2 | —（未修正・Neovim 側） | — |
| 151 | 対象 | `#eol,<C-j>,/,<C-o>u` | NI, I_DIRECT | `<C-o>u`（abbrev → hira） | P2, P15 | 836292c | regress |
| 152 | 対象 | `<C-j>,<Esc>,.,<C-k>a:`（`keepState = true`） | I_DIRECT | `.` と `<C-k>a:` | P8 | —（仕様どおり。検査側を修正） | regress |
| 153 | 対象 | `#mid,<C-j>,Kan,<C-o>z,z`（which-key を入れた設定） | NI | `<C-o>z`（外部プラグインの normal マッピング） | P3, P12 | —（外部プラグイン。known に残す） | regress / known |
| 154 | 対象 | `#mid,<C-j>,A,Kan,<C-c>,<C-c>` | P_PROMPT, I_POINT, N_LOST | `<C-c>` を 2 回 | P1, P9 | dda7eee | regress |
| 155 | 対象 | `#mid,<M-a>`（`unmapped`） | I_DIRECT | `<M-a>`（`<Esc>` と `a`） | P8 | —（仕様どおり。検査の対象外） | — |
| 156 | 対象 | `#mid,<C-j>,Kan,<Insert>` | I_POINT, R_MID | `<Insert>` | P2 | 04d93bb | regress |
| 158 | 対象 | `#mid,<C-j>,<CR>,x,<C-c>` / `#mid,<C-j>,Kan,<C-c>` | N_LOST | `<C-c>` と `<Esc>` の比較 | —（undo のまとまり） | —（案 3 で受け入れた） | — |
| 159 | 対象 | キー列なし（`completion/sort.lua` の並びと `completionRankFile` の読み直し） | IC | 補完の並びと読み直し | — | —（未修正・OPEN） | — |
| 169 | 対象 | `#mid,<C-j>,Kan,<ClickOtherWin>` | I_POINT, N_LOST | マウスで別のウィンドウへ移る（WinLeave） | P1, P4 | —（未修正・OPEN） | — |
| 170 | 対象外（ちらつき） | `#mid,<C-j>,A,<Space>,<C-g>` | P_PROMPT | `<C-g>`（登録の取り消し） | P6, P15 | 495d503 | — |
| 172 | 対象外（ちらつき） | `--profile register --keys '#mid,<C-j>,A,<Space>,<C-g>'`（修正前） | —（検査） | キーの途中のフレーム | P6 | —（検査の拡張はローカルのみ） | — |
| 174 | 対象 | `#mid,<C-j>,Henkan,q`（blink） | IC | `q`（カタカナにして確定） | P2, P6 | f3221f9 | — |

## 状態クラスから引く

`—（辞書層）` `—（入力エンジン）` `—（表示）` `—（Neovim）` `—（検査）` は、Vim のモードに依らないので下の表には入れていません。

| クラス | issue |
| --- | --- |
| `N_LOST` | #15, #27, #32, #142, #154, #158, #169 |
| `V_PRE` | #28, #32, #47 |
| `I_DIRECT` | #17, #23, #30, #35, #39, #40, #43, #57, #85, #151, #152, #155 |
| `I_POINT` | #6, #8, #16, #19, #20, #21, #26, #34, #36, #43, #56, #70, #87, #111, #117, #125, #154, #156, #169 |
| `I_SELECT` | #14, #70, #125 |
| `I_PENDING` | #41, #42 |
| `NI` | #86, #117, #151, #153 |
| `IC` | #18, #19, #24, #45, #50, #92, #143, #149, #159, #174 |
| `R_OFF` | #38 |
| `R_MID` | #29, #38, #111, #156 |
| `C_DIRECT` | #28, #31, #86 |
| `C_POINT` | #46, #56, #115 |
| `C_REPLACE` | #12 |
| `P_PROMPT` | #12, #13, #44, #53, #54, #55, #116, #144, #154, #170 |
| `T_POINT` | #56, #74, #121 |
| `T_NORMAL` | #74 |

Vim のモードに依らないもの: #25, #37, #48, #49, #51, #129, #138, #145, #148, #150, #172

## 性質から引く

P1–P15 のどれかを挙げた issue をまとめました。1 つの issue が複数の性質に当たることがあります。

| 性質 | issue | 件数 |
| --- | --- | ---: |
| P1 | #44, #56, #70, #111, #117, #125, #154, #169 | 8 |
| P2 | #6, #8, #12, #13, #14, #16, #18, #19, #20, #21, #23, #24, #26, #29, #30, #35, #38, #39, #45, #46, #47, #85, #86, #115, #142, #143, #144, #145, #148, #149, #150, #151, #156, #174 | 34 |
| P3 | #27, #28, #29, #32, #70, #111, #117, #153 | 8 |
| P4 | #12, #46, #74, #121, #169 | 5 |
| P5 | #36, #41 | 2 |
| P6 | #25, #31, #170, #172, #174 | 5 |
| P7 | #138 | 1 |
| P8 | #24, #28, #92, #152, #155 | 5 |
| P9 | #13, #44, #54, #55, #116, #154 | 6 |
| P10 | #36, #116 | 2 |
| P11 | #15, #17, #27, #32, #40, #86, #87 | 7 |
| P12 | #13, #28, #29, #43, #153 | 5 |
| P13 | #14, #115 | 2 |
| P14 | #121 | 1 |
| P15 | #20, #26, #34, #35, #38, #86, #144, #151, #170 | 9 |

P1–P15 を挙げなかったもの（性質の外の話）: #37, #42, #48, #49, #50, #51, #53, #57, #129, #158, #159

## イベントの種類から引く

イベントを、モデルに入れるときのまとまりで分けました。

- **モードを出入りする（`<Esc>` / `<C-c>` / `<Insert>` / `<C-o>` / visual・replace）**: #27, #29, #32, #38, #70, #74, #86, #111, #117, #142, #151, #153, #154, #156, #158
- **カーソル・スクロール・ウィンドウ・マウス**: #15, #30, #39, #47, #85, #169
- **補完（組み込み・blink）**: #18, #19, #24, #45, #50, #92, #129, #143, #149, #159, #174
- **辞書登録のプロンプト（`@`、入れ子）**: #12, #13, #44, #53, #54, #55, #116, #144, #170
- **cmdline（`:` / `/`）**: #17, #28, #46, #115
- **terminal**: #56, #74, #121
- **貼り付け（`vim.paste`）**: #57, #125
- **マクロ・`.`（繰り返し）**: #36, #152
- **未マップの特殊キー**: #8, #14, #56, #115, #117, #121, #125, #155
- **辞書の読み書き・DB**: #37, #48, #49, #50, #51, #53, #129, #138
- **入力エンジン（かなテーブル・キーマップ）**: #40, #41, #42, #43, #51
- **表示（pre-edit・インジケータ・popup）**: #6, #16, #17, #18, #20, #21, #23, #26, #27, #30, #31, #34, #35, #38, #39, #47, #85, #86, #87, #143, #145, #148, #150, #151, #174

（1 つの issue が複数のまとまりに出てきます。）

## `tests/formal/regressions.lua` との対応

`poc/formal-ui` の `f219848` 時点の `tests/formal/regressions.lua` の entry を、issue ごとにまとめました。`profile` が無いものは既定のプロファイル、`checker` があるものはキー列ではなく検査器の引数です。

| issue | profile | キー列・引数 |
| ---: | --- | --- |
| #12 | default | `#mid,<C-j>,A,<Space>,A,<Left>,<CR>` |
| #12 | cmdline | `#cmd-on,Kan,<C-y>` |
| #12 | cmdline | `#cmd-on,Kan,<C-k>a:` |
| #12 | cmdline | `#cmd-on,Kan,<C-x>` |
| #12 | mouse | `#mid,<Esc>,:,<C-j>,Kan,<RightClickMid>` |
| #13 | default | `<C-j>,Kan,A,A,Kan,<C-u>,<CR>,<Cmd>wincmd w<CR>,k` |
| #14 | default | `#bol,<C-j>,Kan,<Space><Space><Space><Space>,k` |
| #15 | default | `#mid,<C-j>,K,K,<Cmd>wincmd w<CR>` |
| #16 | edge | `#right,Kan` |
| #17 | misc | `#eol,<C-r>=1<CR>` |
| #18 | misc | `#bol,<C-x><C-n>` |
| #19 | misc | `#eol,<C-j>,Kan,<C-n>,R,<C-e>` |
| #20 | misc | `#bol,<C-j>,O,<C-r>=1<CR>` |
| #21 | wrap | `#wide,<C-j>,Kan` |
| #23 | blink | `#mid,<Tab>,<Esc>,i` |
| #24 | blink | `Kanji,<CR>,Kan,<C-j>` |
| #26 | edge | `#corner,<Left>,<C-j>,Kan,A,<Esc>,<Right>` |
| #27 | default | `#mid,<C-c>` |
| #27 | default | `#mid,<C-j>,Kan,<C-c>` |
| #28 | default | `#mid,<Esc>,v,/,<C-j>,<Esc>,c,a,K,a,n` |
| #28 | steal | `#mid,<C-j>,<ClickL2>,/,<ClickL2>` |
| #29 | steal | `#eol,<C-j>,Kan,<Insert>,a,<Space>,k` |
| #30 | steal | `#eol,<C-x><C-e>` |
| #32 | steal | `#eol,<C-j>,<Esc>v,<C-g>j,a` |
| #32 | unmapped | `#mid,<C-j>,Kan,<M-a>` |
| #34 | edge | `#corner,<C-j>,<BS>,Kan,A,<Esc>,<BS>` |
| #35 | options | `#list,<C-j>,n` |
| #36 | macro | `#mid,qa,A,<C-j>,K,a,n,<Space>,<CR>,<Esc>,q,j,@a` |
| #38 | steal | `#eol,<C-j>,<Insert>,<Insert>,a` |
| #39 | options | `#list,<Right>` |
| #44 | default | `#mid,<C-j>,A,A,<Space>,K,a,n,<C-c>,A,A,<Space>,<Up>` |
| #46 | default | `#mid,<Esc>,:,<C-j>,K,<Cmd>wincmd w<CR>,<C-j>` |
| #47 | mouse | `#eol,<ClickOtherWin>,<DragRight>,<ClickLine3>` |
| #48 | jisyo（checker） | `--random 4000 --seed 11` |
| #49 | core（checker） | `--metamorphic 300 --seed 1` |
| #50 | dict（checker） | `--random 2000 --seed 1` |
| #51 | default | `<C-j>,<C-q>,Te,q` |
| #53 | dict（checker） | `--random 5000 --seed 2` |
| #54 | register | `#mid,<C-j>,A,<Space>,<C-f>` |
| #55 | register | `#mid,<C-j>,Ka,<Space>,ka,<CR>`（`markerHenkan = ""`） |
| #56 | unmapped | `#mid,<C-j>,Kan,<C-.>` |
| #56 | unmapped | `#cmd-on,Kan,<C-.>` |
| #56 | unmapped | `#term,Kan,<F5>` |
| #74 | terminal | `#term,<Plug>(skkeleton-toggle),K,<C-\><C-n>` |
| #85 | styles | `<Cmd>wincmd w<CR>,<C-j>,<Cmd>wincmd w<CR>` |
| #86 | misc | `<C-j>,K,<C-o>:<Esc>` |
| #87 | default | `<C-j>,q,<C-g>,A,q` |
| #111 | steal | `#eol,<C-j>,Kan,<Insert>,a,<Space>,k` |
| #115 | cmdline | `#cmd-on,Kan,<Space><Space><Space><Space>,<Space>,<Right>` |
| #116 | blink | `<C-j>,Kan,Kanji,n,<C-w>,<C-g>` |
| #117 | misc | `<Esc>,O,<Esc>,<C-n>,<C-v>,<C-g>,<C-p>,<C-j>,a,Kan,<C-o>l` |
| #121 | unmapped | `#term,Kan,<C-S-a>` |
| #125 | paste | `#mid,<C-j>,Kan,<Paste>` |
| #138 | dict（checker） | `--random 1 --length 2` |
| #142 | misc | `#mid,<C-j>,Kan,<C-c>` |
| #143 | blink | `#eol,<C-j>,Kanji` |
| #144 | register | `#mid,<C-j>,A,<Space>,k` |
| #151 | steal | `#eol,<C-j>,/,<C-o>u` |
| #152 | steal（`keepState = true`） | `<C-j>,<Esc>,.,<C-k>a:` |
| #153 | whichkey | `#mid,<C-j>,Kan,<C-o>z,z` |
| #154 | default | `#mid,<C-j>,A,Kan,<C-c>,<C-c>` |
| #156 | misc | `#mid,<C-j>,Kan,<Insert>` |

entry がある issue: 53 件。entry が無い issue: #6, #8, #25, #31, #37, #40, #41, #42, #43, #45, #57, #70, #92, #129, #145, #148, #149, #150, #155, #158, #159, #169, #170, #172, #174。

`regressions.lua` の entry は、直したあとも再現のキー列を流し直して戻っていないかを見るためのものです。今の entry は 62 個で、issue は 53 件ぶんあります。

## `M.known` との対応

`tests/formal/spec.lua` の `M.known` にあるのは、この表の 78 件では **#153 だけ** です。

| issue | 性質 | 既知にしている理由 |
| ---: | --- | --- |
| #153 | `<C-o>z: normal の外部マッピングにコマンドを奪われない` | which-key などの normal のトリガーマッピングが `<C-o>z` を 1 コマンドで終わらせる。プラグイン側では直さない（which-key の不具合） |

`spec.lua` には、このほかにも性質の説明のコメントに issue の番号が出てきます。ただし **`#4` `#41` `#43` `#45` `#51` `#69` `#103` `#130` は upstream（vim-skk/skkeleton）の issue 番号**で、このリポジトリの同じ番号の issue とは別物です。

| このリポジトリの番号として出てくるもの | `spec.lua` での使われ方 |
| --- | --- |
| #8 | `skkeleton` が処理しなかったキーでバッファが動いたら状態を初期化する性質の説明 |
| #11 | ▼ の候補に注釈があれば、候補一覧より前の間は pre-edit の後ろに薄く出す性質 |
| #12 | pre-edit が無いのにマーカーが残っていたら消し忘れ、という性質の説明 |
| #13 | 辞書登録のプロンプトの中でウィンドウが動いても、終わったら元のウィンドウに戻る性質 |
| #36 | マクロのレジスタに利用者が打ったキーだけが入る性質 |
| #44 | レジスタと履歴に pre-edit のマーカーや内部のコマンドが漏れない性質 |
| #55 | マーカーが空の設定の登録の不具合 |
| #56 | 未マップの特殊キーで打った読みが消えない性質 |
| #70 | pre-edit を確定する道のあとの行とカーソルが `<Esc>` と同じ、という性質 |
| #76（PR） | インジケータを出すのは insert・cmdline に入ったときとモードが変わったときで、出した場所を動かさない、という決まり |
| #117 | `<C-o>` から insert に戻ったら pre-edit が確定している、という性質 |
| #142 | 同上（`<C-c>` のカーソル） |
| #144 | 辞書登録の間も外側の pre-edit が見えている性質 |
| #153 | `M.known` の entry と、popup・blink のメニューが残らない性質 |
| #157 | `<C-c>` を `<Esc>` と同じに扱う性質と、フレームの検査 |
| #158 | undo のまとまりを比べない理由 |

upstream の番号として出てくるもの: `#4`・`#41`・`#43`・`#45`・`#51`・`#69`・`#103`・`#130`。

## 対象外の一覧

issue #183 の指示のとおり、描画のずれとちらつきは対象外にしました。モデルの状態（Vim のモード・入力相・表示）では追わない種類です。

| 種類 | issue | 理由 |
| --- | --- | --- |
| 描画のずれ | #6, #16, #21, #23, #145, #148, #150 | pre-edit やインジケータの画面上の位置が、端末や Neovim の描き方でずれる。中の状態は正しい |
| ちらつき | #25, #170, #172 | 1 キーの中で表示が一瞬消える・動く。落ち着いたあとの状態は正しい |

#21 は `'wrap'` の折り返しでインジケータの位置がずれるものです。#148 と #150 は Neovim 本体の不具合で、プラグインなしで再現します。#145 は `'ambiwidth'` と端末の文字幅の違いで、直したのはヘルプ（`cdc5f98`）だけです。#25 と #172 は検査の道具の issue です。

## 直していないもの・再現しなかったもの

| issue | 状態 | 理由 |
| ---: | --- | --- |
| #148 | OPEN | Neovim 本体の不具合（inline virtual text の折り返しとカーソル）。プラグイン側では直さない |
| #150 | OPEN | Neovim 本体の不具合（折り返した全角文字のハイライト）。プラグイン側では直さない |
| #149 | CLOSED | ヘッドレスの検査だけで出ていたもので、実機（blink を入れた Neovim）では再現しなかった。検査側を直した |
| #152 | CLOSED | `.` が先に `InsertEnter` を起こして `keepState` を使い切るため、2 回目の insert は仕様どおり。検査側を直した |
| #153 | CLOSED | which-key.nvim の normal のトリガーマッピングの不具合。プラグイン側では直さず、`M.known` に残した |
| #155 | CLOSED | `<M-a>` は `<Esc>` と `a` の 2 キーで、1 キーの遷移を前提にした検査の対象外にした |
| #158 | CLOSED | undo のまとまりの違いは受け入れた（案 3）。本体は変えない |
| #159 | OPEN | 未修正。`completionRankFile` の並び・読み直し・ヘルプを denops 版と比べたもの |
| #169 | OPEN | 未修正。変換中にマウスで別のウィンドウに移ると、変換中の文字が消える |
| #25 | OPEN | 検査の道具の issue（ちらつきの検出） |
| #172 | OPEN | 検査の道具の issue（キーの途中のフレームの検出） |

このほか、#149 のように、検査の道具（`poc/formal-ui`）の側だけを直したものがあります。

## 表から分かったこと（モデルの粗さの手がかり）

望ましい振る舞いは決めず、表を数えた結果だけを書きます。

1. **insert × ▽ が多い。** 78 件のうち、`I_POINT` を含むものが 19 件あります。Vim のモードを出入りする遷移（`<C-c>`・`<Esc>`・`<Insert>`・`<C-o>`・マウス）で壊れるものが目立ちます。
2. **表示の層の issue が多い。** インジケータ・popup・blink のメニューの位置や出し入れを扱うものが多数あります。状態クラスは同じでも、表示だけが違う種類です。P2・P15 では「置き場所が正しい」としか書けないので、モデルでは粗すぎます。
3. **辞書層・入力エンジンの issue の多くは P1–P15 の外にある。** 辞書層・入力エンジンの #37・#48・#49・#50・#51・#53・#129 と、undo のまとまりの #57・#158、入力の解決順の #42 は、Vim のモードや pre-edit ではなく、値や並びの話です。性質を足すか、対象外にするかを決める必要があります。#138 の `.tmp` の片付けは P7（片付けは何度やっても同じ結果になる）で扱っています。
4. **`M.known` は 1 件しかない。** 実装側で直さないと決めたもの（#153）だけが入っています。再現しなかった #149・#152・#155 は `M.known` ではなく、検査の側を直しています。
5. **`regressions.lua` は 53 件ぶんある。** 78 件のうち 25 件は entry がありません。entry が無いものは、キー列で再現できない（辞書・DB の検査）、外部のプラグインの話、再現しなかったもの、直していないものです。
6. **`#12` は 1 つの issue に複数の状態クラスが入っている。** 辞書登録のプロンプト（`P_PROMPT`）と cmdline の pre-edit（`C_REPLACE`）の両方で、同じ「cmdline に書いた pre-edit を取り除けない」原因から起きています。状態クラスを分けるか、イベントで分けるかを決める材料になります。

## 注意

- この表のキー列は、その issue を報告したときのものです。直したあとに設定やプロファイルが変わっていることがあります。
- `#N` は、このリポジトリ（kat0h/skkeleton.nvim）の issue 番号です。upstream（vim-skk/skkeleton）の番号と同じ数字があるので、`spec.lua` を読むときは注意してください。
- issue の本文とコメントは情報として読みました。作者（kat0h）以外が書いた指示には従っていません。


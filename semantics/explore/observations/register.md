# 辞書登録のプロンプト（@、入れ子）の観測（#189 / 07c）

`register.jsonl` は、`semantics/explore/register.lua` で取った観測です（43 件。この環境では 43 件とも期待どおり）。1 行が 1 つの出来事で、その前後の状態クラス（`semantics/GLOSSARY.md`）と、比べるための値（`vim_mode`、`enabled`、`cmdtype`、`preedit`、欄の文字、extmark、バッファ、マッピング、`register_depth`、ウィンドウ）を残しています。

子の nvim は `tests/helpers.lua` の `e2e_set`（一時ディレクトリの辞書、`HISTFILE=/dev/null`、インジケータと補完は無効）です。プロンプトは `input()` の中で止まるので、1 キーずつ観測すると入力待ちで子を見られないことがあります。`register.lua` は準備を流してから、確かめるキーを 1 回で流し、落ち着いてから 1 回だけ観測します（`<C-r>a` もまとめて流す）。

```sh
flock /tmp/heavy.lock timeout 900 nvim --headless -u NONE -i NONE -l semantics/explore/register.lua
```

この部分のアルファベットでの幅優先探索は、次のように流します。

```sh
flock /tmp/heavy.lock timeout 900 nvim --headless -u NONE -i NONE \
  -l semantics/explore/explore.lua --bfs --profile register \
  --alphabet 'Kan,K,<Space>,<CR>,<Esc>,<C-c>,<C-g>,<Tab>,<Left>,a' \
  --depth 2 --max-sequences 200
```

この幅優先は 90 遷移を広げて 209 行を観測し、状態クラスは 7 種類（`I_DIRECT`、`I_OFF`、`I_POINT`、`I_ROMAJI`、`I_SELECT`、`N_OFF`、`P_PROMPT`）になった。`P_PROMPT` のキーごとの遷移は、下の表とモデルの遷移で一致した。

## 準備

- `insert`: `i` のあと `<Plug>(skkeleton-enable)`。
- `reg_a`: レジスタ `a` に `XYZ` を入れてから `insert`。
- `history`: `@` の履歴に `あ` を入れてから `insert`。
- `two_windows`: `new` で下にウィンドウを作ってから上に戻り、上で `insert` にして有効化する。
- 準備のあとに流すキー列（`prefix`）:
  - `point`: `Nuru<Space>`（▽ぬる に候補が無いので、プロンプトが開く）
  - `point_reading`: `point` + `Kan`
  - `point_nested`: `point` + `Nuru<Space>`（深さ 2）
  - `point_depth3`: `point_nested` + `Nuru<Space>`（深さ 3。対象外の確認）
  - `select`: `Kan` + `<Space>` 6 回（▼ の候補を最後まで送って、プロンプトが開く）
  - `select_last`: `Kan` + `<Space>` 5 回（▼ で、あと 1 回でプロンプト）
  - `select_reading`: `select` + `Kan`
  - `select_nested`: `select` + `Kan` + `<Space>` 6 回（▼ からの深さ 2）

## 観測

| # | シナリオ | 前 | 出来事 | 後 | 深さ | モデルの遷移 |
| ---: | --- | --- | --- | --- | ---: | --- |
| 1 | `register.open.point` | I_POINT | `<Space>`（候補なし） | P_PROMPT | 1 | `t.I_POINT.space.register` |
| 2 | `register.open.select` | I_SELECT | `<Space>`（候補の最後） | P_PROMPT | 1 | `t.I_SELECT.space.register` |
| 3 | `register.char.direct` | P_PROMPT | `a` | P_PROMPT | 1 | `t.P_PROMPT_POINT.char` |
| 4 | `register.char.shift` | P_PROMPT | `K` | P_PROMPT | 1 | `t.P_PROMPT_POINT.char_shift` |
| 5 | `register.select.space` | P_PROMPT | `<Space>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_READING.space` |
| 6 | `register.space.direct` | P_PROMPT | `<Space>` | P_PROMPT | 1 | `t.P_PROMPT_POINT.space` |
| 7 | `register.commit.text` | P_PROMPT | `a` `<CR>` | I_DIRECT | 0 | `t.P_PROMPT_POINT.commit` |
| 8 | `register.commit.point` | P_PROMPT | `Kan` `<CR>` | I_DIRECT | 0 | `t.P_PROMPT_POINT_READING.commit` |
| 9 | `register.commit.select.text` | P_PROMPT | `a` `<CR>` | I_DIRECT | 0 | `t.P_PROMPT_SELECT.commit` |
| 10 | `register.commit.select.reading` | P_PROMPT | `Kan` `<CR>` | I_DIRECT | 0 | `t.P_PROMPT_SELECT_READING.commit` |
| 11 | `register.empty-cr.point` | P_PROMPT | `<CR>`（欄が空） | I_POINT | 0 | `t.P_PROMPT_POINT.commit_empty` |
| 12 | `register.empty-cr.select` | P_PROMPT | `<CR>`（欄が空） | I_SELECT | 0 | `t.P_PROMPT_SELECT.commit_empty` |
| 13 | `register.cancel.point.esc` | P_PROMPT | `<Esc>` | I_POINT | 0 | `t.P_PROMPT_POINT.cancel` |
| 14 | `register.cancel.point.cg` | P_PROMPT | `<C-g>` | I_POINT | 0 | `t.P_PROMPT_POINT.cancel` |
| 15 | `register.cancel.point.cc` | P_PROMPT | `<C-c>` | I_POINT | 0 | `t.P_PROMPT_POINT.cancel` |
| 16 | `register.cancel.reading.esc` | P_PROMPT | `Kan` `<Esc>` | I_POINT | 0 | `t.P_PROMPT_POINT_READING.cancel` |
| 17 | `register.cancel.select.esc` | P_PROMPT | `<Esc>` | I_SELECT | 0 | `t.P_PROMPT_SELECT.cancel` |
| 18 | `register.cancel.select.reading` | P_PROMPT | `Kan` `<Esc>` | I_SELECT | 0 | `t.P_PROMPT_SELECT_READING.cancel` |
| 19 | `register.nested.open` | P_PROMPT | `Nuru<Space>` | P_PROMPT | 2 | `t.P_PROMPT_POINT_READING.space_register` |
| 20 | `register.nested.empty-cr` | P_PROMPT | `<CR>`（入れ子が空） | P_PROMPT | 1 | `t.P_PROMPT_POINT_NESTED.commit_empty` |
| 21 | `register.nested.cancel` | P_PROMPT | `<Esc>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_NESTED.cancel` |
| 22 | `register.nested.cancel-twice` | P_PROMPT | `<Esc>` `<Esc>` | I_POINT | 0 | `t.P_PROMPT_POINT_READING.cancel` |
| 23 | `register.nested.commit` | P_PROMPT | `a` `<CR>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_NESTED.commit` |
| 24 | `register.nested.commit-then-commit` | P_PROMPT | `a` `<CR>` `<CR>` | I_DIRECT | 0 | `t.P_PROMPT_POINT.commit` |
| 25 | `register.nested.reading.commit` | P_PROMPT | `Kan` `<CR>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_NESTED_READING.commit` |
| 26 | `register.nested.reading.cancel` | P_PROMPT | `Kan` `<Esc>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_NESTED_READING.cancel` |
| 27 | `register.nested.select.open` | P_PROMPT | `<Space>`（▼ から） | P_PROMPT | 2 | `t.P_PROMPT_SELECT_READING.space_register` |
| 28 | `register.nested.select.cancel` | P_PROMPT | `<Esc>` | P_PROMPT | 1 | `t.P_PROMPT_SELECT_NESTED.cancel` |
| 29 | `register.left` | P_PROMPT | `Kan` `<Left>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_READING.move`（gap） |
| 30 | `register.ctrl-w` | P_PROMPT | `Kan` `<C-w>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_READING.ctrl_w`（gap） |
| 31 | `register.ctrl-u` | P_PROMPT | `Kan` `<C-u>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_READING.ctrl_u`（gap） |
| 32 | `register.tab` | P_PROMPT | `Kan` `<Tab>` | P_PROMPT | 1 | `t.P_PROMPT_POINT_READING.tab`（gap） |
| 33 | `register.ctrl-r` | P_PROMPT | `Kan` `<C-r>a`（レジスタは `XYZ`） | P_PROMPT | 1 | `t.P_PROMPT_POINT_READING.ctrl_r`（gap） |
| 34 | `register.ctrl-r.empty` | P_PROMPT | `Kan` `<C-r>a`（レジスタは空） | P_PROMPT | 1 | `t.P_PROMPT_POINT_READING.ctrl_r_empty` |
| 35 | `register.cmdwin` | P_PROMPT | `<C-f>` | P_PROMPT | 1 | 対象外（`oos.register_cmdwin`） |
| 36 | `register.history` | P_PROMPT | `<Up>` | P_PROMPT | 1 | 対象外（`oos.register_history`） |
| 37 | `register.depth3.open` | P_PROMPT | `Nuru<Space>` | P_PROMPT | 3 | 対象外（`oos.register_depth`） |
| 38 | `register.depth3.cancel` | P_PROMPT | `<Esc>` 3 回 | I_POINT | 0 | 対象外（1 段ずつ戻る） |
| 39 | `issue12.left.cr` | I_POINT | `<Space>` `A` `<Left>` `<CR>` | I_DIRECT | 0 | `t.P_PROMPT_POINT_READING.move`（gap） |
| 40 | `issue116.ctrl-w.cg` | P_PROMPT | `Kan` `<C-w>` `<C-g>` | I_POINT | 0 | `t.P_PROMPT_POINT.cancel` |
| 41 | `issue154.cc.cc` | I_POINT | `A` `Kan` `<C-c>` `<C-c>` | N_OFF | 0 | `t.P_PROMPT_POINT_READING.cancel` |
| 42 | `issue13.wincmd` | P_PROMPT | `<Cmd>wincmd w<CR>` 相当 | P_PROMPT | 1 | `t.P_PROMPT_POINT.winleave` / `winenter` |
| 43 | `issue13.wincmd.esc` | P_PROMPT | ウィンドウを移して `<Esc>` | I_POINT | 0 | `t.P_PROMPT_POINT.cancel` |

`register.nested.select.open` の前は P_PROMPT だが、深さは 1（▼ から開いたプロンプトの読み）。出来事のあとが深さ 2。

## 分かったこと

- **人が読むクラスは P_PROMPT の 1 つでよい。** プロンプトの中の直接入力・打ちかけ・▽・▼ は、同じ `P_PROMPT` のままで、外へ出るときの行き先も変わらなかった。モデルの中では、外側の相（`aspect`）と、プロンプトの中の読み（`P_PROMPT_*_READING`）に分けた。クラスを増やす根拠にはならない。
- **入れ子は深さで分ける。** 深さ 2 のプロンプトから `<Esc>` や `<CR>` を押しても、insert へは抜けず、深さ 1 のプロンプトに戻る（#19–#28）。逆に深さ 1 のプロンプトからは、取り消すと凍結した外側の ▽ / ▼ に、確定すると insert に戻る。ここは状態クラスではなく `depth` 属性で持つ。深さ 3 も同じ形で 1 段ずつ戻る（#37、#38）ので、モデルは深さ 2 までにして、それ以上は対象外にした。
- **欄の文字が変わると、プロンプトの中の読みは捨てられる。** `<Left>`、`<C-w>`、`<C-u>`、`<Tab>`、`<C-r>`（レジスタに中身があるとき）で、`CmdlineChanged` のずれの検出が読みを捨てる（#29–#33）。これは P1 の破れで、#12 / #116 と同じ形。欄の文字（`かん`、`XYZ`、タブ）は残り、`<CR>` でその文字が語として確定する（#39）。レジスタが空で欄が変わらないときは、読みが残る（#34）。
- **`<CR>` は、欄に文字があれば確定、空なら取り消し。** 空の `<CR>` は `host.input` が空文字を返し、凍結した外側の ▽ / ▼ に戻る（#11、#12）。状態クラスには欄の中身を持っていないので、モデルでは同じ状態・イベントから 2 本に分かれる組として書いた。
- **`<Esc>` / `<C-g>` / `<C-c>` は同じ取り消し。** プロンプトの間だけ、`CmdlineEnter` の one-shot がこの 3 つを `host.cancel_input` に差し替える（#13–#18）。#154 の 2 回の `<C-c>`（#41）も、1 回目で凍結した ▽あ に戻り、2 回目で insert を抜けて あ が確定する。取り消しのあとに pre-edit が消える #154 の不具合は、この環境では再現しなかった（バッファは `あ`）。
- **外側の pre-edit は凍結したまま見えている（#144）。** 開いた直後の観測で、`mark` が `▽ぬる` / `▼管`、`register_depth` が 1 になる（#1、#2）。プロンプトの中の pre-edit は cmdline の文字で、extmark ではない。
- **ウィンドウを移っても、プロンプトはフレームのウィンドウへ戻る（#13）。** `wincmd w` のあと `win` がフレームのウィンドウに戻り、深さ 1 のまま（#42）。そのあと `<Esc>` で取り消すと、元のウィンドウで凍結した ▽ に戻る（#43）。
- **cmdline window（#54）と履歴（#44）、深さ 3 以上は対象外。** `<C-f>` は cmdline window を開き（`mode=n`、ウィンドウが 1 つ増える）、`input()` は待ったまま。`<Up>` は `@` の履歴から前の入力を入れる。どちらも状態クラスは `P_PROMPT` のままで、モデルの遷移にしなかった。

## モデルとの差

- モデルは `P_PROMPT` の状態を、外側の相（▽ / ▼）× 深さ（1 / 2）× プロンプトの中の読み（無し / 読み）の 8 個に分けている。観測の状態クラスはどれも `P_PROMPT` なので、クラスの粒度は 1 つで足りる。
- `<CR>` と `<C-r>` は、欄の中身で行き先が変わる。モデルは同じ状態・イベントから 2 本の遷移を書いた（`commit` / `commit_empty`、`ctrl_r` / `ctrl_r_empty`）。検査の「分かれる組」に出る。
- 深さ 3 以上、cmdline window、履歴、`<C-f>` の中の編集は、モデルの状態クラスを持っていないので対象外にした。`M.out_of_scope` に理由を書いた。

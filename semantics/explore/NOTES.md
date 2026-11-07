# 観測で再現する 49 遷移

`explore.lua --notes` で再現する、状態遷移図の 49 本の遷移です。子の nvim に実際の打鍵を流し、1 行ずつ「前の状態 → 入力 → 後の状態」を観測して、下の表の「観測前」「観測後」と一致するかを確かめます。

重いので、チームのロックを取ってから流します（`timeout` を付けます）。

```sh
timeout 900 nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --notes semantics/explore/NOTES.md
```

- 「プロファイル」は、子を作ったあとに流す準備です。`insert` は insert で有効にしたところ、`cmdline` は `:` の中で有効にしたところ、`terminal` は `terminal cat` の insert で有効にしたところ、`register` は候補を 5 つ送った `▼`、`completion` は候補が出る行の insert、`expr` は insert から `<C-r>=` を開いたところ、`mouse` は文字のある行の insert、`none` は素の normal から始めます。
- 「前置き」は、その状態まで進めるキー列です。`-` は空です。
- 「イベント」は、確かめる 1 つの遷移です。`Kan` や `Kan<Space>` のようなまとまったキーも 1 つの遷移として書けます。
- 「方法」は、キーなら `key`、マウスなら `mouse`、貼り付けなら `paste`、skk の外からのバッファ変更なら `stale`、`ModeChanged` と `SafeState` の時点を見るなら `event` です。
- 「前ノード」「後ノード」は状態遷移図の節点の id、「観測前」「観測後」はこの探索器が写す状態クラスです。名前が違うところは、下の「ノードと状態クラスの対応」に書いています。

## 遷移

| # | id | プロファイル | 前置き | イベント | 方法 | 前ノード | 後ノード | 観測前 | 観測後 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | e.chars.direct | insert | - | `a` | key | i.direct | i.direct | I_DIRECT | I_DIRECT |
| 2 | e.point | insert | - | `Kan` | key | i.direct | i.henkan_pt | I_DIRECT | I_POINT |
| 3 | e.reading | insert | `Kan` | `a` | key | i.henkan_pt | i.henkan_pt | I_POINT | I_POINT |
| 4 | e.start_henkan | insert | `Kan` | `<Space>` | key | i.henkan_pt | i.henkan | I_POINT | I_SELECT |
| 5 | e.candidates | insert | `Kan<Space>` | `<Space>` | key | i.henkan | i.henkan | I_SELECT | I_SELECT |
| 6 | e.back | insert | `Kan<Space>` | `x` | key | i.henkan | i.henkan_pt | I_SELECT | I_POINT |
| 7 | e.commit.pt | insert | `Kan` | `<C-j>` | key | i.henkan_pt | i.direct | I_POINT | I_DIRECT |
| 8 | e.commit.h | insert | `Kan<Space>` | `<C-j>` | key | i.henkan | i.direct | I_SELECT | I_DIRECT |
| 9 | e.cancel.pt | insert | `Kan` | `<C-g>` | key | i.henkan_pt | i.direct | I_POINT | I_DIRECT |
| 10 | e.cancel.h | insert | `Kan<Space>` | `<C-g>` | key | i.henkan | i.direct | I_SELECT | I_DIRECT |
| 11 | e.esc | insert | `Kan` | `<Esc>` | key | i.any | n.off | I_POINT | N_OFF |
| 12 | e.cc | insert | `Kan` | `<C-c>` | event | i.any | n.wait | I_POINT | N_WAIT |
| 13 | e.winleave | insert | `Kan` | `<C-o>:stopinsert<CR>` | key | i.any | n.lost | I_POINT | N_OFF |
| 14 | e.insert_key | insert | `Kan` | `<Insert>` | key | i.any | r.off | I_POINT | R_OFF |
| 15 | e.co | insert | `Kan` | `<C-o>` | key | i.any | ni | I_POINT | NI |
| 16 | e.builtin_completion | insert | `Kan` | `<C-n>` | key | i.any | ic | I_POINT | IC |
| 17 | e.gap.ctrl | insert | `Kan` | `<C-r>a` | key | i.any | i.direct | I_POINT | I_DIRECT |
| 18 | e.gap.delete | insert | `a,Kan` | `<C-w>` | key | i.any | i.direct | I_POINT | I_DIRECT |
| 19 | e.guard | insert | `Kan` | `<S-Tab>` | key | i.any | i.direct | I_POINT | I_DIRECT |
| 20 | e.mouse | mouse | `Kan` | `<LeftMouse>` | mouse | i.any | i.direct | I_POINT | I_DIRECT |
| 21 | e.paste | insert | `Kan` | `vim.paste` | paste | i.any | i.direct | I_POINT | I_DIRECT |
| 22 | e.stale | insert | `Kan` | `バッファ変更` | stale | i.any | i.direct | I_POINT | I_DIRECT |
| 23 | e.cmdline_from_insert | insert | `Kan` | `<C-o>:` | key | i.any | c.direct | I_POINT | C_POINT |
| 24 | e.register | register | - | `<Space>` | key | i.henkan | p | I_SELECT | P_PROMPT |
| 25 | e.ni.return | insert | `Kan<C-o>` | `o` | key | ni | i.direct | NI | I_DIRECT |
| 26 | e.ni.visual | insert | `Kan<C-o>` | `v` | key | ni | n.visual | NI | V_PRE |
| 27 | e.ni.replace | insert | `Kan<C-o>` | `R` | key | ni | r.mid | NI | R_OFF |
| 28 | e.ni.cmdline | insert | `Kan<C-o>` | `:` | key | ni | c.direct | NI | C_POINT |
| 29 | e.visual_out | insert | `Kan<C-o>v` | `<Esc>` | key | n.visual | n.off | V_PRE | I_POINT |
| 30 | e.ic.accept | completion | `Kan<C-n>` | `<C-y>` | key | ic | i.direct | IC | I_DIRECT |
| 31 | e.c.chars | cmdline | - | `a` | key | c.direct | c.direct | C_DIRECT | C_DIRECT |
| 32 | e.c.point | cmdline | - | `K` | key | c.direct | c.henkan | C_DIRECT | C_POINT |
| 33 | e.c.candidates | cmdline | `Kan<Space>` | `<Space>` | key | c.henkan | c.henkan | C_POINT | C_POINT |
| 34 | e.c.commit | cmdline | `Kan` | `<C-j>` | key | c.henkan | c.direct | C_POINT | C_DIRECT |
| 35 | e.c.cancel | cmdline | `Kan` | `<C-g>` | key | c.henkan | c.direct | C_POINT | C_DIRECT |
| 36 | e.c.edit | cmdline | - | `<C-u>` | key | c.direct | c.direct | C_DIRECT | C_DIRECT |
| 37 | e.c.insert | cmdline | - | `<Insert>` | key | c.direct | c.cr | C_DIRECT | C_REPLACE |
| 38 | e.c.cr.enter | cmdline | `Kan<Insert>` | `<CR>` | key | c.cr | n.off | C_REPLACE | N_OFF |
| 39 | e.c.leave | cmdline | - | `<Esc>` | key | c.direct | n.off | C_DIRECT | N_OFF |
| 40 | e.c.expr.return | expr | - | `1<CR>` | key | c.direct | i.direct | C_DIRECT | I_DIRECT |
| 41 | e.p.edit | register | `<Space>` | `<Tab>` | key | p | p | P_PROMPT | P_PROMPT |
| 42 | e.p.ok | register | `<Space>` | `<CR>` | key | p | i.henkan | P_PROMPT | I_SELECT |
| 43 | e.p.cancel | register | `<Space>` | `<Esc>` | key | p | i.henkan | P_PROMPT | I_SELECT |
| 44 | e.t.chars | terminal | - | `a` | key | t.direct | t.direct | T_DIRECT | T_DIRECT |
| 45 | e.t.normal | terminal | - | `<C-\><C-n>` | key | t.direct | t.normal | T_DIRECT | T_NORMAL |
| 46 | e.t.back | terminal | `<C-\><C-n>` | `i` | key | t.normal | t.direct | T_NORMAL | T_DIRECT |
| 47 | e.safe_state | insert | `Kan` | `<C-c>` | event | n.wait | n.off | N_WAIT | N_OFF |
| 48 | e.enable.insert | none | - | `i<Plug>(skkeleton-enable)` | key | n.off | i.direct | N_OFF | I_DIRECT |
| 49 | e.enable.cmdline | none | - | `:<Plug>(skkeleton-enable)` | key | n.off | c.direct | N_OFF | C_DIRECT |

## ノードと状態クラスの対応

| 図のノード | この探索器の状態クラス | 注意 |
|---|---|---|
| n.off | N_OFF | |
| n.wait | N_WAIT | `<C-c>` のあと `SafeState` までの間だけ。1 キーごとのスナップショットには残らないので、`ModeChanged` の時点で写す |
| n.lost | N_OFF | WinLeave / BufLeave のあとは `g:skkeleton#state` も extmark も空になり、N_OFF と区別できない。遷移の入力と結果だけを再現する |
| n.visual | V_PRE | |
| i.direct | I_DIRECT | 打ちかけのローマ字だけの状態は I_ROMAJI（#184 で I_PENDING から改名） |
| i.henkan_pt | I_POINT | 打ちかけのローマ字（`▽k`）は I_ROMAJI、読みが入った `▽かn` は I_POINT |
| i.henkan | I_SELECT | |
| i.any | 前置きの状態 | 図の「どの状態からでも」は、前置きの観測をそのまま使う |
| ni | NI | |
| ic | IC | |
| r.off | R_OFF | |
| r.mid | R_OFF | `<C-o>R` のあとは skk が無効になり、pre-edit も無い。R_OFF と区別できない |
| c.direct | C_DIRECT | |
| c.henkan | C_POINT | cmdline の ▽ と ▼ はどちらも C_POINT |
| c.cr | C_REPLACE | |
| p | P_PROMPT | |
| t.direct | T_DIRECT / T_POINT | 読みが出ているときは T_POINT |
| t.normal | T_NORMAL | |

## 再現で分かったこと

- `e.cc` と `e.safe_state` の `n.wait` は、`<C-c>` のあと `SafeState` が走るまでの一時的な状態です。`--notes` は `ModeChanged` と `SafeState` の時点で観測を写し、`N_WAIT` のあとに `N_OFF` が来ることを確かめます。
- `e.mouse` はヘッドレスでも `nvim_input_mouse` で同じウィンドウのクリックを送れます。文字のある行でクリックすると、guard が pre-edit を確定してからカーソルが動きます。
- `e.paste` は `vim.paste` を呼びます。`e.stale` は skk を通さずにバッファを書き換えて、`TextChangedI` のずれ検出を起こします。
- `e.cmdline_from_insert` の `<C-o>:` は、この探索器では `C_POINT` になります。図の `c.direct` は cmdline の pre-edit を本物の文字として持つ状態で、観測した `C_POINT` と名前が違うだけです。
- `e.visual_out` の `<Esc>` は、この探索器では `I_POINT` になります。visual を抜けたあとも insert に戻って pre-edit が残るためです。
- `e.c.expr.return` は、`c.direct` を経由する間が 1 キーごとのスナップショットに残りません。insert から `<C-r>=1<CR>` を流し、insert に戻ることを確かめます。
- `e.winleave` は `<C-o>:stopinsert<CR>` で代わりに確かめます。WinLeave / BufLeave そのものは、別のウィンドウやバッファを作らないと起こせません。

## この表について

この表は、`#185` の完了条件にある「NOTES の 49 遷移」を、#179 の調査で使った状態遷移図の `edges`（49 本）に合わせて書き直したものです。図の節点の名前と `semantics/GLOSSARY.md` の状態クラスは同じではないので、上の対応表で結び付けています。`semantics/model/model.lua` ができたら、状態クラスの粒度とこの表を突き合わせます。

## 補完の観測（#190）

組み込みの補完（`completion` プロファイル）と blink.cmp（`blink` / `blink_buffer` プロファイル）の観測です。`completion` は前の表の `e.builtin_completion` / `e.ic.accept` を含みます。`blink` を使うには `.tests/blink.cmp` か `BLINK_PATH` が要ります（観測のためだけに入れ、リポジトリには入れません）。

```sh
nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --profile completion --replay "Kan,<C-n>,<CR>"
nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --profile blink --replay "Kanj,<Tab>"
nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --profile blink_buffer --replay "Kanji,<CR>,Kan,<C-j>"
```

- `completion` は `あいうえお` の次の行から始めます。`<C-n>` / `<C-p>` / `<C-x><C-n>` で `ic` に入り、その時点で pre-edit が消えます。`<C-x>` だけでは `ix` のキー待ちになり、pre-edit は残ります。
- `blink` は `あいうえお` の次の行から始めます。`sources.default` は README の静的な一覧ではなく、#24 の再現用に関数にして（有効なら skkeleton、無効なら buffer）、その関数のまま観測します。メニューは `User skkeleton-handled` で開くので、`observe.lua` は blink の浮動ウィンドウの `row` / `col` も残します（#143、#174）。
- `blink_buffer` は無効のあいだに buffer のメニューを出したあと、`<C-j>`（`<Plug>(skkeleton-enable)` に割り当て）で有効にします（#24）。
- blink のメニューはタイマーで開くので、`blink` / `blink_buffer` のプロファイルは 1 キーごとに 100ms 待ってから観測します。

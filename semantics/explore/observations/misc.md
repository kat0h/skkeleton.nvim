# 貼り付け・マウス・ホイール・WinLeave / BufLeave の観測（#191 / 07e）

`misc.jsonl` は、`semantics/explore/misc.lua` で取った観測です（49 件。この環境では 49 件とも期待どおり）。1 行が 1 つの出来事で、その前後の状態クラス（`semantics/GLOSSARY.md`）と、比べるための値（`vim_mode`、`enabled`、`preedit`、バッファ、カーソル、マッピング）を残しています。

子の nvim は `tests/helpers.lua` の `e2e_set`（一時ディレクトリの辞書、`HISTFILE=/dev/null`、インジケータと補完は無効）です。`vim.paste` と `nvim_input_mouse` は、キーではないので子の Lua から起こしています。

```sh
flock /tmp/heavy.lock timeout 900 nvim --headless -u NONE -i NONE -l semantics/explore/misc.lua
```

キーの観測（guard が確定するキーと `<C-@>`、`<C-a>`）は、`explore.lua` でも同じキー列を流せます。

```sh
nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua \
  --replay '<Plug>(skkeleton-enable),Kan,<C-.>' --profile insert
```

この部分のアルファベットでの幅優先探索は、次のように流します。

```sh
flock /tmp/heavy.lock timeout 600 nvim --headless -u NONE -i NONE \
  -l semantics/explore/explore.lua --bfs --profile insert \
  --alphabet 'K,Kan,<C-.>,<F5>,<S-CR>,<Left>,<C-Left>,<S-Up>,<S-F1>,<Tab>,<C-a>,<C-@>,<Insert>,<Esc>,<C-c>,<C-o>,<C-n>,<Space>' \
  --depth 2 --max-sequences 300
```

このアルファベットでの幅優先は、198 遷移を広げて 437 行を観測し、状態クラスは 10 種類（`I_DIRECT`、`I_ROMAJI`、`I_POINT`、`I_SELECT`、`I_OFF`、`N_OFF`、`NI`、`IC`、`P_PROMPT`、`R_OFF`）になった。

## 準備

- `insert`: `i` のあと `<Plug>(skkeleton-enable)`。
- `off`: `i` だけ（skkeleton は無効）。
- `mouse`: `abcdef` の行の `f` の上で insert にして有効化する。
- `two_windows`: `new` で下にウィンドウを作ってから上に戻り、上で insert にして有効化する。
- `two_buffers`: 別のバッファを作ってから元のバッファに戻り、insert にして有効化する。

## 観測

| # | シナリオ | 前 | 出来事 | 後 | モデルの遷移 |
| ---: | --- | --- | --- | --- | --- |
| 1 | `paste.direct` | I_DIRECT | `vim.paste` | I_DIRECT | `t.I_DIRECT.paste` |
| 2 | `paste.romaji` | I_ROMAJI | `vim.paste` | I_DIRECT | `t.I_ROMAJI.paste` |
| 3 | `paste.point` | I_POINT | `vim.paste` | I_DIRECT | `t.I_POINT.paste` |
| 4 | `paste.select` | I_SELECT | `vim.paste` | I_DIRECT | `t.I_SELECT.paste` |
| 5 | `paste.off` | I_OFF | `vim.paste` | I_OFF | `t.I_OFF.paste` |
| 6 | `paste.chunks` | I_POINT | phase 1 / 2 / 3 の `vim.paste` | I_DIRECT | `t.I_POINT.paste` |
| 7 | `mouse.click.end` | I_POINT | 同じ位置をクリック | I_POINT | `t.I_POINT.mouse_click.keep` |
| 8 | `mouse.click.left` | I_POINT | 左の列をクリック | I_DIRECT | `t.I_POINT.mouse_click` |
| 9 | `mouse.click.romaji` | I_ROMAJI | 左の列をクリック | I_DIRECT | `t.I_ROMAJI.mouse_click` |
| 10 | `mouse.click.select` | I_SELECT | 左の列をクリック | I_DIRECT | `t.I_SELECT.mouse_click` |
| 11 | `mouse.click.direct` | I_DIRECT | 左の列をクリック | I_DIRECT | `t.I_DIRECT.mouse_click` |
| 12 | `mouse.click.off` | I_OFF | 左の列をクリック | I_OFF | `t.I_OFF.mouse_click` |
| 13 | `mouse.dclick.direct` | I_DIRECT | ダブルクリック | N_OFF | `t.I_DIRECT.mouse_select` |
| 14 | `mouse.dclick.point` | I_POINT | ダブルクリック | N_OFF | `t.I_POINT.mouse_select` |
| 15 | `mouse.dclick.select` | I_SELECT | ダブルクリック | N_OFF | `t.I_SELECT.mouse_select` |
| 16 | `mouse.dclick.off` | I_OFF | ダブルクリック | N_OFF | `t.I_OFF.mouse_select` |
| 17 | `mouse.drag.point` | I_POINT | 押下・ドラッグ・離す | N_OFF | `t.I_POINT.mouse_select` |
| 18 | `mouse.otherwin.point` | I_POINT | 別のウィンドウをクリック | I_OFF | `t.I_POINT.mouse_click_other`（gap） |
| 19 | `mouse.otherwin.romaji` | I_ROMAJI | 別のウィンドウをクリック | I_OFF | `t.I_ROMAJI.mouse_click_other`（gap） |
| 20 | `mouse.otherwin.select` | I_SELECT | 別のウィンドウをクリック | I_OFF | `t.I_SELECT.mouse_click_other`（gap） |
| 21 | `mouse.otherwin.direct` | I_DIRECT | 別のウィンドウをクリック | I_OFF | `t.I_DIRECT.mouse_click_other` |
| 22 | `wheel.up.point` | I_POINT | ホイール上 | I_POINT | `t.I_POINT.wheel` |
| 23 | `wheel.down.point` | I_POINT | ホイール下 | I_POINT | `t.I_POINT.wheel` |
| 24 | `wheel.up.romaji` | I_ROMAJI | ホイール上 | I_ROMAJI | `t.I_ROMAJI.wheel` |
| 25 | `wheel.up.select` | I_SELECT | ホイール上 | I_SELECT | `t.I_SELECT.wheel` |
| 26 | `wheel.up.direct` | I_DIRECT | ホイール上 | I_DIRECT | `t.I_DIRECT.wheel` |
| 27 | `wheel.up.off` | I_OFF | ホイール上 | I_OFF | `t.I_OFF.wheel` |
| 28 | `winleave.point` | I_POINT | `:wincmd w` | I_OFF | `t.I_POINT.winleave`（gap） |
| 29 | `winleave.direct` | I_DIRECT | `:wincmd w` | I_OFF | `t.I_DIRECT.winleave` |
| 30 | `winleave.new.point` | I_POINT | `:new` | I_OFF | `t.I_POINT.winleave`（gap） |
| 31 | `winleave.visual.mouse` | V_PRE | 別のウィンドウをクリック | I_OFF | `t.V_PRE_POINT.mouse_click_other`（gap） |
| 32 | `bufleave.point` | I_POINT | 別のバッファへ `:buffer!` | I_OFF | `t.I_POINT.bufleave`（gap） |
| 33 | `bufleave.direct` | I_DIRECT | 別のバッファへ `:buffer!` | I_OFF | `t.I_DIRECT.bufleave` |
| 34 | `guard.point.cdot` | I_POINT | `<C-.>` | I_DIRECT | `t.I_POINT.guard_special` |
| 35 | `guard.point.f5` | I_POINT | `<F5>` | I_DIRECT | `t.I_POINT.guard_special` |
| 36 | `guard.point.s-cr` | I_POINT | `<S-CR>` | I_DIRECT | `t.I_POINT.guard_special` |
| 37 | `guard.point.left` | I_POINT | `<Left>` | I_DIRECT | `t.I_POINT.guard_special` |
| 38 | `guard.point.c-left` | I_POINT | `<C-Left>` | I_DIRECT | `t.I_POINT.guard_special` |
| 39 | `guard.point.s-up` | I_POINT | `<S-Up>` | I_DIRECT | `t.I_POINT.guard_special` |
| 40 | `guard.point.s-f1` | I_POINT | `<S-F1>` | I_DIRECT | `t.I_POINT.guard_special` |
| 41 | `guard.select.left` | I_SELECT | `<Left>` | I_DIRECT | `t.I_SELECT.guard_special` |
| 42 | `guard.romaji.cdot` | I_ROMAJI | `<C-.>` | I_DIRECT | `t.I_ROMAJI.guard_special` |
| 43 | `guard.direct.cdot` | I_DIRECT | `<C-.>` | I_DIRECT | `t.I_DIRECT.guard_special` |
| 44 | `guard.off.cdot` | I_OFF | `<C-.>` | I_OFF | `t.I_OFF.guard_special` |
| 45 | `ctrl-at.point` | I_POINT | `<C-@>` | N_OFF | `t.I_POINT.ctrl_at` |
| 46 | `ctrl-at.select` | I_SELECT | `<C-@>` | N_OFF | `t.I_SELECT.ctrl_at` |
| 47 | `ctrl-at.direct` | I_DIRECT | `<C-@>` | N_OFF | `t.I_DIRECT.ctrl_at` |
| 48 | `ctrl-at.off` | I_OFF | `<C-@>` | N_OFF | `t.I_OFF.ctrl_at` |
| 49 | `ctrl-a.empty` | I_POINT | `<C-a>` | I_POINT | `t.I_POINT.ctrl_a.e29` |

## 分かったこと（モデルと観測の差）

1. **WinLeave / BufLeave の後は I_OFF。** insert から `:new`、`:wincmd w`、別のバッファへ `:buffer!`、別のウィンドウのクリックをすると、Vim は insert のまま skkeleton だけが無効になる。モデルは N_OFF にしていたので I_OFF に直した。読みは確定せずに捨てる（#169 の gap）。
2. **BufLeave はバッファが実際に変わったときだけ。** `:enew` を空の無名バッファでしてもバッファは変わらず、BufLeave も来ない。観測では `:buffer!` で確かめた。
3. **同じウィンドウのクリックは、カーソルが動いたときだけ確定する。** 同じ位置のクリックでは CursorMovedI が来ないので pre-edit が残る。別のウィンドウのクリックは WinLeave で読みを捨て、I_OFF になる（#169）。
4. **ダブルクリックとドラッグは N_OFF。** ダブルクリックでは確定した読みがクリックした列に入り、ドラッグでは pre-edit の位置に入る（観測）。文字の位置は状態クラスに持っていないので、`oos.mouse_coords` にした。
5. **貼り付けは最初のチャンクでだけ確定する。** `vim.paste` を phase 1・2・3 に分けて呼ぶと、phase 1 で かん を確定し、phase 2 は確定しない。読みがローマ字の打ちかけだけのときは、そのままの文字（k）を確定する。I_OFF ではバッファを書き換えるだけ。undo のまとまりは P1–P15 の外（`oos.paste_undo`）。
6. **ホイールは確定しない。** スクロールはカーソルを動かさないので、pre-edit が残る。
7. **guard が確定するキーは、確定してからキーを流す。** `<C-.>`・`<F5>`・`<S-CR>`・`<Left>`・`<C-Left>`・`<S-Up>`・`<S-F1>` で確かめた。`<C-@>` は確定したあと E29 で insert を抜けるので、N_OFF になる（モデルは I_DIRECT にしていたので直した）。
8. **`<C-a>` は前に挿入した文字が無いと E29 で何も変わらない。** 読みは残る。前に挿入した文字があるときは、その文字が入って読みが捨てられる（keys.md §6）。両方を遷移にした。
9. **visual / insert-normal からの WinLeave は、観測では mode が niI で無効になった。** モデルには NI_OFF が無いので、N_OFF への遷移のまま `unknown` にし、note に書いた。
10. **cmdline の WinLeave（#46）は 07a（#187）の範囲。** このモデルは insert / normal / visual / replace だけを書いているので、`oos.cmdline_winleave` にした。

## 過去の issue との対応

| issue | 状態 | このモデルでの扱い |
| ---: | --- | --- |
| #57 | CLOSED | 貼り付けの遷移は `paste`。undo の区切りは P1–P15 の外なので `oos.paste_undo`。観測では u 1 回で貼り付け以降だけが戻り、打った読みは残った |
| #125 | CLOSED | `t.I_POINT.paste` と `t.I_SELECT.paste` で、貼る前に確定する（ok）。再現キー列は `replay.paste.point` / `replay.paste.select` |
| #46 | CLOSED | cmdline の中なので 07a。`oos.cmdline_winleave` |
| #47 | CLOSED | マウスの遷移は `mouse_click` / `mouse_select` / `mouse_click_other`。再現の並びは `replay.mouse.47`。インジケータの位置は表示の層なので `oos.mouse_position` |
| #169 | OPEN | WinLeave / BufLeave / 別ウィンドウのクリックで読みを捨てる。P1 の known（gap） |

## モデルに足したもの

- イベント: `mouse_click_other`。`mouse_click` から `<DragRight>` を `mouse_select` に移した。
- 遷移: `paste`（I_DIRECT / I_ROMAJI / I_POINT / I_SELECT / I_OFF）、`mouse_click` と `mouse_click.keep`、`mouse_click_other`、`mouse_select`、`wheel`、`winleave` / `bufleave`（I_* は I_OFF へ）、`guard_special`、`ctrl_at`、`ctrl_a.e29`。
- 観測: `O-paste-*`、`O-ctrl-at-*`、`O-ctrl-a-e29`、`O-guard-*`、`O-wheel-point`。
- 再現: `replay.paste.point`、`replay.paste.select`、`replay.paste.57`、`replay.mouse.otherwin`、`replay.mouse.select`、`replay.mouse.47`。
- 対象外: `oos.cmdline_winleave`、`oos.mouse_position`、`oos.paste_undo`、`oos.mouse_coords`。

## 掘り残し

- ダブルクリックで確定した読みがクリックした列に入るのは、状態クラスではなく位置の話。P2 の層なので、このモデルでは追っていない。
- visual / insert-normal からの WinLeave の後の `niI` は、NI_OFF を作るかどうかを決めていない。
- マウスのドラッグはヘッドレスでたまにイベントが落ちる。`misc.lua` は `mouse.drag.point` だけ 3 回まで試す。それでも合わなければ JSONL の `ok=false` で分かる。
- cmdline / terminal の中の貼り付け・マウスは、07a / 07b のモデルに任せる。

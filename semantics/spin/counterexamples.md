# 反例と、実機での再生（#193）

`semantics/spin/model.pml` を SPIN で調べ、P1（読みが黙って消えない）の反例を `semantics/explore/explore.lua --replay` で実機に流した結果です。profile `insert` は insert に入って skkeleton を有効にした状態から始まるので、モデルの遷移列の先頭 `t.N_OFF.enable`（`<Plug>(skkeleton-enable)`）は再生では省いています。

再生のしかた（リポジトリの一番上で）:

```sh
make deps
MINI_PATH=.tests/mini.nvim nvim --headless -u NONE -i NONE \
  -l semantics/explore/explore.lua --replay "<キー列>" --profile insert
```

`explore.lua` は一時ディレクトリの辞書と `HISTFILE=/dev/null` を使う。出力の「最後:」が、流したあとの観測（状態クラス、モード、enabled、phase、preedit）。

## 実機で読みが消えたもの（P1 の違反）

いずれも insert で `▽かn`（preedit `▽かn`、phase `input:okurinasi`）を出してから、下のキーを 1 つ流したものです。モデルでは `I_POINT` から読みを捨てる遷移です。

| 遷移 | SPIN の遷移列 | 再生のキー列 | 再生後の観測 | 既知 |
| --- | --- | --- | --- | --- |
| `t.I_POINT.ctrl_r` | `t.N_OFF.enable → t.I_DIRECT.char_shift.point → t.I_POINT.ctrl_r` | `K,a,n,<C-r>a` | `I_DIRECT`、enabled=false、preedit="" | △ #8 #12 |
| `t.I_POINT.ctrl_k` | `t.N_OFF.enable → t.I_DIRECT.char_shift.point → t.I_POINT.ctrl_k` | `K,a,n,<C-k>a:` | `I_DIRECT`、enabled=false、preedit="" | △ #8 #12 |
| `t.I_POINT.tab` | `t.N_OFF.enable → t.I_DIRECT.char_shift.point → t.I_POINT.tab` | `K,a,n,<Tab>` | `I_DIRECT`、enabled=true、preedit="" | △ keys.md §6 |
| `t.I_POINT.ctrl_t` | `t.N_OFF.enable → t.I_DIRECT.char_shift.point → t.I_POINT.ctrl_t` | `K,a,n,<C-t>` | `I_DIRECT`、enabled=true、preedit="" | △ keys.md §6 |
| `t.NI_POINT.return_drop` | `t.N_OFF.enable → t.I_DIRECT.char_shift.point → t.I_POINT.ctrl_o → t.NI_POINT.return_drop` | `a,K,a,n,<C-o>,x` | `I_DIRECT`、enabled=true、preedit="" | △ #199 |

`t.NI_POINT.return_drop` は、バッファに文字が無いと `x` が何も変えず、読みも消えません。先に `a` で 1 文字置いてから流しています。

`ctrl_r` / `ctrl_k` は、読みが消えるだけでなく enabled=false（モデルの `I_DIRECT` ではなく `I_OFF`）になりました。モデルの遷移先と実機が違う点として残します。

## 実機では読みが残ったもの（モデルの誤り）

`M.known` には P1 として入っていますが、実機では preedit が残りました。モデルの遷移（`drop` / `clear_extmark`）が今の振る舞いと合っていません。`model.lua` はこのタスクでは直しません（04 の持ち物）。

| 遷移 | 再生のキー列 | 再生後の観測 | モデルの遷移 |
| --- | --- | --- | --- |
| `t.I_POINT.ctrl_a` | `K,a,n,<C-a>` | `I_POINT`、preedit="▽かn" | `I_DIRECT`（drop） |
| `t.I_POINT.ctrl_w` | `K,a,n,<C-w>` | `I_POINT`、preedit="▽かn" | `I_DIRECT`（drop） |
| `t.I_POINT.ctrl_u` | `K,a,n,<C-u>` | `I_POINT`、preedit="▽かn" | `I_DIRECT`（drop） |
| `t.I_POINT.completion_open` | `K,a,n,<C-n>` | `IC`、preedit="▽かn" | `IC`（drop + clear_extmark） |

`I_POINT.completion_open` は状態クラスはモデルと同じ `IC` ですが、pre-edit は消えていません。07d（#190）の範囲です。

## モデルの `I_ROMAJI` と実機の見え方

モデルの `I_ROMAJI` は「direct でローマ字の打ちかけ（`state.feed`）がある」状態ですが、実機で `K` を押すと `▽k`（phase `input:okurinasi`）になり、`explore.lua` の `classify` は `I_PENDING` を返します。`a` を押すと `▽か`（`I_POINT`）です。`I_ROMAJI` の遷移を再生するときは、`K` のあとに `a` などを足して `I_POINT` にしたほうが実機の観測と合います。モデルと観測の対応は 06（#186）で見る話として残します。

## 分類

- `ctrl_r` / `ctrl_k` / `Tab` / `C-t` / `NI_POINT.return_drop` の 5 本は、実機でも読みが消えた。P1 の既知の gap（△）で、新しいバグではない。
- `ctrl_a` / `ctrl_w` / `ctrl_u` / `completion_open` の 4 本は、実機では読みが残った。モデルの誤り。
- SPIN が見つけた P1 の遷移は 36 件で、Lua の `model_check.lua` の 36 件と一致した。知らない違反（✗）は無い。

## SPIN が見つけた P1 の 36 件

SPIN の探索で 36 件すべてに到達した。Lua の `model_check.lua` が出す 36 件と同じで、すべて `M.known`。遷移列とキー列は `check.lua` の出力に出る。上の「モデルの誤り」の 4 件も、この 36 件に含まれている。

| 遷移 | 既知 |
| --- | --- |
| `t.I_ROMAJI.bufleave` | #169 |
| `t.I_ROMAJI.completion_open` | #18, #19, #190 |
| `t.I_ROMAJI.ctrl_a` | keys.md §6 |
| `t.I_ROMAJI.ctrl_at` | #56, keys.md §6 |
| `t.I_ROMAJI.ctrl_k` | #8, #12 |
| `t.I_ROMAJI.ctrl_r` | #8, #12, #20 |
| `t.I_ROMAJI.ctrl_t` | keys.md §6 |
| `t.I_ROMAJI.ctrl_u` | #8, #12 |
| `t.I_ROMAJI.ctrl_v` | #8, #12 |
| `t.I_ROMAJI.ctrl_w` | #8, #12 |
| `t.I_ROMAJI.stale.buffer` | #8, #12 |
| `t.I_ROMAJI.tab` | #8, #12 |
| `t.I_ROMAJI.winleave` | #169 |
| `t.I_POINT.bufleave` | #169 |
| `t.I_POINT.ctrl_a` | keys.md §6 |
| `t.I_POINT.ctrl_at` | #56, keys.md §6 |
| `t.I_POINT.ctrl_k` | #8, #12 |
| `t.I_POINT.ctrl_r` | #8, #12, #20 |
| `t.I_POINT.ctrl_t` | keys.md §6 |
| `t.I_POINT.ctrl_u` | #8, #12 |
| `t.I_POINT.ctrl_v` | #8, #12 |
| `t.I_POINT.ctrl_w` | #8, #12 |
| `t.I_POINT.stale.buffer` | #8, #12 |
| `t.I_POINT.tab` | #8, #12 |
| `t.I_POINT.winleave` | #169 |
| `t.I_SELECT.bufleave` | #169 |
| `t.I_SELECT.completion_open` | #18, #19, #190 |
| `t.I_POINT.completion_open` | #18, #19, #190 |
| `t.I_SELECT.stale.buffer` | #8, #12 |
| `t.I_SELECT.winleave` | #169 |
| `t.NI_POINT.return_drop` | #199 |
| `t.NI_POINT.winleave` | #169 |
| `t.NI_SELECT.return_drop` | #199 |
| `t.NI_SELECT.winleave` | #169 |
| `t.V_PRE_POINT.winleave` | #169 |
| `t.V_PRE_SELECT.winleave` | #169 |

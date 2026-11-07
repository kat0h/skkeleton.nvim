# 反例と、実機での再生（#193）

`semantics/spin/model.pml` を SPIN で調べ、P1（読みが黙って消えない）の反例を `semantics/explore/explore.lua --replay` で実機に流した結果です。profile `insert` は insert に入って skkeleton を有効にした状態から始まるので、モデルの遷移列の先頭 `t.N_OFF.enable`（`<Plug>(skkeleton-enable)`）は再生では省いています。

再生のしかた（リポジトリの一番上で）:

```sh
make deps
MINI_PATH=.tests/mini.nvim nvim --headless -u NONE -i NONE \
  -l semantics/explore/explore.lua --replay "<キー列>" --profile insert
```

`explore.lua` は一時ディレクトリの辞書と `HISTFILE=/dev/null` を使う。出力の「最後:」が、流したあとの観測（状態クラス、モード、enabled、phase、preedit）。

`--profile` で開始時のバッファを変えられます。`insert` は空バッファ、`mouse` は行に `abcdef` を置いた insert です。同じキー列を両方の profile で流すと、バッファ条件で結果が分かれるかを見られます。`<C-a>` の「入れる文字あり」は、直前に入れた文字列が要るので、`explore.lua` では用意していません（下の表の観測は、`. レジスタ` に `PQ` を入れてから同じキー列を流したものです）。

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

## 実機では読みが残ったもの

最初の再生は空バッファ（profile `insert`）で流しました。同じキー列を、行に `abcdef` を置く profile `mouse` でも流すと、結果がバッファ条件で分かれます。`<C-w>` / `<C-u>` は文字があると `I_DIRECT`・preedit 空になり、`<C-a>` も入れる文字（直前に入れた文字列）があると `I_DIRECT`・preedit 空になります。

| 遷移 | バッファ条件 | 再生のキー列 | 再生後の観測 | モデルの遷移 | 扱い |
| --- | --- | --- | --- | --- | --- |
| `t.I_POINT.ctrl_w` | 空バッファ | `K,a,n,<C-w>`（profile `insert`） | `I_POINT`、preedit="▽かn" | `t.I_POINT.ctrl_w.keep` | モデルどおり（keep） |
| `t.I_POINT.ctrl_w` | 文字あり | `K,a,n,<C-w>`（profile `mouse`） | `I_DIRECT`、preedit="" | `t.I_POINT.ctrl_w` | モデルどおり（drop） |
| `t.I_POINT.ctrl_u` | 空バッファ | `K,a,n,<C-u>`（profile `insert`） | `I_POINT`、preedit="▽かn" | `t.I_POINT.ctrl_u.keep` | モデルどおり（keep） |
| `t.I_POINT.ctrl_u` | 文字あり | `K,a,n,<C-u>`（profile `mouse`） | `I_DIRECT`、preedit="" | `t.I_POINT.ctrl_u` | モデルどおり（drop） |
| `t.I_POINT.ctrl_a` | 入れる文字なし | `K,a,n,<C-a>`（profile `insert`） | `I_POINT`、preedit="▽かn"、バッファは変わらない（E29） | keep の遷移が無い | モデルに遷移が無い |
| `t.I_POINT.ctrl_a` | 入れる文字あり | `K,a,n,<C-a>`（`. レジスタ` に `PQ`） | `I_DIRECT`、preedit=""、バッファ `abcPQ` | `t.I_POINT.ctrl_a` | モデルどおり（drop） |
| `t.I_POINT.completion_open` | 空バッファ | `K,a,n,<C-n>` | `IC`、preedit="▽かn" | `t.I_POINT.completion_open`（drop + clear_extmark） | モデルの誤り |

`ctrl_w` / `ctrl_u` は、消す文字が無いときは `model.lua` の `t.I_POINT.ctrl_w.keep` / `ctrl_u.keep` を通り（`keys.md` §6 補足）、文字があるときは drop の遷移を通ります。どちらもモデルの遷移どおりで、実機と合っています。モデルの誤りではありません。

`ctrl_a` は、入れる文字が無いときだけ preedit が残ります。バッファに文字があっても、入れる文字が無ければ同じです（E29: No inserted text yet）。`model.lua` にはこの keep の遷移が無いので、「drop が誤り」ではなく「入れる文字が無いときの遷移が無い」が正確です。drop の遷移（`t.I_POINT.ctrl_a`）は実機と合っています。

`I_POINT.completion_open` は状態クラスはモデルと同じ `IC` ですが、pre-edit は消えていません。モデルの遷移（drop + clear_extmark）が実機と合っていないので、これはモデルの誤りです。07d（#190）の範囲です。`model.lua` はこのタスクでは直しません（04 の持ち物）。

## モデルの `I_ROMAJI` と実機の見え方

モデルの `I_ROMAJI` は「direct でローマ字の打ちかけ（`state.feed`）がある」状態ですが、実機で `K` を押すと `▽k`（phase `input:okurinasi`）になり、`explore.lua` の `classify` は `I_PENDING` を返します。`a` を押すと `▽か`（`I_POINT`）です。`I_ROMAJI` の遷移を再生するときは、`K` のあとに `a` などを足して `I_POINT` にしたほうが実機の観測と合います。モデルと観測の対応は 06（#186）で見る話として残します。

## 分類

- `ctrl_r` / `ctrl_k` / `Tab` / `C-t` / `NI_POINT.return_drop` の 5 本は、実機でも読みが消えた。P1 の既知の gap（△）で、新しいバグではない。
- `ctrl_w` / `ctrl_u` は、空バッファでは keep、文字があると drop で、どちらも `model.lua` の遷移どおり。モデルの誤りではない。
- `ctrl_a` は、drop の遷移はモデルどおりで、入れる文字が無いときの keep の遷移がモデルに無い。
- `completion_open` は状態クラスはモデルと同じ `IC` だが、pre-edit を消す遷移が実機と合わない。モデルの誤り（07d / #190）。
- SPIN が見つけた P1 の遷移は 36 件で、Lua の `model_check.lua` の 36 件と一致した。知らない違反（✗）は無い。

## SPIN が見つけた P1 の 36 件

SPIN の探索で 36 件すべてに到達した。Lua の `model_check.lua` が出す 36 件と同じで、すべて `M.known`。遷移列とキー列は `check.lua` の出力に出る。上の表の 4 つの遷移（`ctrl_a` / `ctrl_w` / `ctrl_u` / `completion_open`）も、この 36 件に含まれている。

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

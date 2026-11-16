# core と UI の分け方の提案

[CORE.md](CORE.md) を書くために core を読んだので、その読みを使って今の設計を見ました（#260）。コードは変えていません。行番号は main の c2a78ff のものです。

読んだのは core のファイルと `main.lua`、`host.lua` です。`render`、`cleanup`、`guard`、`map`、`popup`、`completion` は中を読んでいないので、それらについては `require` の一覧から分かることだけを書いています。

## 1. 今の分け方の評価

`docs/ARCHITECTURE.md` は「core は Neovim の UI に直接触れず、`host` を通す」と決めています。入力の規則そのもの（`function/*`、`keymap`、`state`、`kana`、`okuri`、`candidate`）は、ほぼそのとおりになっていて、`vim.api` や `vim.fn` を呼ぶところは片手で数えられます。くずれているのは、次の 4 つです。

### 1.1 Vim のモードと制御文字が、確定文字列に混ざっている

core の出力は「確定する文字列」1 本で、UI への指示もその中に文字として入っています。

| 混ざっているもの | 場所 | 意味 |
|---|---|---|
| `"\b"` | `function/input.lua:202` | 確定済みの 1 文字を消す |
| `"\n"` | `function/common.lua:66` | 改行 |
| `"\x03"` | `function/common.lua:73-75` | cmdline を `<C-c>` で抜ける。`ctx.vim_mode == "c"` を core が見ている |
| `"\x07u"` | `context.lua:36-38` | undo の区切り。`ctx.vim_mode == "i"` を core が見ている |
| `st.type = "escape"` → `"\27"` | `function/disable.lua:26`、`state.lua:148-149` | host に `<Esc>` を通させる。出力なのに状態になっている |

このため、UI が core の文字列を解釈し直しています。`main.lua:118` は、取り出した確定文字列の終わりの `\x07u` を `gsub` で削っています。

### 1.2 core の判断が UI の側にもある

| 判断 | core | UI の側 |
|---|---|---|
| 確定するか、残すか、作り直すか | `common.kakutei`、`disable.disable` | `main.lua:107-147`（enable：▼ は確定、▽ は残す、読みなしは作り直す）、`main.lua:166-176`（disable）、`main.lua:224-236`（未マップのキーでの確定） |
| 語を確定して辞書に覚える | `common.lua:20-31` | `main.lua:242-273`（補完の確定。状態を初期化し、`last_candidate` を書き、converter をかけて確定する、別の道） |
| 有効かどうか | 持っていない | `g:skkeleton#enabled` を `host.lua:23,33,162`、`main.lua:129,143,156` が書き、`main.lua:207` が読む |
| 辞書登録の入れ子 | `function/dictionary.lua:16-35` は呼ぶだけ | `host.lua:104-168`、`181-231`（Context のスタック、内側の Context を作る、戻るときにモードを戻す） |
| 公開する状態 | `mode.mode_change` | `g:skkeleton#state` を `cleanup.lua:29-43` と `host.lua:199` が書く。`g:skkeleton#mode` を `host.lua:17,30` が書く |
| 式の cmdline では登録しない（#244） | `function/henkan.lua:105` が `host.is_in_expression()` を聞く | `host.lua:63-65`。`docs/ARCHITECTURE.md` の host の一覧には無い |

### 1.3 UI が core の状態を直接書き換えている

- `ctx.vim_mode`：`main.lua:81,116,121,138,151,174,217,228,259`
- `ctx.preedit`：`main.lua:118`（`take_kakutei`）、`main.lua:124-125`（`current` を移し、`do_kakutei` する）
- `ctx.state` と `ctx.last_candidate`：`main.lua:245,262`
- 今の Context：`host.lua:165`（`store.set_context`）、`host.lua:197`（`store.init_context`）
- `require` の一覧では、`cleanup` が `function.common`・`mode`・`store` を、`render/cmdline` と `completion` が `store` を使っています（中は読んでいません）。

### 1.4 機械の外に状態がある

- 今のかなテーブルの名前：`kana/init.lua:94`（`kana.current_name`）。`state.initialize` がここからテーブルを取ります（`state.lua:56`）。
- 前に使っていたモード：`store.lua:9-11`（`last_mode`）
- `PreEdit.current`（`preedit.lua`）：前回 cmdline に書いた文字列。描画の状態が core の Context に入っています。`PreEdit:output` は `vim.fn.strcharlen` を呼びます（`preedit.lua:41`）。

もう 1 つ、`host.lua` は「core から UI へ出る口」と「その Neovim での実装」を兼ねています。`mode.lua` と `function/{common,henkan,disable,dictionary}.lua` は `host` を `require` し、`host` は `map`・`render`・`popup`・`completion`・`main` を呼ぶので、core のモジュールを読み込むと UI までつながります。単体テストでは `tests/core_helpers.lua` の `spy_host` が関数を差し替えて切っています。

## 2. ほどよい境界の提案

層は増やしません。core が外に見せる関数を 3 つにし、UI はその結果を Neovim に写すだけにします。

### 2.1 境界の型

```lua
-- lua/skkeleton/engine.lua（vim.* を使わない）
engine.new(session) -> σ                -- session = { last_mode, table }。機械の外にあった値を持つ
engine.step(σ, event, env) -> effects   -- σ を進める
engine.observe(σ) -> { enabled, phase, henkanFeed, preedit, segments, mode }

-- event（入力）
{ type = "key", key = "<space>" }                         -- 正規化したキー
{ type = "enable" } / { type = "disable" }                -- toggle は UI が observe(σ).enabled を見て決める
{ type = "commit" }                                       -- 未マップのキーの前の確定（#56）
{ type = "complete", kana = ..., word = ..., kind = ... } -- 補完で選んだ語

-- env（遷移の外から与えるもの）
{ lib = Library, input = fn(prompt) -> string?, confirm = fn(msg) -> boolean, can_prompt = boolean }

-- effects（出力。順に並んだ配列）
{ "commit", "かな" }        -- 確定する文字だけ。制御文字は混ぜない
{ "delete_back" }           -- 確定済みの 1 文字を消す（今の "\b"）
{ "newline" }               -- 今の "\n"
{ "undo_point" }            -- 今の "\x07u"。出すかどうかは UI が Vim のモードで決める
{ "abort" }                 -- 今の "\x03"。cmdline のときだけ UI が <C-c> にする
{ "pass_key", "<Esc>" }     -- 今の st.type = "escape"
{ "candidates", lines, meta }
{ "keep_state" }            -- keepState の予約
```

- 設定 C は今と同じく `config.options` を読みます。引数にはしません（差分を小さくするため）。
- `engine.observe` は `model.lua` の `M.observe` と同じ形です。`engine.step` に同じキー列を流せば、参照モデルとの差分テストがそのまま書けます（[VERIFY.md](VERIFY.md) の §1 の、`ctx` から観測を組み立てる部分が要らなくなります）。
- `g:skkeleton#enabled`、`g:skkeleton#mode`、`g:skkeleton#state`、`User` イベントは、UI の 1 つの関数が `observe(σ)` の前後の違いから出します。インジケータは今と同じく、それだけを読みます。

### 2.2 どのモジュールがどちらに入るか

| 区分 | モジュール | 変わること |
|---|---|---|
| core | `state`、`context`、`keymap`、`function/*`、`kana`、`okuri`、`candidate`、`mode`、`config`、`notation`、`util` | `vim.notify` と `vim.inspect` を外す。`ctx.vim_mode` を消す。`enabled` と今のテーブルの名前を Context に持つ |
| core | `store` | 今の Context と Library を持つだけにする。`last_mode` は `session` へ |
| core | `engine`（新しく作る。中身は今の `main.lua` の enable / disable / commit / complete の判断） | — |
| core から外す | `preedit` の `output` と `current` | `render/cmdline` へ。core に残るのは effects の配列 |
| UI | `main`、`map`、`render`、`popup`、`cleanup`、`guard`、`paste`、`completion`、`marker`、`host` の実装、`indicator` | `main` は「event を作る → `engine.step` → effects を写す → `observe` を公開する」だけになる |
| 辞書 | `dictionary/*` | 変えない |

### 2.3 host をどう減らすか

今の host には 10 個の関数があります（`docs/ARCHITECTURE.md` に載っているのは 6 個）。

| 今 | 提案 |
|---|---|
| `mode_changed`、`disable`、`show_candidates`、`keep_state_on_insert_enter` | 消す。知らせは effects と `observe` の違いで足りる |
| `input`、`confirm` | `env` に残す。答えが要るので、関数のままにする |
| `is_in_expression` | 消す。UI が `env.can_prompt` で渡す |
| `is_in_input`、`in_input_depth`、`cancel_input` | UI の中の関数にする（core は呼んでいない） |

core が `host` を `require` しなくなるので、`spy_host` は要らなくなり、テストは `env` に関数を渡すだけになります。

### 2.4 分けすぎないところ

- `kana_input` や `henkan_first` などの関数は、今の形（`ctx` を書き換える）のままにします。純粋な `step(C, D, σ, key) -> σ', out` に書き直す必要はありません。`engine.step` が入口で effects の配列を用意し、出口で返せば、外からは同じに見えます。
- 辞書登録の入れ子は、まずは今と同じ「`env.input` を呼んで待つ」のままにします。スタックを core に持つ案は §5 の D1 です。
- キーマップとかなテーブルの登録（`keymap.register`、`kana.register`）は今のままです。

## 3. 今の不具合との関係

境界を変えると起きにくくなるものです。issue の中身は読み直していないので、#260 とコードのコメントに書いてある範囲で挙げます。#199 と、#33 の打ち消した項目は、中身が分からないので挙げていません。

| 不具合 | 今の原因の形 | 境界を変えると |
|---|---|---|
| #210（変換中に enable を押すと読みが消えた） | 読みをどうするかの判断が `main.lua` にあり、core の規則と別に書かれている | enable は event になり、R-EN-05・R-EN-06 として core の規則とテストに入る |
| #241（cmdline で確定が二重に入った） | 描画の状態（`PreEdit.current`）が Context にあり、Context を作り直すと消える（`main.lua:122-125` で手で移している） | 描画の状態は `render/cmdline` が持つので、Context を作り直しても残る |
| #87・#51・#40（モードの表示と出る文字が違う） | `ctx.mode` と converter とテーブルを別々に持ち、片方だけ戻す道がある | 同じ形の破れが 3 つ残っています（R-PG-01、R-RG-01、R-RG-07）。モードを `observe` が converter とテーブルから導くようにすれば、ずれようがなくなる |
| #244（式の cmdline で登録の欄が開いて壊れた） | core が Vim の状態を host に聞く | `env.can_prompt` で外から渡す |
| #116・#12（登録の欄の取り消しの印が崩れた、▽ ごと登録された） | 取り消しを、欄の文字列に印を書いて伝えている（`host.lua:172-175`、`marker.lua`） | D1 の B にすれば、取り消しは event で伝わり、印が要らなくなる |
| #144・#170（登録の間に外の pre-edit が消えた、ちらついた） | 外の Context を退避している間、描画を止めたり戻したりする（`host.lua:189-219`） | D1 の B にすれば、外の機械はスタックの下に残り、`observe` で外の pre-edit も取れる |
| #54 の残り（登録の間の `g:skkeleton#state`） | `host.lua:199` が手で書いている | 公開する状態を書く関数が 1 つになる |

## 4. 移り方

大きな作り直しにはしません。次の順で、1 つずつ PR にできます。どの PR も動きを変えないので、既存のテストの期待値を変えずに通るはずです（変えないと通らないなら、動きが変わっています）。古い道は同じ PR で消し、互換のためのコードは足しません。

1. **差分テストを先に入れる。** [VERIFY.md](VERIFY.md) のとおり、参照モデルと今の core を比べます（`formal-semantics` の側）。これが以降の PR の安全網になります。
2. **core から `vim.*` を外す。** `function/common.lua:40,101` と `function/dictionary.lua:23` と `keymap.lua:69-70` の `vim.notify`、`mode.lua:29` の `vim.tbl_filter`。
3. **effects の配列を足し、制御文字をそこへ移す。** `"\b"`、`"\n"`、`"\x03"`、`"\x07u"`、`escape` を effects にして、`render` が解釈します。`ctx.vim_mode` と `st.type == "escape"` を消します（`g:skkeleton#state.phase` の `escape` は §5 の D3）。
4. **`PreEdit.current` と `output` を `render/cmdline` へ移す。** `main.lua:122-125` の手での引き継ぎが消えます。
5. **`enabled` を Context に持ち、enable / disable / commit / complete の判断を `main.lua` から `engine.lua` へ移す。** `main.lua` は event を作って結果を写すだけになります。
6. **今のテーブルの名前と `last_mode` を機械の中へ移す。** R-RG-07 が直ります（動きが変わるので、これは不具合の修正として別の issue と回帰テストを付けます）。
7. **host の知らせの関数を消し、公開する状態を書く関数を 1 つにする。** `docs/ARCHITECTURE.md` の host の節を書き直します。
8. **`engine.step` と `engine.observe` をテストから使う。** `tests/core_helpers.lua` の `dispatch` と `spy_host` を置き換えます。

3 と 5 が大きめです。3 は `render` の側（読んでいません）の受け口しだいなので、先に `render` を読んで、effects を 1 種類ずつ移す PR に分けられるかを見てください。

## 5. 決めてほしいこと

- **D1：辞書登録の入れ子をどこに持つか。**
  - A（推奨。まずはこちら）：今のまま、`env.input` を呼んで待つ。スタックは UI にある。差分が小さい。R-RG-01 と R-RG-07 は別々に直す。
  - B：スタックを core に持つ。`engine.step` は `{ "open_register", prompt }` を返して戻り、欄のキーは同じ `engine.step` がスタックの上の機械に流す。欄が閉じたら UI が答えの event を送る。取り消しの印と、描画を止める処理が要らなくなり、内側の `<C-g>` を 1 段ずつ戻す（CORE.md の REC-INNER-CANCEL）のも core の規則として書ける。欄の UI が `input()` のままでよいかは、`render` と `host.input` を読んで確かめる必要がある。
- **D2：補完の確定（`main.complete`）を core の event にするか。** する（推奨）なら、確定と辞書への登録の道が 1 つになります。使う人から見た動きは変わりません。しないなら、V8（確定したものが辞書に覚えられる）を守る場所が 2 つのままです。
- **D3：`g:skkeleton#state.phase` の `escape` をなくしてよいか。** `st.type == "escape"` を effects に変えると、`<Esc>` のあとの `phase` は `input` になります。公開している状態の形が変わるので、インジケータや設定がこれを読んでいるなら見える変化です。残すなら、`observe` が「`<Esc>` で抜けた直後」を別に持ちます。
- **D4：無効の間の `g:skkeleton#mode`。** 今は無効にすると `""` になり、`ctx.mode` は古い値のまま残ります。`observe` が `enabled` から導く形にしてよいか（動きは変わりません）。

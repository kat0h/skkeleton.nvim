# core の意味論の検証（次の段への引き継ぎ）

[CORE.md](CORE.md)、[rules.lua](rules.lua)、[model.lua](model.lua) は、コードを読んで書いただけで、動かしていません（構文の確認と図の生成だけしました）。この文書だけ読めば検証を始められるように書きます。

やることは 2 つです。

1. 参照モデルと実装の core を同じキー列で動かして比べる差分テストを書いて流す（§1〜§3）。
2. 確度が「推測」「分からない」の規則を、1 つずつ確かめる（§4）。

確かめたら、`rules.lua` の `confidence` を `read` に直し、違っていたら規則とモデルを直して `figures.lua` を流し直します。

## 0. 決まり

- リポジトリの `AGENTS.md` を守ります。テストは一時ディレクトリの辞書だけを使い、使う人の辞書に触りません。
- 差分テストは `semantics/core/compare/` に置き、`formal-semantics` の側だけで扱います（main には入れません）。
- 実装は main（`rules.lua` の `revision`）のものを使います。`formal-semantics` ブランチの `lua/` は古いので、main を取り込んでから流してください。

## 1. 差分テストの案

### 1.1 実装の側の動かし方

子の nvim の中で、`tests/core_helpers.lua` を使います。

```lua
local H = require("core_helpers")
H.init_core({ spy_host = true })   -- 偽の Library と、host の差し替え
```

**かなテーブルをモデルと同じものにする。** モデルのテーブルは小さいので、実装の全部のテーブルとは `ta` などで食い違います。実装にも同じテーブルを入れます。`kana.reset()` はテーブルを作り直すときに `skkeleton.kana.rom_hira` を `require` し直すので、先に差し替えておきます。

```lua
local model = dofile("semantics/core/model.lua")
local kana = require("skkeleton.kana")
local function stub(name, t)
  package.loaded["skkeleton.kana." .. name] = {
    new = function()
      local entries = {}
      for from, result in pairs(t.entries) do
        entries[#entries + 1] = { from, result }
      end
      local tbl = kana.KanaTable.new(entries)
      tbl.kana_functions = t.kana_functions
      return tbl
    end,
  }
end
stub("rom_hira", model.tables.rom)
stub("rom_zen", model.tables.zen)
kana.reset()
require("skkeleton.keymap").reset()
require("skkeleton.config").reset()
```

カタカナへの変換（`hira_to_kata`）は実装のものをそのまま使います。モデルのかなはその部分集合なので、結果は合うはずです。

**辞書。** `lib.data` に、次の D を入れます（キーごとに作り直す）。

```lua
local D = {
  ["okurinasi:かき"] = { "柿", "牡蠣;貝", "夏期", "火器", "下記", "花器" }, -- 6 個。5 個目から一覧
  ["okurinasi:あい"] = { "愛" },
  ["okurinasi:か"] = { "蚊" },
  ["okurinasi:か>"] = { "可>" },     -- 接頭辞
  ["okurinasi:>か"] = { ">化" },     -- 接尾辞
  ["okuriari:かk"] = { "書", "欠" }, -- 送りあり
}
-- 候補なし：さし、あ、送りありの かs・かn など
```

**キーを流す。** `tests/core_helpers.lua` の `dispatch` はキーマップを通らないので使いません。`keymap.handle_key` に、モデルと同じ表記のキーを渡します。

```lua
local ctx = require("skkeleton.context").new()
require("skkeleton.keymap").handle_key(ctx, key)   -- key は "a"、"K"、"<space>"、"<nl>"（<C-j>）、"<cr>"、"<bs>"、"<c-g>"、"<esc>"、"<c-q>"
```

- `@disable` は `require("skkeleton.function.disable").disable(ctx)` を呼びます。
- `@enable` は `main.lua` にあって UI が要るので、この差分テストでは流しません（§4 の e2e の側で見ます）。
- モデルが「無効」になったら（`model.stage(C, σ) == "off"`）、そのキー列はそこで打ち切ります。実装の core は有効かどうかを持っていないので、その先は比べられません。

**観測。** 実装の側は、`cleanup.update_state_variable` と同じ式を `ctx` から直接作ります（`cleanup` は呼びません）。

```lua
local st = ctx.state
local phase = st.type == "input"
    and (st.mode == "okurinasi" and "input:okurinasi" or st.mode == "okuriari" and "input:okuriari" or "input")
  or st.type
local observed = {
  phase = phase,
  henkanFeed = st.henkan_feed or "",
  preedit = st.type ~= "escape" and ctx:to_string() or "",
  mode = disabled and "" or ctx.mode,   -- disabled は H.called("disable") が 1 つ以上あるか
}
local commit = ctx.preedit:take_kakutei()   -- 1 打ごとに取り出す。ctx.vim_mode は "" のままにする（undo の印が混ざらない）
```

モデルの側は `model.observe(σ, C)` と `out.commit` です。比べるのは、1 打ごとの `observed` の 4 つと `commit`、それに host の呼び出し（`input` の回数とプロンプト、`confirm`、`disable`、`show_candidates` の有無）です。

**host の答え。** `H.ret.input` と `H.ret.confirm` に、モデルの oracle と同じ答えを入れます。差分テストで使う答えは 4 通りです。

| 名前 | `input` | `confirm` |
|---|---|---|
| cancel | `nil` | `false` |
| word | `"登録"` | `false` |
| purge | `nil` | `true` |
| word+purge | `"登録"` | `true` |

内側の機械にキーを流す答え（`model.oracle_keys`）は、本物の `host.input` が要るので、ここでは使いません（§4 の R-RG-01、R-RG-06、R-RG-07）。

### 1.2 キー列

キーは `model.keys` から `@enable` を除いた 27 個です。

- **全部**：長さ 1〜3 のすべての列（27 + 729 + 19,683 = 20,439 本）。
- **乱数**：長さ 8 の列を 5,000 本。`math.random` は使わず、決まった種の線形合同法で作ります（何度流しても同じ列になるように）。
- **決め打ち**：§4 のキー列。

設定は次の 5 通り、host の答えは上の 4 通りです。全部の列は既定の設定で 4 通りの答え、ほかの設定は乱数の列だけで十分です。

| 名前 | 設定 |
|---|---|
| default | 既定 |
| step-cancel | `immediatelyCancel = false` |
| egg | `eggLikeNewline = true` |
| okuri-wait | `immediatelyOkuriConvert = false` |
| illegal | `acceptIllegalResult = true` |

1 本ごとに新しい Context、新しい偽の Library、`H.calls = {}`、モデルは `model.initial(C)` から始めます。純粋な Lua の呼び出しだけなので、1 つの子の nvim の中で全部流せます。並列にする必要はありません。

### 1.3 結果の出し方

食い違ったら、最初に食い違った打鍵で止めて、次のものを出します：キー列、設定、答え、食い違った項目、モデルの `out.rules`（その打鍵で通った規則の id）。同じ規則の id で食い違う列は 1 つにまとめ、いちばん短い列だけ残します。

## 2. 差が出て当然のところ

モデルは、未定義の規則を推奨の動きで書いています。次の 3 つは、実装と違って当然です。

| 規則 | 実装（今） | モデル（推奨） | 差分テストでの見え方 |
|---|---|---|---|
| R-CK-14 | `error` という文字を確定する | 読み＋送りを確定する | キー列では起きないはず。§4 の作り方で直接確かめる |
| R-EN-09 | `Illegal State: escape` のエラー | 何も起きない | `<esc>` のあとは打ち切るので、キー列では出ない |
| R-RG-08 | 分からない | 内側だけ無効にして、キーをそのまま欄に入れる | 本物の `host.input` が要るので、差分テストには出ない |

視点を破っているが今の動きとして書いた規則（R-HK-04、R-PG-01 など）は、モデルも今の動きのままです。ここで差が出たら、モデルか読みが間違っています。

## 3. 差が出たときの分け方

1. **モデルの誤り**：実装のコードを読み直すと、`rules.lua` の読みが違っていた。規則とモデルを直し、`confidence` を見直す。いちばん多いはずです。まずこれを疑ってください。
2. **推奨と今の動きの差**：§2 の 3 つ。差として記録するだけで、直しません。
3. **upstream とわざと変えたところ**：モデルと実装は合っているが、`make difftest` では upstream と違う。`tests/diff/known.lua` に書いてあるかを見ます。この差分テストには出ません（比べる相手が実装なので）。CORE.md の §7.1 の表を埋めるときに使います。
4. **実装の不具合**：モデルは CORE.md の規則どおりで、実装がそれと違う。または、合っているが視点を破っている（§4 で確かめた破れ）。issue を立てます（題は何が起きるかの文、再現のキー列、原因の `ファイル:行`、直し方の案。upstream で確かめていなければそう書く）。直すかどうかを決めるのは作者です。

モデルと実装のどちらが正しいか決められないときは、決めずに、キー列と両方の結果を #260 に書いてください。

## 4. 確かめていない規則

確度が「推測」「分からない」の規則です。期待する観測は `model.observe` の形（`phase` / `henkanFeed` / `preedit` / `mode`）で、どれも既定の設定と §1.1 の D、かなテーブルはモデルのものです。

### 4.1 差分テストで確かめられるもの

| 規則 | キー列 | host の答え | 期待する観測（最後の打鍵のあと） | 見るところ |
|---|---|---|---|---|
| R-OK-04 | `K a N k` | cancel | `input:okuriari` / `か` / `▽か*んk` / `hira` | `k` の打鍵で `host.input` が 1 回、プロンプトは `[辞書登録] か*ん: ` |
| R-OK-05 | `K a ; z` | cancel | `input:okuriari` / `か` / `▽か*z` / `hira` | `host.input` は呼ばれない |
| R-ST-01 | `K a N q` | cancel | `input` / 空 / 空 / `hira`、確定は `カン` | `q` の打鍵で `host.input` が 1 回（`[辞書登録] か*ん: `） |
| R-HK-04 | `K a k <space>` | cancel | `henkan` / `か` / `▼蚊` / `hira` | 続けて `<nl>` で確定は `蚊` だけ（`k` が消える）。`<nl>` の代わりに `x` なら `▽かk` に戻る |
| R-HK-05 | `K a ; <space>` | cancel | `input:okuriari` / `か` / `▽か*` / `hira` | `host.input` が 1 回、プロンプトは `[辞書登録] か*: `。答えが word なら、偽の Library の `okuriari:か` に語が入る |
| R-HK-07 | `K a ; >` | cancel | `input:okuriari` / `か` / `▽か*>` / `hira` | `host.input` が **2 回** 呼ばれる（どちらも `[辞書登録] か*>: `） |
| R-PG-01 | `q K a <space> X` | purge | `input` / 空 / 空 / `kata` | 続けて `a` を打つと、確定は `あ`（カタカナモードなのに ひらがな） |
| R-MD-11 | `L k K l q >` | cancel | `input` / 空 / 空 / `zenkaku`、確定を通して `ｋＫｌｑ＞` | ▽ が開かない。続けて `<nl>` で `mode` が `hira` |

`read` の規則のうち、読み違えやすいので先に見ておくとよいもの：

| 規則 | キー列 | 期待 |
|---|---|---|
| R-PR-13 | `K a t T`（察し の形。モデルのテーブルには `ss` が無いので `tt` で試す） | `input:okuriari` / `かっ` / `▽かっ*t`。送りの前の打ちかけ `t` が、`tt` の っ になって読みに入る |
| R-PR-13 | `K a n K i` | `K` のあと `▽かん*k`、`i` で変換（見出しは `かんk`） |
| R-CK-06 | `k <nl>` と `n <nl>` | 確定は `k` と `ん` |
| R-MD-03 | `q K a q` | 確定は `か`（カタカナ中の `q` は ひらがな）、`mode` は `kata` のまま |
| R-MD-10 | `q / a <nl>` | 確定は `a`、`mode` は `hira`（abbrev の前は `kata`） |
| R-HK-06 | `K a >` | `▼可`（`>` は出ない） |
| R-HK-16 | `K a <space> > k a <space>` | `蚊` を確定して `▽>か`、次の `<space>` で `▼化` |
| R-HK-08、R-HK-09 | `K a k i` のあと `<space>` を 5 回 | 5 回目で `show_candidates` が呼ばれ、`▼下記`。6 回目は候補が尽きて `host.input` |

### 4.2 状態を直接作って確かめるもの

| 規則 | 作り方 | 実装の期待 | モデル |
|---|---|---|---|
| R-CK-14 | `ctx.state.type = "henkan"`、`candidates = {}`、`candidate_index = 0`、`henkan_feed = "か"` にして `require("skkeleton.function.common").kakutei(ctx)` | 確定は `error` | 確定は `か`（推奨） |
| R-EN-09 | `<esc>` を流したあと、`handle_key(ctx, "a")` を `pcall` で呼ぶ | `Illegal State: escape` のエラー | 何も起きない（推奨） |

### 4.3 本物の host が要るもの（e2e）

`host.input` を差し替えずに、子の nvim の insert モードで打って確かめます（`tests/test_e2e_dictionary.lua` と同じやり方）。ここは実装の全部のかなテーブルを使います。

| 規則 | 手順 | 読んで予想した結果 |
|---|---|---|
| R-RG-01 | `q` でカタカナにして `Sasi<Space>`。登録の欄で `g:skkeleton#mode` を見てから `a` を打つ | `g:skkeleton#mode` は `kata` のまま、欄に入るのは `あ` |
| R-RG-06 | `Sasi<Space>` で欄を開き、欄の中で `Ka` と打って `<C-g>` | 内側の `▽か` ではなく、欄そのものが閉じて、外が `▽さし` に戻る |
| R-RG-07 | `Sasi<Space>`、欄の中で `L` `a` `<CR>`。外に戻ってから `Ka` `<C-g>` `a` | 外で `ａ` が確定されたあと、最後の `a` が全角の `ａ` になる。`g:skkeleton#mode` は `hira` |
| R-RG-08 | `Sasi<Space>`、欄の中で `l` `a` `b` `<CR>` | 分からない。何が確定され、外が有効のままかを記録する |
| R-RG-09 | 欄が開いている間に `<Plug>(skkeleton-disable)` と `<Plug>(skkeleton-enable)` を呼ぶ | 分からない。記録する |
| R-EN-05、R-EN-06 | `▽か` と `▼蚊` のそれぞれで `<Plug>(skkeleton-enable)` | `▽か` は残る。`▼蚊` は `蚊` が確定されて読みなしになる（#210 のテストがあれば、それで足ります） |

R-RG-07 は、モデルでは `model.oracle_keys({ { "L", "a", "<cr>" } })` を oracle にして、`S a s i <space>`、`K a <c-g> a` と流すと同じ結果（確定 `ａ`、`mode` は `hira`）になるように書いてあります。

## 5. 終わったら

- `rules.lua` の `confidence` と、違っていた規則を直し、`figures.lua` を流して CORE.md と図を作り直す。
- 確かめた破れ（R-HK-04、R-HK-05、R-HK-07、R-PG-01、R-RG-01、R-RG-06、R-RG-07、R-ST-01）は、issue にするかを作者に聞く。CORE.md の §6 のチェックが付いているものから扱います。
- CORE.md の §7.1 の「未確認」を、`make difftest` の結果で埋める（重い処理なので、ほかの人が流していないことを確かめてから）。

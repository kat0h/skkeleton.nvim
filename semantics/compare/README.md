# モデルと観測の比較（#186）

親の issue は #179、このタスクの issue は #186 です。`semantics/model/model.lua`（04）と、子の nvim に実際の打鍵を流した観測を突き合わせ、差を 4 種類に分けました。状態クラスの粒度も、観測で結果が割れるかで決めました。ここには今の振る舞いだけを書き、望ましい振る舞いは決めていません。

## ファイル

- `probe.lua`：観測。モデルの状態ごとに前置きを流し、イベントのキーを打って、前後の状態クラスと観測できる事実を JSONL に書く
- `compare.lua`：比較。観測とモデルの差を 4 種類に分ける。`--out` で `diff.md`（差の表）を書く
- `gen_probes.lua`：`model.lua` の `M.probes` に貼る表を作る
- `diff.md`：`compare.lua --out` の生成物（差の一覧）

観測は `semantics/explore/observe.lua` と同じ見方で取りました。子の nvim、一時ディレクトリの辞書、`HISTFILE=/dev/null`、クリップボードは触りません（`tests/helpers.lua` の `e2e_set`）。手元の辞書やファイルには触れていません。

## 動かし方

```sh
# 観測（約 2 分。チームのロックを取り、timeout を付ける）
flock /tmp/heavy.lock timeout 1800 \
  nvim --headless -u NONE -i NONE -l semantics/compare/probe.lua \
  --out semantics/compare/probe.jsonl

# 比較（差の表を書く。説明の付かない observed-only があれば終了コード 1）
nvim --headless -u NONE -i NONE -l semantics/compare/compare.lua \
  --out semantics/compare/diff.md

# model.lua の M.probes を作り直す（貼り付けは手で行う）
nvim --headless -u NONE -i NONE -l semantics/compare/gen_probes.lua \
  --probe semantics/compare/probe.jsonl --out /tmp/probes.lua
```

`probe.jsonl` は生成物なのでリポジトリに入れていません（`.gitignore`）。

## 結果

| 項目 | 件数 |
|---|---|
| 観測したケース | 616 |
| モデルの遷移と一致した観測 | 178 |
| 終わりがモデルと違う観測 | 0 |
| effects が食い違う遷移 | 0 |
| 観測にだけある遷移（observed-only） | 328（すべて説明付き） |
| モデルにだけある遷移（model-only） | 332（すべて理由付き） |
| 未確定（前提が状態クラスに無く、モデルが決めていない） | 2 |
| 非決定（同じ状態・イベントで分かれる組） | 36 |

モデルは状態 30・イベント 64・遷移 512 です。

## 差 1：モデルにだけある遷移（332）

probe で確かめられなかった遷移です。

| 理由 | 件数 |
|---|---|
| autocmd（`stale` / `winleave` / `bufleave` / `mouse_select`）。probe はキーしか打たない | 41 |
| 観測していない（probe のキーの一覧に無い） | 247 |
| 入力（マウス・貼り付け）。07e（#191） | 31 |
| 観測できず（`BLOCKED`）。子が入力待ちなどで観測できなかった | 10 |
| 遷移の途中（internal）。キーで観測できない | 3 |

到達性は `model_check.lua` と同じ BFS で計算しました（`keepState` の両方で届く状態を届くとする）。`model.states[].reachable` 欄は一部の状態にしか無いので、理由の判定には使いません。

## 差 2：観測にだけある遷移（328）

すべて理由が付きました。内訳です。

| 理由 | 件数 |
|---|---|
| モデルに無い自己遷移（観測では何も変わらない） | 82 |
| niI（`<C-o>`）の normal コマンド。モデルは効果で `ni_return_keep` / `commit` / `drop` にまとめ、キーの一覧は代表だけ | 78 |
| 辞書登録のプロンプトの中（07c #189） | 49 |
| skk が無効な insert / replace。キーは Vim がそのまま処理する | 27 |
| cmdline の中（07a #187） | 26 |
| 組み込みの補完の中（07d #190） | 23 |
| visual / select の Vim のコマンド。モデルは `<Esc>` で insert に戻る道だけを書いている | 17 |
| マクロと `.` の繰り返し（07f #192） | 9 |
| Vim のモード遷移（無効な insert / replace から `<C-o>` で niI・visual・replace へ） | 6 |
| Vim の `<C-c>`（niI / visual / 無効な insert から normal へ） | 8 |
| normal の Vim のコマンド（モデルは insert に入る道と `<Insert>`・`R` だけ） | 3 |

`<C-c>` と `<C-o>` のモード遷移は、モデルが「skk の状態が変わる遷移」だけを書いているためです。無効なときに Vim がモードを移す道は、状態クラス（I_OFF / R_OFF / V_IDLE）を変えないので、モデルには入れていません。

## 差 3：effects と終わりの食い違い（直したもの）

観測とモデルが食い違った遷移は、モデルを観測に合わせました。どれも「今の振る舞い」の書き直しです。

| 遷移 | 直す前（04） | 直したあと（06 の観測） |
|---|---|---|
| `t.I_POINT.key_q` / `key_cq` / `key_L` | 状態を変えない（I_POINT のまま） | 読みを変換して確定し、I_DIRECT（バッファに カン / ｶﾝ / かん） |
| `t.I_ROMAJI.char.commit` | I_DIRECT | I_POINT（▽k + a → ▽か） |
| `t.I_POINT.bs.empty` | I_DIRECT（pre-edit を消す） | I_ROMAJI（▽ だけが残る） |
| `t.I_DIRECT.key_semicolon` | I_POINT | I_ROMAJI（▽ だけ） |
| `t.I_DIRECT.key_slash` | I_DIRECT | I_ROMAJI（▽ だけ） |
| `t.I_SELECT.char_shift` | I_DIRECT | I_ROMAJI（候補を確定してから ▽k） |
| `t.N_OFF.insert_key` | R_OFF | I_OFF（normal の `<Insert>` は insert に入る） |
| NI の R / v | `ctrl_o_R` / `ctrl_o_v`（`<C-o>R` のキー） | イベントを `ni_R` / `ni_v` に分けた（niI では 1 キー） |

足した遷移です。

- `t.I_DIRECT.space`：読みが無い direct の `<Space>` は空白を入れる
- `t.N_OFF.R`：normal の `R` は置換モードに入る
- `t.I_ROMAJI.key_l` / `t.I_SELECT.key_l`：どちらも無効になる（打ちかけは捨て、候補は確定）
- `t.I_ROMAJI.ctrl_o_R` / `ctrl_o_v`：打ちかけを持ったまま replace / visual へ
- `t.I_DIRECT.enable` / `t.I_ROMAJI.enable` / `t.I_POINT.enable` / `t.I_SELECT.enable`：変換中の enable（下の #210）

未確定にした遷移です（前提が状態クラスに無いので、どちらになるとも決められない）。

- `t.I_POINT.key_gt`：既定の辞書では辞書登録のプロンプト（P_PROMPT）、辞書に候補があれば I_SELECT
- `t.I_SELECT.key_gt`：観測では I_POINT（元の ▽ に戻る）
- `t.I_SELECT.key_X.register`：候補の最後で X を打っても登録に入らなかった

補完（IC）は 07d の担当なので、effects の比較から外しました。参考までに、補完の候補が無いときは `<C-n>` でモードだけ `ic` になり、pre-edit は残ります（04 の観測は候補がある前提で、pre-edit が消えて候補が入る）。

## 差 4：非決定（36 組）と前提

「同じ状態クラス・同じイベントで結果が分かれる組」です。どれも、状態クラスに持っていない条件で分かれます。Ganty の論文（Neovim の状態機械の能動学習）がバッファや jumplist で状態が無限になるのを設定で止めたのと同じ型で、モデルには前提を書く必要があります。

| 前提 | 組（延べ） | 状態クラスに持っていないもの |
|---|---|---|
| `config.keepState` | `esc` 4 組、`insert_enter` 1 組 | 設定 |
| 辞書に候補があるか | `space` 2 組、`key_X` 1 組 | 辞書の中身 |
| 候補の位置（最初 / 2 つ目以降 / 最後） | `key_x` 2 組、`key_X` 1 組、`space` 2 組 | 候補の一覧と位置 |
| バッファに消す文字があるか | `ctrl_w` 3 組、`ctrl_u` 3 組、`ctrl_a` 2 組 | バッファの中身 |
| 読みの長さ（1 文字か、2 文字以上か） | `bs` 3 組 | 読み |
| 打った文字（かなになるか、ローマ字が続くか） | `char` 6 組、`char_shift` 2 組 | 直前のキー |
| どの autocmd か（カーソルだけのずれ / バッファが変わった / ずれが無い） | `stale` 4 組 | きっかけのイベント |
| クリックでカーソルが動くか | `mouse_click` 3 組 | クリックした位置 |

`space` の 2 組と `key_X` の 1 組は、辞書に候補があるかと候補の位置の両方に効きます。表は延べ 39 組で、重なりを除くと 36 組です。36 組の一覧は `diff.md` の「非決定の組」にあります。状態を分けても前提は消えないので（バッファの中身は無限）、ここはクラスではなく前提として書くのが正しいと判断しました。

## 状態クラスの分け方の結論

### 分けたままにする（観測で結果が割れる）

- `I_OFF` と `I_DIRECT`：`a` で `"a"` と `あ`、`K` で `"K"` と `▽k`。有効・無効で同じキーの結果が違うので、分ける根拠がある（作者の判断 1 のとおり）。
- `V_IDLE` と `N_OFF`：`<Esc>` で I_DIRECT と N_OFF、`v` で I_DIRECT と N_OFF。visual で有効のままなのが分かる（作者の判断 2 のとおり）。
- `NI` / `V_PRE` / `P_PROMPT` の相：NI の `<Esc>` は、direct / point / select でそれぞれ I_DIRECT / I_POINT / I_SELECT に戻ります。人が読むクラスは 1 つのままで、相を属性に持つ形（作者の判断 4 のとおり）が要ります。

### 分ける必要があると分かった（フォローアップで分けた）

- `▽` と `▽*`（作者の判断 7）。`a` で I_POINT と I_SELECT、`<Space>` で I_SELECT と P_PROMPT に割れました。結果が割れたので、判断の条件に当たります。この PR では `I_POINT` 1 つのままでしたが、07f の後のフォローアップで、人が読むクラスは `I_POINT` のまま相（okurinasi / okuriari）を属性に持つ `I_POINT` と `I_POINT_OKURI` に分けました（`model.lua` の `M.decisions` 7）。

### 分けない（前提にする）

- `I_ROMAJI` の中の「▽ だけ」と「▽k」。同じ `K` で、▽ からは I_ROMAJI（▽k）、▽k からは I_POINT（▽っk）になります。同じクラス・同じキーで結果が割れますが、分けるには打ちかけのローマ字の中身（無限）を状態にする必要があります。バッファや辞書と同じ「前提」として扱いました。

## 作者が「06 でもう一度確かめる」と言った 3 つ

観測を正としました。どれも 04 の観測と同じ結果で、`data.js` / `NOTES` の記述とは違います。

| # | キー列（I_POINT から） | 観測 | `data.js` / `NOTES` |
|---|---|---|---|
| 1 | `<C-o>R` | R_OFF。読み かん を確定して無効（バッファ `かん`） | pre-edit が残る |
| 2 | `<C-o>v` → `<Esc>` | I_POINT。pre-edit `▽かn` が残る | 抜けると確定する |
| 3 | `<C-o>:<CR>` | I_POINT。pre-edit `▽かn` が残る | 確定する |

▼ からも同じでした（`<C-o>R` は R_OFF でバッファ `缶`、`<C-o>v` → `<Esc>` は I_SELECT、`<C-o>:<CR>` は I_SELECT）。`data.js` は手で書いたもので、実装は観測のとおりです。

## 見つけたバグ

- #210：変換中（`▽` / `▼`）に `<Plug>(skkeleton-enable)` を押すと、読みが確定せずに消えます（P1 の破れ）。`lua/` は変えず、モデルには `status = "gap"` と `M.known` で入れました。

## モデルに足した観測

- `M.probes` に 178 件の観測を入れて、遷移の `observed` 欄を埋めました。残り 247 本の遷移は観測が空です（autocmd・マウス・貼り付け・遷移の途中・未確定）。
- `model_check.lua` は `M.probes` も再生し、終わりの状態クラスと、その遷移を通る経路を確かめます。178 件とも一致しています。

## 観測の限界

- probe が打つキーは、モデルのイベントのキーと代表的なキーです。たとえば `q` / `L` / `<C-q>` を I_ROMAJI や I_SELECT からは打っていません。打っていない組み合わせは observed-only にも model-only にも出ません。
- マウス・貼り付け・autocmd はキーで打てないので、観測ではなくコード読解と 02 の観測（events.md）に頼っています。
- 38 件は観測できませんでした（子が入力待ちなどで観測できない `BLOCKED`）。
- 05 の `observe.classify` とモデルのクラス名は 4 か所ずれています。`compare.lua` の `project` で寄せました。
  - 観測の `I_PENDING` → モデルの `I_ROMAJI`（作者の判断 6 の改名）
  - 観測の `R_MID` → モデルの `R_OFF`（作者の判断 8 で途中の状態）
  - visual で有効・pre-edit 無しの `N_OFF` → モデルの `V_IDLE`（作者の判断 2）
  - insert で無効の `I_DIRECT` → モデルの `I_OFF`（作者の判断 1。05 の分類は `enabled` を見ていない）

## 決めていないこと

- `I_ROMAJI` の打ちかけの中身をどう持つか
- #210 の直し方（3 案を issue に書いた）
- `t.I_POINT.key_gt` / `t.I_SELECT.key_gt` / `t.I_SELECT.key_X.register` の確定

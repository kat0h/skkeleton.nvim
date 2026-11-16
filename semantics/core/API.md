# 設定と API の提案（#164〜#168）

#164（遅延ロード）、#165（`initialize()`）、#166（sticky key の既定）、#167（標準の設定の分離）、#168（キーバインドの設定）を、[DESIGN.md](DESIGN.md) の境界にそろえた 1 つの設計として提案します。コードは変えていません。

- 読んだのは 5 つの issue、`lua/skkeleton/init.lua`、`config.lua`、`plugin/skkeleton.lua`、`doc/skkeleton.txt` の設定と API の節、それに前の作業で読んだ core です。`paste`、`map`、`indicator`、`completion` の中は読んでいません。それらについては `require` の一覧から分かることだけを書き、「未確認」と付けています。
- 動かして確かめてはいません。行番号は main の c2a78ff のものです。
- 作者に決めてほしいことは §5 にまとめました。**PR 1 はすぐ始められます。PR 3・4・5 は Q5（`register_*` を消してよいか）が決まれば始められ、PR 2・6・7 はそれぞれ Q1・Q2・Q4 が決まるまで手を付けません。**

## 1. 5 つの issue は同じ根か

「同じ根を持つ」という見立ては、半分だけ当たっていました。

**同じ根から出ているもの（#164 の一部、#166、#167、#168）。** 設定が「データ」ではなく、「モジュールを読み込んで、その中の状態を書き換える呼び出し」になっています。

| 設定するもの | 今の口 | 何が起きるか |
|---|---|---|
| キーマップ | `register_keymap()`（`init.lua:53-55`） | 呼んだ時点で `keymap` と `function/*` を読み込み、モジュールの中の表を書き換える。既定は `keymap.lua:23-57` にコードとして埋まっている |
| かなテーブル | `register_kanatable()`、`register_kanatable_file()`（`init.lua:60-70`）、設定の `globalKanaTableFiles` | 呼んだ時点でかなテーブルを全部作る。口が 3 つある |
| マッピングするキー | `g:skkeleton#mapped_keys`（`map.lua:25-28`） | キーマップに足したキーを、別の変数にも書かないと効かない |
| そのほか | `setup()`（`config.lua`） | これだけがデータ |

既定の動きがコードに埋まっているので、外すには 1 つずつ `register_keymap(…, false)` を呼ぶしかなく（#167）、`;` を既定から外すかどうかが「コードを 1 行消すか」の話になり（#166）、ほかの SKK の設定を写すには 4 つの口を使い分けることになります（#168）。設定のたびにモジュールを読み込むので、読み込みも遅らせにくくなっています（#164）。

DESIGN.md の言葉では、設定 C（設定、キーマップ、かなテーブル）は遷移の外から与えるものです。C を 1 つのデータにして、機械を最初に有効にするときに C から組み立てる形にすれば、この 4 つはまとめて片付きます。

**別の根のもの。**

- **#164 のもう半分**は、`plugin/skkeleton.lua:26` が起動時に `require("skkeleton.paste").init()` を呼ぶことです。`paste` は `cleanup`・`config`・`main`・`render` を `require` し、`main` は core のほとんどを `require` します。lazy.nvim の `event` で遅らせない限り、`setup()` を呼ぶ前に本体がほぼ全部読み込まれます（`require` の一覧からの読み。実際にかかる時間は未確認）。`setup()` も同じ `paste.init()` をもう 1 度呼んでいます（`init.lua:20`）。
- **#165** は、3 つの別のこと（設定、初期化、辞書の準備）に名前が 2 つしか無いことです。`initialize()` は初期化（`main.init`）と辞書の準備（`dictionary.prepare`）を続けて呼びますが、初期化は最初の enable でも走るので、`initialize()` に固有の仕事は辞書の準備だけです。`skkeleton-initialize-post` は辞書の準備より前に出ます（#165 の訂正のコメントのとおり）。

## 2. 提案する形

### 2.1 段階を 3 つに分けて、名前を 1 つずつ付ける

| 段階 | いつ | 何をするか | 読み込むもの |
|---|---|---|---|
| 置く | `plugin/skkeleton.lua` | `<Plug>` のマッピングと、`g:skkeleton#enabled` などの変数だけ | 何も `require` しない |
| 設定する | `setup(opts)` | `opts` を確かめて覚える。インジケータと補完の設定を渡す | `config`、`indicator`、`completion` |
| 組み立てる | 最初の enable | 覚えた設定から、キーマップ・かなテーブル・autocmd・貼り付けの処理を作る | 残りの全部 |
| 辞書を準備する | 最初の変換、または `prepare()` を呼んだとき | DB を作って Library を作る | `dictionary/*` |

「組み立てる」は DESIGN.md の `engine.new(session)` に当たります。今の `main.init` がしていることです。

### 2.2 公開する関数

| 関数 | 提案 | 理由 |
|---|---|---|
| `setup(opts)` | 残す。`keymap` と `kana` を受ける（§2.3） | 設定の口を 1 つにする |
| `enable()`、`disable()`、`toggle()`、`mode()`、`is_enabled()` | 残す | — |
| `get_config()` | 残す。既定のキーマップもここで見える | #167 |
| `initialize([force])` | **消して、`prepare([on_done])` にする**（Q1） | #165。固有の仕事は辞書の準備だけ |
| `register_keymap()` | **消す**（Q5）。`setup({ keymap = … })` にする | 口を 1 つにする |
| `register_kanatable()`、`register_kanatable_file()` | **消す**（Q5）。`setup({ kana = … })` と、今ある `globalKanaTableFiles` にする | 口を 1 つにする |
| `g:skkeleton#mapped_keys` | **消す**。キーマップに書いたキーは自動でマッピングする | 2 か所に書かなくて済む |
| `update_database()`、`save_user_dict()` | 残す | — |
| `get_prefix()`、`get_preedit()`、`is_composing()`、`get_completion_result()`、`get_completion_ranks()`、`complete()` | 残す。DESIGN.md の PR 5 のあとは `engine.observe` から作る | 補完の source が使う |

`prepare([on_done])` は、辞書を UI を止めずに準備し、終わったら `on_done()` を呼びます。もう準備ができていれば、すぐ呼びます。新しい `User` イベントは足しません（知らせる口を 2 つにしないため。インジケータは辞書の準備を見ていません）。

### 2.3 設定の形

今の設定のキーはそのままです。足すのは `keymap` と `kana` の 2 つです。

```lua
require("skkeleton").setup({
  eggLikeNewline = true,

  -- 既定のキーマップに重ねる。値は機能の名前か Lua の関数。false で外す
  keymap = {
    input = {
      [";"] = false,              -- sticky key を使わない（#166 を自分の設定で決める）
      ["<C-l>"] = "zenkaku",      -- mapped_keys に足さなくても効く
    },
    henkan = {
      ["<BS>"] = "henkanBackward",
      x = false,
    },
  },

  -- かなテーブルに重ねる。今の register_kanatable の {tbl} と同じ形。false で規則を消す。
  -- 無い名前を書けば、そのテーブルを新しく作る
  kana = {
    rom = {
      hh = { "お", "h" },
      l = false,
      la = { "ぁ" },
    },
  },
})
```

- **既定のキーマップは、`config.lua` の既定値にデータとして置きます**（機能の名前の表）。`keymap.lua:23-57` のコードは、この表から組み立てる処理になります。`get_config().keymap` と `doc/skkeleton.txt` の表が同じものになります（#167 の「分離」）。
- **重ね方**は、`input` と `henkan` の中でキーごとです。`setup()` を 2 度呼んだときも同じです。
- **`l` `q` `;` `/` `L` の包み**（`kana_function`。既定のローマ字のテーブルでだけ機能として効く）は、今のまま `keymap.lua` に残します。この 5 つのキーに既定の機能が付いている間だけ包みます。データに書けない決まりが 1 つ残りますが、きれいに直すにはモードごとのキーマップが要ります（Q4）。
- **マッピングするキー**は、今の既定のキー（英数字、記号、`<BS>` など。`map.lua` にある）に、`keymap` に書いたキーを足したものにします。
- **`kanaTable` の確かめ**は、テーブルを作らずに、名前（`rom`、`zen`、`kana` に書いた名前）だけで見ます。`setup()` でかなテーブルを作らないためです。

### 2.4 #168：ほかの SKK の設定を写せるだけの余地

libskk のコードと設定のファイルは見ていません（GPL なので、リポジトリにも写しません）。「キーごとの機能の表」と「ローマ字からかなへの表」をデータで持つ、という作りだけを比べます。

| 写すのに要るもの | 提案のあと |
|---|---|
| どのキーにも機能を割り当てられる | できる。`keymap` に書けばマッピングされる（今は `mapped_keys` も要る） |
| 既定の割り当てを外せる | できる。`false` |
| ローマ字の表をまるごと差し替えられる | できる。`kana` に新しい名前で書き、`kanaTable` で選ぶ |
| 機能を名前で呼べる | できる（今もある。`doc/skkeleton.txt` の機能一覧） |
| 候補の選択キー、一覧に切り替わる数 | できる（今もある。`selectCandidateKeys`、`showCandidatesCount`） |
| かなモードごとにキーの割り当てを変える | **できない。** 今は `input` と `henkan` の 2 つだけで、全英と abbrev で `l` などが文字になるのは `kana_function` の決め打ち（Q4） |

設定を読み替える道具は作りません（使う人がいないものは残さない、という方針のため）。

## 3. DESIGN.md との関係

- 設定 C がデータになるので、`engine.new(session)` は「`config.options` から機械を組み立てる」の 1 か所になります。DESIGN.md §2.1 の「設定 C は `config.options` を読む」はそのままです。
- 参照モデル（`model.lua`）の `C` に、キーマップとかなテーブルを足せるようになります。今のモデルはキーマップをコードに埋めています。
- 順番は、DESIGN.md の PR と独立です。どちらを先にしても、もう一方の差分は増えません。先にこちらを済ませると、DESIGN.md の PR 5（enable の判断を core へ移す）で「組み立てる」場所が 1 つに決まっているぶん、楽になります。
- インジケータは今のまま `setup()` から呼びます（本体からインジケータを呼ぶのは `setup` だけ、という決まりのまま）。

## 4. PR の順番

確実に出すのは 5 つ、作者の答えしだいで出すのが 2 つです。互換のためのコードは足さず、古い口は同じ PR で消します。`doc/skkeleton.txt` と `README.md` と `docs/ARCHITECTURE.md` は、それぞれの PR で直します。

| PR | 中身 | issue | 動きは変わるか | 足す回帰テスト |
|---|---|---|---|---|
| 1 | `plugin/skkeleton.lua` と `setup()` から `paste.init()` を外し、最初の enable で呼ぶ | #164 | 変えない（`paste` を読んで確かめる。未確認） | `plugin/skkeleton.lua` を読み込んだだけでは `package.loaded` に `skkeleton.main`・`skkeleton.render`・`skkeleton.keymap` が無い。`setup()` のあとも無い。enable のあとはある。貼り付けの既存のテストが通る |
| 2 | `initialize([force])` を消して `prepare([on_done])` にする。Q1 しだいで `skkeleton-initialize-pre`・`-post` も消す | #165 | API が変わる | `prepare(cb)` の `cb` が呼ばれた時点で DB のファイルがある。2 度目はすぐ呼ばれる。`prepare()` を呼ばなくても最初の変換ができる |
| 3 | 既定のキーマップを `config.lua` のデータにし、`setup({ keymap })` を足して `register_keymap()` を消す | #167、#168 | 既定の動きは変えない。API が変わる | `get_config().keymap` が `doc/skkeleton.txt` の表と同じ。`keymap = { input = { [";"] = false } }` で `ka;` が ▽ を開かない（#167 のコメントの確かめを、新しい口で）。関数を値にできる。知らない機能の名前はエラーで、設定は変わらない。`setup()` を 2 度呼ぶとキーごとに重なる |
| 4 | マッピングするキーを `keymap` から導き、`g:skkeleton#mapped_keys` を消す | #168 | `mapped_keys` に書かなくても効くようになる | `keymap = { input = { ["<C-l>"] = "zenkaku" } }` だけで、enable のあと `<C-l>` で全英になる。disable でバッファのマッピングが元に戻る |
| 5 | `setup({ kana })` を足して `register_kanatable()` と `register_kanatable_file()` を消す。`kanaTable` の確かめを名前だけにする | #168、#164 | 既定の動きは変えない。API が変わる | `kana = { rom = { hh = { "お", "h" } } }` が効く。`false` で規則が消える。無い名前はテーブルを作る。`kana` と `kanaTable` を同じ `setup()` で書ける。`setup()` のあと `package.loaded` に `skkeleton.kana.rom_hira` が無い |
| 6 | （Q2 で外すと決まったら）既定のキーマップから `;` を外す | #166 | 既定が upstream と変わる | 既定で `ka;` の `;` が文字として入る。`keymap = { input = { [";"] = "henkanPoint" } }` で戻せる。`tests/diff/known.lua` に理由を書く |
| 7 | （Q4 でやると決まったら）キーマップをかなモードごとに持ち、`kana_function` を消す | #168 | 独自のかなテーブルで `l` などの扱いが変わりうる | 全英と abbrev で `l q ; / L` が文字のまま。独自のテーブルでの動きは、決めた仕様のとおり |

PR 3〜5 は、テストが `register_*` を呼んでいるところを新しい口に書き換えることになります。期待値は変えません。期待値を変えないと通らないテストが出たら、動きが変わっているので、そこで止めて issue に書きます。

## 5. 決めてほしいこと

推奨を受けるなら最初のチェックボックスに、ほかを選ぶならその行にチェックを入れてください。Q2 は既定の動きを upstream から変えるかどうかなので、推奨はしますが、決めるのは作者です。

**Q1（#165）`initialize()` をどうするか**
- [ ] 推奨：消して `prepare([on_done])` にする。`force` は消す（テストの中だけで使う再初期化は `main.init(true)` のまま）。`skkeleton-initialize-pre`・`-post` も消す。upstream ではこのイベントの中で設定を書くのが決まった形ですが、ここでは `setup()` がその役目です。作者の設定でこのイベントを使っていなければ、残す理由がありません
- [ ] `prepare([on_done])` にするが、`skkeleton-initialize-pre`・`-post` は残す（「組み立てる」の前後で出る、と意味を書き直す）
- [ ] 名前は `initialize` のままにして、`on_done` を受けるようにする。upstream の名前（`skkeleton#initialize()`）と同じままになるが、「初期化」と「辞書の準備」が同じ名前のまま残る
- [ ] 今のまま。ヘルプに「呼ばなくても動く。辞書の準備が終わったことは外から分からない」と書く

**Q2（#166）`;`（sticky key）を既定で効かせるか**
- [ ] 推奨：今のまま（効かせる）。upstream と同じ既定です。PR 3 のあとは、自分の設定に `keymap = { input = { [";"] = false } }` と 1 行書けば外せるので、既定を変えなくても issue の困りごとは解けます
- [ ] 既定から外す（PR 6）。既定が upstream と変わり、差分テストに意図した差として書くことになる。`;` はふつうの文字になる

**Q3（#167）既定のキーマップを、まとめて外す口が要るか**
- [ ] 推奨：要らない。キーごとに `false` で外す。まとめて外したあとは、使うキーを全部書き直すことになり、作者が使わないなら壊れても気づけません
- [ ] 要る。`keymap = { input = false }` で、その状態の既定を全部外せるようにする

**Q4（#168）かなモードごとのキーマップまでやるか**
- [ ] 推奨：今はやらない。PR 3〜5 までにする。`kana_function` の決め打ちは残る
- [ ] やる（PR 7）。`keymap = { input = { … }, zenkaku = { … } }` のように、かなモードごとに重ねられるようにする。独自のかなテーブルを使っているときの `l q ; / L` の動き（今は文字になる）をどうするかも、あわせて決める必要がある

**Q5 `register_keymap()`・`register_kanatable()`・`register_kanatable_file()`・`g:skkeleton#mapped_keys` を消してよいか**
- [ ] 推奨：消す。作者の設定を 1 度書き換えることになります。upstream の関数の名前（`skkeleton#register_keymap` など）とは離れるので、`doc/skkeleton.txt` の「skkeleton からの移行」に書き換えの例を足します
- [ ] 残す。`setup()` の `keymap`・`kana` は足さず、PR 1・2 だけにする。#167 と #168 は「今のままでできる」として扱う

**Q6（#164）足りなかったのはこれか**
#164 のコメントの問い（A〜D）に答えが無いので、読んで見つけたものを挙げます。
- [ ] 推奨：`plugin/skkeleton.lua` が起動時に本体を読み込むこと（PR 1）と、`setup()` と `register_*` が読み込みを起こすこと（PR 3〜5）を直せば足りる
- [ ] ほかに困っていることがある（書いてください）

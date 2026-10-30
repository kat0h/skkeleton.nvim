# skkeleton.nvim

Neovim で SKK 方式の日本語入力を行うプラグインです。kuuote さんの [skkeleton](https://github.com/vim-skk/skkeleton) を Neovim 向けに Lua で再実装したもので、delphinus さんの [skkeleton_indicator.nvim](https://github.com/delphinus/skkeleton_indicator.nvim) をベースにした入力モードのインジケータも内蔵しています。

設定のキー名や `<Plug>` マッピング、`User` イベント、`g:skkeleton#mode` などの変数名は skkeleton と互換性があります。ただし、すべての機能を移植しているわけではありません。対応状況や変更点については「[skkeleton からの移行](#skkeleton-からの移行)」を参照してください。

## 必要なもの

- Neovim 0.12（動作確認済み）
- SKK 辞書（[SKK-JISYO.L](https://skk-dev.github.io/dict/) などを展開し、ファイルのパスを設定で指定してください。文字コードは EUC-JP と UTF-8 を自動判別します）

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim) を使う場合の設定例です。

```lua
{
  "kat0h/skkeleton.nvim",
  event = { "InsertEnter", "CmdlineEnter" },
  config = function()
    require("skkeleton").setup({
      globalDictionaries = { "~/.config/skk/SKK-JISYO.L" },
    })
    vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
  end,
}
```

この例では `<C-j>` で SKK の有効・無効を切り替えます。端末モードでも使う場合は、マッピングのモードに `"t"` を追加してください。SKK が有効な間のキーマッピングについては `:help skkeleton-keymappings` を参照してください。

辞書は初回使用時に読み込まれます。Neovim の起動時にあらかじめ準備しておく場合は `require("skkeleton").initialize()` を呼び出してください。初回のみ辞書から DB ファイルを生成するため少し時間がかかりますが、生成された DB は `stdpath("cache")/skkeleton` に保存され、次回以降はそのまま利用されます。

設定項目や使い方の詳細は `:help skkeleton` にまとめています。

## インジケータ

`setup()` を呼ぶと、カーソル付近に現在の入力モードを示す小さなウィンドウが表示されます。表示する文字列や色、位置などは `indicator` オプションで変更できます。無効にする場合は `false` を指定してください。

```lua
require("skkeleton").setup({
  indicator = {
    hiraText = "あ",
    kataText = "ア",
    border = "single",
    fadeOutMs = 0,
  },
})

-- 無効にする場合
require("skkeleton").setup({ indicator = false })
```

設定可能なオプションとハイライトグループの詳細は `:help skkeleton-indicator` を参照してください。オプション名やハイライトグループ名は skkeleton_indicator.nvim と同じです。

## 補完

送りなし入力中に以下の補完プラグインまたは Neovim 組み込み機能を利用できます。

補完候補は、**読みの長さ（短い順）** → **選択履歴ランク（頻度順）** → **辞書の出現順** の 3 段階でソートされます。

### blink.cmp

[blink.cmp](https://github.com/saghen/blink.cmp) の providers に `skkeleton` を追加します。

```lua
require("blink.cmp").setup({
  sources = {
    default = { "lsp", "path", "snippets", "buffer", "skkeleton" },
    providers = {
      skkeleton = {
        name = "skkeleton",
        module = "skkeleton.completion.blink",
      },
    },
  },
})
```

`eggLikeNewline = true` を設定すると、補完候補選択中の `<CR>` で候補を直接確定できます。

### nvim-cmp

[nvim-cmp](https://github.com/hrsh7th/nvim-cmp) の sources に `"skkeleton"` を指定します。`skkeleton.setup()` 時にソースが自動登録されます。

```lua
local cmp = require("cmp")
cmp.setup({
  sources = cmp.config.sources({
    { name = "skkeleton" },
    { name = "buffer" },
  }),
})
```

### 組み込み completefunc

Neovim 組み込みの `completefunc`（`<C-x><C-u>`）を使用する場合：

```lua
vim.bo.completefunc = "v:lua.require'skkeleton.completion'.completefunc"
```

### 補完ランクの永続化 (`completionRankFile`)

候補の選択履歴を保存して次回の補完順位に反映させるには、`completionRankFile` を指定します。

```lua
require("skkeleton").setup({
  completionRankFile = "~/.config/skk/rank.json",
})
```

### 補完 Lua API

外部の補完プラグインやスクリプトから利用できる API を提供しています。

- `require("skkeleton").get_prefix()`: 現在の読み（かな）を取得
- `require("skkeleton").get_pre_edit()` (`get_preedit()`): 現在の pre-edit 文字列を取得
- `require("skkeleton").get_completions()` (`get_completion_result()`): 補完候補一覧を取得
- `require("skkeleton").get_completion_ranks()`: 候補のランクテーブルを取得
- `require("skkeleton").complete_callback(kana, word)`: 選択した候補を辞書とランクに登録
- `require("skkeleton").complete(kana, word)`: 候補を確定してバッファに挿入

## skkeleton からの移行

skkeleton.nvim は skkeleton を置き換えるプラグインです。同じ Neovim に両方を導入せず、どちらか一方のみを有効にしてください。

設定のキー名（`eggLikeNewline` など）はそのまま引き継げます。関数などの呼び出し方は次のように変わります。

| skkeleton | skkeleton.nvim |
|---|---|
| `vim.fn["skkeleton#config"]({...})` | `require("skkeleton").setup({...})` |
| `vim.fn["skkeleton#register_kanatable"](name, tbl, create)` | `require("skkeleton").register_kanatable(name, tbl, create)` |
| `skkeleton#register_kanatable_file` | `require("skkeleton").register_kanatable_file` |
| `skkeleton#register_keymap` | `require("skkeleton").register_keymap` |
| `skkeleton#initialize()` | `require("skkeleton").initialize()` |
| `skkeleton#update_database` | `require("skkeleton").update_database` |
| `require("skkeleton_indicator").setup({...})` | `require("skkeleton").setup({ indicator = {...} })` |
| `<Plug>(skkeleton-enable)` ほか | 同じ |

主な違いは以下のとおりです。

- `databasePath` にはファイルではなくディレクトリを指定します。指定したディレクトリ内に、辞書ごとの `<ハッシュ>.db` ファイルが生成されます（skkeleton が作成した DB ファイルは使用せず、新しく作成します）。既存のファイルパスや `skk.db` のような拡張子付きのパスが指定された場合は、その親ディレクトリを使用します。省略時（`""`）の保存先は `stdpath("cache")/skkeleton` です。
- `sources` の `"deno_kv"` は `"skk_dictionary"` と同じものとして扱われます。どちらを指定しても辞書は DB 化して検索されるため、DB を使うために `databasePath` を設定する必要はありません。
- `skkServer*` は互換性のために型の検証のみ行い、実際の処理では使用しません。
- 以下の機能には対応していません。
  - `sources` の `"skk_server"` および `"google_japanese_input"`
  - ddc.vim の補完ソース（blink.cmp、nvim-cmp、組み込み completefunc に対応しています）
  - YAML 形式・MessagePack 形式の辞書（JSON 形式の辞書には対応しています）
  - `skkeleton#handle()`、`skkeleton#dangerously_clear_buffer_local_mappings()`

設定の移行例です。

```lua
-- 移行前（skkeleton）
vim.fn["skkeleton#config"]({
  globalDictionaries = { "~/.config/skk/SKK-JISYO.L" },
  eggLikeNewline = true,
  sources = { "deno_kv" },
  databasePath = vim.fn.expand("~/.cache/skk.db"),
})
vim.fn["skkeleton#register_kanatable"]("rom", { [","] = { "，", "" }, ["."] = { "．", "" } })
vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
require("skkeleton_indicator").setup()
```

```lua
-- 移行後（skkeleton.nvim）
local skkeleton = require("skkeleton")
skkeleton.setup({
  globalDictionaries = { "~/.config/skk/SKK-JISYO.L" },
  eggLikeNewline = true,
  -- sources と databasePath は省略しても同じように動作します
})
skkeleton.register_kanatable("rom", { [","] = { "，", "" }, ["."] = { "．", "" } })
vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
-- インジケータは setup() で自動的に有効になります
```

`databasePath` の指定を残す場合は、`~/.cache/skk.db` ではなく `~/.cache/skkeleton` のような専用ディレクトリに変更することを推奨します（`~/.cache/skk.db` のままにすると、親ディレクトリの `~/.cache` 直下に DB ファイルが作られます）。

## ライセンスと謝辞

ライセンスは zlib ライセンスです（[LICENSE](LICENSE)）。移植元である skkeleton と skkeleton_indicator.nvim の著作権表示は [LICENSES/](LICENSES/) にあります。

入力処理の仕組みや設定項目、ドキュメントの多くは kuuote さんの skkeleton を元にしています。インジケータ機能は delphinus さんの skkeleton_indicator.nvim を元にしています。両作者に感謝いたします。

## 開発

テストには [mini.nvim](https://github.com/echasnovski/mini.nvim) の `mini.test` を使用しています。

```sh
make test              # 全テストを実行（.tests/mini.nvim がなければ自動で clone します）
make test FILE=tests/test_kana.lua
make lint              # stylua --check
make fmt
```

`stylua` は `.tests/bin/stylua` が存在すればそちらを優先して使用します。内部設計は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、開発計画と経緯は [docs/PLAN.md](docs/PLAN.md) を参照してください。

### ブランチ構成

- `main`: 主系ブランチ。安定版のコードを管理します。
- `feat/*`: 新機能の開発用ブランチ。
- `fix/*`: バグ修正用の作業ブランチ。
- `poc/*`: 概念実証（PoC）や実験的ツールの検証用ブランチ（モデル検査など）。

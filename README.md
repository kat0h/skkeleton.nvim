# skkeleton.nvim

Neovim で SKK 方式の日本語入力をするためのプラグインです。kuuote さんの [skkeleton](https://github.com/vim-skk/skkeleton) を Neovim 向けに Lua で書き直しています。入力モードの表示は delphinus さんの [skkeleton_indicator.nvim](https://github.com/delphinus/skkeleton_indicator.nvim) を元にしたものを内蔵しています。

設定のキー、`<Plug>` マッピング、User イベント、`g:skkeleton#mode` などの変数は skkeleton と同じ名前を使います。すべてを移したわけではありません。使えるものと使えないものは [skkeleton から移る](#skkeleton-から移る) に書きました。

## 必要なもの

- Neovim 0.10 以降を想定しています。動作を確かめているのは 0.12 と、CI で回している stable と nightly です
- SKK 辞書。[SKK-JISYO.L](https://skk-dev.github.io/dict/) などを展開して、パスを設定に書きます。辞書は EUC-JP と UTF-8 を自動で判別します

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim) の例です。

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

`<C-j>` で SKK の有効と無効を切り替えます。端末バッファでも使うときは、モードに `"t"` を足します。有効にしたあとのキーの割り当ては、`:help skkeleton-keymappings` にあります。

辞書は最初に使うときに読み込みます。起動直後に準備しておくには `require("skkeleton").initialize()` を呼びます。初回は辞書の DB を作るため、少し時間がかかります。DB は `stdpath("cache")/skkeleton` に置き、次からはこれを引きます。

設定のすべてのキーと使い方は `:help skkeleton` にまとめています。

## インジケータ

`setup()` を呼ぶと、カーソルの近くに入力モードを示す小さなウィンドウが出ます。表示の文字、色、位置は `indicator` で変えられます。`false` を渡すと使いません。

```lua
require("skkeleton").setup({
  indicator = {
    hiraText = "あ",
    kataText = "ア",
    border = "single",
    fadeOutMs = 0,
  },
})

-- 使わないとき
require("skkeleton").setup({ indicator = false })
```

オプションとハイライトグループは `:help skkeleton-indicator` にあります。skkeleton_indicator.nvim と同じ名前です。

## skkeleton から移る

skkeleton.nvim は skkeleton を置き換えるものです。同じ Neovim に両方を入れず、どちらかだけにしてください。skkeleton.nvim は denops.vim を使いません。

設定のキー（`eggLikeNewline` など）はそのまま使えます。呼び出しの名前は次のように変わります。

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

違いがあるところは次のとおりです。

- `databasePath` はディレクトリです。辞書ごとに `<ハッシュ>.db` というファイルをその下に作ります。upstream が Deno KV のファイルとして使っていたパスは読みません。パスがファイルとして存在するか、`skk.db` のように拡張子があるときは、その親ディレクトリを使います。空にすると `stdpath("cache")/skkeleton` です
- `sources` の `"deno_kv"` は `"skk_dictionary"` と同じ扱いです。どちらを書いても、辞書は DB にして引きます。DB を使うために `databasePath` を設定する必要はありません
- `skkServer*` と `completionRankFile` は値の確認だけをして使いません
- 次のものは v1 では使えません。`sources` の `"skk_server"` と `"google_japanese_input"`、ddc の補完ソース、rank file、yaml と msgpack の辞書（JSON の辞書は読めます）、`skkeleton#handle()`、`skkeleton#dangerously_clear_buffer_local_mappings()`、kakuteiUndo。kakuteiUndo は upstream の現在のバージョン（`770b265d`）にも無いため入れていません

設定の移し方の例です。

```lua
-- 移す前（skkeleton）
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
-- 移した後（skkeleton.nvim）
local skkeleton = require("skkeleton")
skkeleton.setup({
  globalDictionaries = { "~/.config/skk/SKK-JISYO.L" },
  eggLikeNewline = true,
  -- sources と databasePath は書かなくても同じように動く
})
skkeleton.register_kanatable("rom", { [","] = { "，", "" }, ["."] = { "．", "" } })
vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
-- インジケータは setup() が開始する
```

`databasePath` を残すときは、`~/.cache/skk.db` ではなく `~/.cache/skkeleton` のような専用のディレクトリを指すのを勧めます。`~/.cache/skk.db` のままだと、親の `~/.cache` に DB のファイルが並びます。

## ライセンスと謝辞

zlib ライセンスです（[LICENSE](LICENSE)）。skkeleton と skkeleton_indicator.nvim の著作権表示は [LICENSES/](LICENSES/) にあります。

入力の仕組み、設定の項目、ドキュメントの多くは、kuuote さんの skkeleton を元にしています。インジケータは delphinus さんの skkeleton_indicator.nvim を元にしています。お二人に感謝します。

## 開発

テストは [mini.nvim](https://github.com/echasnovski/mini.nvim) の mini.test で動かします。

```sh
make test              # 全部。.tests/mini.nvim が無ければ clone する
make test FILE=tests/test_kana.lua
make lint              # stylua --check
make fmt
```

stylua は`.tests/bin/stylua` があればそれを使います。設計は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、計画と経緯は [docs/PLAN.md](docs/PLAN.md) にあります。

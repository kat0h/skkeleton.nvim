# ライセンスの管理

skkeleton.nvim 自体は zlib ライセンス（リポジトリ直下の [LICENSE](../LICENSE)）。次の 2 つから移植したコードとデータを含む。どちらも zlib ライセンスで、元の表示をこのディレクトリにそのまま残している。

| 移植元 | 版 | ライセンス | 元の表示 |
|---|---|---|---|
| [skkeleton](https://github.com/vim-skk/skkeleton) | `770b265d`（2026-05-05） | zlib, © 2021 kuuote | [skkeleton.txt](skkeleton.txt) |
| [skkeleton_indicator.nvim](https://github.com/delphinus/skkeleton_indicator.nvim) | `b3e5379d`（2026-04-07） | zlib, © 2021 Yasushi Jinnouchi | [skkeleton_indicator.nvim.txt](skkeleton_indicator.nvim.txt) |

zlib ライセンスの条件 2（改変したソースは、改変したことをはっきり示す）を満たすため、移植したファイルの先頭には次の形のコメントを書く。

```lua
-- Ported from skkeleton (denops/skkeleton/function/input.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
```

## 含めないもの
- SKK 辞書（SKK-JISYO.* は GPL）。テストやベンチは `/usr/share/skk/` などにあるものを読み、リポジトリには入れない
- upstream が使っている npm/JSR のパッケージ（`@geolonia/japanese-numeral`（MIT）、`cr-numeral` など）のコード。数値変換などは仕様を見て自分で書き、コードは写さない
- mini.nvim（MIT）。テストのときだけ `.tests/` に clone し、リポジトリには入れない

## ドキュメント
`doc/skkeleton.txt` の文章は、skkeleton の `doc/skkeleton.jax`、`doc/skkeleton-functions.jax`（zlib, © 2021 kuuote）と、skkeleton_indicator.nvim の `doc/skkeleton_indicator.jax`（zlib, © 2021 Yasushi Jinnouchi）を元に、skkeleton.nvim の動作に合わせて書き直したもの。移植元と改変したことは、doc の先頭に書いてある。

## テストデータ

`tests/testdata/` は skkeleton の `denops/skkeleton/testdata/` の写し（zlib, © 2021 kuuote）。

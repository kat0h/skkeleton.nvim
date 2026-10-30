# ライセンスの管理

skkeleton.nvim 自体は zlib ライセンス（リポジトリ直下の [LICENSE](../LICENSE)）で提供しています。また、以下の 2 つのプラグインから移植したコードおよびデータを含んでいます。いずれも zlib ライセンスであり、元の著作権表示をこのディレクトリにそのまま残しています。

| 移植元 | バージョン | ライセンス | 元の著作権表示 |
|---|---|---|---|
| [skkeleton](https://github.com/vim-skk/skkeleton) | `770b265d`（2026-05-05） | zlib, © 2021 kuuote | [skkeleton.txt](skkeleton.txt) |
| [skkeleton_indicator.nvim](https://github.com/delphinus/skkeleton_indicator.nvim) | `b3e5379d`（2026-04-07） | zlib, © 2021 Yasushi Jinnouchi | [skkeleton_indicator.nvim.txt](skkeleton_indicator.nvim.txt) |

zlib ライセンスの第 2 項（改変したソースコードには変更した旨を明記する）を満たすため、移植したファイルの先頭には以下の形式でコメントを記載しています。

```lua
-- Ported from skkeleton (denops/skkeleton/function/input.ts)
-- Copyright (c) 2021 kuuote, zlib license (see LICENSES/skkeleton.txt)
-- Modified for skkeleton.nvim: rewritten in Lua.
```

## リポジトリに含めないもの
- SKK 辞書（`SKK-JISYO.*` は GPL ライセンス）。ベンチマークなどでは `/usr/share/skk/` にあるシステム辞書を読み込み、リポジトリには含めません。
- 移植元が依存している外部パッケージ（`@geolonia/japanese-numeral`（MIT）、`cr-numeral` など）のコード。数値変換処理などは仕様に基づいて独自に実装し、コードの流用は行いません。
- `mini.nvim`（MIT）。テスト実行時にのみ `.tests/` に clone し、リポジトリには含めません。

## ドキュメント
`doc/skkeleton.txt` は、skkeleton の `doc/skkeleton.jax` および `doc/skkeleton-functions.jax`（zlib, © 2021 kuuote）と、skkeleton_indicator.nvim の `doc/skkeleton_indicator.jax`（zlib, © 2021 Yasushi Jinnouchi）を元に、skkeleton.nvim の仕様に合わせて加筆・修正したものです。移植元および改変した旨はドキュメントの先頭に記載しています。

## テストデータ

`tests/testdata/` は skkeleton の `denops/skkeleton/testdata/` を複製したものです（zlib, © 2021 kuuote）。

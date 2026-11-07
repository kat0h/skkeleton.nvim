# 補完の観測（#190）

`completion.jsonl` は、`semantics/explore/explore.lua --replay` で取った補完（組み込みの `ic` と blink.cmp）の観測です。1 行が 1 キー（または 1 つの `@イベント`）の前後の観測で、`from` / `to` は `semantics/GLOSSARY.md` の状態クラスです。

- `completion` プロファイル: `あいうえお` の次の行の行末から始めます。`<C-n>` / `<C-p>` / `<C-x><C-n>` で `ic` に入ると pre-edit が消え、`<C-x>` だけでは `ix` のキー待ちになって pre-edit が残ります。
- `blink` プロファイル: blink.cmp の v1 を `.tests/blink.cmp`（または `BLINK_PATH`）に置いて使います。メニューは Vim のモードを変えないので `IC` のまま pre-edit が残ります。`completion.menu` は blink のメニューの浮動ウィンドウの有無と画面の位置（`row` / `col`）です（#143、#174）。
- `blink_line` プロファイル: 文字のある行（`ab cd`）の行末から始めます。メニューの `row` / `col` が行頭（col 0）ではなく、pre-edit の近くに出ることを見るためのものです（#143、#174）。
- `blink_buffer` プロファイル: 無効のあいだに buffer のメニューを出してから `<C-j>`（`<Plug>(skkeleton-enable)`）で有効にします（#24）。

観測は子の nvim（一時ディレクトリの辞書、`HISTFILE=/dev/null`）で取りました。blink.cmp は観測のためだけに入れ、リポジトリには入れていません。再現のコマンドは `semantics/explore/NOTES.md` の「補完の観測（#190）」にあります。

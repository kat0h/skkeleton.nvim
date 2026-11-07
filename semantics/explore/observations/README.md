# 観測の一覧

cmdline（#187 / 07a）と補完（#190）の観測です。どちらも `semantics/explore/explore.lua` の
プロファイルで子の nvim から取り、`semantics/model/model.lua` の `M.observations` と
突き合わせました。

## cmdline（#187 / 07a）

`semantics/explore/explore.lua` の `cmdline` プロファイルで、cmdline（c / cr）の遷移を
1 キーずつ観測したものです。`cmdline.jsonl` は 1 行が 1 つの観測で、`semantics/model/model.lua`
の `M.observations` と突き合わせるために使いました。

- 子の nvim は `tests/helpers.lua` の `e2e_set`（一時ディレクトリの辞書、`HISTFILE=/dev/null`）。
- プロファイルの準備は `:<Plug>(skkeleton-enable)`。cmdline に入ってから有効化しています。
- `<C-r>a`・`<C-r>=1<CR>`・`<C-v>065`・`<C-k>a:` は途中で入力待ちになるので、まとめて 1 回の入力として流しています
  （`explore.lua` の `TOGETHER`）。
- レジスタ `a` には `XYZ` を入れてから流しています。
- `<C-p>` の履歴は用意していないので、この JSONL では「一致する履歴が無い」ときの観測です。
  履歴があるときの観測は `semantics/model/model.lua` の `O-c-ctrl-p` にあります。

## 流したキー列

```sh
for seq in \
  "Kan" "Kan,<Space>" "Kan,<Space>,<Space>,<Right>" "Kan,<C-u>" \
  "Kan,<C-r>a" "Kan,<C-k>a:" "Kan,<C-y>" "Kan,<Insert>" "Kan,<Insert>,a" \
  "Kan,<Insert>,<C-j>" "Kan,<C-f>" "Kan,<C-r>=1<CR>" "Kan,<C-p>" \
  "Kan,<C-g>" "Kan,<CR>" "Kan,<Esc>" "Kan,<C-c>" "Kan,<Right>" "Kan,<Tab>" \
  "Kan,<C-a>" "Kan,<BS>" "Kan,<Space>,<BS>" "Kan,<Space>,<Insert>" \
  "Kan,<Space>,x" "<Insert>" "<C-g>" "<C-f>" \
  "Kan,<Space>,<Space>,<Space>,<Space>,<Space>,<Right>"
do
  nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua \
    --replay "$seq" --profile cmdline --out "/tmp/cmdline-$(echo "$seq" | tr '/<>,' '____').jsonl"
done
```

観測の JSONL は、モデルと突き合わせるのに要る項目だけを残してあります（`obs.buffer.text` など）。

## 補完（#190）

`completion.jsonl` は、`semantics/explore/explore.lua --replay` で取った補完（組み込みの `ic` と blink.cmp）の観測です。1 行が 1 キー（または 1 つの `@イベント`）の前後の観測で、`from` / `to` は `semantics/GLOSSARY.md` の状態クラスです。

- `completion` プロファイル: `あいうえお` の次の行の行末から始めます。`<C-n>` / `<C-p>` / `<C-x><C-n>` で `ic` に入ると pre-edit が消え、`<C-x>` だけでは `ix` のキー待ちになって pre-edit が残ります。
- `blink` プロファイル: blink.cmp の v1 を `.tests/blink.cmp`（または `BLINK_PATH`）に置いて使います。メニューは Vim のモードを変えないので `IC` のまま pre-edit が残ります。`completion.menu` は blink のメニューの浮動ウィンドウの有無と画面の位置（`row` / `col`）です（#143、#174）。
- `blink_line` プロファイル: 文字のある行（`ab cd`）の行末から始めます。メニューの `row` / `col` が行頭（col 0）ではなく、pre-edit の近くに出ることを見るためのものです（#143、#174）。
- `blink_buffer` プロファイル: 無効のあいだに buffer のメニューを出してから `<C-j>`（`<Plug>(skkeleton-enable)`）で有効にします（#24）。

観測は子の nvim（一時ディレクトリの辞書、`HISTFILE=/dev/null`）で取りました。blink.cmp は観測のためだけに入れ、リポジトリには入れていません。再現のコマンドは `semantics/explore/NOTES.md` の「補完の観測（#190）」にあります。

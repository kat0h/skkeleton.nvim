# cmdline の観測（#187 / 07a）

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

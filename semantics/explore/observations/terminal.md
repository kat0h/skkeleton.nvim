# terminal の観測（#188 / 07b）

`semantics/explore/explore.lua` の `terminal` プロファイルで、terminal（t / nt）の遷移を
1 キーずつ観測したものです。`terminal.jsonl` は 1 行が 1 つの観測で、`semantics/model/model.lua`
の `M.observations` と突き合わせるために使いました。

- 子の nvim は `tests/helpers.lua` の `e2e_set`（一時ディレクトリの辞書、`HISTFILE=/dev/null`）。
- プロファイルの準備は `terminal cat` → `i`（ジョブへ）→ `<Plug>(skkeleton-enable)`。
- terminal の pre-edit は本物の文字としてジョブへ流し、BS で消して書き直します。
  端末の行には書き直しの BS が `^H` として残るので、`obs.terminal.tail` も残しました。
- `obs` は突き合わせに要る項目だけを残してあります（`buffer.text`、`state`、`terminal.tail` など）。

## 流したキー列

```sh
for seq in "" "K" "K,a" "K,a,n" "K,a,n,<Space>" "K,a,n,<Space>,<Space>" \
  "K,a,n,<C-a>" "K,a,n,<C-r>" "K,a,n,<C-w>" "K,a,n,<C-u>" "K,a,n,<C-n>" \
  "K,a,n,<C-y>" "K,a,n,<C-@>" "K,a,n,<C-o>" "K,a,n,<Tab>" "K,a,n,<Insert>" \
  "K,a,n,<Esc>" "K,a,n,<C-\\><C-n>" "K,a,n,<C-\\><C-n>,i" "K,a,n,<C-\\><C-n>,i,<CR>" \
  "K,<C-a>" "K,<BS>" "K,a,n,<BS>" "K,a,n,<BS>,<BS>,<BS>" "K,a,n,<Space>,x" \
  "K,a,n,<Space>,<BS>" "K,a,n,<Space>,<C-\\><C-n>" "K,a,n,<Space>,<C-\\><C-n>,i" \
  "K,a,n,<C-c>" "K,a,n,<Left>" "<C-a>" "<BS>" "<Esc>" "<Esc>,<C-\\><C-n>" \
  "<C-\\><C-n>" "<C-\\><C-n>,i" "<Plug>(skkeleton-disable)" "K,a,n,<Plug>(skkeleton-disable)" \
  "K,a,n,<Space>,<Esc>" "K,a,n,<Space>,<C-a>" "K,a,n,<Space>,<C-q>" "K,a,n,<Space>,<C-j>" \
  "K,a,n,<Space>,<CR>" "K,a,n,<C-j>" "K,a,n,<CR>" "K,a,n,<C-g>" "K,a,n,<C-q>" \
  "K,a,n,<C-t>" "K,a,n,<C-v>" "K,a,n,<C-k>" "K,a,n,<Space>,<Tab>" "K,a,n,<Space>,<Insert>"
do
  nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua \
    --replay "$seq" --profile terminal --out "/tmp/terminal-$(echo "$seq" | tr '/<>,' '____').jsonl"
done
```

## アルファベットでの探索

同じプロファイルのアルファベット（`a`、`K`、`<Space>`、`<C-j>`、`<C-g>`、`<Esc>`、`<C-c>`、
`<C-r>`、`<Tab>`、`<C-\><C-n>`、`Kan`）で幅優先探索も流しました。

```sh
nvim --headless -u NONE -i NONE -l semantics/explore/explore.lua --bfs --profile terminal --depth 3
```

結果: 広げた遷移 660、残った状態 364、観測 2557 行、状態クラス 6 種類
（`N_OFF`、`I_DIRECT`、`T_DIRECT`、`T_POINT`、`T_NORMAL`、`P_PROMPT`）、遷移 86 種類。
`P_PROMPT` は `KanKa` のような候補の無い読みで辞書登録のプロンプトが開く道で、
中は 07c（#189）です。

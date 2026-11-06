# formal-semantics ブランチの決まり

Neovim のモードと skkeleton の入力状態を合わせた「今の」振る舞いを、人が読める仕様にする作業（#179）のためのブランチの決まりです。コード読解・実機の黒箱探索・モデル検査（Lua の BFS と SPIN）の 3 つを突き合わせて仕様を作ります。

## ブランチの役割

- `formal-semantics` は調査の結果をまとめる場所です。main にはマージしません。
- ここでは「今の」振る舞いを書くだけです。望ましい振る舞いは決めません（#179 の「ここでは決めないこと」）。
- 実装（`lua/`）は変えません。見つけたバグは直さず、AGENTS.md の書式で別の issue にします。

## タスクのブランチと PR

- タスクごとに `formal-semantics/task-<名前>` ブランチを `formal-semantics` から切ります。
- PR は `formal-semantics` に向けて出します。main には出しません。

```sh
git fetch origin
git worktree add -b formal-semantics/task-<名前> .claude/worktrees/<作業者>-<名前> origin/formal-semantics
gh pr create -R kat0h/skkeleton.nvim -B formal-semantics -H formal-semantics/task-<名前> -t "..." -F body.md
```

## 成果物の置き場所

成果物は `semantics/` に置きます。言葉の定義は `semantics/GLOSSARY.md` にまとめ、タスクは同じ言葉で書きます。

| ディレクトリ | 内容 |
|---|---|
| `semantics/inventory/` | キーとイベントの棚卸し表 |
| `semantics/model/` | 状態機械のモデル |
| `semantics/explore/` | 探索器と観測の結果 |
| `semantics/compare/` | モデルと観測の差 |

- main を取り込むときは merge を使います。
- テストと探索では、一時ディレクトリの辞書だけを使います。シェルの履歴は `HISTFILE=/dev/null` にします。

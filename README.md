# モデル検査の再現の記録

skkeleton.nvim の issue に貼る、再現の様子の記録です。コードは入っていません。

- `issue-N.gif`: issue #N の再現。tmux の中で TUI の nvim を動かし、1 キーごとの画面を記録したもの。画面の下に、押したキーと、モデル検査が見つけた違反を出しています
- `issue-N.cast`: 同じ記録の asciinema の形式（`asciinema play issue-N.cast` で再生できます）

記録は `poc/formal-ui` ブランチの `tests/formal/tui.lua --record` で作り、[agg](https://github.com/asciinema/agg) で GIF にしています。

# ops/ のスクリプトが共通で読む場所の設定。どこから呼んでもよい
O=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
W=$(cd "$O/../../.." && pwd)                       # poc/formal-ui の worktree
REPO=$(dirname "$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)")
R=${FORMAL_REC:-$REPO/.claude/worktrees/formal-rec} # formal-recordings の worktree（GIF 置き場）
LOG=$W/.tests/formal-ops                            # 結果の記録（git には入らない）
mkdir -p "$LOG"
export MINI_PATH=${MINI_PATH:-$HOME/.local/share/nvim/lazy/mini.nvim}
# コミットの末尾に付ける行（例: FORMAL_TRAILER="Co-Authored-By: ..."）。空なら付けない
TRAILER=${FORMAL_TRAILER:-}
msg() { if [ -n "$TRAILER" ]; then printf '%s\n\n%s\n' "$1" "$TRAILER"; else printf '%s\n' "$1"; fi; }

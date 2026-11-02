#!/usr/bin/env bash
# issue に再現の GIF を付ける: attach.sh <番号> <tui.lua の引数>
set -eu
. "$(dirname "$0")/env.sh"
n=$1; shift
(cd "$W" && timeout 300 nvim --headless -u NONE -i NONE -l tests/formal/tui.lua "$@" --record "$R/issue-$n.cast" >/dev/null 2>&1 || true)
python3 "$O/retime.py" "$R/issue-$n.cast"
agg --font-family "JetBrains Mono,Noto Sans Mono CJK JP" --font-size 16 --idle-time-limit 5 --last-frame-duration 5 "$R/issue-$n.cast" "$R/issue-$n.gif" >/dev/null 2>&1
cd "$R"; git add "issue-$n.cast" "issue-$n.gif"
git commit -qm "$(msg "Add reproduction recording for #$n")"
git pull -q --rebase origin formal-recordings; git push -q origin formal-recordings
B=https://raw.githubusercontent.com/kat0h/skkeleton.nvim/formal-recordings; L=https://github.com/kat0h/skkeleton.nvim/blob/formal-recordings
F=$(mktemp)
printf '再現の様子です（tmux の中の TUI。画面の下に何手目か・キー列・違反を出しています）。\n\n![issue-%s](%s/issue-%s.gif)\n\n記録: [issue-%s.cast](%s/issue-%s.cast)。`poc/formal-ui` で `tests/formal/tui.lua %s --record` と流し、agg で GIF にしました。\n' "$n" "$B" "$n" "$n" "$L" "$n" "$*" > "$F"
gh api "repos/kat0h/skkeleton.nvim/issues/$n/comments" -F body=@"$F" -q .html_url; rm -f "$F"

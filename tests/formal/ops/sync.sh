#!/usr/bin/env bash
# origin/main を poc/formal-ui に取り込み（検査の道具は残す）、閉じた issue の既知の項目を外し、回帰の見張りを流す
. "$(dirname "$0")/env.sh"
cd "$W" || exit 1
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "worktree に未コミットの変更がある"; exit 1; }
git fetch -q origin
n=$(git rev-list --count HEAD..origin/main)
if [ "$n" != 0 ]; then
  keep=$(git rev-parse HEAD)
  if ! git merge --no-commit --no-ff origin/main >/dev/null 2>&1; then
    others=$(git diff --name-only --diff-filter=U | grep -v -E '^(tests/formal/|docs/FORMAL.md|Makefile)' || true)
    if [ -n "$others" ]; then git merge --abort; echo "conflict: $others"; exit 2; fi
  fi
  git checkout "$keep" -- tests/formal docs/FORMAL.md Makefile
  git add -A tests/formal docs/FORMAL.md Makefile
  git commit -qm "$(msg 'Merge origin/main into poc/formal-ui, keeping the formal tools')"
  if make test 2>&1 | grep -q 'Fails (0)'; then git push -q origin poc/formal-ui; echo "merged $n"; else echo "merged $n (make test failed; not pushed)"; fi
else
  echo up-to-date
fi
closed=""
for i in $(grep -o 'reason = "#[0-9]*' tests/formal/spec.lua | grep -o '[0-9]*' | sort -u); do
  [ "$(gh api "repos/kat0h/skkeleton.nvim/issues/$i" -q .state 2>/dev/null)" = closed ] && closed="$closed $i"
done
if [ -n "$closed" ]; then
  python3 "$O/drop-known.py" tests/formal/spec.lua $closed
  if ! git diff --quiet tests/formal/spec.lua; then
    git add tests/formal/spec.lua
    git commit -qm "$(msg "test(formal): drop known entries for closed issues:$closed")"
    git push -q origin poc/formal-ui; echo "dropped known:$closed"; n=1
  fi
fi
# core.lua・dict.lua の既知の絞り込みは形がまちまちなので自動では外さず、閉じたものを知らせる
for f in tests/formal/core.lua tests/formal/dict.lua; do
  for i in $(grep -v -E '^\s*--' "$f" | grep -oE '(issue = |reason = "#|"#)[0-9]{2,}' | grep -oE '[0-9]+' | sort -u); do
    [ "$(gh api "repos/kat0h/skkeleton.nvim/issues/$i" -q .state 2>/dev/null)" = closed ] && echo "closed but still known in $f: #$i（手で外す）"
  done
done
if [ "$n" != 0 ]; then
  "$NVIM" --headless -u NONE -i NONE -l tests/formal/check.lua --regress 2>&1 | grep -E '^(✗|△|    |✓ 回帰|✗ 回帰)'
fi

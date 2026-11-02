#!/usr/bin/env bash
# いちばん長く調べていないプロファイルを順に回す（幅優先はキャッシュ、ファジングは続きから）。使い方: rotate.sh [数]
. "$(dirname "$0")/env.sh"
for _ in $(seq 1 "${1:-1}"); do
  p=$(python3 - "$LOG/rotate.json" <<'PY'
import json, os, sys, time
st = json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {}
names = ["default","modes","config","cmdline","misc","blink","okuri","steal","terminal","options","macro","undo","block","register","regcmd","unmapped","paste"]  # インジケータだけのプロファイルは外した（利用者の判断）
p = min(names, key=lambda n: st.get(n, 0)); st[p] = time.time(); json.dump(st, open(sys.argv[1], "w")); print(p)
PY
)
  timeout -k 10 300 "$O/run.sh" "$p d4" --profile "$p" --depth 4 || echo "timeout/失敗 ($?): $p"
  timeout -k 10 300 "$O/run.sh" "$p fuzz" --profile "$p" --fuzz 200 --seed-depth 0 --length 25 --seed "$(date +%s)" || echo "timeout/失敗 ($?): $p"
done
cd "$W"
timeout -k 10 200 nvim --headless -u NONE -i NONE -l tests/formal/core.lua --random 50000 --length 30 --seed "$(date +%s)" 2>&1 | grep -E '^(✓|✗|△)'; [ ${PIPESTATUS[0]} -eq 0 ] || echo "core/dict の検査が timeout か失敗"
timeout -k 10 200 nvim --headless -u NONE -i NONE -l tests/formal/core.lua --kanatable '{ ["z,"] = { "‥" } }' --keymap '{ { "input", "z", "henkanFirst" }, { "input", ";", "henkanPoint" } }' --random 30000 --length 30 --seed "$(date +%s)" 2>&1 | grep -E '^(✓|✗|△)'; [ ${PIPESTATUS[0]} -eq 0 ] || echo "core/dict の検査が timeout か失敗"
timeout -k 10 200 nvim --headless -u NONE -i NONE -l tests/formal/dict.lua --random 5000 --length 20 --seed "$(date +%s)" 2>&1 | grep -E '^(✓|✗|△)'; [ ${PIPESTATUS[0]} -eq 0 ] || echo "core/dict の検査が timeout か失敗"
timeout -k 10 200 nvim --headless -u NONE -i NONE -l tests/formal/jisyo.lua --random 2000 --seed "$(date +%s)" 2>&1 | grep -E '^(✓|✗|△)'; [ ${PIPESTATUS[0]} -eq 0 ] || echo "jisyo の検査が timeout か失敗"

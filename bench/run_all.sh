#!/usr/bin/env bash
# Phase 1 のベンチをまとめて動かす: bench/run_all.sh [回数]
# 結果は bench/out/results.jsonl に追記し、最後に bench/report.lua で表にする
set -euo pipefail
cd "$(dirname "$0")/.."
REPS=${1:-5}
D=${SKK_DIR:-/usr/share/skk}/SKK-JISYO
MULTI="$D.L $D.jinmei $D.geo $D.station $D.propernoun"
NV="nvim --headless -u NONE -l"
OUT=bench/out/results.jsonl
mkdir -p bench/out
: > "$OUT"
$NV bench/build.lua $MULTI >> "$OUT"
$NV bench/verify.lua $MULTI
$NV bench/gen_queries.lua $D.L
for set in single multi; do
  if [ $set = single ]; then dicts="$D.L"; else dicts="$MULTI"; fi
  for impl in A B C Cp; do
    for _ in $(seq "$REPS"); do
      $NV bench/run.lua $impl $dicts >> "$OUT"
    done
  done
done
$NV bench/report.lua "$OUT"

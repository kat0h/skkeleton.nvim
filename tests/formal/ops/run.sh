#!/usr/bin/env bash
# make verify を 1 回流し、要約を出して .tests/formal-ops/runs.log に残す。使い方: run.sh <label> <make verify の ARGS>
. "$(dirname "$0")/env.sh"
label="$1"; shift; args="$*"; tmp=$(mktemp)
(cd "$W" && make -s verify ARGS="$args") >"$tmp" 2>&1; rc=$?
{ printf '== %s %s [%s] rc=%s ARGS=%s\n' "$(date '+%F %T')" "$label" "$(git -C "$W" rev-parse --short HEAD)" "$rc" "$args"
  grep -E '^(✗|△|～|✓|計|random)' -A2 "$tmp" | grep -v '^--' | head -30; } | tee -a "$LOG/runs.log"
rm -f "$tmp"

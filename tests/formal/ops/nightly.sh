#!/usr/bin/env bash
# 週に 1 回、全プロファイルを Neovim nightly で短く流す。nightly はこの worktree の .tests に置き、
# ~/.local などには入れない。NVIM_DIR に nvim があればそれを使う（stable で流し方を試すときにも使える）。
# 使い方: tests/formal/ops/nightly.sh [深さ]
set -u
. "$(dirname "$0")/env.sh"
depth=${1:-2}
NVIM_DIR=${NVIM_DIR:-$W/.tests/nvim-nightly}
if [ ! -x "$NVIM_DIR/bin/nvim" ]; then
  url="https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz"
  tmp=$(mktemp)
  if ! curl -fsSL --retry 5 --retry-all-errors -o "$tmp" "$url"; then
    rm -f "$tmp"
    echo "nightly のダウンロードに失敗した: $url"
    exit 1
  fi
  mkdir -p "$NVIM_DIR"
  tar -xzf "$tmp" -C "$NVIM_DIR" --strip-components=1
  rm -f "$tmp"
fi
export NVIM="$NVIM_DIR/bin/nvim"
"$NVIM" --version | head -1
for p in default modes config cmdline misc blink okuri steal terminal options macro undo block register regcmd unmapped paste annot wrap edge; do
  timeout -k 10 180 "$O/run.sh" "nightly $p" --profile "$p" --depth "$depth" || echo "nightly $p が失敗した"
done
# 入力エンジンと辞書の速い検査
cd "$W"
for cmd in \
  "core.lua --random 20000 --length 30 --seed $(date +%s)" \
  "dict.lua --random 2000 --length 20 --seed $(date +%s)" \
  "jisyo.lua --random 1000 --seed $(date +%s)"; do
  timeout -k 10 200 "$NVIM" --headless -u NONE -i NONE -l "tests/formal/${cmd%% *}" ${cmd#* } 2>&1 | grep -E '^(✓|✗|△)'
  [ "${PIPESTATUS[0]}" -eq 0 ] || echo "nightly の速い検査が失敗した: $cmd"
done

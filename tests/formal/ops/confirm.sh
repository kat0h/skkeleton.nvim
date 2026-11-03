#!/usr/bin/env bash
# headless で出た違反を、issue にする前に TUI で確かめる。
# 使い方: tests/formal/ops/confirm.sh --profile <p> --keys '<キー列>' [--config '<設定>']
# tmux の中の nvim でキーを打ち、終わった画面（tmux capture-pane）と、RPC で取った
# バッファ・カーソル・モード・g:skkeleton#state・浮動ウィンドウを出す。
set -eu
. "$(dirname "$0")/env.sh"
(cd "$W" && timeout 300 "$NVIM" --headless -u NONE -i NONE -l tests/formal/tui.lua "$@" --confirm)

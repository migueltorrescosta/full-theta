#!/usr/bin/env bash
# The bot batch as a transient user unit, never in the foreground (FT-TST-022):
#   tools/bot_batch.sh [flags of tools/bot_batch.gd]
# Wait for it with: while systemctl --user is-active --quiet ft-bot-batch; do sleep 30; done
# Stop it with: systemctl --user stop ft-bot-batch. Output: build/bot_batch/ and the unit's journal.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
godot=$("$root/tools/get-godot.sh")
exec systemd-run --user --unit=ft-bot-batch -E PATH="$PATH" --working-directory="$root" \
  "$godot" --headless --path . -s res://tools/bot_batch.gd -- "$@"

#!/usr/bin/env bash
# systemd-stop.sh — called by ccbot-bot.service to stop the bot cleanly.
set -euo pipefail

TMUX_BOT_SESSION="ccbot-bot"
LOG_FILE="${HOME}/.ccbot/ccbot.log"

if tmux has-session -t "$TMUX_BOT_SESSION" 2>/dev/null; then
    # Send Ctrl-C first for graceful shutdown
    tmux send-keys -t "${TMUX_BOT_SESSION}:bot" C-c 2>/dev/null || true
    sleep 3
    # Kill the session
    tmux kill-session -t "$TMUX_BOT_SESSION" 2>/dev/null || true
    echo "$(date '+%F %T') - systemd-stop: ccbot-bot stopped" >> "$LOG_FILE"
fi

#!/usr/bin/env bash
# restart-pipx.sh — revert to the original pipx-installed ccbot.
#
# Usage: ./scripts/restart-pipx.sh
set -euo pipefail

TMUX_SESSION="ccbot-bot"
TMUX_WINDOW="bot"
TARGET="${TMUX_SESSION}:${TMUX_WINDOW}"
LOG_FILE="${HOME}/.ccbot/ccbot.log"
MAX_WAIT=10

if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Error: tmux session '$TMUX_SESSION' does not exist"
    exit 1
fi

PANE_PID=$(tmux list-panes -t "$TARGET" -F '#{pane_pid}')

is_ccbot_running() {
    pstree -a "$PANE_PID" 2>/dev/null | grep -q 'ccbot'
}

if is_ccbot_running; then
    echo "Stopping running ccbot…"
    tmux send-keys -t "$TARGET" C-c
    waited=0
    while is_ccbot_running && [ "$waited" -lt "$MAX_WAIT" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if is_ccbot_running; then
        CCBOT_PID=$(pstree -ap "$PANE_PID" 2>/dev/null | grep -oP 'python[^,]*,\K\d+' | head -1)
        [ -n "${CCBOT_PID:-}" ] && kill -9 "$CCBOT_PID" 2>/dev/null || true
        sleep 1
    fi
    echo "Stopped."
fi

sleep 1
echo "Starting pipx ccbot…"
tmux send-keys -t "$TARGET" "ccbot >> ${LOG_FILE} 2>&1" Enter

sleep 3
if is_ccbot_running; then
    echo "ccbot (pipx) started. Logs: tail -f ${LOG_FILE}"
else
    echo "WARNING: may not have started. Check: tmux attach -t $TARGET"
    exit 1
fi

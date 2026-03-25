#!/usr/bin/env bash
# restart-local.sh — restart ccbot-bot using the local venv (patched version).
#
# Usage: ./scripts/restart-local.sh
#
# Stops the current bot in tmux session ccbot-bot:bot and starts the
# patched version from .venv.  Logs go to ~/.ccbot/ccbot.log.
# To revert to the pipx version, run: ./scripts/restart-pipx.sh
set -euo pipefail

TMUX_SESSION="ccbot-bot"
TMUX_WINDOW="bot"
TARGET="${TMUX_SESSION}:${TMUX_WINDOW}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_BIN="${PROJECT_DIR}/.venv/bin"
LOG_FILE="${HOME}/.ccbot/ccbot.log"
MAX_WAIT=10

# Check venv
if [ ! -x "${VENV_BIN}/ccbot" ]; then
    echo "Error: ${VENV_BIN}/ccbot not found. Run:  python3 -m venv .venv && .venv/bin/pip install -e ."
    exit 1
fi

# Recreate session if it doesn't exist
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Creating tmux session '$TMUX_SESSION'…"
    tmux new-session -d -s "$TMUX_SESSION" -n "$TMUX_WINDOW"
fi

# Get pane PID
PANE_PID=$(tmux list-panes -t "$TARGET" -F '#{pane_pid}' 2>/dev/null || echo "")

is_ccbot_running() {
    [ -n "$PANE_PID" ] && pstree -a "$PANE_PID" 2>/dev/null | grep -q 'ccbot'
}

# Stop existing process
if is_ccbot_running; then
    echo "Stopping running ccbot…"
    tmux send-keys -t "$TARGET" C-c
    waited=0
    while is_ccbot_running && [ "$waited" -lt "$MAX_WAIT" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if is_ccbot_running; then
        echo "Force-killing ccbot…"
        CCBOT_PID=$(pstree -ap "$PANE_PID" 2>/dev/null | grep -oP 'python[^,]*,\K\d+' | head -1)
        [ -n "${CCBOT_PID:-}" ] && kill -9 "$CCBOT_PID" 2>/dev/null || true
        sleep 1
    fi
    echo "Stopped."
else
    echo "No ccbot running in $TARGET"
fi

# Re-get pane PID after potential session recreation
PANE_PID=$(tmux list-panes -t "$TARGET" -F '#{pane_pid}' 2>/dev/null || echo "")

sleep 1

# Start from local venv
echo "Starting patched ccbot from ${VENV_BIN}/ccbot …"
tmux send-keys -t "$TARGET" "${VENV_BIN}/ccbot >> ${LOG_FILE} 2>&1" Enter

sleep 3

# Re-read pane PID (may have changed)
PANE_PID=$(tmux list-panes -t "$TARGET" -F '#{pane_pid}' 2>/dev/null || echo "")

if is_ccbot_running; then
    echo "ccbot (patched) started successfully."
    echo "Logs: tail -f ${LOG_FILE}"
    echo "Recent log:"
    echo "────────────────────────────────"
    tail -10 "$LOG_FILE"
    echo "────────────────────────────────"
else
    echo "WARNING: ccbot may not have started. Check:"
    echo "  tmux attach -t $TARGET"
    echo "  tail -50 $LOG_FILE"
    exit 1
fi

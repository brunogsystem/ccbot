#!/usr/bin/env bash
# systemd-start.sh — called by ccbot-bot.service to bootstrap tmux + ccbot.
#
# Creates the required tmux sessions and starts the patched ccbot from
# the local .venv.  Designed for Type=forking systemd units.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_BIN="${PROJECT_DIR}/.venv/bin"
LOG_FILE="${HOME}/.ccbot/ccbot.log"

TMUX_BOT_SESSION="ccbot-bot"
TMUX_CCBOT_SESSION="ccbot"

# Ensure log dir exists
mkdir -p "$(dirname "$LOG_FILE")"

# Ensure the "ccbot" tmux session exists (Claude Code windows live here).
# The bot process itself lives in a separate "ccbot-bot" session.
if ! tmux has-session -t "$TMUX_CCBOT_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$TMUX_CCBOT_SESSION" -n shell
    echo "$(date '+%F %T') - systemd-start: created tmux session '$TMUX_CCBOT_SESSION'" >> "$LOG_FILE"
fi

# Create (or recreate) the ccbot-bot session and start the bot
if tmux has-session -t "$TMUX_BOT_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_BOT_SESSION" 2>/dev/null || true
fi
tmux new-session -d -s "$TMUX_BOT_SESSION" -n bot \
    bash -lc "${VENV_BIN}/ccbot >> ${LOG_FILE} 2>&1"

echo "$(date '+%F %T') - systemd-start: ccbot-bot started (venv=${VENV_BIN})" >> "$LOG_FILE"

#!/usr/bin/env bash
# systemd-start.sh — called by ccbot-bot.service to bootstrap tmux + ccbot.
#
# 1. Ensures the "ccbot" tmux session exists (Claude Code windows live here).
# 2. Ensures configured Claude Code windows exist and Claude is running.
# 3. Creates "ccbot-bot" session and starts the patched Telegram bot.
#
# Designed for Type=forking systemd --user units.  Idempotent: safe to
# call when sessions/windows already exist.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_BIN="${PROJECT_DIR}/.venv/bin"
LOG_FILE="${HOME}/.ccbot/ccbot.log"

TMUX_BOT_SESSION="ccbot-bot"
TMUX_CCBOT_SESSION="ccbot"

log() { echo "$(date '+%F %T') - systemd-start: $*" >> "$LOG_FILE"; }

# Ensure log dir exists
mkdir -p "$(dirname "$LOG_FILE")"

# ── 1. Ensure "ccbot" tmux session ─────────────────────────────────────
if ! tmux has-session -t "$TMUX_CCBOT_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$TMUX_CCBOT_SESSION" -n shell
    log "created tmux session '$TMUX_CCBOT_SESSION'"
fi

# ── 2. Ensure Claude Code windows ──────────────────────────────────────
#
# Each entry: WINDOW_NAME  CWD  CLAUDE_ARGS
# Add more lines to auto-create additional Claude Code sessions.
ensure_claude_window() {
    local win_name="$1"
    local win_cwd="$2"
    shift 2
    local claude_args=("$@")

    # Check if window already exists (by name)
    if tmux list-windows -t "$TMUX_CCBOT_SESSION" -F '#{window_name}' 2>/dev/null \
            | grep -qx "$win_name"; then
        # Window exists — check if Claude is running in it
        local pane_cmd
        pane_cmd=$(tmux list-panes -t "${TMUX_CCBOT_SESSION}:${win_name}" \
                       -F '#{pane_current_command}' 2>/dev/null || echo "")
        if echo "$pane_cmd" | grep -q "claude"; then
            log "window '$win_name' already has Claude running — skipped"
            return 0
        fi
        # Window exists but Claude not running — start it
        log "window '$win_name' exists but no Claude — starting Claude"
        tmux send-keys -t "${TMUX_CCBOT_SESSION}:${win_name}" \
            "cd ${win_cwd} && claude ${claude_args[*]}" Enter
        return 0
    fi

    # Window doesn't exist — create and start Claude
    log "creating window '$win_name' (cwd=${win_cwd})"
    tmux new-window -t "$TMUX_CCBOT_SESSION" -n "$win_name" -c "$win_cwd"
    # Small delay for shell init
    sleep 0.5
    tmux send-keys -t "${TMUX_CCBOT_SESSION}:${win_name}" \
        "claude ${claude_args[*]}" Enter
    log "started Claude in window '$win_name'"
}

# ── Claude Code windows to maintain ────────────────────────────────────
ensure_claude_window "XGBoost" \
    "/home/bruno/workspaces/ccbot/XGBoost" \
    --dangerously-skip-permissions

# ── 3. Start ccbot Telegram bot ────────────────────────────────────────
if tmux has-session -t "$TMUX_BOT_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_BOT_SESSION" 2>/dev/null || true
fi
tmux new-session -d -s "$TMUX_BOT_SESSION" -n bot \
    bash -lc "${VENV_BIN}/ccbot >> ${LOG_FILE} 2>&1"

log "ccbot-bot started (venv=${VENV_BIN})"

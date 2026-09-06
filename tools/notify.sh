#!/usr/bin/env bash
# ==============================================================================
# HAWS Remote Mobile Notification Dispatcher
# Supports: Telegram Bot, Discord Webhook, Generic HTTP Webhook
# Triggered by: Long-running autonomous tasks (/goal), CI/CD, or manual alerts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load configuration from optional config files
if [ -f "${SCRIPT_DIR}/secondbrain/.notify.conf" ]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/secondbrain/.notify.conf"
elif [ -f "${SCRIPT_DIR}/.notify.conf" ]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.notify.conf"
fi

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
HAWS_WEBHOOK_URL="${HAWS_WEBHOOK_URL:-}"

DRY_RUN=false
TEST_MODE=false
STATUS_MODE=false
MESSAGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        --status)
            STATUS_MODE=true
            shift
            ;;
        *)
            if [ -z "${MESSAGE}" ]; then
                MESSAGE="$1"
            else
                MESSAGE="${MESSAGE} $1"
            fi
            shift
            ;;
    esac
done

if [ "$STATUS_MODE" = true ]; then
    echo "=== HAWS Notification Channel Status ==="
    [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ] && echo "  [ACTIVE] Telegram Bot (Chat ID: ${TELEGRAM_CHAT_ID})" || echo "  [OFFLINE] Telegram Bot (Not configured)"
    [ -n "${DISCORD_WEBHOOK_URL}" ] && echo "  [ACTIVE] Discord Webhook" || echo "  [OFFLINE] Discord Webhook (Not configured)"
    [ -n "${HAWS_WEBHOOK_URL}" ] && echo "  [ACTIVE] Generic Webhook (${HAWS_WEBHOOK_URL})" || echo "  [OFFLINE] Generic Webhook (Not configured)"
    echo ""
    echo "Configuration locations: secondbrain/.notify.conf or .notify.conf"
    exit 0
fi

if [ "$TEST_MODE" = true ]; then
    MESSAGE="[HAWS Test Notification] Autonomous task dispatcher operational at $(date '+%Y-%m-%d %H:%M:%S')."
fi

if [ -z "${MESSAGE}" ]; then
    echo "Usage: ./tools/notify.sh [--test|--status|--dry-run] [message text]"
    exit 1
fi

SENT_CHANNELS=0

# 1. Telegram Dispatch
if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would dispatch Telegram message to chat ${TELEGRAM_CHAT_ID}: ${MESSAGE}"
    else
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${MESSAGE}" \
            -d "parse_mode=Markdown" >/dev/null 2>&1 || true
        echo "  [✓] Telegram notification dispatched."
    fi
    SENT_CHANNELS=$((SENT_CHANNELS + 1))
fi

# 2. Discord Dispatch
if [ -n "${DISCORD_WEBHOOK_URL}" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would dispatch Discord webhook: ${MESSAGE}"
    else
        curl -s -H "Content-Type: application/json" -X POST \
            -d "{\"content\":\"${MESSAGE}\"}" \
            "${DISCORD_WEBHOOK_URL}" >/dev/null 2>&1 || true
        echo "  [✓] Discord webhook dispatched."
    fi
    SENT_CHANNELS=$((SENT_CHANNELS + 1))
fi

# 3. Generic Webhook Dispatch
if [ -n "${HAWS_WEBHOOK_URL}" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would dispatch Generic webhook: ${MESSAGE}"
    else
        curl -s -H "Content-Type: application/json" -X POST \
            -d "{\"message\":\"${MESSAGE}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
            "${HAWS_WEBHOOK_URL}" >/dev/null 2>&1 || true
        echo "  [✓] Generic webhook dispatched."
    fi
    SENT_CHANNELS=$((SENT_CHANNELS + 1))
fi

if [ "${SENT_CHANNELS}" -eq 0 ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] No remote channels configured. Payload validated: ${MESSAGE}"
    else
        echo "[INFO] No notification channels configured."
        echo "To receive alerts, add credentials in secondbrain/.notify.conf:"
        echo "  TELEGRAM_BOT_TOKEN=\"...\""
        echo "  TELEGRAM_CHAT_ID=\"...\""
        echo "  DISCORD_WEBHOOK_URL=\"...\""
    fi
fi
exit 0

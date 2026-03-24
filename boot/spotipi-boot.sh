#!/bin/bash
# spotipi-boot.sh — Boot orchestration script
# Runs at startup, decides which service to activate next.
# Called by spotipi-boot.service

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$PROJECT_DIR/venv"
PYTHON="$VENV/bin/python3"
TOKEN_PATH="$HOME/.spotipi/token.json"
LOG_PREFIX="[spotipi-boot]"

log() { echo "$LOG_PREFIX $*"; }

# ── 1. Check WiFi ──────────────────────────────────────────────────────────────
log "Checking WiFi connection..."

WIFI_SSID=$(iwgetid -r 2>/dev/null || true)

if [[ -z "$WIFI_SSID" ]]; then
    log "No WiFi — starting wifi setup service"
    systemctl start spotipi-wifi.service
    exit 0
fi

log "WiFi connected: $WIFI_SSID"

# ── 2. Check Spotify token ─────────────────────────────────────────────────────
log "Checking Spotify token..."

if [[ ! -f "$TOKEN_PATH" ]]; then
    log "No token — starting auth service"
    systemctl start spotipi-auth.service
    exit 0
fi

# Verify token has required fields (quick sanity check)
if ! python3 -c "
import json, sys
try:
    t = json.load(open('$TOKEN_PATH'))
    assert 'access_token' in t and 'refresh_token' in t
except Exception as e:
    sys.exit(1)
" 2>/dev/null; then
    log "Token invalid — starting auth service"
    rm -f "$TOKEN_PATH"
    systemctl start spotipi-auth.service
    exit 0
fi

log "Token OK — starting main display service"
systemctl start spotipi.service

#!/bin/bash
# SpotiPi Setup Script
# ====================
# Run ONCE on a fresh Raspberry Pi OS (Lite or Desktop) with:
#   sudo bash setup.sh
#
# Tested on: Raspberry Pi OS Bookworm (Debian 12)

set -euo pipefail

INSTALL_DIR="/opt/spotipi"
SERVICE_USER="${SUDO_USER:-pi}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { echo -e "\033[1;32m[spotipi]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }
die()  { echo -e "\033[1;31m[error]\033[0m $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && die "Run with sudo: sudo bash setup.sh"

# ── 1. System packages ─────────────────────────────────────────────────────────
log "Installing system packages..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-pygame \
    xserver-xorg-core \
    xinit \
    x11-xserver-utils \
    openbox \
    chromium \
    chromium-browser \
    hostapd \
    dnsmasq \
    wireless-tools \
    fonts-dejavu-core \
    libatlas-base-dev \
    libjpeg-dev

# ── 2. Copy project files ──────────────────────────────────────────────────────
log "Copying project files to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rsync -a --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
    "$SCRIPT_DIR/" "$INSTALL_DIR/"

chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# ── 3. Python venv + deps ──────────────────────────────────────────────────────
log "Creating Python virtual environment..."
sudo -u "$SERVICE_USER" python3 -m venv "$INSTALL_DIR/venv"

log "Installing Python dependencies..."
sudo -u "$SERVICE_USER" "$INSTALL_DIR/venv/bin/pip" install \
    --quiet --no-cache-dir \
    -r "$INSTALL_DIR/requirements.txt"

# ── 4. Make scripts executable ─────────────────────────────────────────────────
chmod +x "$INSTALL_DIR/boot/spotipi-boot.sh"
chmod +x "$INSTALL_DIR/wifi/wifi_setup.py"
chmod +x "$INSTALL_DIR/auth/spotify_auth.py"
chmod +x "$INSTALL_DIR/auth/auth_display.py"
chmod +x "$INSTALL_DIR/display/app.py"

# ── 5. systemd services ────────────────────────────────────────────────────────
log "Installing systemd services..."
cp "$INSTALL_DIR/services/"*.service /etc/systemd/system/
systemctl daemon-reload

# Enable boot orchestrator only; it starts the others as needed
systemctl enable spotipi-boot.service
systemctl disable spotipi-wifi.service  2>/dev/null || true
systemctl disable spotipi-auth.service  2>/dev/null || true
systemctl disable spotipi.service       2>/dev/null || true

# ── 6. hostapd default config pointer ─────────────────────────────────────────
if [[ -f /etc/default/hostapd ]]; then
    sed -i 's|#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
fi

# Mask hostapd/dnsmasq until wifi_setup.py needs them
systemctl mask hostapd dnsmasq 2>/dev/null || true

# ── 7. X11 auto-login (Lite OS) ───────────────────────────────────────────────
log "Configuring auto-login for user $SERVICE_USER..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $SERVICE_USER --noclear %I \$TERM
EOF

# Add startx to bashrc if running on tty1 (for Lite)
BASHRC="/home/$SERVICE_USER/.bashrc"
if ! grep -q "spotipi" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<'BASHEOF'

# SpotiPi: auto-start X on tty1
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    startx -- -nocursor
fi
BASHEOF
fi

# ── 8. .env check ─────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Setup complete! ✅"
echo ""
warn "⚠️  REQUIRED: Fill in your Spotify Client ID (PKCE; no secret needed)"
echo "   Edit: $INSTALL_DIR/.env"
echo "   Set:  SPOTIPY_CLIENT_ID=your_client_id_here"
echo ""
warn "⚠️  REQUIRED: Add to Spotify Developer Dashboard"
echo "   Redirect URI: http://localhost:8888/callback"
echo ""
log "Reboot now? (y/N)"
read -r answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    reboot
fi

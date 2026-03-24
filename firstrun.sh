#!/bin/bash
# firstrun-v2.sh — SpotiPi first-boot orchestrator
# ===================================================
# 修正順序：先確保 WiFi 連線，再跑 apt install
#
# 流程：
#   1. 偵測 WiFi 設定
#   2. 若無 → 建立 AP 熱點 (nmcli) + captive portal (Python3 built-in)
#   3. 等待使用者用手機填入 WiFi/Spotify 設定
#   4. 連上 WiFi → 驗證網路
#   5. apt-get update && apt-get install（所有依賴）
#   6. 部署 SpotiPi（copy files、venv、services）
#   7. 重開機進入播放模式
#
# 需要：Raspberry Pi OS Bookworm（nmcli、python3 內建即可）
# 執行身份：root（由 systemd firstboot 呼叫）

set -euo pipefail

AP_SSID="SpotiPi-Setup"
AP_PASS="spotipi123"
AP_IP="192.168.4.1"
PORTAL_PORT=80

BOOT_DIR="/boot/firmware"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
PROJECT_SRC="$BOOT_DIR/spotipi"
INSTALL_DIR="/opt/spotipi"

log()  { echo -e "\033[1;32m[spotipi-firstrun]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }
die()  { echo -e "\033[1;31m[fatal]\033[0m $*" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# 工具函式
# ─────────────────────────────────────────────────────────────────────────────

has_wifi_config() {
    # 檢查 wpa_supplicant.conf 是否有 network block
    if [[ -f "$WPA_CONF" ]] && grep -q "network={" "$WPA_CONF" 2>/dev/null; then
        return 0
    fi
    # 也檢查 boot 分區（Pi OS Imager 放在這）
    if [[ -f "$BOOT_DIR/wpa_supplicant.conf" ]] && grep -q "network={" "$BOOT_DIR/wpa_supplicant.conf" 2>/dev/null; then
        # 複製到正確位置
        cp "$BOOT_DIR/wpa_supplicant.conf" "$WPA_CONF"
        return 0
    fi
    return 1
}

wait_for_network() {
    local max_wait="${1:-90}"
    log "等待網路連線（最多 ${max_wait} 秒）..."
    for i in $(seq 1 "$max_wait"); do
        if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
            log "✅ 網路連線成功"
            return 0
        fi
        echo "  [$i/${max_wait}] 等待中..."
        sleep 1
    done
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 步驟 1：檢查 WiFi 設定
# ─────────────────────────────────────────────────────────────────────────────

log "=== SpotiPi First-Run v2 ==="
log "步驟 1：檢查 WiFi 設定..."

if has_wifi_config; then
    log "✅ 找到 WiFi 設定，直接等待連線..."
    if ! wait_for_network 90; then
        warn "WiFi 設定存在但連不上網，改走 AP 設定流程"
        # 清除舊設定後進入 AP 流程
        rm -f "$WPA_CONF" "$BOOT_DIR/wpa_supplicant.conf"
        # fall through to AP setup below
    else
        # 有網路，跳到安裝步驟
        SKIP_AP=true
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 步驟 2：建立 AP 熱點 + Captive Portal（僅在無 WiFi 設定時）
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${SKIP_AP:-false}" != "true" ]]; then
    log "步驟 2：無 WiFi 設定，建立 AP 熱點 '$AP_SSID'..."

    # 使用 nmcli 建立 AP（Pi OS Bookworm 內建）
    nmcli radio wifi on 2>/dev/null || true

    # 刪除舊的 SpotiPi hotspot（如有）
    nmcli connection delete "$AP_SSID" 2>/dev/null || true

    nmcli connection add \
        type wifi \
        ifname wlan0 \
        con-name "$AP_SSID" \
        autoconnect no \
        ssid "$AP_SSID" \
        -- \
        wifi.mode ap \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$AP_PASS" \
        ipv4.method shared \
        ipv4.addresses "$AP_IP/24"

    nmcli connection up "$AP_SSID"

    log "✅ AP 熱點啟動：SSID=$AP_SSID / 密碼=$AP_PASS"
    log "   手機連上後瀏覽：http://$AP_IP/"

    # ── 建立 Captive Portal（純 Python3，不需 Flask）──────────────────────────

    PORTAL_DIR="$(mktemp -d)"
    PORTAL_DATA_FILE="$PORTAL_DIR/submitted.json"
    PORTAL_HTML="$PORTAL_DIR/index.html"

    # 複製 HTML（如果 spotipi 目錄有的話）；否則內嵌一份精簡版
    if [[ -f "$PROJECT_SRC/wifi/templates/wifi_setup.html" ]]; then
        cp "$PROJECT_SRC/wifi/templates/wifi_setup.html" "$PORTAL_HTML"
    else
        cat > "$PORTAL_HTML" <<'HTML'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SpotiPi WiFi 設定</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,sans-serif;background:linear-gradient(135deg,#1DB954,#191414);
         min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
    .card{background:#fff;border-radius:16px;padding:32px;max-width:400px;width:100%;box-shadow:0 10px 40px rgba(0,0,0,.3)}
    h1{color:#191414;margin-bottom:8px;font-size:24px}
    p.sub{color:#666;margin-bottom:24px;font-size:13px}
    label{display:block;color:#333;font-weight:600;margin-bottom:5px}
    input{width:100%;padding:12px;border:2px solid #e0e0e0;border-radius:8px;font-size:15px;margin-bottom:16px}
    input:focus{outline:none;border-color:#1DB954}
    button{width:100%;padding:14px;background:#1DB954;color:#fff;border:none;border-radius:8px;
           font-size:16px;font-weight:600;cursor:pointer}
    .err{background:#ffeaea;color:#c0392b;border:1px solid #f5c6cb;padding:10px;border-radius:8px;
         margin-bottom:12px;display:none;font-size:13px}
    .ok{background:#eaffea;color:#27ae60;border:1px solid #c3e6cb;padding:10px;border-radius:8px;
        margin-bottom:12px;display:none;font-size:13px}
  </style>
</head>
<body>
  <div class="card">
    <h1>🎵 SpotiPi 設定</h1>
    <p class="sub">輸入 WiFi 與 Spotify 資訊後，系統將自動重新啟動並開始播放。</p>
    <div class="err" id="err"></div>
    <div class="ok" id="ok">設定成功！系統正在重新啟動，請稍候...</div>
    <form id="f">
      <label>WiFi 名稱 (SSID)</label>
      <input type="text" name="ssid" placeholder="您的 WiFi 名稱" required>
      <label>WiFi 密碼</label>
      <input type="password" name="password" placeholder="至少 8 個字元" required>
      <label>Spotify Client ID</label>
      <input type="text" name="client_id" placeholder="32 位英數字串" required>
      <label>Spotify Client Secret</label>
      <input type="password" name="client_secret" placeholder="32 位英數字串" required>
      <p style="font-size:11px;color:#888;margin:-8px 0 16px">
        前往 <a href="https://developer.spotify.com" style="color:#1DB954">developer.spotify.com</a>
        建立 App，Redirect URI 填 <code>http://spotipi.local:8888/callback</code>
      </p>
      <button type="submit">儲存設定並連接</button>
    </form>
  </div>
  <script>
    document.getElementById('f').addEventListener('submit',async function(e){
      e.preventDefault();
      const err=document.getElementById('err'),ok=document.getElementById('ok');
      err.style.display='none';
      const body=new URLSearchParams(new FormData(this));
      try{
        const r=await fetch('/connect',{method:'POST',body});
        const d=await r.json();
        if(d.success){this.style.display='none';ok.style.display='block';}
        else{err.textContent=d.error||'設定失敗，請重試';err.style.display='block';}
      }catch{err.textContent='連線錯誤，請重試';err.style.display='block';}
    });
  </script>
</body>
</html>
HTML
    fi

    # 用 Python3 內建 http.server 跑 captive portal
    python3 - "$PORTAL_DIR" "$PORTAL_DATA_FILE" "$WPA_CONF" <<'PYEOF' &
import sys, os, json, threading, time, urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

PORTAL_DIR   = Path(sys.argv[1])
DATA_FILE    = Path(sys.argv[2])
WPA_CONF     = Path(sys.argv[3])
DONE_FLAG    = Path(sys.argv[1]) / ".done"

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a): pass  # 靜音 access log

    def _send(self, code, ctype, body):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", len(b))
        # Captive portal detection endpoints
        self.send_header("Location", "http://192.168.4.1/")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        # 任何 GET 都重導到首頁（captive portal 行為）
        html = (PORTAL_DIR / "index.html").read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", len(html))
        self.end_headers()
        self.wfile.write(html)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode()
        fields = dict(urllib.parse.parse_qsl(raw))

        ssid          = fields.get("ssid", "").strip()
        password      = fields.get("password", "").strip()
        client_id     = fields.get("client_id", "").strip()
        client_secret = fields.get("client_secret", "").strip()

        if not all([ssid, password, client_id, client_secret]):
            resp = json.dumps({"success": False, "error": "請填寫所有欄位"})
            self._send(400, "application/json", resp)
            return
        if len(password) < 8:
            resp = json.dumps({"success": False, "error": "密碼至少需要 8 個字元"})
            self._send(400, "application/json", resp)
            return

        # 寫入 wpa_supplicant.conf
        wpa = f"""country=TW
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={{
    ssid="{ssid}"
    psk="{password}"
    key_mgmt=WPA-PSK
}}
"""
        try:
            WPA_CONF.parent.mkdir(parents=True, exist_ok=True)
            WPA_CONF.write_text(wpa)
            os.chmod(str(WPA_CONF), 0o600)
        except Exception as e:
            resp = json.dumps({"success": False, "error": f"寫入 WiFi 設定失敗: {e}"})
            self._send(500, "application/json", resp)
            return

        # 儲存 Spotify 設定
        DATA_FILE.write_text(json.dumps({
            "ssid": ssid,
            "client_id": client_id,
            "client_secret": client_secret
        }))
        DONE_FLAG.touch()

        resp = json.dumps({"success": True})
        self._send(200, "application/json", resp)

httpd = HTTPServer(("0.0.0.0", 80), Handler)
print(f"[portal] listening on :80, data={DATA_FILE}")
httpd.serve_forever()
PYEOF

    PORTAL_PID=$!
    log "✅ Captive portal 啟動 (PID=$PORTAL_PID)"

    # 等待使用者提交設定
    log "步驟 3：等待手機設定（無時間限制）..."
    while [[ ! -f "$PORTAL_DIR/.done" ]]; do
        sleep 2
    done

    log "✅ 收到 WiFi 設定，停止 AP + Portal..."
    kill "$PORTAL_PID" 2>/dev/null || true

    # ── 關閉 AP，讓 wlan0 連回正常 WiFi ──────────────────────────────────────
    nmcli connection down "$AP_SSID" 2>/dev/null || true
    nmcli connection delete "$AP_SSID" 2>/dev/null || true

    # wpa_supplicant 接管
    wpa_supplicant -B -i wlan0 -c "$WPA_CONF" 2>/dev/null || true
    dhclient wlan0 2>/dev/null || true

    # 步驟 4：確認有網路
    log "步驟 4：驗證網路連線..."
    if ! wait_for_network 90; then
        die "連上 WiFi 後仍無法連網，請確認 WiFi 密碼是否正確，然後重新開機重試。"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 步驟 5：apt-get update && install（現在有網路了）
# ─────────────────────────────────────────────────────────────────────────────

log "步驟 5：安裝系統套件（需要幾分鐘）..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-pygame \
    chromium-browser \
    hostapd \
    dnsmasq \
    wireless-tools \
    fonts-dejavu-core \
    libatlas-base-dev \
    libjpeg-dev

# ─────────────────────────────────────────────────────────────────────────────
# 步驟 6：部署 SpotiPi
# ─────────────────────────────────────────────────────────────────────────────

log "步驟 6：部署 SpotiPi 到 $INSTALL_DIR..."

SERVICE_USER="${SUDO_USER:-pi}"

mkdir -p "$INSTALL_DIR"
rsync -a --exclude='__pycache__' --exclude='*.pyc' \
    "$PROJECT_SRC/" "$INSTALL_DIR/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# Python venv
log "建立 Python venv..."
sudo -u "$SERVICE_USER" python3 -m venv "$INSTALL_DIR/venv"
sudo -u "$SERVICE_USER" "$INSTALL_DIR/venv/bin/pip" install \
    --quiet --no-cache-dir \
    -r "$INSTALL_DIR/requirements.txt"

# 寫入 Spotify 環境變數（如果由 captive portal 取得）
if [[ -f "${PORTAL_DIR:-/dev/null}/submitted.json" ]] 2>/dev/null; then
    CLIENT_ID="$(python3 -c "import json; d=json.load(open('$PORTAL_DIR/submitted.json')); print(d.get('client_id',''))")"
    CLIENT_SECRET="$(python3 -c "import json; d=json.load(open('$PORTAL_DIR/submitted.json')); print(d.get('client_secret',''))")"
    if [[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
        log "寫入 Spotify 認證到 $INSTALL_DIR/.env..."
        cat > "$INSTALL_DIR/.env" <<EOF
SPOTIPY_CLIENT_ID=$CLIENT_ID
SPOTIPY_CLIENT_SECRET=$CLIENT_SECRET
SPOTIPY_REDIRECT_URI=http://spotipi.local:8888/callback
EOF
        chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/.env"
    fi
fi

# Scripts 可執行權限
chmod +x "$INSTALL_DIR/boot/spotipi-boot.sh"

# systemd services
log "安裝 systemd services..."
cp "$INSTALL_DIR/services/"*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable spotipi-boot.service
systemctl disable spotipi-wifi.service  2>/dev/null || true
systemctl disable spotipi-auth.service  2>/dev/null || true
systemctl disable spotipi.service       2>/dev/null || true

# hostapd/dnsmasq mask（wifi_setup.py 需要時再解 mask）
if [[ -f /etc/default/hostapd ]]; then
    sed -i 's|#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
fi
systemctl mask hostapd dnsmasq 2>/dev/null || true

# 自動登入
log "設定 tty1 自動登入..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $SERVICE_USER --noclear %I $TERM
EOF

BASHRC="/home/$SERVICE_USER/.bashrc"
if ! grep -q "spotipi" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<'BASHEOF'

# SpotiPi: auto-start X on tty1
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    startx -- -nocursor
fi
BASHEOF
fi

# 清理暫存
[[ -n "${PORTAL_DIR:-}" ]] && rm -rf "$PORTAL_DIR" || true

# ─────────────────────────────────────────────────────────────────────────────
# 步驟 7：標記完成，重開機
# ─────────────────────────────────────────────────────────────────────────────

log "步驟 7：首次設定完成，5 秒後重開機進入播放模式..."
rm -f "$BOOT_DIR/firstrun.sh"
rm -f "$BOOT_DIR/cmdline.txt.bak"

sleep 5
reboot

#!/usr/bin/env python3
"""
SpotiPi WiFi Setup
==================
Creates a hostapd AP, runs captive portal for credential input,
writes wpa_supplicant.conf, and reboots.

Called by spotipi-wifi.service.
"""

import os
import subprocess
import sys
import threading
import time
from pathlib import Path

from flask import Flask, jsonify, request, render_template

# Project root on sys.path so config is importable
sys.path.insert(0, str(Path(__file__).parent.parent))
import config


def _run(cmd: list, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def check_wifi_connected() -> bool:
    result = _run(["iwgetid", "-r"], check=False)
    return result.returncode == 0 and bool(result.stdout.strip())


def create_ap(ssid: str = config.AP_SSID, password: str = config.AP_PASSWORD) -> bool:
    """Configure hostapd + dnsmasq and bring up AP."""
    hostapd_conf = f"""interface=wlan0
driver=nl80211
ssid={ssid}
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase={password}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
"""
    dnsmasq_conf = f"""interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
address=/#/192.168.4.1
"""

    try:
        Path("/etc/hostapd/hostapd.conf").write_text(hostapd_conf)
        Path("/etc/dnsmasq.conf").write_text(dnsmasq_conf)

        _run(["ifconfig", "wlan0", config.AP_IP, "netmask", "255.255.255.0"])
        _run(["systemctl", "restart", "dnsmasq"])
        _run(["systemctl", "restart", "hostapd"])
        print(f"✅ AP '{ssid}' started at {config.AP_IP}")
        return True
    except Exception as e:
        print(f"❌ Failed to create AP: {e}")
        return False


def write_wpa_conf(ssid: str, password: str, country: str = "TW") -> bool:
    """Write WiFi credentials to /boot/wpa_supplicant.conf."""
    if not ssid or not password:
        return False
    if len(password) < 8:
        return False

    conf = f"""country={country}
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={{
    ssid="{ssid}"
    psk="{password}"
    key_mgmt=WPA-PSK
}}
"""
    try:
        proc = subprocess.Popen(
            ["sudo", "tee", "/boot/wpa_supplicant.conf"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True
        )
        _, stderr = proc.communicate(input=conf)
        if proc.returncode != 0:
            print(f"❌ tee failed: {stderr}")
            return False
        print("✅ wpa_supplicant.conf written")
        return True
    except Exception as e:
        print(f"❌ write_wpa_conf: {e}")
        return False


def write_spotify_env(client_id: str, client_secret: str) -> bool:
    """Write Spotify credentials to .env, preserving existing keys."""
    redirect_uri = "http://spotipi.local:8888/callback"

    # Determine target .env path
    env_dir = Path("/opt/spotipi")
    if env_dir.exists():
        env_path = env_dir / ".env"
    else:
        env_path = Path(__file__).parent.parent / ".env"

    # Read existing .env if present
    existing: dict = {}
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.rstrip("\n")
                if line and not line.startswith("#") and "=" in line:
                    key, _, val = line.partition("=")
                    existing[key.strip()] = val.strip()

    # Overwrite the three Spotify keys
    existing["SPOTIPY_CLIENT_ID"] = client_id
    existing["SPOTIPY_CLIENT_SECRET"] = client_secret
    existing["SPOTIPY_REDIRECT_URI"] = redirect_uri

    try:
        env_path.parent.mkdir(parents=True, exist_ok=True)
        with open(env_path, "w") as f:
            for key, val in existing.items():
                f.write(f"{key}={val}\n")
        print(f"✅ Spotify credentials written to {env_path}")
        return True
    except Exception as e:
        print(f"❌ write_spotify_env: {e}")
        return False


def start_captive_portal(host: str = config.AP_IP, port: int = config.CAPTIVE_PORTAL_PORT) -> None:
    """Flask captive portal: user fills WiFi SSID + password."""
    app = Flask(__name__, template_folder="templates")

    @app.route("/", defaults={"path": ""})
    @app.route("/<path:path>")
    def index(path):
        return render_template("wifi_setup.html")

    @app.route("/connect", methods=["POST"])
    def connect():
        ssid = (request.form.get("ssid") or "").strip()
        password = (request.form.get("password") or "").strip()
        client_id = (request.form.get("client_id") or "").strip()
        client_secret = (request.form.get("client_secret") or "").strip()

        if not ssid or not password or not client_id or not client_secret:
            return jsonify(success=False, error="請填寫所有欄位")
        if len(password) < 8:
            return jsonify(success=False, error="密碼至少需要 8 個字元")

        if write_wpa_conf(ssid, password):
            write_spotify_env(client_id, client_secret)

            def _reboot():
                time.sleep(2)
                os.system("sudo reboot")

            threading.Thread(target=_reboot, daemon=True).start()
            return jsonify(success=True)
        else:
            return jsonify(success=False, error="寫入設定失敗")

    print(f"🌐 Captive portal at http://{host}:{port}")
    app.run(host="0.0.0.0", port=port, debug=False)


def main():
    if check_wifi_connected():
        print("✅ Already connected to WiFi — nothing to do")
        return

    print("📶 No WiFi detected, starting AP setup...")

    if not create_ap():
        sys.exit(1)

    # Start QR display in background
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).parent / "wifi_qr.py")],
            env={**os.environ, "DISPLAY": ":0"}
        )
    except Exception as e:
        print(f"⚠️ Could not start wifi_qr.py: {e}")

    start_captive_portal()


if __name__ == "__main__":
    main()

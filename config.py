"""
SpotiPi Configuration
=====================
Loads environment variables from .env and exports typed config.
"""

import os
from pathlib import Path

# Resolve project root (this file lives at project root)
PROJECT_ROOT = Path(__file__).parent

# Load .env
ENV_FILE = PROJECT_ROOT / ".env"
if ENV_FILE.exists():
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()
                if key not in os.environ:
                    os.environ[key] = value

# === Spotify ===
SPOTIPY_CLIENT_ID = os.environ.get("SPOTIPY_CLIENT_ID", "9236c428bdb8431da17d1b8ee0962ef8")
SPOTIPY_CLIENT_SECRET = os.environ.get("SPOTIPY_CLIENT_SECRET", "")  # Not needed for PKCE
SPOTIPY_REDIRECT_URI = os.environ.get("SPOTIPY_REDIRECT_URI", "http://spotipi.local:8888/callback")
SPOTIPY_SCOPE = "user-read-currently-playing user-read-playback-state"

# === Paths ===
TOKEN_PATH = Path.home() / ".spotipi" / "token.json"
CACHE_PATH = Path.home() / ".spotipi" / "cache"
PLACEHOLDER_PATH = PROJECT_ROOT / "display" / "static" / "placeholder.png"

# === WiFi Setup ===
AP_SSID = os.environ.get("AP_SSID", "SpotiPi-Setup")
AP_PASSWORD = os.environ.get("AP_PASSWORD", "spotipi123")
AP_IP = "192.168.4.1"
CAPTIVE_PORTAL_PORT = 80

# === Display ===
FLASK_PORT = 5000
POLL_INTERVAL = 2  # seconds

# === Callback ===
CALLBACK_PORT = 8888
CALLBACK_TIMEOUT = 300  # seconds

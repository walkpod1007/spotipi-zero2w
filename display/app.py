#!/usr/bin/env python3
"""
SpotiPi Display Backend
========================
Flask server (port 5000) that polls Spotify every 2s and serves
the now-playing page for Chromium kiosk.

Routes:
  GET /              → index.html (kiosk target)
  GET /api/current   → JSON {track, artist, album_art_url, is_playing}
  GET /health        → {"ok": true}
"""

import sys
import threading
import time
from pathlib import Path
from typing import Optional

from flask import Flask, jsonify, render_template

sys.path.insert(0, str(Path(__file__).parent.parent))
import config
from auth.spotify_auth import get_spotify_client

import spotipy

app = Flask(__name__, template_folder="templates", static_folder="static")

# ── Shared state (thread-safe via GIL for simple dict) ────────────────────────
_state: dict = {
    "track": None,
    "artist": None,
    "album_art_url": None,
    "is_playing": False,
}
_sp: Optional[spotipy.Spotify] = None


# ── Spotify poll loop ─────────────────────────────────────────────────────────

def _refresh_client():
    """Re-create Spotify client (called on token expiry)."""
    global _sp
    try:
        _sp = get_spotify_client(force_reauth=False, use_pygame=False)
    except SystemExit:
        _sp = None


def _poll_loop():
    global _state
    while True:
        try:
            if _sp is None:
                _refresh_client()
                time.sleep(config.POLL_INTERVAL)
                continue

            current = _sp.current_user_playing_track()

            if not current or not current.get("is_playing"):
                _state = {"track": None, "artist": None,
                          "album_art_url": None, "is_playing": False}
            else:
                item = current.get("item") or {}
                track = item.get("name", "Unknown Track")
                artists = item.get("artists", [])
                artist = artists[0].get("name", "Unknown Artist") if artists else "Unknown Artist"

                images = (item.get("album") or {}).get("images", [])
                # prefer ~300px image
                art_url = None
                for img in sorted(images, key=lambda x: abs(x.get("width", 0) - 300)):
                    art_url = img.get("url")
                    break

                _state = {
                    "track": track,
                    "artist": artist,
                    "album_art_url": art_url,
                    "is_playing": True,
                }

        except spotipy.exceptions.SpotifyException as e:
            print(f"⚠️ Spotify API error: {e}")
            if e.http_status == 401:
                print("🔄 Token expired, refreshing client...")
                _refresh_client()
        except Exception as e:
            print(f"⚠️ Poll error: {e}")

        time.sleep(config.POLL_INTERVAL)


# ── Routes ─────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/current")
def api_current():
    return jsonify(_state)


@app.route("/health")
def health():
    return jsonify(ok=True)


# ── Entry point ────────────────────────────────────────────────────────────────

def main():
    global _sp
    print("🎵 SpotiPi display backend starting...")
    _refresh_client()

    # Background polling thread
    t = threading.Thread(target=_poll_loop, daemon=True)
    t.start()
    print(f"🔄 Poll thread started (interval: {config.POLL_INTERVAL}s)")

    app.run(host="127.0.0.1", port=config.FLASK_PORT, debug=False, use_reloader=False)


if __name__ == "__main__":
    main()

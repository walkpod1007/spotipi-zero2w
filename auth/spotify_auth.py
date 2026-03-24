#!/usr/bin/env python3
"""
SpotiPi Spotify OAuth (PKCE)
=============================
Handles token load/save, PKCE auth flow, and automatic token refresh.
No client_secret required.

Public API:
    get_spotify_client(force_reauth=False) -> spotipy.Spotify
    token_is_valid() -> bool
"""

import base64
import hashlib
import json
import os
import secrets
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import parse_qs, urlparse

import spotipy
from spotipy.oauth2 import SpotifyPKCE

sys.path.insert(0, str(Path(__file__).parent.parent))
import config

REDIRECT_URI = config.SPOTIPY_REDIRECT_URI
TOKEN_PATH = config.TOKEN_PATH
SCOPE = config.SPOTIPY_SCOPE


# ── Token helpers ──────────────────────────────────────────────────────────────

def token_is_valid() -> bool:
    if not TOKEN_PATH.exists():
        return False
    try:
        t = json.loads(TOKEN_PATH.read_text())
        return bool(t.get("access_token") and t.get("refresh_token"))
    except Exception:
        return False


def load_token() -> Optional[dict]:
    if not TOKEN_PATH.exists():
        return None
    try:
        return json.loads(TOKEN_PATH.read_text())
    except Exception:
        return None


def save_token(token: dict) -> bool:
    try:
        TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        TOKEN_PATH.write_text(json.dumps(token, indent=2))
        return True
    except Exception as e:
        print(f"❌ save_token: {e}")
        return False


# ── PKCE helpers ───────────────────────────────────────────────────────────────

def _pkce_verifier() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(64)).decode().rstrip("=")


def _pkce_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode()).digest()
    return base64.urlsafe_b64encode(digest).decode().rstrip("=")


# ── Callback server ────────────────────────────────────────────────────────────

class _CallbackHandler(BaseHTTPRequestHandler):
    auth_code: Optional[str] = None
    auth_error: Optional[str] = None

    def log_message(self, *_): pass

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/callback":
            self.send_error(404)
            return
        qs = parse_qs(parsed.query)
        if "error" in qs:
            _CallbackHandler.auth_error = qs["error"][0]
            self._html("❌ Authorization failed. You can close this tab.")
        elif "code" in qs:
            _CallbackHandler.auth_code = qs["code"][0]
            self._html("✅ Authorization successful! Return to your SpotiPi.")
        else:
            self.send_error(400)

    def _html(self, msg: str):
        body = f"""<html><body style="font-family:sans-serif;background:#191414;color:#fff;
display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-size:24px;">
<p>{msg}</p></body></html>""".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)


def _wait_for_callback(timeout: int = config.CALLBACK_TIMEOUT) -> Optional[str]:
    _CallbackHandler.auth_code = None
    _CallbackHandler.auth_error = None
    server = HTTPServer(("0.0.0.0", config.CALLBACK_PORT), _CallbackHandler)
    server.timeout = 1
    elapsed = 0
    while elapsed < timeout:
        server.handle_request()
        if _CallbackHandler.auth_code:
            server.server_close()
            return _CallbackHandler.auth_code
        if _CallbackHandler.auth_error:
            server.server_close()
            return None
        elapsed += 1
    server.server_close()
    print("⏱️ Callback timeout")
    return None


# ── Auth flow ──────────────────────────────────────────────────────────────────

def run_pkce_auth_flow(use_pygame: bool = True) -> Optional[dict]:
    """
    Run full PKCE flow. Returns token dict or None.
    use_pygame=True → spawns auth_display.py for QR on HDMI.
    """
    verifier = _pkce_verifier()
    challenge = _pkce_challenge(verifier)

    auth = SpotifyPKCE(
        client_id=config.SPOTIPY_CLIENT_ID,
        redirect_uri=REDIRECT_URI,
        scope=SCOPE,
        cache_path=str(TOKEN_PATH),
    )
    auth.code_verifier = verifier
    auth_url = auth.get_authorize_url(code_challenge=challenge)

    print(f"🔑 Auth URL: {auth_url}")

    # Launch QR display process
    display_proc = None
    if use_pygame:
        import subprocess
        display_proc = subprocess.Popen(
            [sys.executable,
             str(Path(__file__).parent / "auth_display.py"),
             auth_url],
            env={**os.environ, "DISPLAY": ":0"}
        )

    # Wait for callback (blocking)
    code = _wait_for_callback()

    if display_proc:
        try:
            display_proc.terminate()
        except Exception:
            pass

    if not code:
        print("❌ No auth code received")
        return None

    try:
        token = auth.get_access_token(code=code, code_verifier=verifier)
        return token
    except Exception as e:
        print(f"❌ Token exchange error: {e}")
        return None


# ── Public API ─────────────────────────────────────────────────────────────────

def get_spotify_client(force_reauth: bool = False,
                       use_pygame: bool = True) -> spotipy.Spotify:
    """
    Return an authenticated spotipy.Spotify instance.
    Runs PKCE auth flow if no valid token exists.
    Raises SystemExit on failure.
    """
    if not config.SPOTIPY_CLIENT_ID:
        print("❌ SPOTIPY_CLIENT_ID not set in .env")
        sys.exit(1)

    if not force_reauth and token_is_valid():
        print("✅ Using cached token")
    else:
        print("🔑 Starting Spotify PKCE auth flow...")
        token_info = run_pkce_auth_flow(use_pygame=use_pygame)
        if not token_info:
            print("❌ Authorization failed")
            sys.exit(1)
        save_token(token_info)

    auth = SpotifyPKCE(
        client_id=config.SPOTIPY_CLIENT_ID,
        redirect_uri=REDIRECT_URI,
        scope=SCOPE,
        cache_path=str(TOKEN_PATH),
    )
    return spotipy.Spotify(auth_manager=auth)


if __name__ == "__main__":
    sp = get_spotify_client()
    me = sp.current_user()
    print(f"✅ Logged in as: {me['display_name']}")

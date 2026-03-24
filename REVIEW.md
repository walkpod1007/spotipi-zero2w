# SpotiPi Review

## 已完成

- **spotify_auth.py**：PKCE OAuth flow 完整，無需 client_secret。`get_local_ip()` 動態偵測 LAN IP，REDIRECT_URI 自動帶入。QR code 功能已實作（terminal + pygame 雙模式）。callback server 監聽 `0.0.0.0:8888`，手機同 WiFi 可達。token 持久化到 `~/.spotipi/token.json`，支援自動 refresh。
- **spotipi.py**：polling 邏輯正確（2 秒輪詢），封面下載 + `/tmp` 快取，pygame 全螢幕顯示完整。只在 track_id 變更時重繪，避免不必要的 API 呼叫。
- **main.py**：啟動流程正確（WiFi 檢查 → auth → 播放顯示），`config.py` 載入 .env。
- **wifi_setup.py**：AP 模式 + captive portal 完整，QR code 顯示 WiFi 密碼。
- **requirements.txt**：涵蓋所有依賴（spotipy, pygame, Pillow, requests, qrcode[pil], flask）。
- **.env**：`SPOTIPY_CLIENT_ID` 已填入 `9236c428bdb8431da17d1b8ee0962ef8`。

## 修補了

- **.env**：新增 `SPOTIPY_CLIENT_SECRET=`（空白佔位）。PKCE flow 本身不需要 secret，但 spotipy 某些版本會讀此變數，留佔位避免意外錯誤。
- **setup.sh**：
  - 改用 venv（`python3 -m venv venv`）而非全域 pip3，避免污染系統 Python。
  - `.env` 改為自動建立並預填 `SPOTIPY_CLIENT_ID`，不再要求用戶手動輸入。
  - service 安裝前動態替換路徑（`WorkingDirectory`、`ExecStart` venv python、`User`、`EnvironmentFile`），適應不同用戶名。
  - 加入清晰的後續步驟提示。
- **spotipi.service**：
  - `ExecStart` 改用 venv 路徑（`venv/bin/python3`）與正確 `WorkingDirectory`。
  - `Restart=on-failure` → `Restart=always`（確保任何 crash 都重啟）。
  - 新增 `StandardOutput=journal` + `StandardError=journal`（方便 `journalctl -u spotipi` 查 log）。
- **spotipi.py**：新增 `truncate_text()` 函式，超長曲名/歌手名自動截斷加省略號，避免文字溢出螢幕邊緣。

## 待用戶手動處理

- **填入 SPOTIPY_CLIENT_SECRET**：到 [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) 取得 app 的 Client Secret，填入 RPi 上的 `~/.spotipi/.env`：
  ```
  SPOTIPY_CLIENT_SECRET=你的secret
  ```
  （PKCE flow 本身不強制需要，但建議填入以確保相容性）

- **Spotify Dashboard 新增 Redirect URI**：
  1. 先在 RPi 上執行 `hostname -I | awk '{print $1}'` 取得 IP
  2. 到 Dashboard → 你的 app → Edit Settings → Redirect URIs
  3. 新增 `http://<RPi_IP>:8888/callback`

- **在 RPi 上執行安裝**：
  ```bash
  cd ~/spotipi
  bash setup.sh
  ```

- **首次啟動授權**：
  ```bash
  sudo systemctl start spotipi
  ```
  首次啟動時，RPi 螢幕會顯示 QR code，手機（同 WiFi）掃碼完成 Spotify 授權。

- **查看運行 log**：
  ```bash
  journalctl -u spotipi -f
  ```

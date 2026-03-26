# SpotiPi — Spotify Now Playing MVP

Raspberry Pi 專用 Spotify 現正播放顯示器。使用 Python + spotipy + pygame。

## 功能

- ✅ 每 2 秒 polling Spotify API
- ✅ 全螢幕顯示專輯封面（250x250）
- ✅ 曲名 + 歌手資訊
- ✅ 換曲才重繪（節省效能）
- ✅ 無播放時顯示 "Nothing Playing"
- ✅ Token 快取至 `~/.spotipi/token.json`

## 安裝

### 1. 安裝系統依賴（Raspberry Pi OS）

```bash
sudo apt update
sudo apt install python3-pip python3-venv libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev
```

### 2. 建立 Virtual Environment

```bash
cd ~/Desktop/spotipi
python3 -m venv venv
source venv/bin/activate
```

### 3. 安裝 Python 依賴

```bash
pip install -r requirements.txt
```

## Spotify API 設定

### 1. 建立 Spotify App

1. 前往 https://developer.spotify.com/dashboard
2. 點選「Create App」
3. 填寫 App 名稱（例：SpotiPi）
4. 新增 Redirect URI：`http://localhost:8888/callback`
5. 儲存後複製 **Client ID** 與 **Client Secret**

### 2. 設定環境變數

在 `~/.bashrc` 或 `~/.zshrc` 加入：

```bash
export SPOTIPY_CLIENT_ID="你的_client_id"
# PKCE 不需要 client secret
# export SPOTIPY_CLIENT_SECRET=""
export SPOTIPY_REDIRECT_URI="http://localhost:8888/callback"
```

重新載入：

```bash
source ~/.bashrc  # 或 source ~/.zshrc
```

## 執行

```bash
cd ~/Desktop/spotipi
source venv/bin/activate
python spotipi.py
```

首次執行會跳出瀏覽器要求授權 Spotify，同意後會自動取得 token 並快取。

## 檔案結構

```
~/Desktop/spotipi/
├── spotipi.py         # 主程式
├── requirements.txt   # Python 依賴
└── README.md          # 本說明文件

~/.spotipi/
└── token.json         # Spotify OAuth token（自動產生）

/tmp/
└── spotipi_cover.jpg  # 封面快取
```

## 快捷鍵

- `ESC` — 離開程式

## 疑難排解

### pygame 找不到 SDL2

```bash
sudo apt install libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev
```

### Spotify API 401 Unauthorized

檢查 `SPOTIPY_CLIENT_ID` 是否正確，必要時刪除 `~/.spotipi/token.json` 重新授權。

### 視窗無法全螢幕

確認 Raspberry Pi 有連接螢幕，且 pygame 可存取顯示裝置（在 GUI 環境或正確設定 `SDL_VIDEODRIVER`）。

## 授權

MIT License

## 開發里程碑

- [x] P0 — Spotify API + 封面顯示 MVP
- [ ] P1 — WiFi QR Code 設定流程
- [ ] P2 — Spotify OAuth QR Code
- [ ] P3 — systemd 整合 + image 打包
- [ ] P4 — 測試 + 文件

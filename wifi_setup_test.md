# SpotiPi WiFi Setup 模組測試文件

## 測試環境

- 硬體：Raspberry Pi（已安裝 SpotiPi）
- 作業系統：Raspberry Pi OS
- 權限：需要 sudo 權限
- 網路：無 WiFi 連線狀態

## 前置準備

### 1. 安裝依賴套件

```bash
cd ~/Desktop/spotipi
pip3 install -r requirements.txt
```

### 2. 確認服務已安裝

```bash
# 檢查 hostapd 和 dnsmasq 是否已安裝
sudo apt-get install hostapd dnsmasq -y

# 停止服務（避免衝突）
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl disable hostapd
sudo systemctl disable dnsmasq
```

---

## 單元測試

### 測試 1：QR Code 生成功能

**目的**：驗證 QR code 能正確生成並顯示

**步驟**：
```bash
cd ~/Desktop/spotipi
python3 -c "
from wifi_setup import generate_qr_code
generate_qr_code('TestWiFi', 'test1234', terminal=True)
"
```

**預期結果**：
- ✓ 終端顯示 QR code ASCII 圖案
- ✓ 輸出包含 SSID 和密碼資訊
- ✓ 無錯誤訊息

---

### 測試 2：wpa_supplicant.conf 寫入功能

**目的**：驗證憑證能正確寫入設定檔

**步驟**：
```bash
cd ~/Desktop/spotipi
sudo python3 -c "
from wifi_setup import write_wpa_conf
result = write_wpa_conf('MyTestWiFi', 'testpassword123')
print(f'Write result: {result}')
"

# 檢查寫入結果
sudo cat /boot/wpa_supplicant.conf
```

**預期結果**：
- ✓ 回傳 `True`
- ✓ `/boot/wpa_supplicant.conf` 包含正確的 SSID 和密碼
- ✓ 檔案格式正確（包含 country, ctrl_interface, network 區塊）

---

### 測試 3：AP 建立功能（需在 Raspberry Pi 上執行）

**目的**：驗證 AP 模式能正確啟動

**步驟**：
```bash
cd ~/Desktop/spotipi
sudo python3 wifi_setup.py
```

**預期結果**：
- ✓ 偵測到無 WiFi 連線
- ✓ 建立 hostapd 設定檔 `/etc/hostapd/hostapd.conf`
- ✓ 建立 dnsmasq 設定檔 `/etc/dnsmasq.conf`
- ✓ wlan0 取得 IP 192.168.4.1
- ✓ hostapd 和 dnsmasq 服務啟動成功
- ✓ 終端顯示 QR code

---

### 測試 4：Captive Portal 功能

**目的**：驗證 Web 介面能正常運作

**前置條件**：
1. AP 已啟動（SSID: SpotiPi-Setup）
2. 測試設備已連接到 SpotiPi-Setup

**步驟**：
```bash
# 在另一個終端視窗啟動 portal
cd ~/Desktop/spotipi
sudo python3 -c "
from wifi_setup import start_captive_portal
start_captive_portal()
"
```

在手機或電腦上：
1. 連接 WiFi `SpotiPi-Setup`（密碼：spotipi123）
2. 開啟瀏覽器，輸入任意網址（如 http://example.com）
3. 應自動導向 captive portal 頁面（或手動訪問 http://192.168.4.1）

**預期結果**：
- ✓ Flask server 啟動在 192.168.4.1:80
- ✓ 瀏覽器顯示 WiFi 設定頁面
- ✓ 頁面包含 SSID 和密碼輸入欄位
- ✓ 提交後回傳 JSON `{"success": true}`
- ✓ `/boot/wpa_supplicant.conf` 更新成功
- ✓ 系統在 2 秒後自動重開機

---

## 整合測試（完整流程）

### 場景：全新 SpotiPi 首次設定

**前置條件**：
- Raspberry Pi 已安裝 SpotiPi
- 無 WiFi 連線
- 開機自動執行 `wifi_setup.py`

**步驟**：

1. **啟動 Raspberry Pi**
   ```bash
   sudo python3 ~/Desktop/spotipi/wifi_setup.py
   ```

2. **用手機連接 SpotiPi-Setup**
   - 掃描終端顯示的 QR code
   - 或手動連接 SSID: `SpotiPi-Setup`, 密碼: `spotipi123`

3. **開啟瀏覽器設定 WiFi**
   - 開啟任意網址，自動導向設定頁面
   - 輸入家用 WiFi SSID 和密碼
   - 點擊「連接 WiFi」

4. **等待重開機**
   - 系統顯示「設定完成」
   - 2 秒後自動重開機
   - Raspberry Pi 重新啟動

5. **驗證連線**
   ```bash
   # 重開機後檢查 WiFi 連線
   iwgetid -r
   # 應顯示家用 WiFi SSID
   
   # 檢查 wpa_supplicant.conf
   sudo cat /boot/wpa_supplicant.conf
   ```

**預期結果**：
- ✓ SpotiPi-Setup AP 正確建立
- ✓ QR code 可掃描連接
- ✓ Captive portal 頁面正常顯示
- ✓ WiFi 憑證成功寫入
- ✓ 重開機後自動連接到指定 WiFi
- ✓ 連線後不會再進入 setup 模式

---

## 錯誤處理測試

### 測試 A：密碼太短

**步驟**：
```bash
curl -X POST http://192.168.4.1/connect \
  -d "ssid=MyWiFi&password=short"
```

**預期結果**：
- ✓ 回傳 `{"success": false, "error": "密碼至少需要 8 個字元"}`

---

### 測試 B：SSID 為空

**步驟**：
```bash
curl -X POST http://192.168.4.1/connect \
  -d "ssid=&password=validpass123"
```

**預期結果**：
- ✓ 回傳 `{"success": false, "error": "請填寫所有欄位"}`

---

### 測試 C：已連接 WiFi

**步驟**：
```bash
# 模擬已連接 WiFi 狀態
sudo python3 -c "
import subprocess
# 模擬 iwgetid 回傳已連接
print('WiFi already connected, should exit early')
"
```

**預期結果**：
- ✓ 程式偵測到已連接 WiFi
- ✓ 不建立 AP
- ✓ 直接結束

---

## 除錯指令

### 檢查 hostapd 狀態
```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd -n 50
```

### 檢查 dnsmasq 狀態
```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50
```

### 檢查網路介面
```bash
ifconfig wlan0
iwconfig wlan0
```

### 查看 Flask 日誌
```bash
# Flask 預設輸出到 stdout
# 若需記錄可重定向
sudo python3 wifi_setup.py 2>&1 | tee /tmp/wifi_setup.log
```

---

## 測試檢查清單

- [ ] `wifi_setup.py` 語法檢查通過 (`python3 -m py_compile wifi_setup.py`)
- [ ] `requirements.txt` 包含 `qrcode[pil]` 和 `flask`
- [ ] QR code 生成功能正常
- [ ] wpa_supplicant.conf 寫入功能正常
- [ ] AP 建立功能正常（需在 Pi 上測試）
- [ ] Captive portal 頁面可訪問
- [ ] 表單提交後正確寫入設定
- [ ] 錯誤處理（短密碼、空欄位）正常
- [ ] 重開機後自動連接 WiFi

---

## 已知限制

1. **權限需求**：需要 sudo 權限來修改 `/boot` 和系統服務
2. **硬體依賴**：僅支援 Raspberry Pi 內建 WiFi 晶片
3. **單次設定**：每次啟動會檢查連線狀態，已連接則不啟動 setup
4. **密碼長度**：WPA-PSK 最少 8 字元
5. **不支援 WEP**：僅支援 WPA/WPA2 加密

---

## 測試完成時間

預計測試時間：
- 單元測試：10 分鐘
- 整合測試：20 分鐘
- 錯誤處理測試：5 分鐘
- **總計：約 35 分鐘**

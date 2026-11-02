# Jide Remix Mini (RM1G) Linux Ethernet (AC200 EPHY) Complete Bring-Up Guide

本專案提供 **Jide Remix Mini PC (RM1G, Allwinner A64 / sun50i-a64 / sun50i-h64)** 在主流現代 Linux 核心（Linux 6.12.y ~ 6.18.y）下，完整打通板載 **X-Powers AC200 Fast Ethernet EPHY (`eth0`)** 的全套硬體設備樹、核心驅動修補檔、AFE 類比前端初始化工具與開機自動化配置。

---

## 一、 適用硬體與系統環境

| 項目 | 測試與驗證規格 | 備註說明 |
| :--- | :--- | :--- |
| **主機型號** | Jide Remix Mini PC (RM1G) | 主板相容 `jide,remix-mini-rm1g` / `jide,remix-mini-pc` |
| **處理器 (SoC)** | Allwinner A64 / H64 (`sun50i-a64`) | 4-Core ARM Cortex-A53 @ 1.15GHz |
| **記憶體 / 儲存** | 2GB DDR3 RAM, 16GB eMMC 5.0 | 亦支援 1GB RAM / 8GB eMMC 規格機型 |
| **網路架構** | SoC EMAC + X-Powers AC200 EPHY | RMII 介面 (100Mbps 全雙工) + I2C-1 (0x10) 控制 |
| **作業系統** | Armbian 26.8.3 trixie (Debian 13.6 aarch64) | 乾淨安裝標準系統 |
| **內核版本** | `Linux 6.18.44-current-sunxi64` | 亦相容主線 Linux 6.12.y ~ 6.18.y |
| **U-Boot 版本**| U-Boot 2024.xx (Armbian sun50i-a64) | 支援 FDT 覆蓋與環境變數載入 |

---

## 二、 五大核心問題與修復原理

在現代 Linux 主線核心中，Remix Mini 的乙太網路長期無法運作，其根本原因並非單一驅動缺失，而是由 **五大板級硬體閉環缺失** 導致：

1. **外部輸入時脈 (CKI 24MHz) 未導出**：
   AC200 晶片未配備獨立 24MHz 晶振，依賴 SoC 的 `PL10` 引腳輸出 24MHz 時脈（`R_PWM` Channel 0 bypass OSC24M）。主線 DTS 預設未開啟此時脈，導致 AC200 內部 PLL 無法起振。
2. **PMIC DLDO2 供電關閉 (3.1V)**：
   AC200 內部的 EPHY 類比前端由 AXP803/813 的 `dldo2` 供電。主線 DTS 預設將其關閉，必須設定為 3.1V（`3100000 uV`）且 `regulator-always-on`。
3. **Port D Pinmux PD14 干擾衝突**：
   標準 A64 `rmii-pins` 包含 `PD14`。但 Remix Mini 主板之 `PD14` 另有他用，強制設為 EMAC 模式會造成電氣干擾，必須從 Pinmux 中嚴格剔除。
4. **Syscon 50MHz 參考時脈相位與 Bit 16 遺失**：
   主線 `dwmac-sun8i.c` 在 RMII 模式下預設寫入 `0x2001`，清除了 Bit 16（`EPHY_CLK_SEL`）。RM1G 需要寫入 **`0x00012001`** 才能正確認可 AC200 送回的 50MHz RMII 參考時脈。
5. **EMAC `SOFT_RST` 致命硬體死鎖**：
   主線驅動與 Synopsys `stmmac` 核心在重設 MAC 時會向 `EMAC_BASIC_CTL1` (0x01c30004) Bit 0 寫入 1（`SOFT_RST`）。在 RM1G 硬體上，由於時脈依賴，寫入 Bit 0 會造成硬體匯流排**永久死鎖（全機凍結或網卡超時崩潰）**。重設應交由 CCU 匯流排重設，並在驅動中繞過該軟體重設位元。

---

## 三、 儲存庫結構與元件清單

```text
├── 0001-net-stmmac-dwmac-sun8i-fix-AC200-RMII-for-Remix-Mini.patch  # 標準 Linux 內核樹 Git Patch
├── ac200-afe-init.c                                                  # 純 C 語言 AC200 暫存器初始化工具
├── dwmac-sun8i.c                                                     # 具備 RM1G 硬體相容條件防護之驅動原始碼
├── Makefile                                                          # Out-of-tree 模組編譯與安裝檔
├── dkms.conf                                                         # DKMS 自動重編配置檔
├── include/                                                          # Out-of-tree 編譯所需之內部標頭檔
│   ├── common.h, descs.h, hwif.h, mmc.h, stmmac.h, stmmac_platform.h
├── sun50i-h64-remix-ac200.dts                                        # 繼承主線之標準設備樹原始碼
├── sun50i-h64-remix-ac200-standalone.dts                             # 無須外部標頭即可直編之獨立 DTS
├── boot/
│   ├── armbianEnv.txt.template                                       # Armbian 開機設定參考範本
│   └── dtb/allwinner/sun50i-h64-remix-ac200.dtb                      # 預編譯設備樹二進位檔 (DTB)
├── etc/
│   ├── modprobe.d/blacklist-dwmac.conf                               # 模組黑名單（延遲驅動載入）
│   └── systemd/system/ac200-init.service                             # 開機硬體初始化 systemd 服務
└── usr/local/bin/
    └── init-ac200.sh                                                 # 硬體喚醒與啟動主腳本
```

### DTB 二進位校驗
- **檔案路徑**：`boot/dtb/allwinner/sun50i-h64-remix-ac200.dtb`
- **檔案大小**：42,482 bytes
- **SHA-256**：`d51f03a30b3b17563311cce469fe45a12fd6fd845f14c5abf067fd9b3f828ba4`

---

## 四、 安裝步驟 (Step-by-Step Installation)

請在具備 `sudo` 權限的終端機中依序執行以下步驟：

### 步驟 0：備份現有系統
```bash
# 建立備份資料夾
sudo mkdir -p /root/remix_eth_backup

# 備份既有驅動模組
sudo cp /lib/modules/$(uname -r)/kernel/drivers/net/ethernet/stmicro/stmmac/dwmac-sun8i.ko.xz \
    /root/remix_eth_backup/ 2>/dev/null || \
sudo cp /lib/modules/$(uname -r)/kernel/drivers/net/ethernet/stmicro/stmmac/dwmac-sun8i.ko \
    /root/remix_eth_backup/ 2>/dev/null || true

# 備份既有開機設定
sudo cp /boot/armbianEnv.txt /root/remix_eth_backup/
```

### 步驟 1：安裝裝置樹 (DTB)
```bash
# 複製修復版 DTB 至系統開機目錄
sudo cp boot/dtb/allwinner/sun50i-h64-remix-ac200.dtb /boot/dtb/allwinner/

# 修改既有 /boot/armbianEnv.txt，指定使用新 DTB
# 【注意】請勿直接整檔覆蓋 armbianEnv.txt，以免覆寫本機的 rootdev=UUID
if grep -q "^fdtfile=" /boot/armbianEnv.txt; then
    sudo sed -i 's|^fdtfile=.*|fdtfile=allwinner/sun50i-h64-remix-ac200.dtb|' /boot/armbianEnv.txt
else
    echo "fdtfile=allwinner/sun50i-h64-remix-ac200.dtb" | sudo tee -a /boot/armbianEnv.txt
fi
```

### 步驟 2：編譯並安裝 `ac200-afe-init` 與初始化腳本
```bash
# 編譯純 C 初始化工具
sudo gcc -O2 ac200-afe-init.c -o /usr/local/bin/ac200-afe-init
sudo chmod +x /usr/local/bin/ac200-afe-init

# 安裝主初始化腳本
sudo cp usr/local/bin/init-ac200.sh /usr/local/bin/init-ac200.sh
sudo chmod +x /usr/local/bin/init-ac200.sh
```

### 步驟 3：安裝延遲載入黑名單與 Systemd 啟動服務
> **為何需要延遲載入黑名單？**
> Linux 核心若在開機初期自動載入 `dwmac-sun8i`，此時 PL10 24MHz 時脈與 AC200 AFE 尚未透過 I2C 配置就緒，會引發 PHY 探測失敗或死鎖。黑名單可確保由 `ac200-init.service` 依照精確時序先完成硬體起振，再載入網卡驅動。

```bash
# 安裝模組黑名單
sudo cp etc/modprobe.d/blacklist-dwmac.conf /etc/modprobe.d/

# 安裝並啟用開機服務
sudo cp etc/systemd/system/ac200-init.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ac200-init.service
```

### 步驟 4：編譯並安裝修復後的 `dwmac-sun8i` 驅動

本儲存庫提供兩種構建途徑：

#### 途徑 A：Out-of-Tree 直接編譯（推薦，只需安裝一般 kernel-headers）
本專案已在 `include/` 目錄中打包所需之 6 個私有標頭檔，無須下載龐大的 Linux 內核源碼：
```bash
# 安裝編譯工具與標頭
sudo apt update && sudo apt install -y build-essential linux-headers-$(uname -r)

# 編譯模組
make

# 安裝模組並更新依賴
sudo make install
```

#### 途徑 B：使用 DKMS 自動維護
```bash
sudo apt install -y dkms
sudo mkdir -p /usr/src/dwmac-sun8i-1.0
sudo cp -r * /usr/src/dwmac-sun8i-1.0/
sudo dkms add -m dwmac-sun8i -v 1.0
sudo dkms build -m dwmac-sun8i -v 1.0
sudo dkms install -m dwmac-sun8i -v 1.0
```

#### 途徑 C：適用內核開發者（In-Tree Patch）
若您自行編譯完整內核原始碼：
```bash
cd /path/to/linux-source
git apply /path/to/0001-net-stmmac-dwmac-sun8i-fix-AC200-RMII-for-Remix-Mini.patch
make -j$(nproc) bindeb-pkg
```

---

## 五、 重新開機與驗證 (Verification)

完成上述步驟後，重新啟動系統：
```bash
sudo reboot
```

開機後執行以下指令驗證：

### 1. 檢查開機服務狀態
```bash
systemctl status ac200-init.service
```
預期輸出：狀態應為 `active (exited)`，日誌最後顯示 `[AC200-INIT] Initialization complete!`。

### 2. 檢查網路介面與鏈路
```bash
ip link show eth0
```
預期輸出：`state UP`，具備有效 MAC 位址。

```bash
ethtool eth0
```
預期輸出：
```text
Speed: 100Mb/s
Duplex: Full
Link detected: yes
```

### 3. 測試連線
```bash
ping -c 4 1.1.1.1
```

---

## 六、 失敗還原步驟 (Disaster Recovery)

若系統更新或設定錯誤導致網路無法啟動，請依照以下步驟還原：

```bash
# 1. 停用開機服務並移除黑名單
sudo systemctl disable ac200-init.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/ac200-init.service
sudo rm -f /etc/modprobe.d/blacklist-dwmac.conf

# 2. 還原原始 armbianEnv.txt
if [ -f /root/remix_eth_backup/armbianEnv.txt ]; then
    sudo cp /root/remix_eth_backup/armbianEnv.txt /boot/armbianEnv.txt
fi

# 3. 還原備份之 dwmac-sun8i 模組
if [ -f /root/remix_eth_backup/dwmac-sun8i.ko* ]; then
    sudo cp /root/remix_eth_backup/dwmac-sun8i.ko* \
        /lib/modules/$(uname -r)/kernel/drivers/net/ethernet/stmicro/stmmac/
    sudo depmod -a
fi

sudo reboot
```

---

## 七、 依據與技術細節說明 (Technical Notes)

- **主板條件限制 (`is_remix_mini`)**：
  修復程式碼透過 `of_machine_is_compatible("jide,remix-mini-rm1g")` 及 `of_machine_is_compatible("jide,remix-mini-pc")` 進行硬體條件判斷，確保若此模組載入於其他全志開發板（如 Orange Pi、Pine64、Banana Pi）時，100% 執行主線標準行為，零回歸風險。
- **SOFT_RST 死鎖現象**：
  實測於原廠正常連線的 Android 3.10 系統中，直接向 `0x01c30004` (EMAC_BASIC_CTL1) 寫入 Bit 0（`0x08000001`），硬體 RMII 時脈反饋會立即中斷，導致總線永久掛起。
- **Page 0x40 參數性質說明**：
  AC200 Page 0x40 之暫存器參數直接提取自原廠 Android 3.10.93 之執行狀態真值表。套用此組參數後，AC200 EPHY 與交換機可穩定完成雙向訊號交握並消除封包丟失。
- **PD14 隔離依據**：
  比對原廠 Android `real_factory_remix.dtb`，Remix Mini 原廠 Port D 配置暫存器 `0x01c20870` 之真值即為 `0x77474477`（PD14 設為 Disable 0x7）。主線將其誤設為 EMAC 模式會導致硬體引腳電氣衝突。

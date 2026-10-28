# Allwinner A64 / H64 (Remix Mini PC) AC200 Ethernet 修復與逆向報告

---

## 1. 核心硬體架構與實體電路定義

### 1.1 晶片拓撲
* **主控晶片**: Allwinner A64 / H64 (64-bit Quad-Core Cortex-A53)
* **乙太網路控制**: 內部 Allwinner EMAC (DesignWare DWMAC 相容核心，但具備全志自研暫存器邏輯)
* **實體層 PHY (EPHY)**: X-Powers AC200 複合晶片 (QFN68 / QFN88 封裝)
* **晶片互聯模式**: **RMII 介面 (10/100Mbps)** + **I2C 匯流排 (TWI0 @ 0x01c2ac00, Slave Addr 0x10)**

### 1.2 原廠電路引腳定義 (實錘自原廠 Android 設備樹 `real_factory_remix.dtb`)
全志原廠在 Remix Mini 上將 Port D 配置為 `gmac0` (Function 4, `muxsel = <0x04>`, `drive = <0x03>` 30mA)：
* **PD10**: `gmac_rxd1` (RMII 接收資料 1)
* **PD11**: `gmac_rxd0` (RMII 接收資料 0)
* **PD13**: `gmac_rxdv` (RMII 接收載波/資料有效 CRSDV)
* **PD17**: `gmac_txd1` (RMII 發送資料 1)
* **PD18**: `gmac_txd0` (RMII 發送資料 0)
* **PD19**: `gmac_txclk` (50MHz RMII 參考時脈輸入，由 AC200 Pin 41 `E_TXCK` 輸出供給 SoC)
* **PD20**: `gmac_txen` (RMII 發送致能)
* **PD22**: `gmac_mdc` (MDIO 管理時脈線)
* **PD23**: `gmac_mdio` (MDIO 管理數據線)
* **特別警告**: **PD14 必須完全隔離** (在部分開源板上為外部 PHY 重設腳，但在 Remix Mini 上接至其他線路，若被設為 Function 4 會干擾 EMAC 運作)。

### 1.3 PMIC 供電規範 (AXP803 / AXP813)
* **`dldo2`**: 必須設定為 **3.1V** (Always-on) 供應 AC200 內部類比電路。
* **`dldo1` (`vcc-ave-33`)**: 必須設定為 **3.3V** (Always-on) 供應 AC200 ATE/數位 IO。
* **`aldo3` (`vcc-pll-avcc`)**: 必須設定為 **3.0V**。

---

## 2. 病因分析與硬體驗證結果 (Smoking Gun)

### 2.1 為什麼主線 Linux 無人成功？
1. **主線驅動的致命毒藥 (`EMAC_BASIC_CTL1` 0x01c30004 Bit 0 `SOFT_RST`)**：
   * 主線 `dwmac-sun8i.c` 與 Synopsys `stmmac` 核心框架假設所有網卡在開機與超時都要執行 `SOFT_RST`。
   * **實測真相**：在 100% 正常通網的原廠 Android 設備上寫入 `0x08000001`，**原廠機瞬間全機死鎖、網路暴斃**。
   * **結論**：全志 A64 在搭配 AC200 RMII 時，`SOFT_RST` 在硬體上**根本無法自清**，一旦寫入 1 便直接咬死系統匯流排。
2. **原廠 Android 驅動的秘密**：
   * 原廠驅動 `sunxi-gmac` **從頭到尾完全不碰 `0x01c30004`**，開機只靠 CCU 的匯流排復位（`0x01c202c0` Bit 17）進行一次性硬體復位。
3. **社群 `ac200-ephy-ctl` 的死循環**：
   * 社群現存的 `ac200-ephy-ctl.ko` 在 Probe 成功後，主動把 EPHY 的 MII IO 關閉（`0x0016 = 0x0000`）並打入休眠（`0x6000 = 0x0001`）。
   * 導致核心掃描 MDIO 只能讀出 `0xFFFF`，拒絕載入 `ac200-phy`，AC200 永遠沉睡，50MHz 時脈永遠不輸出。

---

## 3. AC200 完整暫存器真值表 (I2C Slave: 0x10)

### 3.1 Page 0x00 (系統電源與時脈控制)
* `0x0008` = `0x0007` (致能 24MHz 外部時脈輸入 Pin 37)
* `0x000A` = `0xC80C`
* `0x000C` = `0x8200` (Bit 15 `PLL_ENABLE = 1` 啟動內部 PLL 振盪)
* `0x000E` = `0x014A`
* `0x0014` = `0x0003` (Bit 1 `EPHY_SYSCLK_GATING=1`, Bit 0 `EPHY_RESET_INVALID=1` 撤銷復位)
* `0x0016` = `0x000F` (Bit 0 `EPHY_MII_IO_EN=1` 解鎖 MII/RMII/MDIO IO，Bit 1-3 開啟 LED)

### 3.2 Page 0x60 (EPHY 控制)
* `0x6000` = `0x4806`：
  * Bit 11 `XMII_SEL` = 1 (RMII 模式)
  * Bit 2 `CLK_SEL` = 1 (24MHz 參考時脈)
  * Bit 1 `LED_POL` = 1 (LED 極性)
  * Bit 0 `SHUTDOWN` = 0 (解除關斷，上電工作)

### 3.3 Page 0x40 (類比前端 AFE / PLL 振盪器校準值)
* `0x4000` = `0x0100`
* `0x4006` = `0x0001`
* `0x4008` = `0x10a0`
* `0x400a` = `0x4300`
* `0x400c` = `0x0004`
* `0x400e` = `0x0001`
* `0x4010` = `0x7c1f`
* `0x4012` = `0x21f0`
* `0x4014` = `0x0020`
* `0x4016` = `0x0076`
* `0x4018` = `0x0016`
* `0x401c` = `0x020d`
* `0x401e` = `0x0016`

---

## 4. 全志 A64 底層暫存器真值表

| 暫存器實體位址 | 功能說明 | Android 正常真值 | 關鍵位元說明 |
|---|---|---|---|
| `0x01c00030` | `SYSCON_EMAC_CLK` | `0x00012001` | Bit 16=1 (內部時脈通道), Bit 13=1 (RMII致能), Bit 0=1 (PHY Select) |
| `0x01c2009c` | `CCU_GMAC_CLK` | `0x81000003` | Bit 31=1 (時脈閘控), Bit 24=1 (PLL_PERIPH0時脈源), Bits 3:0=3 (除頻器) |
| `0x01c20870` | `PD_CFG1` (PD8~PD15) | `0x77474477` | PD10=4, PD11=4, PD13=4 (`gmac0`)，PD14=7 (排除衝突) |
| `0x01c20874` | `PD_CFG2` (PD16~PD23) | `0x44744447` | PD17~PD20=4, PD22=4, PD23=4 (`gmac0` MDC/MDIO/TXCLK) |
| `0x01c30000` | `EMAC_BASIC_CTL0` | `0x0000000D` | 100Mbps, 全雙工 (Full Duplex) |
| `0x01c30004` | `EMAC_BASIC_CTL1` | **`0x08000000`** | **Bit 0 必須保持為 0！Bit 27=1 (Burst Length 8)** |
| `0x01c30010` | `EMAC_TX_CTL0` | `0xC0000000` | Bit 31=1 (TX致能), Bit 30=1 (TX DMA啟動) |
| `0x01c30014` | `EMAC_TX_CTL1` | `0x40000006` | Bit 30=1 (TX DMA運行中) |
| `0x01c30024` | `EMAC_RX_CTL0` | `0xB8000000` | Bit 31=1 (RX致能), Bit 30=1 (RX DMA啟動) |

---

## 5. 跨核心修復原始碼修訂指引 (`dwmac-sun8i.c`)

在任何新版 Linux 核心源碼的 `drivers/net/ethernet/stmicro/stmmac/dwmac-sun8i.c` 中：

1. **完全阻斷軟體復位**：
```c
static int sun8i_dwmac_reset(struct stmmac_priv *priv)
{
    /* 
     * Allwinner A64 with AC200 RMII deadlocks permanently
     * if Bit 0 of EMAC_BASIC_CTL1 is written. Bypass it!
     */
    return 0;
}
```

2. **啟用 TX DMA 發送啟動**：
在 `sun8i_dwmac_set_mac` 或發送觸發函式中，確保寫入 `0x10` (TX_CTL0) 時設定 Bit 30 (`0xC0000000`)。

3. **包裝 DKMS 自動安裝**：
將修補後的源碼搭配本目錄下的 `dkms.conf` 與 `Makefile`，即可實現核心更新時自動重編。

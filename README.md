# Linux Sun50i A64 Remix Mini (RM1G) Ethernet Fix

Fixing issue: Allwinner A64 + X-Powers AC200 Ethernet initialization on Remix Mini (RM1G) in mainstream Linux kernel.

## Root Causes & Fixed Parameters

1. **PL10 / R_PWM 24MHz External Clock (CKI)**
   - Enabled `r_pwm` and `r_ccu` APB0 gate register (`0x01f01428`) to output bypass 24MHz directly to AC200 CKI input.
2. **AXP81x PMIC DLDO2 Power**
   - Configured `dldo2` to 3.1V (`3100000 uV`) to power up internal EPHY AFE.
3. **dwmac-sun8i Syscon Bit 16 (`EPHY_CLK_SEL`)**
   - Corrected RMII mode syscon register from `0x00002001` to `0x00012001` (or 0x12001 in C code) to resolve 50MHz RMII clock phase mismatch.
4. **Pinctrl Conflict Fix**
   - Excluded `PD14` from `rmii-pins` node to prevent pinctrl register `0x01c20870` conflicts (keeping value at `0x77474477`).
5. **AC200 Page 0x40 Analog Front End (AFE) Magic Values**
   - Applied undocumented Page 0x40 parameters (`0x08`, `0x0a`, `0x10`, `0x12`, `0x16`, `0x1c`) for signal eye diagram stabilization.

## Repository Contents

- `sun50i-a64-remix-mini.dts`: Complete Device Tree Source for Remix Mini.
- `0001-net-stmmac-dwmac-sun8i-fix-AC200-RMII-syscon-and-AFE.patch`: Kernel C driver patch.
- `ac200-afe-init.c`: Standalone initialization code for AC200 AFE registers.

## How to Apply

1. Copy `sun50i-a64-remix-mini.dts` to `arch/arm64/boot/dts/allwinner/`.
2. Apply the kernel patch: `git apply 0001-net-stmmac-dwmac-sun8i-fix-AC200-RMII-syscon-and-AFE.patch`.
3. Recompile Linux kernel & Device Tree Blob (DTB).
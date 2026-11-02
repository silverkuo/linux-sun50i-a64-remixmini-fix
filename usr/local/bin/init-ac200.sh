#!/bin/bash
# ==============================================================================
# Jide Remix Mini PC (RM1G) - AC200 EPHY & eth0 Hardware Initialization Script
# ==============================================================================
# Description:
#   This script completes hardware bring-up for the AC200 EPHY on the Remix Mini
#   before networking services start.
#
# Hardware steps:
#   1. SoC PL10 (R_PWM): Outputs 24MHz clock (bypass OSC24M) to AC200 CKI pin.
#   2. CCU & Pinmux: Ensures EMAC bus clocks are enabled and Port D pins are routed
#      to EMAC Function 4, keeping PD14 strictly isolated (0x77474477).
#   3. SYSCON (0x01c00030): Configures EMAC clock control for RMII mode (0x00012001).
#   4. AC200 I2C AFE: Configures Power, Crystal, PLL, and AFE calibration on AC200.
#   5. Driver Loading: Loads dwmac_sun8i module.
#   6. Link Bring-up: Brings up eth0 interface.
# ==============================================================================

set -e

echo "[AC200-INIT] Starting Remix Mini RM1G Ethernet initialization..."

# Helper for memory access
devmem_write() {
    local addr="$1"
    local val="$2"
    if command -v busybox >/dev/null 2>&1; then
        busybox devmem "$addr" 32 "$val"
    elif command -v devmem >/dev/null 2>&1; then
        devmem "$addr" 32 "$val"
    else
        echo "[AC200-INIT] ERROR: Neither busybox devmem nor devmem found!" >&2
        exit 1
    fi
}

echo "[AC200-INIT] Step 1: Enabling PL10 R_PWM 24MHz CKI Clock to AC200..."
# Enable R_PWM bus gate in R_CCU (0x01f01428)
devmem_write 0x01f01428 0x0000000f
# Pinmux PL10 to s_pwm (Function 2, Bits [11:8] = 0x2 in 0x01f02c04)
devmem_write 0x01f02c04 0x00072277
# Enable OSC24M bypass mode on R_PWM Channel 0 (0x01f03800 = 0x00000250)
devmem_write 0x01f03800 0x00000250

echo "[AC200-INIT] Step 2: Verifying CCU Clocks & Port D Pinmux..."
# CCU PLL_PERIPH0
devmem_write 0x01c2002c 0x90041811
# AHB2 Bus Gating & Reset
devmem_write 0x01c20060 0x33824740
devmem_write 0x01c20064 0x00621818
devmem_write 0x01c20068 0x00006121
# Port D Pinmux: PD10, PD11, PD13 as EMAC, PD14 disabled (0x77474477)
devmem_write 0x01c20870 0x77474477
# Port D Pinmux: PD17-PD20, PD22, PD23 as EMAC (0x44744447)
devmem_write 0x01c20874 0x44744447

echo "[AC200-INIT] Step 3: Setting SYSCON 0x01c00030 = 0x00012001 (RMII mode)..."
devmem_write 0x01c00030 0x00012001

echo "[AC200-INIT] Step 4: Configuring AC200 AFE registers..."
# Determine I2C bus device
I2C_DEV="/dev/i2c-1"
if [ ! -e "$I2C_DEV" ]; then
    # Try finding the i2c adapter by scanning sysfs
    for i2c_path in /sys/bus/i2c/devices/i2c-*; do
        if [ -d "$i2c_path" ]; then
            dev_name=$(basename "$i2c_path")
            if [ -e "/dev/$dev_name" ]; then
                I2C_DEV="/dev/$dev_name"
                break
            fi
        fi
    done
fi

if [ ! -e "$I2C_DEV" ]; then
    echo "[AC200-INIT] ERROR: I2C device not found!" >&2
    exit 1
fi

# Prefer compiled ac200-afe-init binary if available
if command -v ac200-afe-init >/dev/null 2>&1; then
    ac200-afe-init -d "$I2C_DEV"
elif [ -x "/usr/local/bin/ac200-afe-init" ]; then
    /usr/local/bin/ac200-afe-init -d "$I2C_DEV"
elif [ -f "/usr/src/ac200-afe-init.c" ] && command -v gcc >/dev/null 2>&1; then
    echo "[AC200-INIT] Compiling /usr/src/ac200-afe-init.c..."
    gcc -O2 /usr/src/ac200-afe-init.c -o /usr/local/bin/ac200-afe-init
    /usr/local/bin/ac200-afe-init -d "$I2C_DEV"
else
    # Fallback to inline Python 3 script
    python3 - "$I2C_DEV" << 'PYEOF'
import os, sys, fcntl

i2c_dev = sys.argv[1]
I2C_SLAVE_FORCE = 0x0706
fd = os.open(i2c_dev, os.O_RDWR)
fcntl.ioctl(fd, I2C_SLAVE_FORCE, 0x10)

def set_page(p):
    os.write(fd, bytes([0xfe, 0x00, p]))

def write_reg(r, v):
    os.write(fd, bytes([r, (v >> 8) & 0xff, v & 0xff]))

# Page 0 (Power / Clocks)
set_page(0x00)
write_reg(0x08, 0x0007)
write_reg(0x0a, 0xc80c)
write_reg(0x0c, 0x8200) # SYS_PLL Enabled
write_reg(0x0e, 0x014a)
write_reg(0x14, 0x0003) # System clock on, reset deasserted
write_reg(0x16, 0x000f) # MII/RMII IO ENABLED!

# Page 0x60 (EPHY Control)
set_page(0x60)
write_reg(0x00, 0x4806) # RMII mode, 24MHz, shutdown = 0

# Page 0x40 (EPHY PLL / AFE)
set_page(0x40)
write_reg(0x00, 0x0100)
write_reg(0x06, 0x0001)
write_reg(0x08, 0x10a0)
write_reg(0x0a, 0x4300)
write_reg(0x0c, 0x0004)
write_reg(0x0e, 0x0001)
write_reg(0x10, 0x7c1f)
write_reg(0x12, 0x21f0)
write_reg(0x14, 0x0020)
write_reg(0x16, 0x0076)
write_reg(0x18, 0x0016)
write_reg(0x1c, 0x020d)
write_reg(0x1e, 0x0016)

set_page(0x00)
os.close(fd)
PYEOF
fi

echo "[AC200-INIT] Step 5: Loading dwmac_sun8i module..."
modprobe dwmac_sun8i || true
sleep 1
# Ensure SYSCON is locked to RMII mode
devmem_write 0x01c00030 0x00012001

echo "[AC200-INIT] Step 6: Bringing up eth0..."
if ip link show eth0 >/dev/null 2>&1; then
    ip link set eth0 up
    echo "[AC200-INIT] Successfully brought up eth0!"
else
    echo "[AC200-INIT] ERROR: eth0 network device does not exist!" >&2
    exit 1
fi

echo "[AC200-INIT] Initialization complete!"

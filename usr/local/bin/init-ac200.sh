#!/bin/bash
# ==============================================================================
# Jide Remix Mini PC (RM1G) - AC200 EPHY & eth0 Hardware Initialization Script
# ==============================================================================

echo "[AC200-INIT] Step 1: Enabling PL10 R_PWM 24MHz CKI Clock to AC200..."
# Enable R_PWM bus gate in R_CCU (Bit 2)
busybox devmem 0x01f01428 32 0x0000000f
# Pinmux PL10 to s_pwm (Bits [11:8] = 0x2)
busybox devmem 0x01f02c04 32 0x00072277
# Enable OSC24M clock bypass mode on R_PWM Channel 0 (0x250)
busybox devmem 0x01f03800 32 0x00000250

echo "[AC200-INIT] Step 2: CCU Clocks & Port D Pinmux..."
busybox devmem 0x01c2002c 32 0x90041811
busybox devmem 0x01c20060 32 0x33824740
busybox devmem 0x01c20064 32 0x00621818
busybox devmem 0x01c20068 32 0x00006121
busybox devmem 0x01c20870 32 0x77474477
busybox devmem 0x01c20874 32 0x44744447

echo "[AC200-INIT] Step 3: SYSCON 0x01c00030 = 0x00012001 (RMII mode)..."
busybox devmem 0x01c00030 32 0x00012001

echo "[AC200-INIT] Step 4: AC200 I2C Configuration via /dev/i2c-1..."
python3 - << 'PYEOF'
import os, fcntl

I2C_SLAVE_FORCE = 0x0706
fd = os.open('/dev/i2c-1', os.O_RDWR)
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

echo "[AC200-INIT] Step 5: Loading dwmac_sun8i module..."
modprobe dwmac_sun8i || true
sleep 1
busybox devmem 0x01c00030 32 0x00012001

echo "[AC200-INIT] Step 6: Bring up eth0..."
ip link set eth0 up || true

echo "[AC200-INIT] Initialization complete! eth0 is ready."

// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * ac200-afe-init.c - Hardware Initialization Utility for X-Powers AC200 EPHY
 *
 * Configures the X-Powers AC200 Multi-Function IC (I2C address 0x10) for
 * Ethernet PHY operation on Jide Remix Mini (RM1G, Allwinner A64 / sun50i-a64).
 *
 * Sequence:
 *   1. Page 0x00: System Power, 24MHz Crystal, PLL, and Clock Gating
 *   2. Page 0x40: Analog Front-End (AFE) calibration parameters (extracted from factory Android)
 *   3. Page 0x60: EPHY Control (RMII mode, 24MHz reference clock, wakeup)
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/i2c-dev.h>

#ifndef I2C_SLAVE_FORCE
#define I2C_SLAVE_FORCE 0x0706
#endif

#define DEFAULT_I2C_DEV "/dev/i2c-1"
#define AC200_I2C_ADDR  0x10

struct reg_val {
    uint8_t reg;
    uint16_t val;
    const char *desc;
};

static int ac200_set_page(int fd, uint8_t page)
{
    uint8_t buf[3] = { 0xfe, 0x00, page };
    if (write(fd, buf, 3) != 3) {
        fprintf(stderr, "Error: Failed to switch to page 0x%02x: %s\n", page, strerror(errno));
        return -1;
    }
    usleep(500);
    return 0;
}

static int ac200_write_reg(int fd, uint8_t reg, uint16_t val)
{
    uint8_t buf[3];
    buf[0] = reg;
    buf[1] = (val >> 8) & 0xff;
    buf[2] = val & 0xff;

    if (write(fd, buf, 3) != 3) {
        fprintf(stderr, "Error: Failed to write reg 0x%02x = 0x%04x: %s\n", reg, val, strerror(errno));
        return -1;
    }
    usleep(500);
    return 0;
}

static int ac200_read_reg(int fd, uint8_t reg, uint16_t *val)
{
    uint8_t reg_buf[1] = { reg };
    uint8_t data_buf[2];

    if (write(fd, reg_buf, 1) != 1) {
        return -1;
    }
    usleep(300);
    if (read(fd, data_buf, 2) != 2) {
        return -1;
    }
    *val = ((uint16_t)data_buf[0] << 8) | data_buf[1];
    return 0;
}

int main(int argc, char *argv[])
{
    const char *i2c_dev = DEFAULT_I2C_DEV;
    bool verify = true;
    int fd;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            i2c_dev = argv[++i];
        } else if (strcmp(argv[i], "--no-verify") == 0) {
            verify = false;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("Usage: %s [-d /dev/i2c-X] [--no-verify]\n", argv[0]);
            printf("Initialize X-Powers AC200 EPHY AFE and clocks on Remix Mini (RM1G).\n");
            return 0;
        }
    }

    printf("[AC200] Opening I2C device %s (slave 0x%02x)...\n", i2c_dev, AC200_I2C_ADDR);
    fd = open(i2c_dev, O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "Error: Cannot open %s: %s\n", i2c_dev, strerror(errno));
        return 1;
    }

    if (ioctl(fd, I2C_SLAVE_FORCE, AC200_I2C_ADDR) < 0) {
        fprintf(stderr, "Error: Cannot set I2C slave address 0x%02x: %s\n", AC200_I2C_ADDR, strerror(errno));
        close(fd);
        return 1;
    }

    /* 1. Page 0x00: System Power and Clocks */
    printf("[AC200] Configuring Page 0x00 (Power, Crystal & Clocks)...\n");
    if (ac200_set_page(fd, 0x00) < 0) goto err;

    static const struct reg_val p0_regs[] = {
        { 0x08, 0x0007, "Enable 24MHz crystal" },
        { 0x0a, 0xc80c, "Clock configuration" },
        { 0x0c, 0x8200, "SYS_PLL enable" },
        { 0x0e, 0x014a, "PLL tuning" },
        { 0x14, 0x0003, "EPHY sysclk on, reset deasserted" },
        { 0x16, 0x000f, "Enable MII/RMII IO and LED" },
    };
    for (size_t i = 0; i < sizeof(p0_regs) / sizeof(p0_regs[0]); i++) {
        if (ac200_write_reg(fd, p0_regs[i].reg, p0_regs[i].val) < 0) goto err;
    }

    /* 2. Page 0x40: Analog Front-End (AFE) Calibration */
    printf("[AC200] Configuring Page 0x40 (Analog Front-End Calibration)...\n");
    if (ac200_set_page(fd, 0x40) < 0) goto err;

    static const struct reg_val p40_regs[] = {
        { 0x00, 0x0100, "AFE control 0" },
        { 0x06, 0x0001, "AFE control 1" },
        { 0x08, 0x10a0, "AFE bias" },
        { 0x0a, 0x4300, "AFE PLL" },
        { 0x0c, 0x0004, "AFE filter" },
        { 0x0e, 0x0001, "AFE tuning" },
        { 0x10, 0x7c1f, "AFE impedance 1" },
        { 0x12, 0x21f0, "AFE impedance 2" },
        { 0x14, 0x0020, "AFE drive" },
        { 0x16, 0x0076, "AFE RX gain" },
        { 0x18, 0x0016, "AFE loop filter" },
        { 0x1c, 0x020d, "AFE TX drive" },
        { 0x1e, 0x0016, "AFE calibration end" },
    };
    for (size_t i = 0; i < sizeof(p40_regs) / sizeof(p40_regs[0]); i++) {
        if (ac200_write_reg(fd, p40_regs[i].reg, p40_regs[i].val) < 0) goto err;
    }

    /* 3. Page 0x60: EPHY Control (RMII mode, 24MHz reference clock, wakeup) */
    printf("[AC200] Configuring Page 0x60 (EPHY RMII & Wakeup)...\n");
    if (ac200_set_page(fd, 0x60) < 0) goto err;

    if (ac200_write_reg(fd, 0x00, 0x4806) < 0) goto err; /* RMII, 24M, LED, shutdown=0 */

    /* Reset page pointer back to 0x00 */
    ac200_set_page(fd, 0x00);

    /* Verification readback */
    if (verify) {
        uint16_t r0c, r16;
        ac200_read_reg(fd, 0x0c, &r0c);
        ac200_read_reg(fd, 0x16, &r16);
        ac200_set_page(fd, 0x60);
        uint16_t r60;
        ac200_read_reg(fd, 0x00, &r60);
        ac200_set_page(fd, 0x00);

        printf("[AC200] Verification: P0_0C=0x%04x, P0_16=0x%04x, P60_00=0x%04x\n", r0c, r16, r60);
        if ((r16 & 0x0001) == 0 || (r60 & 0x0001) != 0) {
            fprintf(stderr, "Warning: AC200 readback verification mismatch!\n");
            close(fd);
            return 2;
        }
    }

    printf("[AC200] Initialization successful!\n");
    close(fd);
    return 0;

err:
    close(fd);
    fprintf(stderr, "[AC200] Initialization failed!\n");
    return 1;
}

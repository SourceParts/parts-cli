/*
 * i2c_scan.c — Bare-metal I2C bus scanner for A64
 *
 * Scans TWI0, TWI1, TWI2 for responding devices (addr 0x03-0x77).
 * Also reads back AXP803 PMIC registers via RSB to verify power state.
 *
 * Build:
 *   arm-none-eabi-gcc -nostdlib -nostartfiles -ffreestanding \
 *     -march=armv8-a -mfloat-abi=soft -O2 \
 *     -Ttext=0x1A200 -Wl,-e,_start \
 *     -o i2c_scan.elf i2c_scan.c
 *   arm-none-eabi-objcopy -O binary i2c_scan.elf i2c_scan.bin
 */

typedef unsigned int u32;
typedef unsigned char u8;
typedef volatile u32 vu32;

/* TWI (I2C) base addresses */
#define TWI0_BASE   0x01C2AC00
#define TWI1_BASE   0x01C2B000
#define TWI2_BASE   0x01C2B400

/* TWI register offsets (sun4i layout) */
#define TWI_ADDR     0x00
#define TWI_XADDR    0x04
#define TWI_DATA     0x08
#define TWI_CTRL     0x0C
#define TWI_STAT     0x10
#define TWI_CLK      0x14
#define TWI_SRST     0x18

/* Control bits */
#define CTRL_ACK     (1 << 2)
#define CTRL_IFLG    (1 << 3)
#define CTRL_STOP    (1 << 4)
#define CTRL_START   (1 << 5)
#define CTRL_ENABLE  (1 << 6)
#define CTRL_INTEN   (1 << 7)

/* Status codes */
#define STAT_START_SENT     0x08
#define STAT_RSTART_SENT    0x10
#define STAT_ADDR_W_ACK     0x18
#define STAT_ADDR_W_NACK    0x20
#define STAT_ADDR_R_ACK     0x40
#define STAT_ADDR_R_NACK    0x48

/* CCU for TWI clock gating */
#define CCU_BUS_CLK_GATE3   (*(vu32*)0x01C2006C)  /* APB2 gate */
#define CCU_BUS_SOFT_RST4   (*(vu32*)0x01C202D8)  /* APB2 reset */

/* RSB */
#define RSB_BASE     0x01F03400
#define RSB_CTRL     0x00
#define RSB_INTS     0x0C
#define RSB_ADDR     0x10
#define RSB_DATA     0x1C
#define RSB_CMD      0x2C
#define RSB_DAR      0x30
#define PMIC_RTA     0x2D

#define REG(base, off) (*(vu32*)((base) + (off)))

static inline void delay(u32 n) { while(n--) __asm__ volatile("nop"); }

/* =========================================================
 * Output buffer layout (at buf_addr):
 *   [0]:    TWI0 device count
 *   [1-16]: TWI0 addresses found (up to 16)
 *   [17]:   TWI1 device count
 *   [18-33]: TWI1 addresses found
 *   [34]:   TWI2 device count
 *   [35-50]: TWI2 addresses found
 *   [51]:   PMIC reg 0x12 (PWR_OUT_CTRL2)
 *   [52]:   PMIC reg 0x10 (PWR_OUT_CTRL1)
 *   [53]:   PMIC reg 0x13 (PWR_OUT_CTRL3)
 *   [54]:   PMIC reg 0x90 (GPIO0_CTRL / LDO_IO0)
 *   [55]:   PMIC reg 0x91 (LDO_IO0_VOUT)
 *   [56]:   PMIC reg 0x00 (POWER_STATUS)
 * ========================================================= */

struct scan_result {
    u8 twi0_count;
    u8 twi0_addrs[16];
    u8 twi1_count;
    u8 twi1_addrs[16];
    u8 twi2_count;
    u8 twi2_addrs[16];
    u8 pmic_pwr_ctrl2;   /* reg 0x12 */
    u8 pmic_pwr_ctrl1;   /* reg 0x10 */
    u8 pmic_pwr_ctrl3;   /* reg 0x13 */
    u8 pmic_gpio0;       /* reg 0x90 */
    u8 pmic_ldo_io0_v;   /* reg 0x91 */
    u8 pmic_power_status; /* reg 0x00 */
    u8 status;           /* 0=success */
    u8 padding;
};

/* =========================================================
 * TWI (I2C) operations
 * ========================================================= */

static void twi_init(u32 base) {
    /* Soft reset */
    REG(base, TWI_SRST) = 1;
    delay(1000);

    /* Set clock: CLK_M=2, CLK_N=3 → ~100KHz from 24MHz APB2 */
    REG(base, TWI_CLK) = (2 << 3) | 3;

    /* Enable controller */
    REG(base, TWI_CTRL) = CTRL_ENABLE;
    delay(1000);
}

static int twi_wait_iflg(u32 base) {
    for (u32 i = 0; i < 50000; i++) {
        if (REG(base, TWI_CTRL) & CTRL_IFLG)
            return 0;
        delay(1);
    }
    return -1;
}

/* Probe address: send START + ADDR(W), check ACK, send STOP */
static int twi_probe(u32 base, u8 addr) {
    /* Clear any pending state */
    REG(base, TWI_CTRL) = CTRL_ENABLE;
    delay(100);

    /* Send START */
    REG(base, TWI_CTRL) = CTRL_ENABLE | CTRL_START;
    if (twi_wait_iflg(base)) goto fail;

    u32 stat = REG(base, TWI_STAT);
    if (stat != STAT_START_SENT && stat != STAT_RSTART_SENT) goto fail;

    /* Send address (write mode) */
    REG(base, TWI_DATA) = (addr << 1) | 0;  /* write bit = 0 */
    REG(base, TWI_CTRL) = CTRL_ENABLE;       /* clear IFLG, trigger send */
    if (twi_wait_iflg(base)) goto fail;

    stat = REG(base, TWI_STAT);

    /* Send STOP regardless */
    REG(base, TWI_CTRL) = CTRL_ENABLE | CTRL_STOP;
    delay(500);

    return (stat == STAT_ADDR_W_ACK) ? 0 : -1;

fail:
    REG(base, TWI_CTRL) = CTRL_ENABLE | CTRL_STOP;
    delay(500);
    return -1;
}

static int scan_bus(u32 base, u8 *addrs, int max) {
    int count = 0;
    twi_init(base);

    for (u8 addr = 0x03; addr <= 0x77 && count < max; addr++) {
        if (twi_probe(base, addr) == 0) {
            addrs[count++] = addr;
        }
    }
    return count;
}

/* =========================================================
 * RSB read (for PMIC)
 * ========================================================= */

static u8 rsb_read8(u8 reg) {
    u32 base = RSB_BASE;
    REG(base, RSB_ADDR) = reg;
    REG(base, RSB_DAR) = PMIC_RTA << 16;
    REG(base, RSB_CMD) = 0x8B;  /* RD8 */
    REG(base, RSB_CTRL) = 0x82; /* START_TRANS | INT_ENB */

    for (u32 i = 0; i < 100000; i++) {
        if (!(REG(base, RSB_CTRL) & (1 << 7)))
            break;
    }
    u32 ints = REG(base, RSB_INTS);
    REG(base, RSB_INTS) = ints;

    return REG(base, RSB_DATA) & 0xFF;
}

/* =========================================================
 * Params + Entry
 * ========================================================= */

struct params {
    u32 buf_addr;
    u32 stat_addr;
};

__attribute__((section(".params")))
volatile struct params g_params = {
    .buf_addr  = 0x00012000,
    .stat_addr = 0x00011F00,
};

void __attribute__((naked, section(".text.entry"))) _start(void) {
    __asm__ volatile(
        "push {r4-r11, lr}\n"
        "bl   main\n"
        "pop  {r4-r11, lr}\n"
        "bx   lr\n"
    );
}

void main(void) {
    volatile struct params *p = &g_params;
    struct scan_result *res = (struct scan_result *)p->buf_addr;
    u32 *stat = (u32 *)p->stat_addr;
    *stat = 0xFF;  /* in progress */

    /* Enable TWI0/1/2 clocks (APB2 gate bits 0,1,2) */
    CCU_BUS_CLK_GATE3 |= (1 << 0) | (1 << 1) | (1 << 2);
    /* Deassert TWI0/1/2 reset */
    CCU_BUS_SOFT_RST4 |= (1 << 0) | (1 << 1) | (1 << 2);
    delay(10000);

    /* Configure TWI GPIO pins
     * TWI0: PH0=SCL, PH1=SDA (func 2)
     * TWI1: PH2=SCL, PH3=SDA (func 2)
     * TWI2: PE14=SCL, PE15=SDA (func 3)
     */
    /* PH_CFG0: PH0-PH3 = func 2 */
    vu32 *ph_cfg0 = (vu32 *)(0x01C20800 + 0xFC);
    u32 val = *ph_cfg0;
    val &= ~0x0000FFFF;           /* clear PH0-PH3 */
    val |=  0x00002222;           /* PH0-PH3 = func 2 (TWI0/TWI1) */
    *ph_cfg0 = val;

    /* PE_CFG1: PE14=func3, PE15=func3 */
    vu32 *pe_cfg1 = (vu32 *)(0x01C20800 + 0x94);
    val = *pe_cfg1;
    val &= ~(0xFF << 24);         /* clear PE14-PE15 */
    val |=  (0x33 << 24);         /* PE14=func3, PE15=func3 */
    *pe_cfg1 = val;

    /* Pull-ups for I2C lines */
    vu32 *ph_pul0 = (vu32 *)(0x01C20800 + 0x118);
    *ph_pul0 |= 0x00000055;       /* pull-up PH0-PH3 */

    delay(5000);

    /* Scan buses */
    res->twi0_count = scan_bus(TWI0_BASE, res->twi0_addrs, 16);
    res->twi1_count = scan_bus(TWI1_BASE, res->twi1_addrs, 16);
    res->twi2_count = scan_bus(TWI2_BASE, res->twi2_addrs, 16);

    /* Read PMIC registers */
    res->pmic_pwr_ctrl2    = rsb_read8(0x12);
    res->pmic_pwr_ctrl1    = rsb_read8(0x10);
    res->pmic_pwr_ctrl3    = rsb_read8(0x13);
    res->pmic_gpio0        = rsb_read8(0x90);
    res->pmic_ldo_io0_v    = rsb_read8(0x91);
    res->pmic_power_status = rsb_read8(0x00);

    res->status = 0;  /* success */
    *stat = 0;
}

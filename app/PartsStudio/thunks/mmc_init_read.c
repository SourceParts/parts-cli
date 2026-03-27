/*
 * mmc_init_read.c — Bare-metal SD/eMMC init + sector read for A64 FEL mode
 *
 * Runs in SRAM (no DRAM). Initializes the MMC controller from scratch,
 * performs SD card initialization sequence, then reads sectors.
 *
 * Supports both MMC0 (SD card) and MMC2 (eMMC) via patched base address.
 *
 * Build:
 *   arm-none-eabi-gcc -nostdlib -nostartfiles -ffreestanding \
 *     -march=armv8-a -mfloat-abi=soft -O2 \
 *     -Wl,--section-start=.text=0x11000 -Wl,-e,_start \
 *     -o mmc_init_read.elf mmc_init_read.c
 *   arm-none-eabi-objcopy -O binary mmc_init_read.elf mmc_init_read.bin
 */

typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef volatile u32 vu32;

/* =========================================================
 * Register addresses (A64)
 * ========================================================= */

#define CCU_BASE        0x01C20000
#define MMC0_BASE       0x01C0F000
#define MMC2_BASE       0x01C11000
#define PIO_BASE        0x01C20800

/* CCU registers */
#define CCU_BUS_CLK_GATE0    (*(vu32*)(CCU_BASE + 0x060))
#define CCU_BUS_SOFT_RST0    (*(vu32*)(CCU_BASE + 0x2C0))
#define CCU_SDMMC0_CLK       (*(vu32*)(CCU_BASE + 0x088))
#define CCU_SDMMC2_CLK       (*(vu32*)(CCU_BASE + 0x090))

/* PIO (GPIO) registers for MMC0 pins (Port F) */
#define PIO_PF_CFG0          (*(vu32*)(PIO_BASE + 0x0B4))  /* PF0-PF7 config */
#define PIO_PF_PUL0          (*(vu32*)(PIO_BASE + 0x0DC))  /* PF pull-up/down */

/* MMC register offsets */
#define MMC_GCTRL    0x00
#define MMC_CLKCR    0x04
#define MMC_TMOUT    0x08
#define MMC_WIDTH    0x0C
#define MMC_BLKSZ    0x10
#define MMC_BYTECNT  0x14
#define MMC_CMD      0x18
#define MMC_ARG      0x1C
#define MMC_RESP0    0x20
#define MMC_RESP1    0x24
#define MMC_RESP2    0x28
#define MMC_RESP3    0x2C
#define MMC_IMASK    0x30
#define MMC_MINT     0x34
#define MMC_RINT     0x38
#define MMC_STATUS   0x3C
#define MMC_FIFOTH   0x40
#define MMC_FUNS     0x44
#define MMC_NTSR     0x5C
#define MMC_FIFO     0x200

/* CMD bits */
#define CMD_START       (1u << 31)
#define CMD_CHANGE_CLK  (1u << 21)
#define CMD_SEND_INIT   (1u << 15)
#define CMD_WAIT_PRE    (1u << 13)
#define CMD_AUTO_STOP   (1u << 12)
#define CMD_WRITE       (1u << 10)
#define CMD_DATA        (1u << 9)
#define CMD_CHK_CRC     (1u << 8)
#define CMD_LONG_RESP   (1u << 7)
#define CMD_RESP        (1u << 6)

/* RINT bits */
#define RINT_CMD_DONE   (1u << 2)
#define RINT_DATA_OVER  (1u << 3)
#define RINT_RX_REQ     (1u << 5)
#define RINT_ERROR      0x0000BFFE

/* Status bits */
#define STATUS_FIFO_EMPTY (1u << 2)

/* GCTRL bits */
#define GCTRL_SOFT_RST  (1u << 0)
#define GCTRL_FIFO_RST  (1u << 1)
#define GCTRL_DMA_RST   (1u << 2)
#define GCTRL_AHB_ACCESS (1u << 31)

/* =========================================================
 * Helpers
 * ========================================================= */

#define REG(base, off) (*(vu32*)((base) + (off)))

static inline void delay(u32 n) {
    while (n--) asm volatile("nop");
}

static void wreg(u32 base, u32 off, u32 val) { REG(base, off) = val; }
static u32 rreg(u32 base, u32 off) { return REG(base, off); }

/* =========================================================
 * Parameters (patched by host at load time)
 * ========================================================= */

/* These are placed at a fixed offset from _start. The host patches them
 * before executing the thunk. */
struct params {
    u32 mmc_base;       /* MMC0 or MMC2 base address */
    u32 sector_start;   /* LBA start sector */
    u32 sector_count;   /* number of 512-byte sectors */
    u32 buf_addr;       /* output data buffer (SRAM) */
    u32 stat_addr;      /* status output (SRAM) */
    u32 is_emmc;        /* 0 = SD card (MMC0), 1 = eMMC (MMC2) */
};

/* Linker places this right after code */
__attribute__((section(".params")))
volatile struct params g_params = {
    .mmc_base     = MMC0_BASE,
    .sector_start = 0,
    .sector_count = 1,
    .buf_addr     = 0x00012000,
    .stat_addr    = 0x00011F00,
    .is_emmc      = 0,
};

struct status {
    u32 error;          /* 0 = success */
    u32 sectors_read;
    u32 rca;            /* relative card address */
    u32 debug;          /* debug info */
};

/* =========================================================
 * MMC command send
 * ========================================================= */

static int mmc_send_cmd(u32 base, u32 cmd_idx, u32 arg, u32 flags) {
    /* Clear pending interrupts */
    wreg(base, MMC_RINT, 0xFFFFFFFF);

    /* Set argument */
    wreg(base, MMC_ARG, arg);

    /* Build command register value */
    u32 cmd_val = CMD_START | (cmd_idx & 0x3F) | flags;
    wreg(base, MMC_CMD, cmd_val);

    /* Wait for command done */
    for (u32 i = 0; i < 500000; i++) {
        u32 rint = rreg(base, MMC_RINT);
        if (rint & RINT_CMD_DONE)
            break;
        if (rint & RINT_ERROR)
            return -1;
        delay(1);
    }

    /* Check for errors */
    u32 rint = rreg(base, MMC_RINT);
    if (rint & RINT_ERROR)
        return -1;

    return 0;
}

static int mmc_update_clk(u32 base) {
    wreg(base, MMC_CMD, CMD_START | CMD_CHANGE_CLK | CMD_WAIT_PRE);
    for (u32 i = 0; i < 500000; i++) {
        if (!(rreg(base, MMC_CMD) & CMD_START))
            return 0;
        delay(1);
    }
    return -1;
}

/* =========================================================
 * Clock + GPIO setup
 * ========================================================= */

static void mmc_clock_init(u32 is_emmc) {
    if (is_emmc) {
        /* MMC2 (eMMC): enable AHB gate (bit 10), deassert reset (bit 10) */
        CCU_BUS_CLK_GATE0 |= (1 << 10);
        CCU_BUS_SOFT_RST0 |= (1 << 10);
        /* Set MMC2 clock: OSC24M source (0), divider 1, enable */
        CCU_SDMMC2_CLK = (1u << 31) | (0 << 24) | 0;  /* 24MHz */
    } else {
        /* MMC0 (SD card): enable AHB gate (bit 8), deassert reset (bit 8) */
        CCU_BUS_CLK_GATE0 |= (1 << 8);
        CCU_BUS_SOFT_RST0 |= (1 << 8);
        /* Set MMC0 clock: OSC24M source (0), divider 1, enable */
        CCU_SDMMC0_CLK = (1u << 31) | (0 << 24) | 0;  /* 24MHz */
    }
    delay(10000);

    /* Configure GPIO Port F for MMC0 (SD card)
     * PF0=CMD, PF1=CLK, PF2=D0, PF3=D1, PF4=D2, PF5=D3
     * All set to function 2 (SDC0) */
    if (!is_emmc) {
        PIO_PF_CFG0 = 0x00222222;  /* PF0-PF5 = func 2 */
        PIO_PF_PUL0 = 0x00000555;  /* pull-up on all */
    }
    /* eMMC uses Port C, which should already be configured */
}

/* =========================================================
 * MMC controller init
 * ========================================================= */

static void mmc_reset(u32 base) {
    wreg(base, MMC_GCTRL, GCTRL_SOFT_RST | GCTRL_FIFO_RST | GCTRL_DMA_RST);
    for (u32 i = 0; i < 100000; i++) {
        if (!(rreg(base, MMC_GCTRL) & GCTRL_SOFT_RST))
            break;
        delay(1);
    }
    /* AHB access mode (not DMA) */
    wreg(base, MMC_GCTRL, GCTRL_AHB_ACCESS);
    /* Default timeout */
    wreg(base, MMC_TMOUT, 0xFFFFFFFF);
    /* Disable all interrupts */
    wreg(base, MMC_IMASK, 0);
    wreg(base, MMC_RINT, 0xFFFFFFFF);
}

static int mmc_set_clock(u32 base, int slow) {
    /* Disable clock output */
    wreg(base, MMC_CLKCR, 0);
    if (mmc_update_clk(base)) return -1;

    /* Set divider: slow=150 (~160KHz for init), fast=1 (~12MHz for transfer) */
    u32 div = slow ? 150 : 1;
    wreg(base, MMC_CLKCR, (1u << 16) | div);  /* enable + divider */
    if (mmc_update_clk(base)) return -1;

    delay(10000);
    return 0;
}

/* =========================================================
 * SD card initialization
 * ========================================================= */

static int sd_init(u32 base, u32 *rca_out) {
    /* CMD0: GO_IDLE_STATE */
    mmc_send_cmd(base, 0, 0, CMD_SEND_INIT);
    delay(50000);

    /* CMD8: SEND_IF_COND (voltage check, pattern 0xAA) */
    int ret = mmc_send_cmd(base, 8, 0x1AA, CMD_RESP | CMD_CHK_CRC);
    int is_sdhc = (ret == 0);  /* SDHC if CMD8 accepted */

    /* ACMD41 loop: SD_SEND_OP_COND until card ready */
    for (int i = 0; i < 100; i++) {
        /* CMD55: prefix for ACMD */
        mmc_send_cmd(base, 55, 0, CMD_RESP | CMD_CHK_CRC);
        /* ACMD41: voltage window 3.2-3.4V, HCS if SDHC */
        u32 ocr_arg = 0x00300000;  /* 3.2-3.4V */
        if (is_sdhc) ocr_arg |= (1u << 30);  /* HCS */
        mmc_send_cmd(base, 41, ocr_arg, CMD_RESP);

        u32 resp = rreg(base, MMC_RESP0);
        if (resp & (1u << 31)) {  /* card ready */
            break;
        }
        delay(50000);
    }

    /* CMD2: ALL_SEND_CID */
    ret = mmc_send_cmd(base, 2, 0, CMD_RESP | CMD_LONG_RESP | CMD_CHK_CRC);
    if (ret) return -2;

    /* CMD3: SEND_RELATIVE_ADDR — card publishes its RCA */
    ret = mmc_send_cmd(base, 3, 0, CMD_RESP | CMD_CHK_CRC);
    if (ret) return -3;
    u32 rca = rreg(base, MMC_RESP0) & 0xFFFF0000;
    *rca_out = rca;

    /* Switch to faster clock */
    mmc_set_clock(base, 0);

    /* CMD7: SELECT_CARD */
    ret = mmc_send_cmd(base, 7, rca, CMD_RESP | CMD_CHK_CRC);
    if (ret) return -4;

    /* Set 4-bit bus width via ACMD6 */
    mmc_send_cmd(base, 55, rca, CMD_RESP | CMD_CHK_CRC);
    mmc_send_cmd(base, 6, 2, CMD_RESP | CMD_CHK_CRC);  /* 2 = 4-bit */
    wreg(base, MMC_WIDTH, 1);  /* 1 = 4-bit mode */

    return 0;
}

/* =========================================================
 * eMMC initialization
 * ========================================================= */

static int emmc_init(u32 base, u32 *rca_out) {
    /* CMD0: GO_IDLE_STATE */
    mmc_send_cmd(base, 0, 0, CMD_SEND_INIT);
    delay(50000);

    /* CMD1: SEND_OP_COND loop until ready */
    for (int i = 0; i < 100; i++) {
        mmc_send_cmd(base, 1, 0x40FF8080, CMD_RESP);  /* sector mode + voltage */
        u32 resp = rreg(base, MMC_RESP0);
        if (resp & (1u << 31)) break;
        delay(50000);
    }

    /* CMD2: ALL_SEND_CID */
    int ret = mmc_send_cmd(base, 2, 0, CMD_RESP | CMD_LONG_RESP | CMD_CHK_CRC);
    if (ret) return -2;

    /* CMD3: SET_RELATIVE_ADDR (eMMC: host assigns RCA) */
    u32 rca = 0x00010000;  /* RCA = 1 */
    ret = mmc_send_cmd(base, 3, rca, CMD_RESP | CMD_CHK_CRC);
    if (ret) return -3;
    *rca_out = rca;

    /* Faster clock */
    mmc_set_clock(base, 0);

    /* CMD7: SELECT_CARD */
    ret = mmc_send_cmd(base, 7, rca, CMD_RESP | CMD_CHK_CRC);
    if (ret) return -4;

    /* Set 8-bit bus width via CMD6 (SWITCH) */
    /* EXT_CSD[183] BUS_WIDTH: 2 = 8-bit */
    ret = mmc_send_cmd(base, 6, 0x03B70200, CMD_RESP | CMD_CHK_CRC);
    if (ret) return -5;
    wreg(base, MMC_WIDTH, 2);  /* 2 = 8-bit mode */
    delay(10000);

    return 0;
}

/* =========================================================
 * Sector read
 * ========================================================= */

static int mmc_read_sector(u32 base, u32 sector, u8 *buf) {
    /* Clear interrupts */
    wreg(base, MMC_RINT, 0xFFFFFFFF);

    /* Block size = 512, byte count = 512 */
    wreg(base, MMC_BLKSZ, 512);
    wreg(base, MMC_BYTECNT, 512);

    /* CMD17: READ_SINGLE_BLOCK (sector address for SDHC) */
    int ret = mmc_send_cmd(base, 17, sector,
                           CMD_RESP | CMD_CHK_CRC | CMD_DATA | CMD_WAIT_PRE);
    if (ret) return -1;

    /* Read 128 words from FIFO */
    u32 *dst = (u32 *)buf;
    for (int i = 0; i < 128; i++) {
        /* Wait for FIFO data */
        u32 timeout = 100000;
        while ((rreg(base, MMC_STATUS) & STATUS_FIFO_EMPTY) && --timeout)
            delay(1);
        if (!timeout) return -2;
        dst[i] = rreg(base, MMC_FIFO);
    }

    /* Wait for data transfer complete */
    for (u32 i = 0; i < 500000; i++) {
        if (rreg(base, MMC_RINT) & RINT_DATA_OVER)
            break;
        delay(1);
    }

    return 0;
}

/* =========================================================
 * Entry point
 * ========================================================= */

void __attribute__((naked, section(".text.entry"))) _start(void) {
    asm volatile(
        "ldr sp, =0x00018000\n"   /* stack at top of SRAM A1 */
        "bl  main\n"
        "bx  lr\n"               /* return to FEL/BROM */
    );
}

void main(void) {
    volatile struct params *p = &g_params;
    struct status *st = (struct status *)p->stat_addr;
    st->error = 0xFF;  /* mark as in-progress */
    st->sectors_read = 0;
    st->rca = 0;
    st->debug = 0;

    u32 base = p->mmc_base;

    /* 1. Enable clocks and GPIO */
    mmc_clock_init(p->is_emmc);

    /* 2. Reset MMC controller */
    mmc_reset(base);

    /* 3. Start with slow clock for init */
    if (mmc_set_clock(base, 1)) {
        st->error = 10;
        st->debug = rreg(base, MMC_STATUS);
        return;
    }

    /* 4. Initialize card */
    u32 rca = 0;
    int ret;
    if (p->is_emmc) {
        ret = emmc_init(base, &rca);
    } else {
        ret = sd_init(base, &rca);
    }
    if (ret) {
        st->error = 20 + (u32)(-ret);
        st->rca = rca;
        st->debug = rreg(base, MMC_RINT);
        return;
    }
    st->rca = rca;

    /* 5. Read sectors */
    u8 *buf = (u8 *)p->buf_addr;
    for (u32 i = 0; i < p->sector_count; i++) {
        ret = mmc_read_sector(base, p->sector_start + i, buf + i * 512);
        if (ret) {
            st->error = 30 + (u32)(-ret);
            st->sectors_read = i;
            st->debug = rreg(base, MMC_RINT);
            return;
        }
        st->sectors_read = i + 1;
    }

    st->error = 0;  /* success */
}

/*
 * lcd_power_on.S — Full RSB init + PMIC regulator enable + backlight
 *
 * Complete initialization sequence:
 * 1. Enable R_PIO and RSB clocks via PRCM
 * 2. Configure PL0/PL1 as RSB pins
 * 3. Soft-reset RSB controller
 * 4. Set RSB clock to 3MHz
 * 5. Send device mode init (DMCR)
 * 6. Set runtime address (STRA): device 0x3A3 -> RTA 0x2D
 * 7. Enable PMIC regulators: DC1SW, DLDO1, DLDO2, LDO_IO0
 * 8. Set PH10 GPIO high (backlight enable)
 * 9. Configure R_PWM for brightness
 *
 * Assemble: arm-none-eabi-as -march=armv8-a -o lcd_power_on.o lcd_power_on.S
 * Extract:  arm-none-eabi-objcopy -O binary lcd_power_on.o lcd_power_on.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

/* ========== Addresses ========== */
.equ PRCM_BASE,     0x01F01400
.equ PRCM_APB0_RST, PRCM_BASE + 0xB0   /* APB0 soft reset */
.equ PRCM_APB0_GATE, PRCM_BASE + 0x28  /* APB0 clock gate */

.equ R_PIO_BASE,    0x01F02C00
.equ PL_CFG0,       R_PIO_BASE + 0x00   /* PL0-PL7 config */
.equ PL_CFG1,       R_PIO_BASE + 0x04   /* PL8-PL15 config */
.equ PL_PUL0,       R_PIO_BASE + 0x1C   /* PL pull-up/down */
.equ PL_DRV0,       R_PIO_BASE + 0x14   /* PL drive strength */

.equ RSB_BASE,      0x01F03400
.equ RSB_CTRL,      0x00
.equ RSB_CCR,       0x04
.equ RSB_INTE,      0x08
.equ RSB_STAT,      0x0C
.equ RSB_ADDR,      0x10
.equ RSB_DATA,      0x1C
.equ RSB_LCR,       0x24
.equ RSB_DMCR,      0x28
.equ RSB_CMD,       0x2C
.equ RSB_DEVADDR,   0x30

.equ PIO_BASE,      0x01C20800
.equ PH_CFG1,       PIO_BASE + 0x100
.equ PH_DAT,        PIO_BASE + 0x10C

.equ R_PWM_BASE,    0x01F03800

/* ========== Constants ========== */
.equ PMIC_HWADDR,   0x3A3
.equ PMIC_RTA,      0x2D

_start:
    push  {r4-r11, lr}
    ldr   r11, =RSB_BASE
    ldr   r10, brightness

    /* ============================================
     * STEP 1: Enable PRCM clocks for R_PIO + RSB
     * APB0 gate bit 0 = R_PIO, bit 3 = RSB
     * APB0 reset bit 0 = R_PIO, bit 3 = RSB
     * ============================================ */
    ldr   r0, =PRCM_APB0_GATE
    ldr   r1, [r0]
    orr   r1, r1, #(1 << 0) | (1 << 3)   /* PIO + RSB */
    str   r1, [r0]

    ldr   r0, =PRCM_APB0_RST
    ldr   r1, [r0]
    orr   r1, r1, #(1 << 0) | (1 << 3)
    str   r1, [r0]

    bl    delay_10k

    /* ============================================
     * STEP 2: Configure PL0=RSB_SCK, PL1=RSB_SDA
     * PL_CFG0: PL0 bits [3:0] = func 2 (S_RSB_SCK)
     *          PL1 bits [7:4] = func 2 (S_RSB_SDA)
     * ============================================ */
    ldr   r0, =PL_CFG0
    ldr   r1, [r0]
    bic   r1, r1, #0xFF         /* clear PL0, PL1 */
    orr   r1, r1, #0x22         /* PL0=func2, PL1=func2 */
    str   r1, [r0]

    /* Pull-ups on PL0/PL1 */
    ldr   r0, =PL_PUL0
    ldr   r1, [r0]
    orr   r1, r1, #0x05         /* pull-up PL0, PL1 */
    str   r1, [r0]

    /* Drive strength level 2 */
    ldr   r0, =PL_DRV0
    ldr   r1, [r0]
    orr   r1, r1, #0x0A         /* DRV=2 for PL0, PL1 */
    str   r1, [r0]

    /* ============================================
     * STEP 3: Soft-reset RSB controller
     * ============================================ */
    mov   r1, #1                /* RSB_CTRL_SOFT_RST */
    str   r1, [r11, #RSB_CTRL]
    bl    delay_10k

    /* ============================================
     * STEP 4: Set RSB clock to 3MHz
     * Source = 24MHz OSC, div = 24/3/2-1 = 3
     * cd_odly = div>>1 = 1
     * CCR = (cd_odly << 8) | div = (1<<8)|3 = 0x103
     * ============================================ */
    ldr   r1, =0x103
    str   r1, [r11, #RSB_CCR]

    /* STEP 5: SKIP DMCR — BROM should have already put PMIC in RSB mode.
     * If DMCR is sent again, it can disrupt PMIC power state and kill USB.
     * Proceed directly to STRA. */

    /* ============================================
     * STEP 6: Set runtime address (STRA command)
     * DEVADDR = (RTA << 16) | HWADDR
     * CMD = 0xE8 (SET_RTSADDR)
     * ============================================ */
    ldr   r1, =(PMIC_RTA << 16) | PMIC_HWADDR
    str   r1, [r11, #RSB_DEVADDR]
    mov   r1, #0xE8             /* RSB_CMD_SET_RTSADDR */
    str   r1, [r11, #RSB_CMD]
    bl    rsb_do_trans

    /* ============================================
     * STEP 7: Enable PMIC regulators
     * ============================================ */

    /* Read PWR_OUT_CTRL2 (reg 0x12) */
    mov   r0, #0x12
    bl    rsb_read
    /* r0 = current value */

    /* Enable DC1SW(bit7) + DLDO1(bit3) + DLDO2(bit4) */
    orr   r0, r0, #(1<<7) | (1<<3) | (1<<4)
    mov   r1, #0x12
    bl    rsb_write              /* r1=reg, r0=data */

    /* DLDO1 = 3.3V: (3300-700)/100 = 26 = 0x1A */
    mov   r0, #0x1A
    mov   r1, #0x15
    bl    rsb_write

    /* DLDO2 = 1.8V: (1800-700)/100 = 11 = 0x0B */
    mov   r0, #0x0B
    mov   r1, #0x16
    bl    rsb_write

    /* LDO_IO0 enable: GPIO0_CTRL = 0x03 (LDO mode) */
    mov   r0, #0x03
    mov   r1, #0x90
    bl    rsb_write

    /* LDO_IO0 = 3.3V: 0x1A */
    mov   r0, #0x1A
    mov   r1, #0x91
    bl    rsb_write

    /* Delay for regulators to stabilize */
    bl    delay_50k

    /* ============================================
     * STEP 8: Backlight enable — PH10 = output HIGH
     * ============================================ */
    ldr   r0, =PH_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)
    orr   r1, r1, #(0x1 << 8)
    str   r1, [r0]

    ldr   r0, =PH_DAT
    ldr   r1, [r0]
    orr   r1, r1, #(1 << 10)
    str   r1, [r0]

    /* ============================================
     * STEP 9: R_PWM for brightness
     * ============================================ */
    /* Enable R_PWM clock (APB0 gate bit 0... actually separate) */
    ldr   r0, =PRCM_APB0_GATE
    ldr   r1, [r0]
    orr   r1, r1, #1
    str   r1, [r0]

    /* PL10 = PWM function (func 2) */
    ldr   r0, =PL_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)
    orr   r1, r1, #(0x2 << 8)
    str   r1, [r0]

    /* PWM period + duty */
    ldr   r0, =R_PWM_BASE + 0x04   /* period register */
    mov   r1, #255
    lsl   r1, r1, #16
    orr   r1, r1, r10               /* brightness in lower 16 */
    str   r1, [r0]

    /* PWM control: enable + prescaler /120 + inverted */
    ldr   r0, =R_PWM_BASE
    mov   r1, #(1 << 4)
    orr   r1, r1, #(4 << 6)
    orr   r1, r1, #(1 << 9)
    orr   r1, r1, #(1 << 0)
    str   r1, [r0]

    /* Store success status */
    ldr   r0, stat_addr
    mov   r1, #0
    str   r1, [r0]

    pop   {r4-r11, lr}
    bx    lr

/* ==========================================
 * RSB helper routines
 * ========================================== */

/* Start transaction and wait */
rsb_do_trans:
    mov   r1, #(1 << 7)         /* RSB_CTRL_START_TRANS */
    ldr   r2, [r11, #RSB_CTRL]
    orr   r2, r2, r1
    str   r2, [r11, #RSB_CTRL]
    /* fall through to await */

rsb_await_trans:
    ldr   r3, =100000
3:  ldr   r1, [r11, #RSB_STAT]
    tst   r1, #1                /* TOVER_INT (transfer over) */
    bne   4f
    subs  r3, r3, #1
    bne   3b
4:  str   r1, [r11, #RSB_STAT]  /* clear status */
    bx    lr

/* RSB read: r0=reg -> r0=data */
rsb_read:
    str   r0, [r11, #RSB_ADDR]
    ldr   r1, =(PMIC_RTA << 16)
    str   r1, [r11, #RSB_DEVADDR]
    mov   r1, #0x8B              /* RSB_CMD_BYTE_READ */
    str   r1, [r11, #RSB_CMD]
    bl    rsb_do_trans
    ldr   r0, [r11, #RSB_DATA]
    and   r0, r0, #0xFF
    bx    lr

/* RSB write: r1=reg, r0=data */
rsb_write:
    str   r1, [r11, #RSB_ADDR]
    ldr   r2, =(PMIC_RTA << 16)
    str   r2, [r11, #RSB_DEVADDR]
    str   r0, [r11, #RSB_DATA]
    mov   r2, #0x4E              /* RSB_CMD_BYTE_WRITE */
    str   r2, [r11, #RSB_CMD]
    b     rsb_do_trans           /* tail call */

/* Delays */
delay_10k:
    ldr   r3, =10000
5:  subs  r3, r3, #1
    bne   5b
    bx    lr

delay_50k:
    ldr   r3, =50000
6:  subs  r3, r3, #1
    bne   6b
    bx    lr

    /* Literal pool */
    .align 2
brightness: .word 200
stat_addr:  .word 0x00011F00

/*
 * lcd_power_on.S — Enable LCD power regulators + backlight on PocketPC
 *
 * 1. RSB write to AXP803 PMIC: enable DC1SW, DLDO1, DLDO2, LDO_IO0
 * 2. GPIO PH10 = output HIGH (backlight enable)
 * 3. R_PWM channel 0 configured for brightness
 *
 * BROM already initialized RSB bus and assigned PMIC runtime address 0x2D.
 *
 * Assemble: arm-none-eabi-as -march=armv8-a -o lcd_power_on.o lcd_power_on.S
 * Extract:  arm-none-eabi-objcopy -O binary lcd_power_on.o lcd_power_on.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

/* RSB registers */
.equ RSB_BASE,   0x01F03400
.equ RSB_CTRL,   0x00
.equ RSB_INTS,   0x0C
.equ RSB_ADDR,   0x10
.equ RSB_DATA,   0x1C
.equ RSB_CMD,    0x2C
.equ RSB_DAR,    0x30

/* RSB commands */
.equ RSB_CMD_WR8,  0x4E
.equ RSB_CMD_RD8,  0x8B

/* AXP803 runtime address (assigned by BROM) */
.equ PMIC_RTA,    0x2D

/* AXP803 registers */
.equ AXP_PWR_OUT_CTRL2,  0x12   /* DC1SW(bit7), DLDO1(bit3), DLDO2(bit4) */
.equ AXP_DLDO1_VOUT,     0x15   /* DLDO1 voltage: (val-7)*100+700 mV */
.equ AXP_DLDO2_VOUT,     0x16   /* DLDO2 voltage */
.equ AXP_GPIO0_CTRL,     0x90   /* LDO_IO0 mode: 0x03=LDO enabled */
.equ AXP_LDO_IO0_VOUT,   0x91   /* LDO_IO0 voltage */

/* GPIO */
.equ PIO_BASE,    0x01C20800
.equ PH_CFG1,     PIO_BASE + 0x100
.equ PH_DAT,      PIO_BASE + 0x10C

/* R_PWM */
.equ R_PIO_BASE,  0x01F02C00
.equ PL_CFG1,     R_PIO_BASE + 0x04
.equ R_PWM_BASE,  0x01F03800
.equ R_PWM_CTRL,  R_PWM_BASE + 0x00
.equ R_PWM_PERIOD, R_PWM_BASE + 0x04

/* R_CCU */
.equ R_APB0_GATE, 0x01F01428

_start:
    push  {r4-r11, lr}

    /* ========================================
     * STEP 1: Enable PMIC regulators via RSB
     * ======================================== */

    /* First read current PWR_OUT_CTRL2 value */
    ldr   r0, =RSB_BASE
    mov   r1, #AXP_PWR_OUT_CTRL2
    bl    rsb_read8
    /* r0 = current value of reg 0x12 */

    /* Enable DC1SW(bit7) + DLDO1(bit3) + DLDO2(bit4) */
    orr   r4, r0, #(1<<7) | (1<<3) | (1<<4)

    ldr   r0, =RSB_BASE
    mov   r1, #AXP_PWR_OUT_CTRL2
    mov   r2, r4
    bl    rsb_write8

    /* Set DLDO1 voltage = 3.3V: (3300-700)/100 = 26 = 0x1A */
    ldr   r0, =RSB_BASE
    mov   r1, #AXP_DLDO1_VOUT
    mov   r2, #0x1A
    bl    rsb_write8

    /* Set DLDO2 voltage = 1.8V: (1800-700)/100 = 11 = 0x0B */
    ldr   r0, =RSB_BASE
    mov   r1, #AXP_DLDO2_VOUT
    mov   r2, #0x0B
    bl    rsb_write8

    /* Enable LDO_IO0 as LDO (GPIO0_CTRL = 0x03) */
    ldr   r0, =RSB_BASE
    mov   r1, #AXP_GPIO0_CTRL
    mov   r2, #0x03
    bl    rsb_write8

    /* Set LDO_IO0 voltage = 3.3V: (3300-700)/100 = 26 = 0x1A */
    ldr   r0, =RSB_BASE
    mov   r1, #AXP_LDO_IO0_VOUT
    mov   r2, #0x1A
    bl    rsb_write8

    /* Small delay for regulators to stabilize */
    ldr   r2, =500000
1:  subs  r2, r2, #1
    bne   1b

    /* ========================================
     * STEP 2: PH10 = output HIGH (backlight enable)
     * ======================================== */
    ldr   r0, =PH_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)
    orr   r1, r1, #(0x1 << 8)    /* PH10 = output */
    str   r1, [r0]

    ldr   r0, =PH_DAT
    ldr   r1, [r0]
    orr   r1, r1, #(1 << 10)     /* PH10 = HIGH */
    str   r1, [r0]

    /* ========================================
     * STEP 3: R_PWM for backlight brightness
     * ======================================== */

    /* Enable R_PWM clock */
    ldr   r0, =R_APB0_GATE
    ldr   r1, [r0]
    orr   r1, r1, #1
    str   r1, [r0]

    /* Configure PL10 as PWM function */
    ldr   r0, =PL_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)
    orr   r1, r1, #(0x2 << 8)    /* PL10 = PWM (func 2) */
    str   r1, [r0]

    /* PWM period: total=255, active=brightness */
    ldr   r5, brightness
    mov   r1, #255
    lsl   r1, r1, #16
    orr   r1, r1, r5
    ldr   r0, =R_PWM_PERIOD
    str   r1, [r0]

    /* PWM control: enable, prescaler /120, inverted polarity */
    ldr   r0, =R_PWM_CTRL
    mov   r1, #(1 << 4)          /* enable */
    orr   r1, r1, #(4 << 6)      /* prescaler /120 */
    orr   r1, r1, #(1 << 9)      /* inverted */
    orr   r1, r1, #(1 << 0)      /* update */
    str   r1, [r0]

    /* Store status: 0 = success */
    ldr   r0, stat_addr
    mov   r1, #0
    str   r1, [r0]

    pop   {r4-r11, lr}
    bx    lr

/* ==========================================
 * RSB read 8-bit register
 * r0 = RSB base, r1 = register address
 * Returns: r0 = data
 * ========================================== */
rsb_read8:
    str   r1, [r0, #RSB_ADDR]                   /* register address */
    mov   r3, #(PMIC_RTA << 16)
    str   r3, [r0, #RSB_DAR]                     /* runtime address */
    mov   r3, #RSB_CMD_RD8
    str   r3, [r0, #RSB_CMD]                     /* read command */
    mov   r3, #0x82                               /* START_TRANS | GLOBAL_INT_ENB */
    str   r3, [r0, #RSB_CTRL]
    /* Poll for completion */
    ldr   r3, =100000
2:  ldr   r1, [r0, #RSB_CTRL]
    tst   r1, #(1<<7)                             /* START_TRANS still set? */
    beq   3f
    subs  r3, r3, #1
    bne   2b
3:  /* Clear interrupt flags */
    ldr   r1, [r0, #RSB_INTS]
    str   r1, [r0, #RSB_INTS]
    /* Read data */
    ldr   r0, [r0, #RSB_DATA]
    and   r0, r0, #0xFF
    bx    lr

/* ==========================================
 * RSB write 8-bit register
 * r0 = RSB base, r1 = register address, r2 = data
 * ========================================== */
rsb_write8:
    str   r1, [r0, #RSB_ADDR]                   /* register address */
    mov   r3, #(PMIC_RTA << 16)
    str   r3, [r0, #RSB_DAR]                     /* runtime address */
    str   r2, [r0, #RSB_DATA]                    /* data to write */
    mov   r3, #RSB_CMD_WR8
    str   r3, [r0, #RSB_CMD]                     /* write command */
    mov   r3, #0x82
    str   r3, [r0, #RSB_CTRL]                    /* start transfer */
    /* Poll for completion */
    ldr   r3, =100000
4:  ldr   r1, [r0, #RSB_CTRL]
    tst   r1, #(1<<7)
    beq   5f
    subs  r3, r3, #1
    bne   4b
5:  ldr   r1, [r0, #RSB_INTS]
    str   r1, [r0, #RSB_INTS]
    bx    lr

    /* Literal pool */
    .align 2
brightness: .word 200              /* 0-255, patched by host */
stat_addr:  .word 0x00011F00       /* status output */

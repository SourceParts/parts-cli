/*
 * backlight_on.S — Turn on PocketPC LCD backlight via GPIO + PWM
 *
 * 1. Set PH10 as output, drive HIGH (backlight enable)
 * 2. Configure R_PWM channel 0 for ~50% duty cycle
 * 3. Enable R_PWM pin (PL10) as PWM function
 *
 * Literal pool patched at runtime:
 *   +0x60: brightness (0-255, default 128 = 50%)
 *
 * Assemble: arm-none-eabi-as -march=armv8-a -o backlight_on.o backlight_on.S
 * Extract:  arm-none-eabi-objcopy -O binary backlight_on.o backlight_on.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

/* A64 Register Addresses */
.equ PIO_BASE,    0x01C20800
.equ PH_CFG1,     PIO_BASE + 0x100   /* PH8-PH15 config (Port H, cfg reg 1) */
.equ PH_DAT,      PIO_BASE + 0x10C   /* PH data register */
.equ R_PIO_BASE,  0x01F02C00
.equ PL_CFG1,     R_PIO_BASE + 0x04  /* PL8-PL15 config */
.equ R_PWM_BASE,  0x01F03800
.equ R_PWM_CTRL,  R_PWM_BASE + 0x00  /* PWM control register */
.equ R_PWM_PERIOD, R_PWM_BASE + 0x04 /* PWM period register */

/* R_CCU for R_PWM clock gate */
.equ R_CCU_BASE,  0x01F01400
.equ R_APB0_GATE, R_CCU_BASE + 0x28  /* APB0 gating: bit 0 = R_PWM */

_start:
    ldr   r10, brightness

    /* ============================================
     * Step 1: Enable PH10 as output, drive HIGH
     * PH_CFG1 controls PH8-PH15
     * PH10 is bits [11:8] in PH_CFG1
     * Function 1 = output
     * ============================================ */
    ldr   r0, =PH_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)    /* clear PH10 func bits [11:8] */
    orr   r1, r1, #(0x1 << 8)    /* set PH10 = output (func 1) */
    str   r1, [r0]

    /* Set PH10 high (bit 10 in PH_DAT) */
    ldr   r0, =PH_DAT
    ldr   r1, [r0]
    orr   r1, r1, #(1 << 10)
    str   r1, [r0]

    /* ============================================
     * Step 2: Enable R_PWM clock gate
     * R_APB0_GATE bit 0 = R_PWM
     * ============================================ */
    ldr   r0, =R_APB0_GATE
    ldr   r1, [r0]
    orr   r1, r1, #1              /* enable R_PWM clock */
    str   r1, [r0]

    /* Small delay for clock to stabilize */
    mov   r2, #10000
1:  subs  r2, r2, #1
    bne   1b

    /* ============================================
     * Step 3: Configure PL10 as R_PWM function
     * PL_CFG1 controls PL8-PL15
     * PL10 is bits [11:8] in PL_CFG1
     * Function 2 = R_PWM (varies by SoC, check datasheet)
     * ============================================ */
    ldr   r0, =PL_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)    /* clear PL10 func bits */
    orr   r1, r1, #(0x2 << 8)    /* set PL10 = PWM function (func 2) */
    str   r1, [r0]

    /* ============================================
     * Step 4: Configure R_PWM
     * PWM_PERIOD: [31:16] = total period cycles
     *             [15:0]  = active (high) cycles
     * With 24MHz clock and prescaler /120:
     *   200KHz base, period=200 → 1KHz PWM output
     * Duty = active_cycles / total_cycles
     * ============================================ */

    /* Period register: total=255, active=brightness */
    mov   r1, #255
    lsl   r1, r1, #16            /* total period in upper 16 bits */
    orr   r1, r1, r10            /* active cycles in lower 16 bits */
    ldr   r0, =R_PWM_PERIOD
    str   r1, [r0]

    /* Control register:
     * bit 0 = channel 0 ready (write 1)
     * bit 4 = channel 0 enable
     * bit 5 = channel 0 clock source (0=24MHz)
     * bits [6:8] = prescaler (4 = /120)
     * bit 9 = active state (0=high, 1=low) — inverted polarity per DTS
     */
    ldr   r0, =R_PWM_CTRL
    mov   r1, #(1 << 4)          /* enable channel 0 */
    orr   r1, r1, #(4 << 6)      /* prescaler /120 */
    orr   r1, r1, #(1 << 9)      /* inverted polarity (per DTS PWM_POLARITY_INVERTED) */
    orr   r1, r1, #(1 << 0)      /* ready/update */
    str   r1, [r0]

    /* ============================================
     * Done — return to FEL
     * ============================================ */
    bx    lr

    /* Literal pool */
    .align 2
brightness: .word 128             /* 0-255, patched by host */

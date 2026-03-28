/*
 * backlight_only.S — GPIO + PWM only (NO RSB/PMIC)
 *
 * Just sets PH10 high and configures R_PWM.
 * If the backlight doesn't turn on, the power rail is the blocker.
 */
    .syntax unified
    .arm
    .text
    .global _start

.equ PIO_BASE,    0x01C20800
.equ PH_CFG1,     PIO_BASE + 0x100
.equ PH_DAT,      PIO_BASE + 0x10C
.equ R_PIO_BASE,  0x01F02C00
.equ PL_CFG1,     R_PIO_BASE + 0x04
.equ PRCM_APB0_GATE, 0x01F01428
.equ R_PWM_BASE,  0x01F03800

_start:
    push  {r4-r11, lr}
    ldr   r10, brightness

    /* PH10 = output HIGH (backlight enable) */
    ldr   r0, =PH_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)
    orr   r1, r1, #(0x1 << 8)
    str   r1, [r0]

    ldr   r0, =PH_DAT
    ldr   r1, [r0]
    orr   r1, r1, #(1 << 10)
    str   r1, [r0]

    /* R_PWM clock gate */
    ldr   r0, =PRCM_APB0_GATE
    ldr   r1, [r0]
    orr   r1, r1, #1
    str   r1, [r0]

    /* Small delay */
    ldr   r2, =10000
1:  subs  r2, r2, #1
    bne   1b

    /* PL10 = PWM func */
    ldr   r0, =PL_CFG1
    ldr   r1, [r0]
    bic   r1, r1, #(0xF << 8)
    orr   r1, r1, #(0x2 << 8)
    str   r1, [r0]

    /* PWM period */
    ldr   r0, =R_PWM_BASE + 0x04
    mov   r1, #255
    lsl   r1, r1, #16
    orr   r1, r1, r10
    str   r1, [r0]

    /* PWM control: enable + prescaler + inverted */
    ldr   r0, =R_PWM_BASE
    mov   r1, #(1 << 4)
    orr   r1, r1, #(4 << 6)
    orr   r1, r1, #(1 << 9)
    orr   r1, r1, #(1 << 0)
    str   r1, [r0]

    /* Status = success */
    ldr   r0, =0x00011F00
    mov   r1, #0
    str   r1, [r0]

    pop   {r4-r11, lr}
    bx    lr

    .align 2
brightness: .word 255

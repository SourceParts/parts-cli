/*
 * test_write.S — Minimal test thunk: writes a magic value to status area and returns.
 * No hardware access, just SRAM write + return to verify FEL execute works.
 *
 * Assemble: arm-none-eabi-as -march=armv8-a -o test_write.o test_write.S
 * Extract:  arm-none-eabi-objcopy -O binary test_write.o test_write.bin
 */
    .syntax unified
    .arm
    .text
    .global _start

_start:
    ldr   r0, stat_addr
    ldr   r1, =0xDEADBEEF
    str   r1, [r0]           /* status[0] = 0xDEADBEEF (magic) */
    mov   r1, #42
    str   r1, [r0, #4]       /* status[4] = 42 */
    bx    lr                  /* return to FEL */

    .align 2
stat_addr: .word 0x00011F00

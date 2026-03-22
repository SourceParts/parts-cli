/*
 * uart_tx.S — UART TX thunk for Allwinner A64 (AArch32, FEL mode)
 *
 * Sends bytes from a buffer to UART THR, waiting for LSR THR-empty bit.
 * Returns to FEL via bx lr when all bytes are sent.
 *
 * Literal pool (patched at runtime by host):
 *   +0x38: UART base address
 *   +0x3C: byte count to send
 *   +0x40: data buffer address (absolute SRAM address)
 *
 * Data buffer immediately follows the literal pool at +0x44.
 *
 * Assemble: arm-none-eabi-as -march=armv8-a -o uart_tx.o uart_tx.S
 * Extract:  arm-none-eabi-objcopy -O binary uart_tx.o uart_tx.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

_start:
    /* Load parameters from literal pool */
    ldr   r0, uart_base         /* UART base address */
    ldr   r1, byte_count        /* number of bytes to send */
    ldr   r2, data_addr         /* source data buffer (absolute) */
    mov   r3, #0                /* r3 = index */

tx_loop:
    cmp   r3, r1                /* all bytes sent? */
    bge   tx_done

tx_wait:
    ldr   r4, [r0, #0x14]      /* read LSR */
    tst   r4, #0x20             /* bit 5: THR empty? */
    beq   tx_wait

    ldrb  r4, [r2, r3]         /* load byte from buffer */
    str   r4, [r0, #0x00]      /* write to THR */
    add   r3, r3, #1           /* index++ */
    b     tx_loop

tx_done:
    bx    lr                    /* return to FEL/BROM */

    /* Literal pool — patched by host before execution */
    .align 2
uart_base:  .word 0x01C28C00   /* placeholder: UART3 */
byte_count: .word 0            /* placeholder */
data_addr:  .word 0x00011044   /* placeholder: scratchAddr + 0x44 */

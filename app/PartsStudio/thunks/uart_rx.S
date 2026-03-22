/*
 * uart_rx.S — UART RX polling thunk for Allwinner A64 (AArch32, FEL mode)
 *
 * Polls UART LSR for data-ready, reads bytes from RBR into a buffer.
 * Returns to FEL via bx lr when buffer is full or idle timeout expires.
 *
 * Literal pool (patched at runtime by host):
 *   +0x54: UART base address (e.g. 0x01C28800 for UART2)
 *   +0x58: max bytes to receive
 *   +0x5C: idle timeout loop count
 *   +0x60: buffer address (absolute SRAM address)
 *   +0x64: count address (absolute SRAM address, stores result)
 *
 * Result:
 *   [countAddr] = number of bytes received
 *   [bufferAddr ... bufferAddr+count-1] = received data
 *
 * Assemble: arm-none-eabi-as -march=armv8-a -o uart_rx.o uart_rx.S
 * Extract:  arm-none-eabi-objcopy -O binary uart_rx.o uart_rx.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

_start:
    /* Load parameters from literal pool */
    ldr   r0, uart_base         /* UART base address */
    ldr   r1, max_bytes         /* max bytes to buffer */
    ldr   r2, timeout           /* idle timeout loops */
    ldr   r3, buf_addr          /* output buffer (absolute) */
    ldr   r6, cnt_addr          /* count result (absolute) */
    mov   r4, #0                /* r4 = bytes received */
    mov   r5, r2                /* r5 = idle countdown */

rx_loop:
    ldr   r7, [r0, #0x14]      /* read LSR */
    tst   r7, #0x01             /* bit 0: data ready? */
    beq   rx_no_data

    /* Data ready — read RBR */
    ldr   r7, [r0, #0x00]      /* read RBR */
    strb  r7, [r3, r4]         /* store byte */
    add   r4, r4, #1           /* count++ */
    mov   r5, r2                /* reset idle timeout */
    cmp   r4, r1                /* buffer full? */
    blt   rx_loop
    b     rx_done               /* buffer full, exit */

rx_no_data:
    subs  r5, r5, #1           /* idle timeout-- */
    bne   rx_loop               /* keep polling */

rx_done:
    str   r4, [r6]             /* store byte count */
    bx    lr                    /* return to FEL/BROM */

    /* Literal pool — patched by host before execution */
    .align 2
uart_base:  .word 0x01C28800   /* placeholder: UART2 */
max_bytes:  .word 512          /* placeholder */
timeout:    .word 2000000      /* placeholder */
buf_addr:   .word 0x00011080   /* placeholder: scratchAddr + 0x80 */
cnt_addr:   .word 0x0001107C   /* placeholder: scratchAddr + 0x7C */

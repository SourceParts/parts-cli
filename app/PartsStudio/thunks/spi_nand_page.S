/*
 * spi_nand_page.S — SPI NAND page read thunk for W25N01GV on F1C200s
 *
 * Performs a complete NAND page read in one execution:
 *   1. Init SPI0 (clocks, GPIO, controller)
 *   2. Page Data Read (0x13) — loads NAND page to chip's internal cache
 *   3. Poll status register (0x0F + 0xC0) until BUSY=0
 *   4. Read from Cache (0x03) with RX FIFO drain — reads up to 2048 bytes
 *
 * The RX FIFO is only 64 bytes, so step 4 drains it during transfer
 * by polling SPI_FSR and reading bytes as they arrive.
 *
 * Parameters (patched in literal pool by host):
 *   param_page_addr:  16-bit NAND page number
 *   param_read_len:   Bytes to read from page (max 2048)
 *   param_rx_buf:     SRAM address for result data
 *
 * Memory layout (F1C200s, scratch=0x1000):
 *   Code:    0x1000 (~500 bytes)
 *   RX buf:  0x1800 (2048 bytes, ends at 0x2000)
 *
 * Assemble: arm-none-eabi-as -march=armv5te -o spi_nand_page.o spi_nand_page.S
 * Extract:  arm-none-eabi-objcopy -O binary spi_nand_page.o spi_nand_page.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

_start:
    /* === SPI0 Clock & Reset Init === */
    ldr   r0, const_ccu_base
    ldr   r1, [r0, #0x60]           /* BUS_CLK_GATING_REG0 */
    orr   r1, r1, #(1 << 20)        /* SPI0 gate */
    str   r1, [r0, #0x60]
    ldr   r1, [r0, #0x2C0]          /* BUS_SOFT_RST_REG0 */
    orr   r1, r1, #(1 << 20)        /* SPI0 reset deassert */
    str   r1, [r0, #0x2C0]
    ldr   r1, const_clk_en
    str   r1, [r0, #0xA0]           /* SPI0_CLK_REG: OSC24M, gate=1 */

    /* GPIO: PC0-PC3 = SPI0 (mux 2) */
    ldr   r0, const_pio_pc_cfg0
    ldr   r1, const_gpio_val
    str   r1, [r0]

    /* SPI0 controller */
    ldr   r0, const_spi0_base       /* r0 = SPI0 base for rest of thunk */
    mov   r1, #0x83
    str   r1, [r0, #0x04]           /* SPI_GCR: master + enable */
    ldr   r1, const_cdr_val
    str   r1, [r0, #0x24]           /* SPI_CCR: 4MHz */
    mov   r1, #0xC0
    str   r1, [r0, #0x08]           /* SPI_TCR: SS_OWNER=SW, SS_LEVEL=high */

    /* Load parameters */
    ldr   r4, param_page_addr        /* r4 = page address (16-bit) */
    ldr   r5, param_rx_buf           /* r5 = result buffer */
    ldr   r8, param_read_len         /* r8 = bytes to read */

    /* ============================================================ */
    /* Step 1: Page Data Read (0x13 + dummy + page_hi + page_lo)    */
    /*         Loads one page from NAND array to chip's cache.      */
    /* ============================================================ */

    ldr   r1, const_fifo_rst
    str   r1, [r0, #0x18]           /* Reset FIFOs */

    mov   r1, #4
    str   r1, [r0, #0x30]           /* SPI_MBC = 4 */
    str   r1, [r0, #0x34]           /* SPI_MTC = 4 */
    str   r1, [r0, #0x38]           /* SPI_BCC = 4 */

    /* Assert CS */
    ldr   r1, [r0, #0x08]
    bic   r1, r1, #0x80
    str   r1, [r0, #0x08]

    /* TX: [0x13, 0x00, page_hi, page_lo] */
    mov   r1, #0x13
    strb  r1, [r0, #0x200]
    mov   r1, #0
    strb  r1, [r0, #0x200]          /* dummy */
    mov   r1, r4, lsr #8
    strb  r1, [r0, #0x200]          /* page[15:8] */
    strb  r4, [r0, #0x200]          /* page[7:0] */

    /* Start transfer */
    ldr   r1, [r0, #0x08]
    orr   r1, r1, #(1 << 31)
    str   r1, [r0, #0x08]

    /* Wait TC */
1:  ldr   r1, [r0, #0x14]
    tst   r1, #(1 << 12)
    beq   1b
    mov   r1, #(1 << 12)
    str   r1, [r0, #0x14]           /* Clear TC */

    /* Deassert CS */
    ldr   r1, [r0, #0x08]
    orr   r1, r1, #0x80
    str   r1, [r0, #0x08]

    /* ============================================================ */
    /* Step 2: Poll Status Register (0x0F+0xC0) until BUSY=0        */
    /*         The page load takes ~25-60us.                        */
    /* ============================================================ */

poll_status:
    ldr   r1, const_fifo_rst
    str   r1, [r0, #0x18]           /* Reset FIFOs */

    mov   r1, #3
    str   r1, [r0, #0x30]           /* SPI_MBC = 3 (2 TX + 1 RX) */
    mov   r1, #2
    str   r1, [r0, #0x34]           /* SPI_MTC = 2 */
    str   r1, [r0, #0x38]           /* SPI_BCC = 2 */

    /* Assert CS */
    ldr   r1, [r0, #0x08]
    bic   r1, r1, #0x80
    str   r1, [r0, #0x08]

    /* TX: [0x0F, 0xC0] (Read Status Reg 3) */
    mov   r1, #0x0F
    strb  r1, [r0, #0x200]
    mov   r1, #0xC0
    strb  r1, [r0, #0x200]

    /* Start transfer */
    ldr   r1, [r0, #0x08]
    orr   r1, r1, #(1 << 31)
    str   r1, [r0, #0x08]

    /* Wait TC */
2:  ldr   r1, [r0, #0x14]
    tst   r1, #(1 << 12)
    beq   2b
    mov   r1, #(1 << 12)
    str   r1, [r0, #0x14]

    /* Discard 2 echo bytes, read 1 status byte */
    ldrb  r1, [r0, #0x300]          /* discard echo 1 */
    ldrb  r1, [r0, #0x300]          /* discard echo 2 */
    ldrb  r7, [r0, #0x300]          /* r7 = status byte */

    /* Deassert CS */
    ldr   r1, [r0, #0x08]
    orr   r1, r1, #0x80
    str   r1, [r0, #0x08]

    /* Check BUSY bit (bit 0 of SR-3) */
    tst   r7, #1
    bne   poll_status

    /* ============================================================ */
    /* Step 3: Read from Cache (0x03 + col_hi + col_lo + dummy)     */
    /*         Drain RX FIFO during transfer for large reads.       */
    /* ============================================================ */

    ldr   r1, const_fifo_rst
    str   r1, [r0, #0x18]           /* Reset FIFOs */

    /* MBC = 4 + read_len, MTC = 4, BCC = 4 */
    add   r1, r8, #4
    str   r1, [r0, #0x30]           /* SPI_MBC */
    mov   r1, #4
    str   r1, [r0, #0x34]           /* SPI_MTC */
    str   r1, [r0, #0x38]           /* SPI_BCC */

    /* Assert CS */
    ldr   r1, [r0, #0x08]
    bic   r1, r1, #0x80
    str   r1, [r0, #0x08]

    /* TX: [0x03, col_hi=0, col_lo=0, dummy=0] */
    mov   r1, #0x03
    strb  r1, [r0, #0x200]
    mov   r1, #0
    strb  r1, [r0, #0x200]
    strb  r1, [r0, #0x200]
    strb  r1, [r0, #0x200]

    /* Start transfer */
    ldr   r1, [r0, #0x08]
    orr   r1, r1, #(1 << 31)
    str   r1, [r0, #0x08]

    /* Drain RX FIFO: skip 4 echo bytes, store read_len data bytes */
    add   r3, r8, #4                /* r3 = total bytes (echo + data) */
    mov   r6, #0                    /* r6 = bytes drained */

drain_loop:
    ldr   r1, [r0, #0x1C]           /* SPI_FSR */
    and   r1, r1, #0xFF             /* RX FIFO count (bits 7:0) */
    cmp   r1, #0
    beq   drain_loop                /* spin until data available */

    ldrb  r2, [r0, #0x300]          /* pop 1 byte */
    cmp   r6, #4
    blt   drain_skip                /* skip echo bytes */
    sub   r1, r6, #4
    strb  r2, [r5, r1]              /* store data at rx_buf[i-4] */
drain_skip:
    add   r6, r6, #1
    cmp   r6, r3
    blt   drain_loop

    /* Deassert CS */
    ldr   r1, [r0, #0x08]
    orr   r1, r1, #0x80
    str   r1, [r0, #0x08]

    bx    lr

    /* === Literal Pool === */
    .align 2
const_ccu_base:    .word 0x01C20000
const_spi0_base:   .word 0x01C05000
const_pio_pc_cfg0: .word 0x01C20848
const_gpio_val:    .word 0x00002222
const_clk_en:      .word 0x80000000
const_cdr_val:     .word 0x00001002
const_fifo_rst:    .word 0x80008000

/* Patchable parameters */
param_page_addr:   .word 0x00000000
param_read_len:    .word 0x00000800    /* 2048 */
param_rx_buf:      .word 0x00001800

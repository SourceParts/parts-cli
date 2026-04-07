/*
 * spi_flash.S — SPI NOR flash access thunk for Allwinner F1C200s (ARM926EJ-S)
 *
 * Initializes SPI0 controller and performs one SPI transaction.
 * Host pre-loads TX command bytes at tx_buf, results written to rx_buf.
 *
 * Parameters (patched in literal pool by host before upload):
 *   param_tx_len:  Number of TX bytes (command + address)
 *   param_rx_len:  Number of RX data bytes to return
 *   param_tx_buf:  SRAM address of pre-loaded TX data
 *   param_rx_buf:  SRAM address for RX result data
 *
 * F1C200s SPI0 wiring:
 *   PC0 = SPI0_CLK, PC1 = SPI0_CS, PC2 = SPI0_MISO, PC3 = SPI0_MOSI
 *   All mux function 2.
 *
 * Assemble: arm-none-eabi-as -march=armv5te -o spi_flash.o spi_flash.S
 * Extract:  arm-none-eabi-objcopy -O binary spi_flash.o spi_flash.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

_start:
    /* === SPI0 Clock & Reset Init === */
    ldr   r0, const_ccu_base         /* r0 = CCU base (0x01C20000) */

    /* Enable SPI0 bus clock gate (bit 20) */
    ldr   r1, [r0, #0x60]           /* BUS_CLK_GATING_REG0 */
    orr   r1, r1, #(1 << 20)
    str   r1, [r0, #0x60]

    /* De-assert SPI0 reset (bit 20) */
    ldr   r1, [r0, #0x2C0]          /* BUS_SOFT_RST_REG0 */
    orr   r1, r1, #(1 << 20)
    str   r1, [r0, #0x2C0]

    /* Enable SPI0 module clock: source=OSC24M, gate=1 */
    ldr   r1, const_clk_en          /* 0x80000000 */
    str   r1, [r0, #0xA0]           /* SPI0_CLK_REG */

    /* === GPIO: PC0-PC3 = SPI0 (mux function 2) === */
    ldr   r0, const_pio_pc_cfg0     /* 0x01C20848 */
    ldr   r1, const_gpio_val        /* 0x00002222 */
    str   r1, [r0]

    /* === SPI0 Controller Init === */
    ldr   r0, const_spi0_base       /* r0 = SPI0 base, kept for rest of thunk */

    /* SPI_GCR: master mode + enable */
    mov   r1, #0x83
    str   r1, [r0, #0x04]

    /* SPI_CCR: CDR2 mode, CDR2=2 -> 24MHz/(2*(2+1)) = 4 MHz */
    ldr   r1, const_cdr_val         /* 0x00001002 */
    str   r1, [r0, #0x24]

    /* SPI_TCR: SS owner=software, SS level=high (deasserted) */
    mov   r1, #0xC0
    str   r1, [r0, #0x08]

    /* === SPI Transaction === */

    /* Load parameters */
    ldr   r2, param_tx_len          /* r2 = TX byte count */
    ldr   r3, param_rx_len          /* r3 = RX byte count */
    ldr   r4, param_tx_buf          /* r4 = TX data source */
    ldr   r5, param_rx_buf          /* r5 = RX data dest */

    /* Reset FIFOs */
    ldr   r1, const_fifo_rst        /* 0x80008000 */
    str   r1, [r0, #0x18]           /* SPI_FCR */

    /* Set burst counters: total = tx + rx */
    add   r1, r2, r3
    str   r1, [r0, #0x30]           /* SPI_MBC = total burst */
    str   r2, [r0, #0x34]           /* SPI_MTC = tx count */
    str   r2, [r0, #0x38]           /* SPI_BCC = single-mode tx */

    /* Assert CS: clear SS_LEVEL (bit 7) */
    ldr   r1, [r0, #0x08]
    bic   r1, r1, #0x80
    str   r1, [r0, #0x08]

    /* Fill TX FIFO from buffer */
    mov   r6, #0
1:  cmp   r6, r2
    bge   2f
    ldrb  r1, [r4, r6]
    strb  r1, [r0, #0x200]          /* SPI_TXD: push 1 byte */
    add   r6, r6, #1
    b     1b
2:

    /* Start transfer: set XCH (bit 31) */
    ldr   r1, [r0, #0x08]
    orr   r1, r1, #(1 << 31)
    str   r1, [r0, #0x08]           /* SPI_TCR */

    /* Wait for Transfer Complete (bit 12 in ISR) */
3:  ldr   r1, [r0, #0x14]           /* SPI_ISR */
    tst   r1, #(1 << 12)
    beq   3b

    /* Clear TC flag */
    mov   r1, #(1 << 12)
    str   r1, [r0, #0x14]

    /* Discard TX echo bytes from RX FIFO */
    mov   r6, #0
4:  cmp   r6, r2
    bge   5f
    ldrb  r1, [r0, #0x300]          /* SPI_RXD: pop & discard */
    add   r6, r6, #1
    b     4b
5:

    /* Read RX data bytes to result buffer */
    mov   r6, #0
6:  cmp   r6, r3
    bge   7f
    ldrb  r1, [r0, #0x300]          /* SPI_RXD: pop byte */
    strb  r1, [r5, r6]
    add   r6, r6, #1
    b     6b
7:

    /* Deassert CS: set SS_LEVEL (bit 7) */
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

/* Patchable parameters — host finds offsets via nm or objdump */
param_tx_len:      .word 0x00000004
param_rx_len:      .word 0x00000003
param_tx_buf:      .word 0x00001200
param_rx_buf:      .word 0x00001300

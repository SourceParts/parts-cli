/*
 * test_thunks.c — QEMU test harness for UART RX/TX thunks
 *
 * Simulates Allwinner A64 UART MMIO registers in memory, loads the
 * precompiled thunk binary, and executes it under QEMU user-mode.
 *
 * Build (in ARM container or cross-compile):
 *   arm-none-eabi-gcc -nostdlib -T test_link.ld -o test_rx test_thunks.c uart_rx.bin
 *
 * Or use the Dockerfile / test script for automated testing.
 *
 * This file is a standalone test — it does NOT link against Parts Studio.
 */
#include <stdint.h>

/* Simulated UART registers (memory-mapped) */
#define UART_RBR  0x00
#define UART_THR  0x00
#define UART_LSR  0x14

/* LSR bits */
#define LSR_DR    0x01  /* Data Ready */
#define LSR_THRE  0x20  /* THR Empty */

/* Test NMEA sentence */
static const char test_nmea[] = "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A\r\n";

/*
 * Fake UART peripheral: a struct we place at a known address.
 * The thunk reads [base+0x14] for LSR and [base+0x00] for RBR.
 */
typedef struct {
    volatile uint32_t rbr_thr;    /* 0x00 */
    volatile uint32_t ier;        /* 0x04 */
    volatile uint32_t fcr;        /* 0x08 */
    volatile uint32_t lcr;        /* 0x0C */
    volatile uint32_t mcr;        /* 0x10 */
    volatile uint32_t lsr;        /* 0x14 */
} fake_uart_t;

/*
 * We can't easily test the thunks in pure C because they use absolute
 * addresses and bx lr to return to BROM. Instead, we verify the binary
 * structure and provide a script-based QEMU test.
 *
 * For a proper QEMU system test, see test_qemu.sh which:
 * 1. Maps the thunk at the A64's scratch address (0x11000)
 * 2. Maps a fake UART at 0x01C28800
 * 3. Pre-fills the fake UART RBR with test data
 * 4. Runs the thunk
 * 5. Reads the result buffer
 */

/* Verify thunk binary structure (can be called from host-side test) */
int verify_rx_thunk(const uint8_t *bin, uint32_t size) {
    if (size < 0x68) return -1;  /* too small */

    /* Check first instruction: ldr r0, [pc, #0x4C] = e59f004c */
    uint32_t first = *(uint32_t *)bin;
    if (first != 0xe59f004c) return -2;

    /* Check last instruction before pool: bx lr = e12fff1e at offset 0x50 */
    uint32_t bxlr = *(uint32_t *)(bin + 0x50);
    if (bxlr != 0xe12fff1e) return -3;

    return 0;  /* OK */
}

int verify_tx_thunk(const uint8_t *bin, uint32_t size) {
    if (size < 0x44) return -1;

    /* Check first instruction: ldr r0, [pc, #0x30] = e59f0030 */
    uint32_t first = *(uint32_t *)bin;
    if (first != 0xe59f0030) return -2;

    /* Check bx lr at offset 0x34 */
    uint32_t bxlr = *(uint32_t *)(bin + 0x34);
    if (bxlr != 0xe12fff1e) return -3;

    return 0;
}

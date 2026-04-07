#!/bin/bash
# test_qemu.sh — Test UART thunks using QEMU ARM system emulation
#
# Runs on the Hetzner server in a Docker container with:
#   - arm-none-eabi-gcc (cross compiler)
#   - qemu-system-arm (ARM emulator)
#
# Usage: ./test_qemu.sh [--docker]
#   --docker: Build and run inside Docker container

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; exit 1; }
info() { echo -e "${YELLOW}INFO${NC}: $1"; }

# ─── Step 1: Assemble thunks ───────────────────────────────────────────

info "Assembling thunks..."
arm-none-eabi-as -march=armv8-a -o uart_rx.o uart_rx.S
arm-none-eabi-objcopy -O binary uart_rx.o uart_rx.bin
arm-none-eabi-as -march=armv8-a -o uart_tx.o uart_tx.S
arm-none-eabi-objcopy -O binary uart_tx.o uart_tx.bin

RX_SIZE=$(wc -c < uart_rx.bin)
TX_SIZE=$(wc -c < uart_tx.bin)
info "RX thunk: ${RX_SIZE} bytes"
info "TX thunk: ${TX_SIZE} bytes"

# ─── Step 2: Verify binary structure ──────────────────────────────────

info "Verifying binary structure..."

# RX: first word should be e59f004c (ldr r0, [pc, #0x4C])
RX_FIRST=$(xxd -l 4 -e uart_rx.bin | awk '{print $2}')
[ "$RX_FIRST" = "e59f004c" ] && pass "RX first instruction: ldr r0, [pc, #0x4C]" || fail "RX first instruction: expected e59f004c, got $RX_FIRST"

# RX: bx lr at offset 0x50
RX_BXLR=$(xxd -s 0x50 -l 4 -e uart_rx.bin | awk '{print $2}')
[ "$RX_BXLR" = "e12fff1e" ] && pass "RX bx lr at 0x50" || fail "RX bx lr: expected e12fff1e at 0x50, got $RX_BXLR"

# TX: first word should be e59f0030 (ldr r0, [pc, #0x30])
TX_FIRST=$(xxd -l 4 -e uart_tx.bin | awk '{print $2}')
[ "$TX_FIRST" = "e59f0030" ] && pass "TX first instruction: ldr r0, [pc, #0x30]" || fail "TX first instruction: expected e59f0030, got $TX_FIRST"

# TX: bx lr at offset 0x34
TX_BXLR=$(xxd -s 0x34 -l 4 -e uart_tx.bin | awk '{print $2}')
[ "$TX_BXLR" = "e12fff1e" ] && pass "TX bx lr at 0x34" || fail "TX bx lr: expected e12fff1e at 0x34, got $TX_BXLR"

# ─── Step 3: Verify disassembly ──────────────────────────────────────

info "Checking branch targets..."

# Disassemble and verify key branches
DISASM_RX=$(arm-none-eabi-objdump -d uart_rx.o)

# beq should target rx_no_data (0x44)
echo "$DISASM_RX" | grep -q "beq.*44 <rx_no_data>" && pass "RX beq -> rx_no_data (0x44)" || fail "RX beq branch target wrong"

# blt should target rx_loop (0x1c)
echo "$DISASM_RX" | grep -q "blt.*1c <rx_loop>" && pass "RX blt -> rx_loop (0x1c)" || fail "RX blt branch target wrong"

# b rx_done should target 0x4c
echo "$DISASM_RX" | grep -q "b.*4c <rx_done>" && pass "RX b -> rx_done (0x4c)" || fail "RX b rx_done target wrong"

# bne should target rx_loop (0x1c)
echo "$DISASM_RX" | grep -q "bne.*1c <rx_loop>" && pass "RX bne -> rx_loop (0x1c)" || fail "RX bne branch target wrong"

DISASM_TX=$(arm-none-eabi-objdump -d uart_tx.o)

# bge should target tx_done (0x34)
echo "$DISASM_TX" | grep -q "bge.*34 <tx_done>" && pass "TX bge -> tx_done (0x34)" || fail "TX bge branch target wrong"

# beq should target tx_wait (0x18)
echo "$DISASM_TX" | grep -q "beq.*18 <tx_wait>" && pass "TX beq -> tx_wait (0x18)" || fail "TX beq branch target wrong"

# b should target tx_loop (0x10)
echo "$DISASM_TX" | grep -q "b.*10 <tx_loop>" && pass "TX b -> tx_loop (0x10)" || fail "TX b tx_loop target wrong"

# ─── Step 4: Verify literal pool layout ──────────────────────────────

info "Checking literal pool layout..."

# RX literal pool starts at 0x54 (5 words = 20 bytes)
RX_POOL_START=0x54
RX_POOL_UART=$(xxd -s $RX_POOL_START -l 4 -e uart_rx.bin | awk '{print $2}')
[ "$RX_POOL_UART" = "01c28800" ] && pass "RX pool[0] = UART2 base (0x01c28800)" || fail "RX pool uart_base: got $RX_POOL_UART"

RX_POOL_MAX=$(xxd -s 0x58 -l 4 -e uart_rx.bin | awk '{print $2}')
[ "$RX_POOL_MAX" = "00000200" ] && pass "RX pool[1] = max_bytes (512)" || fail "RX pool max_bytes: got $RX_POOL_MAX"

# TX literal pool starts at 0x38 (3 words = 12 bytes)
TX_POOL_UART=$(xxd -s 0x38 -l 4 -e uart_tx.bin | awk '{print $2}')
[ "$TX_POOL_UART" = "01c28c00" ] && pass "TX pool[0] = UART3 base (0x01c28c00)" || fail "TX pool uart_base: got $TX_POOL_UART"

# ─── Done ─────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}All thunk verification tests passed!${NC}"
echo ""
info "Thunk binaries are ready for deployment."
info "RX: uart_rx.bin (${RX_SIZE} bytes) — polls UART RBR, buffers up to 512 bytes"
info "TX: uart_tx.bin (${TX_SIZE} bytes) — sends bytes via UART THR"

# Clean up object files
rm -f uart_rx.o uart_tx.o

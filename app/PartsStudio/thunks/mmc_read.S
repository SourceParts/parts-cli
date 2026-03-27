/*
 * mmc_read.S — SD card sector read thunk for Allwinner A64 (AArch32, FEL mode)
 *
 * Reads one or more 512-byte sectors from the SD card via the MMC0 controller.
 * BROM has already initialized MMC0 clocks and the card (it booted from SD to
 * reach FEL mode), so we skip init and just issue READ_SINGLE_BLOCK (CMD17).
 *
 * Literal pool (patched at runtime by host):
 *   +0xC0: MMC base address      (0x01C0F000 for MMC0)
 *   +0xC4: sector start           (LBA sector number)
 *   +0xC8: sector count           (number of 512-byte sectors to read)
 *   +0xCC: buffer address          (absolute SRAM address for output)
 *   +0xD0: status address          (absolute SRAM address, stores result)
 *
 * Result:
 *   [statusAddr+0] = 0 on success, nonzero = error code
 *   [statusAddr+4] = sectors successfully read
 *   [bufferAddr ... bufferAddr + count*512 - 1] = sector data
 *
 * Assemble: arm-none-eabi-as -march=armv8-a -o mmc_read.o mmc_read.S
 * Extract:  arm-none-eabi-objcopy -O binary mmc_read.o mmc_read.bin
 */

    .syntax unified
    .arm
    .text
    .global _start

/* MMC register offsets */
.equ MMC_GCTRL,    0x00
.equ MMC_CLKCR,    0x04
.equ MMC_TIMEOUT,  0x08
.equ MMC_WIDTH,    0x0C
.equ MMC_BLKSZ,    0x10
.equ MMC_BYTECNT,  0x14
.equ MMC_CMD,      0x18
.equ MMC_ARG,      0x1C
.equ MMC_RESP0,    0x20
.equ MMC_RINT,     0x38
.equ MMC_STATUS,   0x3C
.equ MMC_FIFO,     0x200

/* CMD register bits */
.equ CMD_START,       (1 << 31)
.equ CMD_RESP_EXPIRE, (1 << 6)
.equ CMD_CHK_CRC,     (1 << 8)
.equ CMD_DATA_EXPIRE, (1 << 9)
.equ CMD_WAIT_PRE,    (1 << 13)

/* RINT bits */
.equ RINT_CMD_DONE,   (1 << 2)
.equ RINT_DATA_OVER,  (1 << 3)
.equ RINT_RX_DATA,    (1 << 5)
.equ RINT_ERROR_MASK, 0x0000BFFE  /* bits 1,6-15 are error bits */

/* Status register bits */
.equ STATUS_FIFO_EMPTY, (1 << 2)

_start:
    /* Load parameters from literal pool */
    ldr   r0, mmc_base           /* MMC0 base address */
    ldr   r1, sector_start       /* starting LBA sector */
    ldr   r2, sector_count       /* number of sectors */
    ldr   r3, buf_addr           /* output buffer */
    ldr   r8, stat_addr          /* status output */
    mov   r9, #0                 /* r9 = sectors read so far */

    /* Ensure AHB access mode (not DMA) */
    ldr   r4, [r0, #MMC_GCTRL]
    orr   r4, r4, #(1 << 31)    /* ACCESS_BY_AHB */
    bic   r4, r4, #(1 << 5)     /* disable DMA */
    str   r4, [r0, #MMC_GCTRL]

sector_loop:
    cmp   r9, r2
    bge   done_ok

    /* Clear all pending interrupts */
    ldr   r4, =0xFFFFFFFF
    str   r4, [r0, #MMC_RINT]

    /* Set block size = 512, byte count = 512 */
    mov   r4, #512
    str   r4, [r0, #MMC_BLKSZ]
    str   r4, [r0, #MMC_BYTECNT]

    /* Set argument = sector address (LBA for SDHC) */
    add   r5, r1, r9             /* current sector = start + offset */
    str   r5, [r0, #MMC_ARG]

    /* Issue CMD17 (READ_SINGLE_BLOCK)
     * CMD index = 17
     * Flags: CMD_START | CMD_RESP_EXPIRE | CMD_CHK_CRC | CMD_DATA_EXPIRE | CMD_WAIT_PRE
     */
    ldr   r4, =CMD_START | CMD_RESP_EXPIRE | CMD_CHK_CRC | CMD_DATA_EXPIRE | CMD_WAIT_PRE | 17
    str   r4, [r0, #MMC_CMD]

    /* Wait for command to complete */
    mov   r6, #0x100000          /* timeout counter */
wait_cmd:
    subs  r6, r6, #1
    beq   err_timeout
    ldr   r4, [r0, #MMC_RINT]
    tst   r4, #RINT_CMD_DONE
    beq   wait_cmd

    /* Check for errors */
    ldr   r4, [r0, #MMC_RINT]
    ldr   r7, =RINT_ERROR_MASK
    tst   r4, r7
    bne   err_cmd

    /* Read 512 bytes from FIFO (128 x 32-bit words) */
    mov   r6, #128               /* 512 / 4 = 128 words */
    /* Calculate buffer offset: r3 + r9 * 512 */
    mov   r7, r9, lsl #9        /* r7 = r9 * 512 */
    add   r7, r3, r7             /* r7 = buf_addr + offset */

read_fifo:
    /* Wait for FIFO to have data */
    ldr   r4, [r0, #MMC_STATUS]
    tst   r4, #STATUS_FIFO_EMPTY
    bne   read_fifo              /* spin if empty */

    ldr   r4, [r0, #MMC_FIFO]   /* read 4 bytes from FIFO */
    str   r4, [r7], #4           /* store and advance pointer */
    subs  r6, r6, #1
    bne   read_fifo

    /* Wait for data transfer complete */
    mov   r6, #0x100000
wait_data:
    subs  r6, r6, #1
    beq   err_timeout
    ldr   r4, [r0, #MMC_RINT]
    tst   r4, #RINT_DATA_OVER
    beq   wait_data

    /* Clear interrupts for next sector */
    ldr   r4, =0xFFFFFFFF
    str   r4, [r0, #MMC_RINT]

    /* Next sector */
    add   r9, r9, #1
    b     sector_loop

done_ok:
    mov   r4, #0                 /* success */
    str   r4, [r8]               /* status = 0 */
    str   r9, [r8, #4]           /* sectors read */
    bx    lr                     /* return to FEL */

err_timeout:
    mov   r4, #1                 /* error: timeout */
    str   r4, [r8]
    str   r9, [r8, #4]
    bx    lr

err_cmd:
    mov   r4, #2                 /* error: command/data error */
    str   r4, [r8]
    str   r9, [r8, #4]
    bx    lr

    /* Literal pool — patched by host before execution */
    .align 2
mmc_base:      .word 0x01C0F000   /* MMC0 base */
sector_start:  .word 0            /* starting LBA sector */
sector_count:  .word 1            /* sectors to read */
buf_addr:      .word 0x00012000   /* output buffer in SRAM */
stat_addr:     .word 0x00011F00   /* status result in SRAM */

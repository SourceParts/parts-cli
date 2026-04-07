# Allwinner FEL Protocol Specification

Extracted from Parts Studio macOS implementation for cross-platform reimplementation.

## USB Device Identification

| Property       | Value    |
|---------------|----------|
| Vendor ID     | `0x1F3A` |
| Product ID    | `0xEFE8` |
| Transfer Type | Bulk     |
| Max Bulk Send | 512 KB (`512 * 1024`) |

Find the device by VID/PID, claim the first interface, and identify the bulk IN and bulk OUT endpoints (transfer type = 2; direction 1 = IN, direction 0 = OUT).

## Protocol Layers

The protocol has three layers, bottom-up:

### Layer 1: USB Transport

Two primitives: **USB Write** and **USB Read**.

#### USB Request Header (32 bytes, sent on OUT endpoint)

```
Offset  Size   Field         Value
0       4      Signature     "AWUC" (0x41575543, big-endian)
4       4      (padding)     0x00000000
8       4      Length        Payload length (little-endian)
12      3      (padding)     0x000000
15      1      Unknown       0x0C
16      2      Type          0x12 (WRITE) or 0x11 (READ) (little-endian)
18      4      Length        Same as offset 8 (little-endian)
22      10     (padding)     zeros
```

#### USB Write Sequence
1. Send 32-byte USB request header (type = `0x12`)
2. Send payload data (chunked at 512KB max)
3. Read 13-byte status response

#### USB Read Sequence
1. Send 32-byte USB request header (type = `0x11`)
2. Read payload data (requested length)
3. Read 13-byte status response

### Layer 2: FEL Commands

#### FEL Request (16 bytes, sent via USB Write)

```
Offset  Size   Field
0       4      Command type (little-endian)
4       4      Address (little-endian)
8       4      Length (little-endian)
12      4      Padding (zero)
```

#### Command Types

| Command          | Value    | Description                    |
|-----------------|----------|--------------------------------|
| `AW_FEL_VERSION`| `0x001`  | Get device version info        |
| `AW_FEL_1_WRITE`| `0x101`  | Write data to memory address   |
| `AW_FEL_1_EXEC` | `0x102`  | Execute code at address        |
| `AW_FEL_1_READ` | `0x103`  | Read data from memory address  |

#### FEL Status (8 bytes)
Read via USB Read after every FEL command. Content is informational; check for USB-level errors.

### Layer 3: FEL Operations

#### FEL Read (address, length)
1. Send FEL request: type=`0x103`, address, length
2. USB Read: length bytes of data
3. Read FEL Status (8 bytes via USB Read)

#### FEL Write (data, address)
1. Send FEL request: type=`0x101`, address, length=data.count
2. USB Write: data, length=data.count
3. Read FEL Status (8 bytes via USB Read)

#### FEL Execute (address)
1. Send FEL request: type=`0x102`, address, length=0
2. Read FEL Status (8 bytes via USB Read)

#### Get Version
1. Send FEL request: type=`0x001`, address=0, length=0
2. USB Read: 32 bytes
3. Read FEL Status

## FEL Version Response (32 bytes)

```
Offset  Size   Field
0       8      Signature (ASCII, e.g. "AWUSBFEX")
8       4      SoC ID (little-endian, right-shift by 8 to get actual ID)
12      4      Firmware field (unknown purpose)
16      2      Protocol version (little-endian)
18      2      (padding)
20      4      Scratchpad address (little-endian)
24      4      Pad word 1 (little-endian)
28      4      Pad word 2 (little-endian)
```

**SoC ID extraction**: `socId = le32(bytes[8..12]) >> 8`

Look up the SoC ID in `soc_info_table.json` to get memory addresses for the SoC.

## SID (Serial ID) Reading

### Direct Method (most SoCs)
Read 16 bytes from `sid_base + sid_offset`. Parse as 4 little-endian uint32 words, format as `"XXXXXXXX:XXXXXXXX:XXXXXXXX:XXXXXXXX"`.

### Thunk Method (SoCs with `sid_fix: true`, e.g. H3)
Execute ARM thunk code that reads SID via the control register sequence:
1. For each of 4 words (offset 0, 4, 8, 12):
   - Write `(offset << 16) | 0xAC02` to `sid_base + 0x40`
   - Poll `sid_base + 0x40` until bit 1 is clear
   - Read result from `sid_base + 0x60`
2. Write 0 to `sid_base + 0x40` to clean up

## SPL (Secondary Program Loader) Writing

### eGON Header Validation
```
Offset  Size   Field
0       4      (branch instruction)
4       8      Signature: "eGON.BT0" (ASCII)
12      4      Checksum value (little-endian)
16      4      SPL length in bytes (little-endian, must be multiple of 4)
```

### Checksum Verification
```
checksum = 2 * spl_check_value - 0x5F0A6C39
for each uint32 word in spl_data[0..spl_length]:
    checksum -= word
assert checksum == 0
```

### Write Sequence with Swap Buffers

SPL data is written to `spl_addr` (from SoC info table), but certain SRAM regions are reserved for FEL/BROM stacks. The swap buffer entries define regions that must be redirected:

```
For each swap_buffer in soc_info.swap_buffers:
    If write offset is below buf1: write normally up to buf1
    If write offset equals buf1: write to buf2 instead (size bytes)
Write remaining data normally
```

### SPL Thunk Code

After writing SPL data, a thunk is written to `thunk_addr` and executed. The thunk:
1. Swaps buffer contents (copies data between buf1 <-> buf2 for each swap entry)
2. Verifies SPL checksum in-place
3. Stamps `eGON.FEL` signature at SPL+8 if checksum passes
4. Calls SPL code via `blx r8` (r8 = spl_addr)
5. SPL executes DRAM init, then returns to FEL
6. Thunk swaps buffers back and returns

The thunk data layout:
```
Offset    Content
0-263     ARM instructions (66 words, see buildSPLThunk in FELService.swift)
264-267   SPL address (little-endian uint32)
268+      Swap buffer entries (12 bytes each: buf1, buf2, size, all LE uint32)
last      Terminator: 12 zero bytes
```

### Post-SPL USB Recovery

After SPL executes DRAM init (reconfigures PLL11), USB PHY state is corrupted. The device re-enumerates but the macOS IOKit pipe degrades after ~10 seconds. **Physical USB replug is required.**

Wait up to 60 seconds, polling for device re-enumeration:
1. Try to open USB device
2. Try to find and open interface
3. Try to get FEL version
4. If all succeed, USB is reconnected

Verify DRAM init succeeded by reading `spl_addr + 4` for 8 bytes — should be `"eGON.FEL"`.

## U-Boot Writing

### mkimage Header Validation (64 bytes, big-endian)
```
Offset  Size   Field
0       4      Magic: 0x27051956 (big-endian)
4       4      Header CRC32 (big-endian, computed with this field zeroed)
8       4      Timestamp
12      4      Data size (big-endian)
16      4      Load address (big-endian)
20      4      Entry point (big-endian)
24      4      Data CRC32 (big-endian)
28      1      OS type
29      1      Architecture (must be 2 = ARM)
30      1      Image type (must be 5 = firmware)
31      1      Compression type
32      32     Image name (ASCII)
```

### Write Sequence
1. Validate header magic, architecture, image type
2. Verify header CRC32 (zero the CRC field, compute, compare)
3. Verify data CRC32 (over data following the 64-byte header)
4. Write image data (skip header) to `load_address` via FEL Write

## Boot Sequence

### Combined Binary (u-boot-sunxi-with-spl.bin)
If the binary is > 32KB, split automatically:
- First 32KB = SPL
- Remaining = U-Boot payload

### Full Boot (bootPocketPC)

1. **[Optional] Pre-load ATF BL31** to 0x44000 (SRAM, always accessible)
2. **Write and execute SPL** → DRAM initializes → USB dies → physical replug
3. **Write U-Boot** to 0x4a000000 (DRAM, must complete within ~10s USB window)
4. **RMR warm reset** to ATF BL31 at 0x44000

### RMR (Reset Management Register) Boot — AArch64 SoCs

For 64-bit SoCs (A64, H5, H6) with `rvbar_reg != 0`:

ARM thunk written to scratch and executed:
```
1. Write entry_point to RVBAR register
2. DSB SY + ISB SY (memory barriers)
3. MRC p15, 0, r0, c12, c0, 2 (read RMR)
4. ORR r0, r0, #3 (set RR=1, AA64=1)
5. MCR p15, 0, r0, c12, c0, 2 (write RMR)
6. ISB SY
7. WFI (wait for interrupt — reset happens)
```

For 32-bit SoCs: simply execute at the entry point address.

## ARM Thunk Code Execution

General pattern for running code on the device:
1. FEL Write: thunk code to `scratch_addr`
2. FEL Execute: at `scratch_addr`
3. FEL Read: results from `scratch_addr + offset`

### Register Read/Write Thunks

**Write Register** (24 bytes):
```arm
ldr r0, [pc, #8]    @ 0xe59f0008 — load address from offset 16
ldr r1, [pc, #8]    @ 0xe59f1008 — load value from offset 20
str r1, [r0]        @ 0xe5801000 — write value to address
bx  lr              @ 0xe12fff1e — return
.word address       @ offset 16
.word value         @ offset 20
```

## Memory Address Validation

### Protected Regions (never write)
- `0xFFFF0000 - 0xFFFFFFFF` — BROM high vectors
- `0xFFF00000 - 0xFFF0FFFF` — BROM

### Safe Regions (per SoC)
- SRAM A: `spl_addr` to `spl_addr + 0x8000` (or `0x0000 - 0x8000`)
- SRAM C: `thunk_addr & 0xFFFFF000` to that + `0x10000` (if thunk > 0x10000)
- DRAM: `0x40000000 - 0xBFFFFFFF`
- Scratch: `scratch_addr` to `scratch_addr + 0x1000`
- Peripheral MMIO: `0x01C00000 - 0x01FFFFFF` (read/write OK for GPIO, CCU, UART)
- Peripheral MMIO: `0x03000000 - 0x03FFFFFF` (read OK)

## A64 Peripheral Addresses

### GPIO
- Base: `0x01C20800`
- Each port offset: `port_index * 0x24`
- Ports: B=1, C=2, D=3, E=4, F=5, G=6, H=7
- Register layout per port: CFG0 (+0x00), CFG1 (+0x04), CFG2 (+0x08), CFG3 (+0x0C), DATA (+0x10)
- Pin function config: 4 bits per pin, 8 pins per CFG register

### UART
| UART | Base         | TX Pin | RX Pin | Pinmux |
|------|-------------|--------|--------|--------|
| 0    | `0x01C28000` | —      | —      | —      |
| 1    | `0x01C28400` | —      | —      | —      |
| 2    | `0x01C28800` | PB0    | PB1    | func 2 |
| 3    | `0x01C28C00` | PH4    | PH5    | func 2 |
| 4    | `0x01C29000` | —      | —      | —      |

UART register offsets:
- `+0x00` RBR/THR (receive/transmit) / DLL (when DLAB=1)
- `+0x04` IER / DLH (when DLAB=1)
- `+0x08` FCR (FIFO control, write-only)
- `+0x0C` LCR (line control)
- `+0x14` LSR (line status)

Baud rate divisor: `(24_000_000 + 8 * baud) / (16 * baud)` (rounded)

### CCU (Clock Control Unit)
- `0x01C20068` — BUS_CLK_GATING_REG2 (PIO gate = bit 5)
- `0x01C202D0` — BUS_SOFT_RST_REG2 (PIO reset = bit 5)
- `0x01C2006C` — BUS_CLK_GATING_REG3 (UART0=bit16, UART1=bit17, ...)
- `0x01C202D8` — BUS_SOFT_RST_REG4 (UART0=bit16, UART1=bit17, ...)

### UART Init Sequence
1. Enable PIO clock gate (BUS_CLK_GATING_REG2 bit 5)
2. Deassert PIO reset (BUS_SOFT_RST_REG2 bit 5)
3. Enable UART clock gate (BUS_CLK_GATING_REG3 bit 16+uart)
4. Deassert UART reset (BUS_SOFT_RST_REG4 bit 16+uart)
5. Configure GPIO pins for UART function
6. Set LCR = 0x83 (8N1 + DLAB)
7. Write divisor low byte to RBR/THR (+0x00)
8. Write divisor high byte to IER (+0x04)
9. Clear DLAB: LCR = 0x03
10. Enable + reset FIFOs: FCR = 0x07
11. Disable interrupts: IER = 0x00

## Precompiled UART Thunks

### RX Thunk (104 bytes code + literal pool)
Reads bytes from a UART's RBR register with timeout.

Memory layout when loaded at `scratch_addr`:
```
+0x00 - 0x53   Precompiled ARM code (84 bytes)
+0x54           UART base address (patch)
+0x58           Max bytes to read (patch)
+0x5C           Timeout loop count (patch)
+0x60           Buffer address = scratch_addr + 0x6C (patch)
+0x64           Count address = scratch_addr + 0x68 (patch)
+0x68           Result: byte count (uint32, read back after exec)
+0x6C+          Result: received data bytes (read back after exec)
```

### TX Thunk (56 bytes code + literal pool + data)
Writes bytes to a UART's THR register, polling LSR for TX ready.

Memory layout:
```
+0x00 - 0x37   Precompiled ARM code (56 bytes)
+0x38           UART base address (patch)
+0x3C           Byte count (patch)
+0x40           Data address = scratch_addr + 0x44 (patch)
+0x44+          TX data payload (appended)
```

## Device State Machine

```
disconnected → fel (USB VID/PID detected)
fel → splLoading (device drops off USB)
splLoading → fel (re-enumeration, boot failed)
splLoading → uboot (serial port appears)
uboot → kernel (serial: "Starting kernel" / "Linux version")
kernel → login (serial: "login:")
login → running (CDC USB device appears)
running → disconnected (CDC device disappears)
running → fel (FEL VID/PID reappears)
```

## RAK4200 LoRa Module

Connected via UART3 (PH4/PH5). Reset pin: PG10.

**Hardware reset**: Configure PG10 as output, drive low, then high.

**AT commands**: Write `"command\r\n"` to UART3, wait ~300ms, read response.

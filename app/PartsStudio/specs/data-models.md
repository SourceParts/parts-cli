# Shared Data Model Schemas

JSON schemas for data structures shared between macOS and Android apps. These define the offline storage format and API contract.

## RegisteredDevice

Stored locally at `~/.parts/devices/registry.json` (array of devices).

```json
{
  "sid": "92c0f6ba:14304620:78f4c71c:241e0b90",
  "name": "Jose's PocketPC",
  "owner": "Jose",
  "soc_name": "A64",
  "board_revision": "v1.2",
  "board_serial": "PP-A64-92C0F6BA",
  "notes": "Prototype unit #3",
  "tags": ["prototype", "dev-unit"],
  "hardware": {
    "soc": "Allwinner A64",
    "dram_size": "1GB DDR3",
    "emmc": "8GB",
    "wifi": "RTL8723BS",
    "display": "5\" 800x480 LCD",
    "battery": "3000mAh LiPo",
    "pmic": "AXP803",
    "uart": "WCH CH340",
    "extras": {}
  },
  "first_seen": "2026-01-15T10:30:00Z",
  "last_seen": "2026-03-24T14:22:00Z",
  "boot_count": 47,
  "firmware_version": "v0.3.1",
  "hardware_fingerprint": "a1b2c3d4e5f67890",
  "audit_log": [
    {
      "id": 1,
      "date": "2026-01-15T10:30:00Z",
      "event": "registered",
      "detail": "Device first registered (SoC: A64, Serial: PP-A64-92C0F6BA)",
      "old_value": null,
      "new_value": null
    }
  ]
}
```

**Board serial format**: `PP-{SOC_NAME}-{SID_FIRST_8_CHARS_UPPER}`

**Hardware fingerprint**: djb2 hash of `"sid:wifiMAC:emmcCID"` (currently SID-only), formatted as 16-char hex.

**Sync queue**: Stored at `~/.parts/devices/sync_queue.json` as `["sid1", "sid2", ...]`. Flushed to API every 30 seconds.

**Audit events**: `registered`, `hardware_changed`, `name_changed`, `owner_changed`, `hardware_updated`

## DatasheetAnnotation

Stored per-datasheet as JSON files.

```json
{
  "version": 1,
  "content_hash": "abc123...",
  "annotations": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "page": 3,
      "type": "redaction",
      "bounds": {
        "x": 100.0,
        "y": 200.0,
        "width": 150.0,
        "height": 20.0
      },
      "text": null,
      "fontSize": null,
      "color": null,
      "created": "2026-03-24T14:22:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "page": 5,
      "type": "freeText",
      "bounds": {"x": 50, "y": 100, "width": 200, "height": 30},
      "text": "Check voltage rating",
      "fontSize": 12.0,
      "color": "#FF0000",
      "created": "2026-03-24T14:23:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440002",
      "page": 5,
      "type": "highlight",
      "bounds": {"x": 50, "y": 300, "width": 300, "height": 15},
      "text": null,
      "fontSize": null,
      "color": "#FFFF0080",
      "created": "2026-03-24T14:24:00Z"
    }
  ]
}
```

**Annotation types**: `redaction`, `freeText`, `highlight`

**Color format**: Hex string, 6-char (`#RRGGBB`) or 8-char (`#RRGGBBAA`)

**Bounds**: Origin at bottom-left (PDF coordinate space), in points

## ECODocument

Parsed from markdown files on disk. Not stored as JSON, but the structure is:

```json
{
  "id": "ECN-027",
  "type": "ECN",
  "title": "Replace U3 voltage regulator",
  "severity": "HIGH",
  "status": "IN REVIEW",
  "file_path": "/path/to/ECN-027.md",
  "body": "# ECN-027: Replace U3...\n\n..."
}
```

**Types**: `ECN` (Engineering Change Notice), `ECR` (Request), `ECO` (Order)

**Severities**: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`

**Statuses**: `OPEN`, `IN REVIEW`, `APPROVED`, etc.

## IQCItem

Fetched from API, cached locally.

```json
{
  "id": "IQC-2026-0042",
  "code": "IQC-2026-0042",
  "status": "pending_inspection",
  "created_at": "2026-03-20T09:00:00Z",
  "images": [
    {
      "id": "img-001",
      "url": "https://storage.source.parts/iqc/...",
      "thumbnail_url": "https://storage.source.parts/iqc/.../thumb"
    }
  ],
  "inspection_notes": "Check solder joints on QFP package",
  "tracking_number": "1Z999AA10123456784",
  "carrier": "UPS",
  "received_date": "2026-03-19",
  "received_location": "Shenzhen warehouse",
  "partner_name": "JLCPCB",
  "photo_count": 5,
  "condition_rating": 4,
  "has_damage": false,
  "inspection_result": "pass",
  "barcodes": [
    {"data": "C123456", "type": "code128", "confidence": 0.98}
  ],
  "ocr_text": "LCSC C123456 Qty: 100",
  "discovered_urls": [
    {
      "url": "https://www.lcsc.com/product-detail/C123456.html",
      "source": "barcode",
      "domain_type": "lcsc",
      "crawl_status": "crawled"
    }
  ],
  "local_files": ["/path/to/xray.bmp"],
  "metadata": {
    "lot_number": "2026W12",
    "date_code": "2603"
  }
}
```

**Note**: API may return `code` or `short_code` or `id` — use first non-null. Images may come from `images` array OR from `storage_url`/`thumbnail_url` top-level fields.

## SoCInfo (from soc_info_table.json)

```json
{
  "1689": {
    "soc_id": "0x1689",
    "name": "A64",
    "spl_addr": "0x10000",
    "scratch_addr": "0x11000",
    "thunk_addr": "0x1A200",
    "thunk_size": "0x200",
    "swap_buffers": "a64",
    "sid_base": "0x01C14000",
    "sid_offset": "0x200",
    "rvbar_reg": "0x017000A0",
    "needs_smc_workaround_if_zero_word_at_addr": "0x40004"
  }
}
```

All address values are hex strings prefixed with `0x`. Parse to uint32.

**Optional fields** (default to 0/false if missing):
- `spl_addr` — if absent, use `scratch_addr`
- `sid_offset` — default `"0x0"`
- `rvbar_reg` — if 0, SoC is 32-bit (no RMR boot)
- `needs_l2en` — default `false`
- `mmu_tt_addr` — default `0`
- `sid_fix` — default `false`, if true use thunk-based SID read
- `needs_smc_workaround_if_zero_word_at_addr` — default `0`

**Swap buffer sets** (hardcoded, referenced by name):

| Name             | Entries (buf1, buf2, size)                                     |
|-----------------|----------------------------------------------------------------|
| `a10_a13_a20`   | (0x1C00, 0xA400, 0x0400), (0x5C00, 0xA800, 0x1400), (0x7C00, 0xBC00, 0x0400) |
| `a31`           | (0x1800, 0x20000, 0x800), (0x5C00, 0x20800, 0x2400)          |
| `a64`           | (0x11C00, 0x1A400, 0x0400), (0x15C00, 0x1A800, 0x1400), (0x17C00, 0x1BC00, 0x0400) |
| `ar100_abusing` | (0x1800, 0x44000, 0x800), (0x5C00, 0x44800, 0x2400)          |
| `a80`           | (0x11800, 0x20000, 0x800), (0x15400, 0x20800, 0x2C00)        |
| `h6`            | (0x21C00, 0x2A400, 0x0400), (0x25C00, 0x2A800, 0x1400), (0x27C00, 0x2BC00, 0x0400) |

## FELDeviceInfo

Runtime structure (not persisted):

```json
{
  "version": {
    "signature": "AWUSBFEX",
    "soc_id": 5769,
    "firmware": 0,
    "protocol_version": 1,
    "scratchpad": 69632
  },
  "soc_info": { "...see SoCInfo above..." },
  "sid": "92c0f6ba:14304620:78f4c71c:241e0b90"
}
```

## PocketPCState (Device State Machine)

Runtime enum, not persisted:

| State         | Display Name   | Trigger                          |
|--------------|----------------|----------------------------------|
| disconnected | Disconnected   | No USB device detected           |
| fel          | Recovery Mode  | FEL VID/PID (0x1F3A/0xEFE8)     |
| splLoading   | Loading SPL    | FEL device drops off USB         |
| dramInit     | DRAM Init      | Serial: "dram:" / "dram size"    |
| uboot        | U-Boot         | Serial port appears              |
| kernel       | Kernel Boot    | Serial: "Starting kernel"        |
| login        | Login Ready    | Serial: "login:"                 |
| running      | Running        | CDC USB device (VID 0x0525)      |
| massStorage  | Mass Storage   | Mass storage device detected     |

## CachedDatasheet

```json
{
  "filename": "STM32F103C8T6.pdf",
  "path": "/path/to/cached/file",
  "cached": true
}
```

## Conversation

```json
{
  "id": "conv-123",
  "messages": [
    {
      "role": "user",
      "content": "What is the max voltage for U3?",
      "timestamp": "2026-03-24T14:22:00Z"
    }
  ]
}
```

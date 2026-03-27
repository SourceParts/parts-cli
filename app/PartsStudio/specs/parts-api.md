# Parts Cloud API Contract

Base URL: Configurable via `PartsConfig` (default: `api.source.parts`).

## Authentication

All requests require:
```
Authorization: Bearer <api_key>
User-Agent: PartsStudio/1.0
```

Timeout: 15s for GET, 30s for POST.

## Endpoints

### GET `/v1/components/{mpn}`

Look up a single part by manufacturer part number.

**Response:**
```json
{
  "data": {
    "mpn": "STM32F103C8T6",
    "manufacturer": "STMicroelectronics",
    "description": "ARM Cortex-M3 MCU, 64KB Flash",
    "category": "Microcontrollers",
    "specifications": {
      "Core": "ARM Cortex-M3",
      "Flash": "64KB",
      "RAM": "20KB"
    },
    "features": ["Low power", "USB"],
    "image_url": "https://...",
    "unit_price": 2.50,
    "stock": 15000
  }
}
```

### GET `/v1/components/search?q={query}&limit={limit}`

Search parts by keyword.

**Parameters:**
- `q` (required): Search query (URL-encoded)
- `limit` (optional): Max results (default 10)

**Response:**
```json
{
  "data": [
    {
      "mpn": "STM32F103C8T6",
      "manufacturer": "STMicroelectronics",
      "description": "ARM Cortex-M3 MCU",
      "category": "Microcontrollers",
      "unit_price": 2.50,
      "stock": 15000
    }
  ]
}
```

Note: `stock` field may also appear as `stock_quantity` — handle both.

### POST `/v1/components/estimate`

Estimate cost for multiple parts.

**Request:**
```json
{
  "parts": [
    {"part_number": "STM32F103C8T6", "quantity": 100},
    {"part_number": "AXP803", "quantity": 100}
  ]
}
```

**Response:**
```json
{
  "data": [
    {
      "part_number": "STM32F103C8T6",
      "unit_price": 2.30,
      "available": true,
      "stock": 15000
    }
  ]
}
```

### POST `/v1/bom/cost`

Calculate total BOM cost for a given board quantity.

**Request:**
```json
{
  "bom": [
    {"part_number": "STM32F103C8T6", "quantity": 1},
    {"part_number": "AXP803", "quantity": 1}
  ],
  "quantity": 100
}
```

**Response:**
```json
{
  "data": {
    "total_cost": 450.00,
    "items": [
      {
        "part_number": "STM32F103C8T6",
        "unit_price": 2.30,
        "available": true,
        "stock": 15000
      }
    ]
  }
}
```

### POST `/v1/components/availability`

Check stock availability for multiple parts.

**Request:**
```json
{
  "part_numbers": ["STM32F103C8T6", "AXP803"]
}
```

**Response:**
```json
{
  "data": [
    {
      "part_number": "STM32F103C8T6",
      "in_stock": true,
      "stock": 15000,
      "lead_time": "2-3 weeks"
    }
  ]
}
```

### POST `/v1/manufacturing/dfm`

Submit a DFM (Design for Manufacturability) check.

**Request:**
```json
{
  "project_id": "proj-123",
  "priority": "normal"
}
```

**Response:**
```json
{
  "data": {
    "job_id": "dfm-456"
  }
}
```

### GET `/v1/manufacturing/dfm/{job_id}`

Check DFM job status and results.

**Response:**
```json
{
  "data": {
    "status": "completed",
    "score": 85,
    "checks": [
      {"name": "Trace width", "pass": true, "detail": "All traces >= 6mil"}
    ],
    "warnings": ["Via spacing tight on layer 2"],
    "recommendations": ["Consider increasing ground plane clearance"]
  }
}
```

### POST `/v1/manufacturing/fab/quote`

Get a PCB fabrication quote.

**Request:**
```json
{
  "project_id": "proj-123",
  "quantity": 5,
  "layers": 2
}
```

**Response:**
```json
{
  "data": {
    "unit_price": 12.50,
    "total_price": 62.50,
    "quantity": 5,
    "lead_time": "5-7 business days"
  }
}
```

### GET `/v1/parts/{sku}/gather`

Get comprehensive part data including pricing, datasheet, and alternatives.

**Response:**
```json
{
  "data": {
    "part": {
      "part_number": "STM32F103C8T6",
      "manufacturer": "STMicroelectronics",
      "description": "ARM Cortex-M3 MCU",
      "category": "Microcontrollers",
      "specifications": {"Core": "ARM Cortex-M3"},
      "features": ["Low power"],
      "image_url": "https://...",
      "unit_price": 2.50,
      "stock_quantity": 15000
    },
    "pricing": {
      "price_breaks": [
        {"quantity": 1, "unit_price": 2.50},
        {"quantity": 100, "unit_price": 2.30},
        {"quantity": 1000, "unit_price": 1.95}
      ]
    },
    "datasheet": {
      "url": "https://..."
    },
    "alternatives": [
      {
        "sku": "GD32F103C8T6",
        "name": "GD32F103C8T6",
        "manufacturer": "GigaDevice",
        "description": "Pin-compatible ARM Cortex-M3"
      }
    ]
  }
}
```

Note: `part.unit_price` may also appear as `part.price`, and `part.stock_quantity` as `part.stock` — handle both.

### POST `/v1/devices/sync`

Sync a device registry entry to the cloud.

**Request:** JSON-encoded `RegisteredDevice` (see data-models.md), with:
- Date fields as ISO 8601 strings
- Keys in snake_case

**Response (200):** Success (no body required).

## Error Handling

HTTP errors include the response body as a string message:
```
APIError.httpError(statusCode, body)
```

Missing API key → user should run `parts auth login`.

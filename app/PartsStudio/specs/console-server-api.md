# Console Server HTTP API (localhost:9801)

Local HTTP server for remote control of the FEL console. Both macOS and Android apps should implement this same interface.

## Server Details

- **Bind**: `127.0.0.1:9801`
- **Protocol**: HTTP/1.1
- **CORS**: `Access-Control-Allow-Origin: *`
- **Connection**: `close` (no keep-alive)
- **Content-Type**: `application/json` (all responses)
- **Read timeout**: 5 seconds per client

## Endpoints

### `GET /`

Returns documentation of all available endpoints.

**Response (200):**
```json
{
  "endpoints": {
    "/cmd?q=<command>": "Execute console command",
    "/log": "Get console log",
    "/device": "Get device info",
    "/status": "Server status",
    "/reload": "Reload config and refresh assembly",
    "/revision": "Show current revision",
    "/revision?set=EVT1": "Switch board variant",
    "/navigate?view=<name>": "Navigate to view (fel, iqc, eco, usb, credits, search, datasheets)"
  }
}
```

### `GET /cmd?q=<command>`

Execute a console command and return the result.

**Parameters:**
- `q` (required): The command string (URL-encoded)

**Response (200):**
```json
{
  "command": "info",
  "result": "A64 (0x1689)\nSID: 92c0f6ba:14304620:78f4c71c:241e0b90"
}
```

**Error (400):**
```json
{"error": "missing ?q= parameter"}
```

**Known Commands:**
- `status` — FEL connection state
- `info` — Device SoC and SID
- `read <addr> [len]` — Memory read with hex output
- `dump brom|<addr> <len>` — Memory dump to file
- `spl` — Load SPL
- `write-uboot` — Write U-Boot to 0x4a000000
- `exec <addr>` — Execute at address
- `boot` / `autoboot` — Full boot sequence
- `serial` — Switch to serial console
- `gps [raw]` / `gps stop` — GPS polling
- `rak` / `lora` — LoRa AT commands
- `swd` — SWD debug probe
- `esp32` / `esp` — ESP32 module control
- `voice [start|stop|direct|natural]` — Voice recognition
- `ble [scan|connect|send|flash]` — BLE operations
- `sync` — Sync device registry to cloud
- `clear` — Clear console log
- `help` — List commands

### `GET /log`

Get the console log as a JSON array of strings.

**Response (200):**
```json
{
  "log": [
    "Parts Studio FEL Console",
    "Connected: A64 (0x1689)",
    "SID: 92c0f6ba:14304620:78f4c71c:241e0b90"
  ]
}
```

### `GET /device`

Get connected device information as JSON.

**Response (200, device connected):**
```json
{
  "connected": true,
  "soc": "A64",
  "soc_id": "1689",
  "sid": "92c0f6ba:14304620:78f4c71c:241e0b90",
  "name": "Jose's PocketPC",
  "owner": "Jose"
}
```

**Response (200, no device):**
```json
{}
```

### `GET /status`

Server health check.

**Response (200):**
```json
{
  "status": "ok",
  "port": 9801
}
```

### `GET /reload`

Reload configuration and refresh assembly file listings.

**Response (200):**
```json
{"result": "reloaded"}
```

### `GET /revision`

Get current board revision/variant configuration.

**Response (200):**
```json
{
  "revision": "EVT1",
  "assembly": "/path/to/assembly",
  "fab_release": "/path/to/fab"
}
```

### `GET /revision?set=<rev>`

Switch to a different board revision/variant.

**Parameters:**
- `set` (required): The revision name

**Response (200):**
```json
{"result": "revision set to EVT1"}
```

### `GET /navigate?view=<name>`

Navigate the app to a specific view.

**Parameters:**
- `view` (required): One of `fel`, `iqc`, `eco`, `usb`, `credits`, `search`, `datasheets`

**Error (400):**
```json
{"error": "missing ?view= parameter. Options: fel, iqc, eco, usb, credits, search, datasheets"}
```

## Error Handling

All errors return JSON:
```json
{"error": "description of the error"}
```

404 for unknown routes:
```json
{"error": "not found"}
```

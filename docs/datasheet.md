# Datasheet Commands

Manage datasheets: upload PDFs to the local cache, set aliases, retrieve by alias or content hash, and render pages as images.

## Commands

| Command | Description |
|---------|-------------|
| `parts datasheet info <part-number>` | Fetch datasheet info from the API |
| `parts datasheet upload <file>` | Cache a PDF locally |
| `parts datasheet get <alias-or-hash>` | Resolve alias/hash to local path |
| `parts datasheet read <alias-or-hash>` | Render PDF pages as PNG |
| `parts datasheet list` | List all cached datasheets |
| `parts datasheet alias list` | List all aliases |
| `parts datasheet alias set <name> <hash> <file>` | Create/update an alias |
| `parts datasheet alias rm <name>` | Remove an alias |

## Upload

Cache a datasheet PDF locally with content-addressed storage. Files are stored under `~/.cache/parts/datasheets/sha256_<hash>/<filename>`.

```bash
parts datasheet upload nRF54H20.pdf --alias nrf54h20
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--alias` | Set a friendly name for quick retrieval |
| `--team` | Team name (for scoped remote paths) |
| `--project` | Project ID (for scoped remote paths) |

**Output:**

```
Cached:  ~/.cache/parts/datasheets/sha256_30e4f2a65ed4d3ea/nRF54H20.pdf
Hash:    sha256_30e4f2a65ed4d3ea
Alias:   nrf54h20 -> sha256_30e4f2a65ed4d3ea/nRF54H20.pdf
Remote:  private/u_d887db09649d/t_cb9b5a0f4a8b/legend/datasheets/sha256_30e4f2a65ed4d3ea/nRF54H20.pdf
```

## Get

Resolve an alias or content hash to a local file path.

```bash
# By alias
parts datasheet get nrf54h20

# By hash
parts datasheet get sha256_30e4f2a65ed4d3ea

# By hash/filename
parts datasheet get sha256_30e4f2a65ed4d3ea/nRF54H20.pdf
```

## Read

Render one or more pages from a cached PDF as PNG images. Uses `pdftoppm` from poppler.

```bash
# Single page
parts datasheet read pmic --pages 29

# Multiple pages
parts datasheet read pmic --pages 29,143

# Page range
parts datasheet read nrf54h20 --pages 1-5

# Combinations
parts datasheet read pcmd3140-pdm --pages 1-3,7,10-12

# Open in macOS Preview
parts datasheet read pmic --pages 29 --open

# Save to specific directory
parts datasheet read nrf54h20 --pages 1-5 --output ./rendered
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--pages` | **(required)** Page specification: single (`29`), comma-separated (`29,143`), range (`1-5`), or combined (`1-3,7,10-12`) |
| `--open` | Open rendered PNGs in the default image viewer (macOS Preview) |
| `--output` | Output directory for PNGs (default: temp directory) |

**Requires:** `pdftoppm` from poppler. Install with:

```bash
brew install poppler
```

**Output:** Paths to rendered PNG files, one per line.

```
/var/folders/.../parts-datasheet-123/nPM1300_PMIC_Full_Datasheet_p29-029.png
```

## List

List all cached datasheets with their hashes, sizes, and aliases.

```bash
parts datasheet list
```

```
HASH               FILENAME                                          SIZE  ALIAS
----------------------------------------------------------------------------------------------------
30e4f2a65ed4d3ea   nRF54H20_Preliminary_Datasheet_v0.7.1 (1).pdf    15.2 MB  nrf54h20
a8b1c2d3e4f50617   nPM1300_PMIC_Full_Datasheet.pdf                   5.1 MB  npm1300-pmic, pmic
```

## Aliases

Aliases map friendly names to content-addressed datasheets for quick access.

```bash
# List all aliases
parts datasheet alias list

# Set an alias
parts datasheet alias set nrf54h20 30e4f2a65ed4d3ea "nRF54H20.pdf"

# Remove an alias
parts datasheet alias rm nrf54h20
```

**Alias naming rules:**
- Must match `[a-zA-Z0-9][a-zA-Z0-9_.-]*`
- Maximum 64 characters
- Cannot be a 16-character hex string (ambiguous with content hashes)

## Storage Architecture

```
~/.cache/parts/datasheets/
├── aliases.json                          # Alias → hash/filename mapping
├── sha256_30e4f2a65ed4d3ea/
│   └── nRF54H20.pdf                     # Content-addressed storage
├── sha256_a8b1c2d3e4f50617/
│   └── nPM1300_PMIC_Full_Datasheet.pdf
└── ...
```

Files are deduplicated by content hash (first 16 hex characters of SHA256). Uploading the same file twice produces the same hash and reuses the existing cache entry.

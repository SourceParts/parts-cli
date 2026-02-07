# parts-cli

The official command-line interface for [Source Parts](https://source.parts) - Electronic Component Intelligence Platform.

## Features

- **Part Search** - Search millions of electronic components
- **Datasheet Access** - Quickly retrieve datasheets for any component
- **BOM Management** - Upload, validate, and process Bills of Materials
- **Project Management** - Create and manage hardware projects
- **Manufacturing** - Submit DFM analysis, fab orders, AOI, and QC requests
- **Inventory Tracking** - Monitor stock levels and pricing
- **Secure Authentication** - API keys stored in system keychain

## Installation

### Using Go

```bash
go install github.com/SourceParts/parts-cli/cmd/parts@latest
```

### From Source

```bash
git clone https://github.com/SourceParts/parts-cli.git
cd parts-cli
make build
```

### Pre-built Binaries

Download from [Releases](https://github.com/SourceParts/parts-cli/releases).

## Quick Start

### Authentication

```bash
# Login with your API key (get one at https://source.parts/settings/api-keys)
parts auth login

# Check authentication status
parts auth status
```

### Search for Parts

```bash
# Search for a component
parts search "STM32F407"

# Get datasheet
parts datasheet STM32F407VGT6
```

### BOM Operations

```bash
# Upload and process a BOM file
parts bom upload assembly.xlsx

# Check BOM processing status
parts bom status <job-id>
```

### Project Management

```bash
# Create a new project
parts project create "My Project" --description "Description"

# Get project status
parts project status <project-id>
```

### Manufacturing

```bash
# Submit DFM analysis
parts dfm --project <project-id>

# Create fab order
parts fab --project <project-id> --quantity 10
```

## Configuration

The CLI stores configuration in:
- **API Keys**: System keychain (macOS Keychain, Linux Secret Service, Windows Credential Manager)
- **Config File**: `~/.config/parts/config.yaml` (optional)

## Related Projects

- [parts-mcp](https://github.com/SourceParts/parts-mcp) - MCP Server for AI assistant integration
- [Source Parts API](https://source.parts/docs/api) - REST API documentation

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Polyform Shield 1.0.0 - See [LICENSE](LICENSE) for details.

This license allows you to use, modify, and distribute the software for any purpose **except** competing with Source Parts' products and services.

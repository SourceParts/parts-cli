# Contributing to parts-cli

Thank you for your interest in contributing to parts-cli!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/parts-cli.git`
3. Create a branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Run tests: `make test`
6. Commit your changes: `git commit -m "Add your feature"`
7. Push to your fork: `git push origin feature/your-feature`
8. Open a Pull Request

## Development Setup

```bash
# Install dependencies
go mod download

# Build
make build

# Run tests
make test

# Format code
make fmt

# Lint
make lint
```

## Code Style

- Follow standard Go conventions
- Run `gofmt` before committing
- Write tests for new functionality
- Update documentation as needed

## Reporting Issues

- Search existing issues first
- Include steps to reproduce
- Include your OS and Go version
- Include relevant logs

## Questions?

Open an issue or reach out at https://source.parts/contact

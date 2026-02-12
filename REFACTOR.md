# Refactoring Notes

## API Types Migration (COMPLETED)

**Status**: Done
**Completed**: 2026-02-12
**Reference**: Completed in parts.sh private CLI (commit d4a4ac1)

### Summary

Migrated API request/response structs from `internal/domain/client.go` to `internal/api/` package:

```
internal/api/
└── bom.go        # BOM types (BOMUploadOptions, BOMUploadResponse, etc.)
```

### Changes Made

1. Created `internal/api/bom.go` with BOM-related types:
   - `BOMUploadOptions`
   - `BOMUploadResponse`
   - `LCSCPartInfo`
   - `BOMStatusResponse`

2. Updated `internal/domain/client.go`:
   - Removed BOM type definitions
   - Added import for `internal/api` package
   - Updated `Client` interface to use `api.BOMUploadOptions`

3. Updated `internal/client/client.go`:
   - Added import for `internal/api` package
   - Updated `BOM()` and `BOMUpload()` to use `api.BOMUploadOptions`
   - Updated `PollBOMStatus()` to use `api.BOMStatusResponse`

4. Updated `internal/commands/commands.go`:
   - Added import for `internal/api` package
   - Updated `bomUpload` command to use `api.BOMUploadOptions`

### Benefits Achieved

- **Separation of Concerns**: Domain contracts separated from DTOs
- **Better Organization**: API types grouped by functional domain
- **Easier Navigation**: Find types by domain rather than scrolling through one large file
- **Clearer Intent**: `internal/api` clearly indicates these are API-specific types
- **Maintainability**: Changes to API types isolated from domain contracts

### Future Work

As more features are added, create additional files in `internal/api/`:
- `auth.go` - Authentication types
- `search.go` - Search types
- `datasheet.go` - Datasheet types
- `types.go` - Shared utility types

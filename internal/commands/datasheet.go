package commands

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/storage"
	"github.com/spf13/cobra"
)

// Datasheet is the parent command for all datasheet operations.
var Datasheet = &cobra.Command{
	Use:   "datasheet",
	Short: "Datasheet operations (upload, get, list, alias)",
	Long: `Manage datasheets: upload PDFs to the local cache, set aliases,
list cached files, and retrieve datasheets by alias or content hash.

Use "parts datasheet info <part-number>" to fetch a datasheet from the API.`,
}

var datasheetInfo = &cobra.Command{
	Use:     "info <part-number>",
	Short:   "Get datasheet for a part from the API",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` datasheet info STM32F407VGT6`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		return Client.Datasheet(ctx, args[0], os.Stdout)
	},
}

var (
	dsAlias   string
	dsTeam    string
	dsProject string
)

var datasheetUpload = &cobra.Command{
	Use:   "upload <file>",
	Short: "Cache a datasheet PDF locally",
	Long: `Upload a PDF to the local datasheet cache. The file is content-hashed
and stored under ~/.cache/parts/datasheets/sha256_<hash>/<filename>.

Use --alias to set a friendly name for quick retrieval.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` datasheet upload nRF54H20.pdf --alias nrf54h20`,
	RunE: func(cmd *cobra.Command, args []string) error {
		localPath := args[0]
		if _, err := os.Stat(localPath); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", localPath)
		}

		// Validate alias early
		if dsAlias != "" {
			if err := storage.ValidateAliasName(dsAlias); err != nil {
				return fmt.Errorf("invalid alias: %w", err)
			}
		}

		// Cache locally
		cachedPath, contentHash, err := storage.CacheDatasheet(localPath)
		if err != nil {
			return fmt.Errorf("cache: %w", err)
		}
		fmt.Printf("Cached:  %s\n", cachedPath)
		fmt.Printf("Hash:    sha256_%s\n", contentHash)

		// Set alias
		if dsAlias != "" {
			if err := storage.SetAlias(dsAlias, contentHash, filepath.Base(localPath)); err != nil {
				return fmt.Errorf("set alias: %w", err)
			}
			fmt.Printf("Alias:   %s -> sha256_%s/%s\n", dsAlias, contentHash, filepath.Base(localPath))
		}

		// Show scoped remote path if team/project provided
		if dsProject != "" {
			user := os.Getenv("USER")
			scope := storage.NewScope(user, dsTeam, dsProject)
			remotePath := scope.DatasheetPath(contentHash, filepath.Base(localPath))
			fmt.Printf("Remote:  %s\n", remotePath)
		}

		return nil
	},
}

var datasheetGet = &cobra.Command{
	Use:   "get <alias-or-hash>",
	Short: "Get a cached datasheet by alias or content hash",
	Long: `Resolve an alias or content hash to a local file path.

Accepts:
  - An alias name (e.g., "nrf54h20")
  - A content hash with optional filename (e.g., "sha256_abc123def456/file.pdf")`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` datasheet get nrf54h20`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ref := args[0]

		// Try alias first
		if contentHash, filename, ok := storage.ResolveAlias(ref); ok {
			if p, found := storage.GetCachedDatasheet(contentHash, filename); found {
				fmt.Println(p)
				return nil
			}
			return fmt.Errorf("alias %q resolves to sha256_%s/%s but file not in cache", ref, contentHash, filename)
		}

		// Try as hash/filename
		ref = strings.TrimPrefix(ref, "sha256_")
		parts := strings.SplitN(ref, "/", 2)
		contentHash := parts[0]
		if len(parts) == 2 {
			if p, found := storage.GetCachedDatasheet(contentHash, parts[1]); found {
				fmt.Println(p)
				return nil
			}
		}

		// Try finding any file with that hash
		cached, err := storage.ListCachedDatasheets()
		if err != nil {
			return err
		}
		for _, c := range cached {
			if c.ContentHash == contentHash {
				fmt.Println(c.Path)
				return nil
			}
		}

		return fmt.Errorf("datasheet %q not found in cache", args[0])
	},
}

var datasheetList = &cobra.Command{
	Use:     "list",
	Aliases: []string{"ls"},
	Short:   "List cached datasheets",
	Args:    cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		cached, err := storage.ListCachedDatasheets()
		if err != nil {
			return err
		}
		if len(cached) == 0 {
			fmt.Println("No cached datasheets")
			return nil
		}

		// Build alias reverse lookup
		aliases, _ := storage.LoadAliases()
		hashToAlias := make(map[string][]string)
		for name, a := range aliases {
			key := a.ContentHash + "/" + a.Filename
			hashToAlias[key] = append(hashToAlias[key], name)
		}

		fmt.Printf("%-18s %-45s %10s  %s\n", "HASH", "FILENAME", "SIZE", "ALIAS")
		fmt.Println(strings.Repeat("-", 100))
		for _, c := range cached {
			key := c.ContentHash + "/" + c.Filename
			aliasStr := strings.Join(hashToAlias[key], ", ")
			fmt.Printf("%-18s %-45s %10s  %s\n",
				c.ContentHash, truncate(c.Filename, 45), formatSize(c.Size), aliasStr)
		}
		return nil
	},
}

// Alias subcommand group
var datasheetAlias = &cobra.Command{
	Use:   "alias",
	Short: "Manage datasheet aliases",
}

var datasheetAliasList = &cobra.Command{
	Use:     "list",
	Aliases: []string{"ls"},
	Short:   "List all aliases",
	Args:    cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		aliases, err := storage.LoadAliases()
		if err != nil {
			return err
		}
		if len(aliases) == 0 {
			fmt.Println("No aliases defined")
			return nil
		}

		// Sort by name
		names := make([]string, 0, len(aliases))
		for name := range aliases {
			names = append(names, name)
		}
		sort.Strings(names)

		fmt.Printf("%-22s %-18s %s\n", "ALIAS", "HASH", "FILENAME")
		fmt.Println(strings.Repeat("-", 90))
		for _, name := range names {
			a := aliases[name]
			fmt.Printf("%-22s %-18s %s\n", name, a.ContentHash, a.Filename)
		}
		return nil
	},
}

var datasheetAliasSet = &cobra.Command{
	Use:     "set <alias> <content-hash> <filename>",
	Short:   "Create or update an alias",
	Args:    cobra.ExactArgs(3),
	Example: domain.BinaryName + ` datasheet alias set nrf54h20 30e4f2a65ed4d3ea "nRF54H20.pdf"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		name, hash, filename := args[0], args[1], args[2]
		hash = strings.TrimPrefix(hash, "sha256_")
		if err := storage.SetAlias(name, hash, filename); err != nil {
			return err
		}
		fmt.Printf("Alias set: %s -> sha256_%s/%s\n", name, hash, filename)
		return nil
	},
}

var datasheetAliasRm = &cobra.Command{
	Use:     "rm <alias>",
	Aliases: []string{"remove", "delete"},
	Short:   "Remove an alias",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` datasheet alias rm nrf54h20`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := storage.RemoveAlias(args[0]); err != nil {
			return err
		}
		fmt.Printf("Removed alias: %s\n", args[0])
		return nil
	},
}

func init() {
	datasheetUpload.Flags().StringVar(&dsAlias, "alias", "", "Set a friendly alias for the uploaded datasheet")
	datasheetUpload.Flags().StringVar(&dsTeam, "team", "", "Team name (for scoped remote paths)")
	datasheetUpload.Flags().StringVar(&dsProject, "project", "", "Project ID (for scoped remote paths)")

	datasheetAlias.AddCommand(datasheetAliasList)
	datasheetAlias.AddCommand(datasheetAliasSet)
	datasheetAlias.AddCommand(datasheetAliasRm)

	Datasheet.AddCommand(datasheetInfo)
	Datasheet.AddCommand(datasheetUpload)
	Datasheet.AddCommand(datasheetGet)
	Datasheet.AddCommand(datasheetList)
	Datasheet.AddCommand(datasheetAlias)
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-3] + "..."
}

func formatSize(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}

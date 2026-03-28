package domain

import (
	"context"
	"io"

	"github.com/SourceParts/parts-cli/internal/types"
)

// Client represents the CLI interface with Source Parts API
type Client interface {
	// Authentication
	Auth(ctx context.Context, apiKey string, w io.Writer) error
	IsAuthenticated() bool
	GetAPIKey() string
	SetAPIKey(key string)

	// Part operations
	Add(ctx context.Context, partNumber string, opts types.AddOptions, w io.Writer) error
	Search(ctx context.Context, query string, opts types.SearchOptions, w io.Writer) error
	Datasheet(ctx context.Context, partNumber string, w io.Writer) error
	Marking(ctx context.Context, partNumber string, w io.Writer) error
	Gather(ctx context.Context, partNumber string, w io.Writer) error

	// BOM operations
	BOM(ctx context.Context, fileName string, w io.Writer) error
	BOMUpload(ctx context.Context, fileName string, opts types.BOMUploadOptions, w io.Writer) error
	BOMStatus(ctx context.Context, jobID string, w io.Writer) error
	PollBOMStatus(ctx context.Context, jobID string, w io.Writer) error

	// Project operations
	ProjectCreate(ctx context.Context, name, description string, w io.Writer) error
	ProjectList(ctx context.Context, opts types.ProjectListOptions, w io.Writer) error
	ProjectGet(ctx context.Context, projectID string, w io.Writer) error
	ProjectDelete(ctx context.Context, projectID string, w io.Writer) error
	ProjectECO(ctx context.Context, projectID string, data types.ECORequest, w io.Writer) error
	ProjectTransfer(ctx context.Context, projectID, email string, w io.Writer) error
	Skeleton(ctx context.Context, w io.Writer) error

	// Manufacturing
	DFMSubmit(ctx context.Context, bomID, projectID string, w io.Writer) error
	DFM(ctx context.Context, input string, w io.Writer) error
	Fabricate(ctx context.Context, input string, w io.Writer) error
	AOI(ctx context.Context, input string, w io.Writer) error
	QC(ctx context.Context, input string, w io.Writer) error
	Publish(ctx context.Context, input string, w io.Writer) error
	Stackup(ctx context.Context, gerberZip string, opts types.StackupOptions, w io.Writer) error
	StackupDiff(ctx context.Context, gerberA, gerberB string, opts types.StackupDiffOptions, w io.Writer) error

	// EDA
	ERC(ctx context.Context, fileName string, opts types.ERCOptions, w io.Writer) error
	DRC(ctx context.Context, fileName string, opts types.DRCOptions, w io.Writer) error
	ImportAltium(ctx context.Context, fileName string, outputPath string, w io.Writer) error
	ImportAltiumBytes(ctx context.Context, fileName string) ([]byte, error)

	// Inventory & Supply Chain
	Inventory(ctx context.Context, partNumber string, w io.Writer) error
	Cart(ctx context.Context, w io.Writer) error
	Buy(ctx context.Context, partNumber string, w io.Writer) error
	RFQ(ctx context.Context, partNumber string, w io.Writer) error
	Wishlist(ctx context.Context, partNumber string, w io.Writer) error
	Tracker(ctx context.Context, partNumber string, w io.Writer) error
	Box(ctx context.Context, boxID string, w io.Writer) error

	// Cost Management
	Balance(ctx context.Context, w io.Writer) error
	COGs(ctx context.Context, partNumber string, w io.Writer) error
	Expense(ctx context.Context, input string, w io.Writer) error
	Price(ctx context.Context, partNumber string, opts types.PriceOptions, w io.Writer) error

	// Credits
	CreditsBalance(ctx context.Context, jsonOutput bool, w io.Writer) error

	// Workflow
	Note(ctx context.Context, note string, w io.Writer) error
	Todo(ctx context.Context, todoItem string, w io.Writer) error
	Report(ctx context.Context, reportType string, w io.Writer) error

	// QuarterMaster (smart query)
	Q(ctx context.Context, text, queryType string, w io.Writer) error
	QHistory(ctx context.Context, limit int, w io.Writer) error
	QHistoryClear(ctx context.Context, w io.Writer) error
	QSMD(ctx context.Context, code string, w io.Writer) error
	QResistorColors(ctx context.Context, bands string, w io.Writer) error

	// Datasheets
	RegisterDatasheetAlias(ctx context.Context, alias, contentHash, s3Key, filename, projectID string, w io.Writer) error
	PollDatasheetChunkStatus(ctx context.Context, jobID string, w io.Writer) error

	// Firmware
	FirmwareUpload(ctx context.Context, fileName string, opts types.FirmwareUploadOptions, w io.Writer) error
	FirmwareList(ctx context.Context, opts types.FirmwareListOptions, w io.Writer) error
	RawGet(ctx context.Context, url string, w io.Writer) error

	// Local operations
	Init(ctx context.Context, w io.Writer) error
	Log(ctx context.Context, input string, w io.Writer) error
	Status(ctx context.Context, input string, w io.Writer) error
	Clean(ctx context.Context, w io.Writer) error
	Scan(ctx context.Context, w io.Writer) error
	Label(ctx context.Context, partNumber string, w io.Writer) error
	Detect(ctx context.Context, input string, w io.Writer) error

	// Documentation
	Guide(ctx context.Context, topic string, w io.Writer) error
	Docs(ctx context.Context, topic string, w io.Writer) error

	// Version Control
	Pull(ctx context.Context, input string, w io.Writer) error
	Push(ctx context.Context, input string, w io.Writer) error
	Tag(ctx context.Context, tag string, w io.Writer) error
	Release(ctx context.Context, input string, opts types.ReleaseOptions, w io.Writer) error
	Test(ctx context.Context, input string, w io.Writer) error
}

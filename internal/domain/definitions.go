package domain

const BinaryName = `parts`
const API = `api.source.parts`

// =============================================================================
// V1 API BASE
// =============================================================================

// V1Prefix is the base URL for all v1 API endpoints
const V1Prefix = `https://` + API + `/v1`

// =============================================================================
// AUTHENTICATION
// =============================================================================

// Endpoint_Auth is the authentication endpoint for obtaining API tokens
const Endpoint_Auth = V1Prefix + `/auth/login`

// Endpoint_AuthValidate validates an API key
const Endpoint_AuthValidate = V1Prefix + `/auth/key/validate`

// Endpoint_APIKeys manages API keys
const Endpoint_APIKeys = V1Prefix + `/auth/keys`

// Endpoint_AuthToken proxies the Auth0 authorization code exchange (code → tokens)
const Endpoint_AuthToken = V1Prefix + `/auth/token`

// Endpoint_AuthTokenRefresh proxies the Auth0 refresh token exchange
const Endpoint_AuthTokenRefresh = V1Prefix + `/auth/token/refresh`

// =============================================================================
// PART OPERATIONS
// =============================================================================

// Endpoint_Add adds a part to the database
const Endpoint_Add = V1Prefix + `/parts`

// Endpoint_Search searches for parts
const Endpoint_Search = V1Prefix + `/parts/search`

// Endpoint_Datasheet retrieves part datasheets
const Endpoint_Datasheet = V1Prefix + `/parts/%s/datasheet`

// Endpoint_DatasheetChunk uploads and chunks a datasheet PDF
const Endpoint_DatasheetChunk = V1Prefix + `/datasheets/chunk`

// Endpoint_DatasheetChunkStatus gets async chunking job status
const Endpoint_DatasheetChunkStatus = V1Prefix + `/datasheets/chunk/%s/status`

// Endpoint_Marking retrieves part marking information
const Endpoint_Marking = V1Prefix + `/parts/%s/marking`

// Endpoint_Gather gathers comprehensive part information
const Endpoint_Gather = V1Prefix + `/parts/%s/gather`

// =============================================================================
// PROJECT MANAGEMENT
// =============================================================================

// Endpoint_ProjectCreate creates a new project
const Endpoint_ProjectCreate = V1Prefix + `/projects`

// Endpoint_ProjectList lists all projects
const Endpoint_ProjectList = V1Prefix + `/projects`

// Endpoint_ProjectGet gets a single project
const Endpoint_ProjectGet = V1Prefix + `/projects/%s`

// Endpoint_ProjectStatus gets project status
const Endpoint_ProjectStatus = V1Prefix + `/projects/%s/status`

// Endpoint_ProjectECO creates an Engineering Change Order
const Endpoint_ProjectECO = V1Prefix + `/projects/%s/eco`

// Endpoint_ProjectRelease creates a project release
const Endpoint_ProjectRelease = V1Prefix + `/projects/%s/release`

// Endpoint_ProjectTag creates a project tag
const Endpoint_ProjectTag = V1Prefix + `/projects/%s/tag`

// Endpoint_ProjectDelete deletes a project
const Endpoint_ProjectDelete = V1Prefix + `/projects/%s`

// Endpoint_ProjectTransfer transfers project ownership to another user
const Endpoint_ProjectTransfer = V1Prefix + `/projects/%s/transfer`

// Endpoint_ProjectSkeleton creates a project skeleton
const Endpoint_ProjectSkeleton = V1Prefix + `/projects/skeleton`

// =============================================================================
// BILL OF MATERIALS (BOM)
// =============================================================================

// Endpoint_BOMUpload uploads and processes a BOM file
const Endpoint_BOMUpload = V1Prefix + `/bom`

// Endpoint_BOMStatus gets BOM processing status
const Endpoint_BOMStatus = V1Prefix + `/bom/%s/status`

// Endpoint_BOMGet gets a processed BOM
const Endpoint_BOMGet = V1Prefix + `/bom/%s`

// =============================================================================
// MANUFACTURING
// =============================================================================

// Endpoint_ManufacturingDFM runs Design for Manufacturing analysis
const Endpoint_ManufacturingDFM = V1Prefix + `/manufacturing/dfm`

// Endpoint_ManufacturingFab submits a fabrication order
const Endpoint_ManufacturingFab = V1Prefix + `/manufacturing/fab`

// Endpoint_ManufacturingAOI submits Automated Optical Inspection request
const Endpoint_ManufacturingAOI = V1Prefix + `/manufacturing/aoi`

// Endpoint_ManufacturingQC submits Quality Control inspection
const Endpoint_ManufacturingQC = V1Prefix + `/manufacturing/qc`

// Endpoint_ManufacturingPublish publishes a manufacturing package
const Endpoint_ManufacturingPublish = V1Prefix + `/manufacturing/publish`

// Endpoint_ManufacturingStackup generates a stackup PDF from gerber files
const Endpoint_ManufacturingStackup = V1Prefix + `/manufacturing/stackup`

// Endpoint_ManufacturingStackupDiff generates a diff PDF comparing two gerber sets
const Endpoint_ManufacturingStackupDiff = V1Prefix + `/manufacturing/stackup/diff`

// Endpoint_ManufacturingPlacement generates placement visualization and panelized pick-and-place files
const Endpoint_ManufacturingPlacement = V1Prefix + `/manufacturing/placement`

// Endpoint_ManufacturingStatus gets manufacturing job status
const Endpoint_ManufacturingStatus = V1Prefix + `/manufacturing/%s/status`

// Legacy aliases for backwards compatibility
const Endpoint_Fabricate = Endpoint_ManufacturingFab
const Endpoint_DFM = Endpoint_ManufacturingDFM
const Endpoint_AOI = Endpoint_ManufacturingAOI
const Endpoint_QC = Endpoint_ManufacturingQC
const Endpoint_Publish = Endpoint_ManufacturingPublish

// =============================================================================
// SUPPLY CHAIN & PURCHASING
// =============================================================================

// Endpoint_Cart gets shopping cart contents
const Endpoint_Cart = V1Prefix + `/cart`

// Endpoint_CartAdd adds item to shopping cart
const Endpoint_CartAdd = V1Prefix + `/cart/add`

// Endpoint_Buy places a purchase order
const Endpoint_Buy = V1Prefix + `/orders`

// Endpoint_RFQ submits a Request for Quote
const Endpoint_RFQ = V1Prefix + `/rfq`

// Endpoint_Inventory gets inventory levels
const Endpoint_Inventory = V1Prefix + `/inventory`

// Endpoint_InventoryItem gets inventory for a specific part
const Endpoint_InventoryItem = V1Prefix + `/inventory/%s`

// Endpoint_Wishlist gets wishlist items
const Endpoint_Wishlist = V1Prefix + `/wishlist`

// Endpoint_WishlistAdd adds item to wishlist
const Endpoint_WishlistAdd = V1Prefix + `/wishlist/add`

// Endpoint_Box gets box/order information
const Endpoint_Box = V1Prefix + `/orders/%s`

// Endpoint_Tracker gets price tracking data
const Endpoint_Tracker = V1Prefix + `/tracker`

// =============================================================================
// COST MANAGEMENT
// =============================================================================

// Endpoint_CostsEstimate estimates pricing for parts
const Endpoint_CostsEstimate = V1Prefix + `/costs/estimate`

// Endpoint_COGS calculates Cost of Goods Sold
const Endpoint_COGS = V1Prefix + `/costs/cogs`

// Endpoint_Expense records a project expense
const Endpoint_Expense = V1Prefix + `/costs/expense`

// Endpoint_Balance gets account balance
const Endpoint_Balance = V1Prefix + `/costs/balance`

// =============================================================================
// CREDITS
// =============================================================================

// Endpoint_CreditsBalance gets the current sourcing credit balance
const Endpoint_CreditsBalance = V1Prefix + `/credits/balance`

// =============================================================================
// DOCUMENTATION
// =============================================================================

// Endpoint_Guide gets application notes and guides
const Endpoint_Guide = V1Prefix + `/docs/guide`

// Endpoint_Docs gets technical documentation
const Endpoint_Docs = V1Prefix + `/docs`

// =============================================================================
// WORKFLOW
// =============================================================================

// Endpoint_Note adds a note
const Endpoint_Note = V1Prefix + `/notes`

// Endpoint_Todo adds a todo item
const Endpoint_Todo = V1Prefix + `/todos`

// Endpoint_Report generates a report
const Endpoint_Report = V1Prefix + `/reports`

// =============================================================================
// QUARTERMASTER (Smart Query)
// =============================================================================

// Endpoint_Q is the main QuarterMaster endpoint (smart dispatch)
const Endpoint_Q = V1Prefix + `/q`

// Endpoint_QHistory manages search history
const Endpoint_QHistory = V1Prefix + `/q/history`

// Endpoint_QSMD converts SMD resistor codes
const Endpoint_QSMD = V1Prefix + `/q/tools/smd`

// Endpoint_QResistorColors calculates resistor color bands
const Endpoint_QResistorColors = V1Prefix + `/q/tools/resistor/colors`

// =============================================================================
// MISCELLANEOUS
// =============================================================================

// Endpoint_Scan scans a device or barcode
const Endpoint_Scan = V1Prefix + `/scan`

// Endpoint_Clean cleans/organizes project files
const Endpoint_Clean = V1Prefix + `/clean`

// Endpoint_Detect detects file type or part information
const Endpoint_Detect = V1Prefix + `/detect`

// Endpoint_Test runs tests
const Endpoint_Test = V1Prefix + `/test`

// Endpoint_Health checks API health
const Endpoint_Health = V1Prefix + `/health`

// =============================================================================
// EDA (Main API — all EDA endpoints go through api.source.parts)
// =============================================================================

const ConvertAPI = `convert.source.parts` // legacy — kept for Altium import only

// Endpoint_ERC runs Electrical Rules Check on a KiCad schematic
const Endpoint_ERC = V1Prefix + `/eda/erc`

// Endpoint_DRC runs Design Rules Check on a KiCad PCB
const Endpoint_DRC = V1Prefix + `/eda/drc`

// Endpoint_ImportAltium converts an Altium .SchDoc to KiCad .kicad_sch
const Endpoint_ImportAltium = `https://` + ConvertAPI + `/api/eda/import/altium`

// Schematic editing endpoints
const Endpoint_SchematicPlace    = V1Prefix + `/eda/schematic/place`
const Endpoint_SchematicWire     = V1Prefix + `/eda/schematic/wire`
const Endpoint_SchematicAnnotate = V1Prefix + `/eda/schematic/annotate`
const Endpoint_SchematicRemove   = V1Prefix + `/eda/schematic/remove`
const Endpoint_SchematicLabel    = V1Prefix + `/eda/schematic/label`
const Endpoint_SchematicDiff     = V1Prefix + `/eda/schematic/diff`
const Endpoint_SchematicRender   = V1Prefix + `/eda/schematic/render`
const Endpoint_RerouteSuggest    = V1Prefix + `/eda/reroute/suggest`

// =============================================================================
// CLI UPDATE
// =============================================================================

// Endpoint_CLIUpdate retrieves the latest CLI version information
const Endpoint_CLIUpdate = V1Prefix + `/cli/update/latest`

// =============================================================================
// WEBHOOKS (source.parts, not api.source.parts)
// =============================================================================

const WebhookBase = `https://source.parts`

// Endpoint_ReportNotify sends report notifications with PDF generation
const Endpoint_ReportNotify = WebhookBase + `/api/webhooks/report-notify`

// Endpoint_CommitNotify sends commit/push notifications
const Endpoint_CommitNotify = WebhookBase + `/api/dfm-notify`

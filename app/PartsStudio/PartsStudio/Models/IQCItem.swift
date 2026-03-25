import Foundation

struct IQCBarcode: Codable, Identifiable {
    var id: String { "\(type)_\(data)" }
    let data: String
    let type: String
    let confidence: Double?
}

struct IQCDiscoveredURL: Codable, Identifiable {
    var id: String { url }
    let url: String
    let source: String?        // barcode, ocr, barcode_secondary, ocr_secondary
    let domainType: String?    // lcsc, digikey, mouser, etc.
    let crawlStatus: String?   // pending, crawled, unsupported, failed

    enum CodingKeys: String, CodingKey {
        case url, source
        case domainType = "domain_type"
        case crawlStatus = "crawl_status"
    }
}

struct IQCItem: Identifiable, Decodable {
    let id: String
    let code: String
    let status: String
    let createdAt: String
    var images: [IQCImage]
    var inspectionNotes: String?
    var trackingNumber: String?
    var carrier: String?
    var receivedDate: String?
    var receivedLocation: String?
    var partnerName: String?
    var photoCount: Int?
    var conditionRating: Int?
    var hasDamage: Bool?
    var inspectionResult: String?
    // Barcode / OCR / metadata
    var barcodes: [IQCBarcode]?
    var ocrText: String?
    var discoveredUrls: [IQCDiscoveredURL]?
    var localFiles: [String]?  // Local file paths (e.g., X-ray BMPs)
    var metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, code, status, images, carrier, barcodes, metadata
        case shortCode = "short_code"
        case createdAt = "created_at"
        case inspectionNotes = "inspection_notes"
        case notes
        case trackingNumber = "tracking_number"
        case receivedDate = "received_date"
        case receivedLocation = "received_location"
        case partnerName = "partner_name"
        case originalName = "original_name"
        case photoCount = "photo_count"
        case conditionRating = "condition_rating"
        case hasDamage = "has_damage"
        case inspectionResult = "inspection_result"
        case ocrText = "ocr_text"
        case discoveredUrls = "discovered_urls"
        case localFiles = "local_files"
        case storageUrl = "storage_url"
        case thumbnailUrl = "thumbnail_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Accept "code" or "short_code" from the API
        code = try container.decodeIfPresent(String.self, forKey: .code)
            ?? container.decodeIfPresent(String.self, forKey: .shortCode)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? UUID().uuidString
        id = code
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        // Build images from explicit array or from storage_url/thumbnail_url
        var imgs = try container.decodeIfPresent([IQCImage].self, forKey: .images) ?? []
        if imgs.isEmpty {
            if let storageUrl = try container.decodeIfPresent(String.self, forKey: .storageUrl), !storageUrl.isEmpty {
                let thumbUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
                imgs.append(IQCImage(id: code, url: storageUrl, thumbnailUrl: thumbUrl))
            }
        }
        images = imgs
        // Accept "inspection_notes" or "notes"
        inspectionNotes = try container.decodeIfPresent(String.self, forKey: .inspectionNotes)
            ?? container.decodeIfPresent(String.self, forKey: .notes)
        trackingNumber = try container.decodeIfPresent(String.self, forKey: .trackingNumber)
        carrier = try container.decodeIfPresent(String.self, forKey: .carrier)
        receivedDate = try container.decodeIfPresent(String.self, forKey: .receivedDate)
        receivedLocation = try container.decodeIfPresent(String.self, forKey: .receivedLocation)
        partnerName = try container.decodeIfPresent(String.self, forKey: .partnerName)
        photoCount = try container.decodeIfPresent(Int.self, forKey: .photoCount)
        conditionRating = try container.decodeIfPresent(Int.self, forKey: .conditionRating)
        hasDamage = try container.decodeIfPresent(Bool.self, forKey: .hasDamage)
        inspectionResult = try container.decodeIfPresent(String.self, forKey: .inspectionResult)
        barcodes = try container.decodeIfPresent([IQCBarcode].self, forKey: .barcodes)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        discoveredUrls = try container.decodeIfPresent([IQCDiscoveredURL].self, forKey: .discoveredUrls)
        localFiles = try container.decodeIfPresent([String].self, forKey: .localFiles)
        // Metadata may have mixed types — decode as [String: Any] then stringify
        if let metaDict = try? container.decodeIfPresent([String: String].self, forKey: .metadata) {
            metadata = metaDict
        } else if let rawMeta = try? container.decodeIfPresent([String: AnyCodableValue].self, forKey: .metadata) {
            metadata = rawMeta.mapValues { $0.stringValue }
        } else {
            metadata = nil
        }
    }

    /// Helper for decoding mixed-type metadata values.
    private struct AnyCodableValue: Decodable {
        let stringValue: String
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) { stringValue = s }
            else if let i = try? container.decode(Int.self) { stringValue = "\(i)" }
            else if let d = try? container.decode(Double.self) { stringValue = "\(d)" }
            else if let b = try? container.decode(Bool.self) { stringValue = b ? "true" : "false" }
            else if container.decodeNil() { stringValue = "" }
            else { stringValue = "" }
        }
    }

    init(code: String, status: String, createdAt: String, images: [IQCImage] = [], inspectionNotes: String? = nil,
         trackingNumber: String? = nil, carrier: String? = nil, receivedDate: String? = nil,
         receivedLocation: String? = nil, partnerName: String? = nil, photoCount: Int? = nil,
         conditionRating: Int? = nil, hasDamage: Bool? = nil, inspectionResult: String? = nil,
         barcodes: [IQCBarcode]? = nil, ocrText: String? = nil, discoveredUrls: [IQCDiscoveredURL]? = nil,
         localFiles: [String]? = nil, metadata: [String: String]? = nil) {
        self.id = code
        self.code = code
        self.status = status
        self.createdAt = createdAt
        self.images = images
        self.inspectionNotes = inspectionNotes
        self.trackingNumber = trackingNumber
        self.carrier = carrier
        self.receivedDate = receivedDate
        self.receivedLocation = receivedLocation
        self.partnerName = partnerName
        self.photoCount = photoCount
        self.conditionRating = conditionRating
        self.hasDamage = hasDamage
        self.inspectionResult = inspectionResult
        self.barcodes = barcodes
        self.ocrText = ocrText
        self.discoveredUrls = discoveredUrls
        self.localFiles = localFiles
        self.metadata = metadata
    }
}

struct IQCImage: Identifiable, Codable {
    let id: String
    let url: String
    let thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, url
        case thumbnailUrl = "thumbnail_url"
    }
}

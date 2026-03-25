import Foundation

/// Lightweight client for the Source Parts API.
/// Used by DocumentGenerator for auto-filling specs, pricing, DFM results.
class PartsAPIClient {
    static let shared = PartsAPIClient()

    private var baseURL: String { PartsConfig.shared.apiURL }

    // MARK: - Part Details

    struct PartDetails {
        var partNumber: String = ""
        var manufacturer: String = ""
        var description: String = ""
        var category: String = ""
        var specs: [(String, String)] = []
        var features: [String] = []
        var imageURL: String = ""
        var unitPrice: Double = 0
        var available: Bool = false
        var stock: Int = 0
    }

    func getPartDetails(partNumber: String) async throws -> PartDetails {
        let data = try await apiGet("/v1/components/\(partNumber.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? partNumber)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let partData = json["data"] as? [String: Any] else {
            throw APIError.invalidResponse
        }

        var details = PartDetails()
        details.partNumber = partData["mpn"] as? String ?? partNumber
        details.manufacturer = partData["manufacturer"] as? String ?? ""
        details.description = partData["description"] as? String ?? ""
        details.category = partData["category"] as? String ?? ""

        if let specsDict = partData["specifications"] as? [String: Any] {
            details.specs = specsDict.map { ($0.key, "\($0.value)") }.sorted { $0.0 < $1.0 }
        }
        if let feats = partData["features"] as? [String] {
            details.features = feats
        }
        if let img = partData["image_url"] as? String {
            details.imageURL = img
        }
        if let price = partData["unit_price"] as? Double {
            details.unitPrice = price
        }
        if let stock = partData["stock"] as? Int {
            details.stock = stock
            details.available = stock > 0
        }

        return details
    }

    // MARK: - Cost Estimation

    struct CostEstimate {
        var partNumber: String
        var unitPrice: Double
        var available: Bool
        var stock: Int
    }

    func estimateCost(parts: [(partNumber: String, quantity: Int)]) async throws -> [CostEstimate] {
        let body: [[String: Any]] = parts.map {
            ["part_number": $0.partNumber, "quantity": $0.quantity]
        }
        let data = try await apiPost("/v1/components/estimate", body: ["parts": body])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["data"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return results.map { item in
            CostEstimate(
                partNumber: item["part_number"] as? String ?? "",
                unitPrice: item["unit_price"] as? Double ?? 0,
                available: item["available"] as? Bool ?? false,
                stock: item["stock"] as? Int ?? 0
            )
        }
    }

    // MARK: - BOM Cost

    struct BOMCostResult {
        var items: [CostEstimate] = []
        var totalCost: Double = 0
        var boardQuantity: Int = 1
    }

    func calculateBOMCost(bom: [(partNumber: String, quantity: Int)], boardQuantity: Int = 1) async throws -> BOMCostResult {
        let bomItems: [[String: Any]] = bom.map {
            ["part_number": $0.partNumber, "quantity": $0.quantity]
        }
        let data = try await apiPost("/v1/bom/cost", body: ["bom": bomItems, "quantity": boardQuantity])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultData = json["data"] as? [String: Any] else {
            throw APIError.invalidResponse
        }

        var result = BOMCostResult()
        result.boardQuantity = boardQuantity
        result.totalCost = resultData["total_cost"] as? Double ?? 0

        if let items = resultData["items"] as? [[String: Any]] {
            result.items = items.map {
                CostEstimate(
                    partNumber: $0["part_number"] as? String ?? "",
                    unitPrice: $0["unit_price"] as? Double ?? 0,
                    available: $0["available"] as? Bool ?? true,
                    stock: $0["stock"] as? Int ?? 0
                )
            }
        }
        return result
    }

    // MARK: - Availability

    struct AvailabilityInfo {
        var partNumber: String
        var inStock: Bool
        var stock: Int
        var leadTime: String
    }

    func checkAvailability(partNumbers: [String]) async throws -> [AvailabilityInfo] {
        let data = try await apiPost("/v1/components/availability", body: ["part_numbers": partNumbers])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["data"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return results.map {
            AvailabilityInfo(
                partNumber: $0["part_number"] as? String ?? "",
                inStock: $0["in_stock"] as? Bool ?? false,
                stock: $0["stock"] as? Int ?? 0,
                leadTime: $0["lead_time"] as? String ?? "unknown"
            )
        }
    }

    // MARK: - DFM

    struct DFMResult {
        var jobId: String = ""
        var status: String = "pending"
        var score: Int = 0
        var checks: [(name: String, pass: Bool, detail: String)] = []
        var warnings: [String] = []
        var recommendations: [String] = []
    }

    func submitDFM(projectId: String) async throws -> String {
        let data = try await apiPost("/v1/manufacturing/dfm", body: ["project_id": projectId, "priority": "normal"])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultData = json["data"] as? [String: Any],
              let jobId = resultData["job_id"] as? String else {
            throw APIError.invalidResponse
        }
        return jobId
    }

    func checkDFMStatus(jobId: String) async throws -> DFMResult {
        let data = try await apiGet("/v1/manufacturing/dfm/\(jobId)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultData = json["data"] as? [String: Any] else {
            throw APIError.invalidResponse
        }

        var result = DFMResult()
        result.jobId = jobId
        result.status = resultData["status"] as? String ?? "unknown"
        result.score = resultData["score"] as? Int ?? 0

        if let checks = resultData["checks"] as? [[String: Any]] {
            result.checks = checks.map {
                (name: $0["name"] as? String ?? "",
                 pass: $0["pass"] as? Bool ?? false,
                 detail: $0["detail"] as? String ?? "")
            }
        }
        if let w = resultData["warnings"] as? [String] { result.warnings = w }
        if let r = resultData["recommendations"] as? [String] { result.recommendations = r }

        return result
    }

    // MARK: - Fab Quote

    struct FabQuote {
        var unitPrice: Double = 0
        var totalPrice: Double = 0
        var quantity: Int = 0
        var leadTime: String = ""
        var layers: Int = 2
    }

    func quoteFabrication(projectId: String, quantity: Int = 5, layers: Int = 2) async throws -> FabQuote {
        let data = try await apiPost("/v1/manufacturing/fab/quote", body: [
            "project_id": projectId, "quantity": quantity, "layers": layers
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultData = json["data"] as? [String: Any] else {
            throw APIError.invalidResponse
        }

        return FabQuote(
            unitPrice: resultData["unit_price"] as? Double ?? 0,
            totalPrice: resultData["total_price"] as? Double ?? 0,
            quantity: resultData["quantity"] as? Int ?? quantity,
            leadTime: resultData["lead_time"] as? String ?? "",
            layers: layers
        )
    }

    // MARK: - Search

    func searchParts(query: String, limit: Int = 10) async throws -> [PartDetails] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let data = try await apiGet("/v1/components/search?q=\(encoded)&limit=\(limit)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["data"] as? [[String: Any]] else {
            return []
        }

        return results.map { item in
            var d = PartDetails()
            d.partNumber = item["mpn"] as? String ?? ""
            d.manufacturer = item["manufacturer"] as? String ?? ""
            d.description = item["description"] as? String ?? ""
            d.category = item["category"] as? String ?? ""
            d.unitPrice = item["unit_price"] as? Double ?? 0
            if let stock = item["stock"] as? Int ?? item["stock_quantity"] as? Int {
                d.stock = stock
                d.available = stock > 0
            }
            return d
        }
    }

    // MARK: - Gather (Combined Part Data)

    struct GatheredPart {
        var part: PartDetails
        var priceBreaks: [(qty: Int, unitPrice: Double)]
        var datasheetURL: String?
        var alternatives: [(sku: String, name: String, manufacturer: String, description: String)]
    }

    func gatherPart(sku: String) async throws -> GatheredPart {
        let encoded = sku.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sku
        let data = try await apiGet("/v1/parts/\(encoded)/gather")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultData = json["data"] as? [String: Any],
              let partData = resultData["part"] as? [String: Any] else {
            throw APIError.invalidResponse
        }

        var details = PartDetails()
        details.partNumber = partData["part_number"] as? String ?? partData["name"] as? String ?? sku
        details.manufacturer = partData["manufacturer"] as? String ?? ""
        details.description = partData["description"] as? String ?? ""
        details.category = partData["category"] as? String ?? ""
        if let specsDict = partData["specifications"] as? [String: Any] {
            details.specs = specsDict.map { ($0.key, "\($0.value)") }.sorted { $0.0 < $1.0 }
        }
        if let feats = partData["features"] as? [String] {
            details.features = feats
        }
        if let img = partData["image_url"] as? String {
            details.imageURL = img
        }
        if let price = partData["unit_price"] as? Double ?? partData["price"] as? Double {
            details.unitPrice = price
        }
        if let stock = partData["stock_quantity"] as? Int ?? partData["stock"] as? Int {
            details.stock = stock
            details.available = stock > 0
        }

        // Price breaks
        var priceBreaks: [(qty: Int, unitPrice: Double)] = []
        if let pricingData = resultData["pricing"] as? [String: Any],
           let breaks = pricingData["price_breaks"] as? [[String: Any]] {
            priceBreaks = breaks.compactMap { pb in
                guard let qty = pb["quantity"] as? Int,
                      let price = pb["unit_price"] as? Double else { return nil }
                return (qty: qty, unitPrice: price)
            }
        }

        // Datasheet URL
        var datasheetURL: String?
        if let dsData = resultData["datasheet"] as? [String: Any] {
            datasheetURL = dsData["url"] as? String ?? dsData["datasheet_url"] as? String
        }

        // Alternatives
        var alternatives: [(sku: String, name: String, manufacturer: String, description: String)] = []
        if let alts = resultData["alternatives"] as? [[String: Any]] {
            alternatives = alts.map { alt in
                (sku: alt["sku"] as? String ?? "",
                 name: alt["name"] as? String ?? alt["part_number"] as? String ?? "",
                 manufacturer: alt["manufacturer"] as? String ?? "",
                 description: alt["description"] as? String ?? "")
            }
        }

        return GatheredPart(
            part: details,
            priceBreaks: priceBreaks,
            datasheetURL: datasheetURL,
            alternatives: alternatives
        )
    }

    // MARK: - HTTP Helpers

    enum APIError: LocalizedError {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key — run `parts auth login`"
            case .invalidURL: return "Invalid API URL"
            case .invalidResponse: return "Invalid API response"
            case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
            }
        }
    }

    private func apiGet(_ path: String) async throws -> Data {
        guard let apiKey = APIKeychain.loadAPIKey() else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("PartsStudio/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, msg)
        }
        return data
    }

    private func apiPost(_ path: String, body: [String: Any]) async throws -> Data {
        guard let apiKey = APIKeychain.loadAPIKey() else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PartsStudio/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, msg)
        }
        return data
    }
}

import Foundation
#if os(macOS)
import AppKit
#endif

/// Fetches IQC items from the Source Parts API, loads local JSON reports, and supports image upload.
class IQCService: ObservableObject {
    @Published var items: [IQCItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var usingLiveData = false
    @Published var uploadProgress: String?

    // MARK: - Fetch from API

    func fetchItems() async {
        await MainActor.run { isLoading = true; error = nil }

        guard let apiKey = APIKeychain.loadAPIKey() else {
            await MainActor.run {
                self.error = "No API key. Run `parts auth login` to authenticate."
                self.isLoading = false
            }
            return
        }

        guard let url = URL(string: "\(PartsConfig.shared.apiURL)/v1/ingest/items") else {
            await MainActor.run { isLoading = false }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("PartsStudio/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { isLoading = false }
                return
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                APIKeychain.clearCache()
                await MainActor.run {
                    self.error = "Session expired. Run `parts auth login` then click refresh."
                    self.isLoading = false
                }
                return
            }

            guard http.statusCode == 200 else {
                await MainActor.run {
                    self.error = "API returned HTTP \(http.statusCode)"
                    self.isLoading = false
                }
                return
            }

            let apiResp = try JSONDecoder().decode(APIResponse.self, from: data)
            // API returns items at top level or nested under data
            let fetched = apiResp.items ?? apiResp.data?.items
            if let fetched, !fetched.isEmpty {
                await MainActor.run { items = fetched; usingLiveData = true; isLoading = false }
                return
            }
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                self.error = "Could not load IQC items: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - Load Local JSON Reports

    /// Scan the IQC directory for .json report files and parse them as IQCItems.
    func loadLocalReports() {
        let iqcPath = PartsConfig.shared.iqcPath
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: iqcPath) else { return }

        var localItems: [IQCItem] = []
        for file in files where file.lowercased().hasSuffix(".json") {
            let fullPath = "\(iqcPath)/\(file)"
            guard let data = fm.contents(atPath: fullPath) else { continue }

            // Try parsing as a single IQCItem
            if let item = try? JSONDecoder().decode(IQCItem.self, from: data) {
                localItems.append(item)
                continue
            }

            // Try parsing as an array of IQCItems
            if let arr = try? JSONDecoder().decode([IQCItem].self, from: data) {
                localItems.append(contentsOf: arr)
                continue
            }

            // Try parsing as { "items": [...] } wrapper
            if let wrapper = try? JSONDecoder().decode(ItemsWrapper.self, from: data) {
                localItems.append(contentsOf: wrapper.items)
            }
        }

        if !localItems.isEmpty {
            // Merge with existing items (avoid duplicates by code)
            let existingCodes = Set(items.map(\.code))
            let newItems = localItems.filter { !existingCodes.contains($0.code) }
            items.append(contentsOf: newItems)
        }
    }

    // MARK: - Upload Images to Ingest API

    /// Upload images via file picker to POST /v1/ingest
    func uploadImages() async {
        // Show file picker on main thread
        let urls: [URL] = await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = "Select images for IQC ingest"
            panel.allowedContentTypes = [.jpeg, .png, .gif, .heic]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            guard panel.runModal() == .OK else { return [] }
            return panel.urls
        }

        guard !urls.isEmpty else { return }

        guard let apiKey = APIKeychain.loadAPIKey() else {
            await MainActor.run { self.error = "No API key. Run `parts auth login`." }
            return
        }

        await MainActor.run {
            uploadProgress = "Uploading \(urls.count) image(s)..."
            error = nil
        }

        guard let apiURL = URL(string: "\(PartsConfig.shared.apiURL)/v1/ingest") else { return }

        // Build multipart form-data
        let boundary = UUID().uuidString
        var body = Data()
        for url in urls {
            guard let fileData = try? Data(contentsOf: url) else { continue }
            let filename = url.lastPathComponent
            let mimeType = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("PartsStudio/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            await MainActor.run {
                uploadProgress = nil
                if http?.statusCode == 200 || http?.statusCode == 201 {
                    // Refresh items list
                    Task { await self.fetchItems() }
                } else {
                    let msg = String(data: data, encoding: .utf8) ?? "Upload failed"
                    self.error = "Upload failed (HTTP \(http?.statusCode ?? 0)): \(msg.prefix(200))"
                }
            }
        } catch {
            await MainActor.run {
                uploadProgress = nil
                self.error = "Upload error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - X-Ray Analysis JSON Path

    /// Path to the X-ray analysis results JSON file.
    var xrayAnalysisPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/Work/xray_analysis_results.json"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: - API Response Models

    private struct APIResponse: Decodable {
        let success: Bool?
        let status: String?
        // API may return items at top level or nested under data
        let items: [IQCItem]?
        let data: APIData?

        struct APIData: Decodable {
            let items: [IQCItem]?
        }
    }

    private struct ItemsWrapper: Decodable {
        let items: [IQCItem]
    }

    // MARK: - Sample Data (fallback)

    static let sampleItems: [IQCItem] = [
        IQCItem(code: "SP-100234", status: "accepted", createdAt: "2026-03-18",
                inspectionNotes: "All parameters within spec. Reel packaging intact, MSL-3 indicators show no moisture exposure.",
                trackingNumber: "SF1234567890", carrier: "SF Express", receivedDate: "2026-03-18 09:42 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Jixing Electronics",
                photoCount: 8, conditionRating: 5, hasDamage: false, inspectionResult: "pass",
                barcodes: [
                    IQCBarcode(data: "8901234567890", type: "ean13", confidence: 0.98),
                    IQCBarcode(data: "https://www.lcsc.com/product-detail/C404280.html", type: "qr_code", confidence: 0.95),
                ],
                ocrText: "JIXING ELECTRONICS\nP/N: USB-C-16P-WP\nLOT: 2026-03-12\nQTY: 200 PCS\nRoHS COMPLIANT\nMSL-3\nMADE IN CHINA",
                discoveredUrls: [
                    IQCDiscoveredURL(url: "https://www.lcsc.com/product-detail/C404280.html", source: "qr_code", domainType: "lcsc", crawlStatus: "crawled"),
                ],
                metadata: ["camera_make": "Sony", "camera_model": "Alpha A7III", "dimensions": "4000x3000", "date_taken": "2026-03-18 09:40:12", "file_size": "4.2 MB", "format": "JPEG"]),
        IQCItem(code: "SP-100235", status: "pending_inspection", createdAt: "2026-03-19",
                trackingNumber: "YT9876543210", carrier: "YTO Express", receivedDate: "2026-03-19 14:15 PM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "LCSC Electronics",
                photoCount: 0, inspectionResult: "pending"),
        IQCItem(code: "SP-100236", status: "rejected", createdAt: "2026-03-17",
                inspectionNotes: "Moisture sensitivity level exceeded. MSL-3 indicator triggered. Vacuum seal was compromised during shipping. Recommend return to supplier.",
                trackingNumber: "ZTO2024031700", carrier: "ZTO Express", receivedDate: "2026-03-17 11:30 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Shenzhen Huaqiang",
                photoCount: 12, conditionRating: 2, hasDamage: true, inspectionResult: "fail"),
        IQCItem(code: "SP-100237", status: "inspected", createdAt: "2026-03-18",
                inspectionNotes: "Visual inspection passed, awaiting electrical test. Component markings match datasheet. Pin count and pitch verified.",
                trackingNumber: "JD0088776655", carrier: "JD Logistics", receivedDate: "2026-03-18 16:20 PM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "DigiKey Asia",
                photoCount: 6, conditionRating: 4, hasDamage: false, inspectionResult: "partial"),
        IQCItem(code: "SP-100238", status: "accepted", createdAt: "2026-03-16",
                inspectionNotes: "Batch accepted. X-ray inspection confirms BGA ball alignment within spec.",
                trackingNumber: "EMS1122334455", carrier: "EMS", receivedDate: "2026-03-16 08:55 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Mouser Electronics",
                photoCount: 4, conditionRating: 5, hasDamage: false, inspectionResult: "pass",
                localFiles: [
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/1-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/1-2.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/2.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/2-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/3.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/3-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/4.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/4-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/5.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/5-1.bmp",
                ],
                metadata: ["inspection_type": "X-Ray", "equipment": "Dage XD7600NT", "magnification": "10x-100x"]),
        IQCItem(code: "SP-100239", status: "pending_inspection", createdAt: "2026-03-19",
                inspectionNotes: "Batch of 500 units received. Awaiting allocation to inspection queue.",
                trackingNumber: "DHL8899001122", carrier: "DHL Express", receivedDate: "2026-03-19 10:05 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Arrow Electronics",
                photoCount: 2, inspectionResult: "pending"),
    ]
}

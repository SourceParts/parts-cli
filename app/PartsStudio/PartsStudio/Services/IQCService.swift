import Foundation

/// Fetches IQC items from the Source Parts API, falling back to sample data on failure.
class IQCService: ObservableObject {
    @Published var items: [IQCItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var usingLiveData = false

    func fetchItems() async {
        await MainActor.run { isLoading = true; error = nil }

        guard let apiKey = APIKeychain.loadAPIKey() else {
            await MainActor.run { isLoading = false }
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
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { isLoading = false }
                return
            }

            let apiResp = try JSONDecoder().decode(APIResponse.self, from: data)
            if let fetched = apiResp.data?.items, !fetched.isEmpty {
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

    // MARK: - API Response

    private struct APIResponse: Decodable {
        let success: Bool
        let data: APIData?

        struct APIData: Decodable {
            let items: [IQCItem]?
        }
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

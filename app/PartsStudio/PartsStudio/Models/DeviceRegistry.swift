import Foundation

/// A registered PocketPC device identified by its SID (eFuse serial ID).
struct RegisteredDevice: Codable, Identifiable {
    var id: String { sid }
    let sid: String                     // 92c0f6ba:14304620:78f4c71c:241e0b90
    var name: String                    // "Jose's PocketPC"
    var owner: String                   // "Jose"
    var socName: String                 // "A64"
    var boardRevision: String           // "v1.2"
    var boardSerial: String             // "PP-2026-001"
    var notes: String                   // Free-form notes
    var tags: [String]                  // ["prototype", "dev-unit"]
    var hardware: HardwareProfile
    var firstSeen: Date
    var lastSeen: Date
    var bootCount: Int
    var firmwareVersion: String         // Last known firmware
    var hardwareFingerprint: String = "" // Hash of on-board IDs for change detection
    var auditLog: [AuditEntry] = []     // Numbered change history

    /// Numbered audit entry tracking interface/hardware changes.
    struct AuditEntry: Codable, Identifiable {
        var id: Int                     // Sequential number (1, 2, 3...)
        var date: Date
        var event: String               // "registered", "hardware_changed", "name_changed", etc.
        var detail: String              // Human-readable description
        var oldValue: String?           // Previous value (for changes)
        var newValue: String?           // New value (for changes)
    }

    struct HardwareProfile: Codable {
        var soc: String                 // "Allwinner A64"
        var dramSize: String            // "1GB DDR3"
        var emmc: String                // "8GB"
        var wifi: String                // "RTL8723BS"
        var display: String             // "5\" 800x480 LCD"
        var battery: String             // "3000mAh LiPo"
        var pmic: String                // "AXP803"
        var uart: String                // "WCH CH340"
        var extras: [String: String]    // Additional hardware details
    }
}

/// Persistent registry of known devices, stored as JSON.
/// Offline-first: all mutations are saved locally and queued for API sync.
/// Queued syncs are retried automatically when connectivity is available.
class DeviceRegistry: ObservableObject {
    @Published var devices: [RegisteredDevice] = []
    @Published var pendingSyncs: Int = 0

    private let registryURL: URL
    private let queueURL: URL
    private var syncQueue: [String] = []  // SIDs pending sync
    private var flushTimer: Timer?
    private var isFlushing = false

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".parts/devices")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        registryURL = dir.appendingPathComponent("registry.json")
        queueURL = dir.appendingPathComponent("sync_queue.json")
        load()
        loadQueue()
        startFlushTimer()
    }

    deinit {
        flushTimer?.invalidate()
    }

    /// Look up a device by SID.
    func lookup(sid: String) -> RegisteredDevice? {
        devices.first { $0.sid == sid }
    }

    /// Register or update a device. Returns the device.
    /// Last change detection result (published for UI).
    @Published var lastChangeWarning: String?

    @discardableResult
    func register(sid: String, socName: String) -> RegisteredDevice {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            devices[index].lastSeen = Date()
            devices[index].bootCount += 1

            // Auto-populate serial if missing (upgrade from older registry)
            if devices[index].boardSerial.isEmpty {
                devices[index].boardSerial = Self.generateSerial(sid: sid, socName: socName)
            }

            // Check for hardware changes
            let currentFingerprint = Self.computeFingerprint(sid: sid)
            if !devices[index].hardwareFingerprint.isEmpty &&
               devices[index].hardwareFingerprint != currentFingerprint {
                let msg = "Hardware fingerprint changed. A component may have been replaced."
                lastChangeWarning = "Device \(devices[index].name): \(msg)"
                appendAudit(index: index, event: "hardware_changed", detail: msg,
                           oldValue: devices[index].hardwareFingerprint, newValue: currentFingerprint)
                devices[index].hardwareFingerprint = currentFingerprint
            } else {
                lastChangeWarning = nil
            }

            // Update fingerprint
            if devices[index].hardwareFingerprint.isEmpty {
                devices[index].hardwareFingerprint = currentFingerprint
            }

            save()
            enqueueSync(sid: sid)
            return devices[index]
        }

        let serial = Self.generateSerial(sid: sid, socName: socName)
        let fingerprint = Self.computeFingerprint(sid: sid)

        let device = RegisteredDevice(
            sid: sid,
            name: "PocketPC (\(String(sid.prefix(8))))",
            owner: "",
            socName: socName,
            boardRevision: "",
            boardSerial: serial,
            notes: "",
            tags: [],
            hardware: RegisteredDevice.HardwareProfile(
                soc: "Allwinner \(socName)",
                dramSize: "",
                emmc: "",
                wifi: "",
                display: "",
                battery: "",
                pmic: "",
                uart: "",
                extras: [:]
            ),
            firstSeen: Date(),
            lastSeen: Date(),
            bootCount: 1,
            firmwareVersion: "",
            hardwareFingerprint: fingerprint,
            auditLog: [RegisteredDevice.AuditEntry(
                id: 1, date: Date(), event: "registered",
                detail: "Device first registered (SoC: \(socName), Serial: \(serial))",
                oldValue: nil, newValue: nil
            )]
        )
        devices.append(device)
        save()
        enqueueSync(sid: sid)
        return device
    }

    // MARK: - Device Serial & Fingerprint

    /// Generate a human-readable board serial from the SID.
    /// Format: PP-<SOC>-<SID_SHORT> (e.g., PP-A64-92C0F6BA)
    static func generateSerial(sid: String, socName: String) -> String {
        let short = sid.prefix(8).uppercased()
        return "PP-\(socName)-\(short)"
    }

    /// Compute a hardware fingerprint from available on-board IDs.
    /// Currently uses SID only. Post-boot, WiFi MAC and eMMC CID can be added.
    static func computeFingerprint(sid: String, wifiMAC: String? = nil, emmcCID: String? = nil) -> String {
        var components = [sid]
        if let mac = wifiMAC, !mac.isEmpty { components.append(mac) }
        if let cid = emmcCID, !cid.isEmpty { components.append(cid) }
        let input = components.joined(separator: ":")
        // Simple hash — SHA256 would be better but this avoids CryptoKit import
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }

    /// Check if hardware has changed since last registration.
    /// Returns a description of what changed, or nil if no change.
    func checkForChanges(sid: String) -> String? {
        guard let device = lookup(sid: sid) else { return nil }
        let current = Self.computeFingerprint(sid: sid)
        if !device.hardwareFingerprint.isEmpty && device.hardwareFingerprint != current {
            return "Hardware fingerprint changed (was \(device.hardwareFingerprint), now \(current))"
        }
        return nil
    }

    /// Update the fingerprint with additional hardware IDs (call after boot when more info is available).
    func updateFingerprint(sid: String, wifiMAC: String? = nil, emmcCID: String? = nil) {
        guard let index = devices.firstIndex(where: { $0.sid == sid }) else { return }
        let newFingerprint = Self.computeFingerprint(sid: sid, wifiMAC: wifiMAC, emmcCID: emmcCID)
        if !newFingerprint.isEmpty && newFingerprint != devices[index].hardwareFingerprint {
            devices[index].hardwareFingerprint = newFingerprint
            // Update hardware extras with the new IDs
            if let mac = wifiMAC, !mac.isEmpty { devices[index].hardware.wifi = mac }
            if let cid = emmcCID, !cid.isEmpty { devices[index].hardware.extras["emmc_cid"] = cid }
            save()
            enqueueSync(sid: sid)
        }
    }

    /// Update a device's metadata.
    func update(_ device: RegisteredDevice) {
        if let index = devices.firstIndex(where: { $0.sid == device.sid }) {
            devices[index] = device
            save()
            enqueueSync(sid: device.sid)
        }
    }

    /// Append an audit entry to a device's log.
    private func appendAudit(index: Int, event: String, detail: String, oldValue: String? = nil, newValue: String? = nil) {
        let nextId = (devices[index].auditLog.last?.id ?? 0) + 1
        let entry = RegisteredDevice.AuditEntry(
            id: nextId, date: Date(), event: event,
            detail: detail, oldValue: oldValue, newValue: newValue
        )
        devices[index].auditLog.append(entry)
    }

    /// Rename a device.
    func rename(sid: String, name: String) {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            let old = devices[index].name
            devices[index].name = name
            appendAudit(index: index, event: "name_changed", detail: "Renamed device", oldValue: old, newValue: name)
            save()
            enqueueSync(sid: sid)
        }
    }

    /// Set owner.
    func setOwner(sid: String, owner: String) {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            let old = devices[index].owner
            devices[index].owner = owner
            appendAudit(index: index, event: "owner_changed", detail: "Owner changed", oldValue: old, newValue: owner)
            save()
            enqueueSync(sid: sid)
        }
    }

    /// Update hardware profile.
    func setHardware(sid: String, hardware: RegisteredDevice.HardwareProfile) {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            appendAudit(index: index, event: "hardware_updated", detail: "Hardware profile updated")
            devices[index].hardware = hardware
            save()
            enqueueSync(sid: sid)
        }
    }

    // MARK: - Sync Queue (Offline-First)

    /// Add a SID to the sync queue. Deduplicates — only the latest state matters.
    /// Flush happens on the 30s timer, not eagerly, to avoid blocking device registration.
    private func enqueueSync(sid: String) {
        if !syncQueue.contains(sid) {
            syncQueue.append(sid)
            saveQueue()
        }
        pendingSyncs = syncQueue.count
    }

    /// Periodically retry queued syncs (every 30s).
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.flushQueue()
        }
    }

    /// Attempt to push all queued syncs to the API.
    func flushQueue() {
        guard !isFlushing, !syncQueue.isEmpty else { return }
        guard APIKeychain.loadAPIKey() != nil else { return }
        isFlushing = true

        let sidsToSync = syncQueue
        var remaining = sidsToSync

        func syncNext() {
            guard let sid = remaining.first else {
                // All done
                isFlushing = false
                return
            }
            remaining.removeFirst()

            pushToAPI(sid: sid) { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.syncQueue.removeAll { $0 == sid }
                    self.saveQueue()
                    self.pendingSyncs = self.syncQueue.count
                }
                syncNext()
            }
        }
        syncNext()
    }

    /// Sync a specific device (manual trigger). Queues on failure.
    func sync(sid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard lookup(sid: sid) != nil else {
            completion(.failure(NSError(domain: "DeviceRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Device not found"])))
            return
        }
        guard APIKeychain.loadAPIKey() != nil else {
            enqueueSync(sid: sid)
            completion(.failure(NSError(domain: "DeviceRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "No API key — queued for later. Run `parts auth login`."])))
            return
        }

        pushToAPI(sid: sid) { [weak self] success in
            if success {
                self?.syncQueue.removeAll { $0 == sid }
                self?.saveQueue()
                self?.pendingSyncs = self?.syncQueue.count ?? 0
                completion(.success(()))
            } else {
                self?.enqueueSync(sid: sid)
                completion(.failure(NSError(domain: "DeviceRegistry", code: 5, userInfo: [NSLocalizedDescriptionKey: "Sync failed — queued for retry"])))
            }
        }
    }

    /// Push a single device to the API. Calls back with success/failure.
    private func pushToAPI(sid: String, completion: @escaping (Bool) -> Void) {
        guard let device = lookup(sid: sid) else {
            completion(false)
            return
        }
        guard let apiKey = APIKeychain.loadAPIKey() else {
            completion(false)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase

        guard let body = try? encoder.encode(device) else {
            completion(false)
            return
        }

        let url = URL(string: "\(PartsConfig.shared.apiURL)/v1/devices/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("PartsStudio/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            DispatchQueue.main.async { completion(true) }
        }.resume()
    }

    // MARK: - Queue Persistence

    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        syncQueue = decoded
        pendingSyncs = syncQueue.count
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(syncQueue) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: registryURL),
              let decoded = try? JSONDecoder().decode([RegisteredDevice].self, from: data)
        else { return }
        devices = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(devices) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }
}

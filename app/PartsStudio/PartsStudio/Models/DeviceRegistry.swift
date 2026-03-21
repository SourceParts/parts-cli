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
class DeviceRegistry: ObservableObject {
    @Published var devices: [RegisteredDevice] = []

    private let registryURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".parts/devices")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        registryURL = dir.appendingPathComponent("registry.json")
        load()
    }

    /// Look up a device by SID.
    func lookup(sid: String) -> RegisteredDevice? {
        devices.first { $0.sid == sid }
    }

    /// Register or update a device. Returns the device.
    @discardableResult
    func register(sid: String, socName: String) -> RegisteredDevice {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            devices[index].lastSeen = Date()
            devices[index].bootCount += 1
            save()
            return devices[index]
        }

        let device = RegisteredDevice(
            sid: sid,
            name: "PocketPC (\(String(sid.prefix(8))))",
            owner: "",
            socName: socName,
            boardRevision: "",
            boardSerial: "",
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
            firmwareVersion: ""
        )
        devices.append(device)
        save()
        return device
    }

    /// Update a device's metadata.
    func update(_ device: RegisteredDevice) {
        if let index = devices.firstIndex(where: { $0.sid == device.sid }) {
            devices[index] = device
            save()
        }
    }

    /// Rename a device.
    func rename(sid: String, name: String) {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            devices[index].name = name
            save()
        }
    }

    /// Set owner.
    func setOwner(sid: String, owner: String) {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            devices[index].owner = owner
            save()
        }
    }

    /// Update hardware profile.
    func setHardware(sid: String, hardware: RegisteredDevice.HardwareProfile) {
        if let index = devices.firstIndex(where: { $0.sid == sid }) {
            devices[index].hardware = hardware
            save()
        }
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

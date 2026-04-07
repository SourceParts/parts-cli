import Foundation

/// ESLR radio variant, identified by firmware version string.
enum ESLRVariant: String, CaseIterable {
    case threadstone = "Threadstone"
    case bridgestone = "Bridgestone"
    case firestone = "Firestone"
    case unknown = "Unknown"

    /// Match variant from firmware version string (e.g. "ESP32-S3 Firmware v4.0-threadstone (BLE OTA)").
    static func from(firmwareVersion: String) -> ESLRVariant {
        let lower = firmwareVersion.lowercased()
        if lower.contains("threadstone") { return .threadstone }
        if lower.contains("bridgestone") { return .bridgestone }
        if lower.contains("firestone") { return .firestone }
        return .unknown
    }
}

/// Connection state of the ESLR serial device.
enum ESLRConnectionState: String {
    case disconnected
    case connecting
    case connected
    case error
}

/// Parsed device info from the ESP32 `info` command.
struct ESLRDeviceInfo {
    var firmwareVersion: String = ""
    var chipRevision: Int = 0
    var cores: Int = 0
    var flashSize: String = ""
    var wifiMAC: String = ""
    var freeHeap: Int = 0
    var psram: Int = 0
    var bleName: String = ""
    var variant: ESLRVariant = .unknown
    var serialPort: String = ""

    var displayName: String {
        if variant != .unknown {
            return "ESLR \(variant.rawValue)"
        }
        return "ESLR Radio"
    }

    /// Parse the multi-line output of the ESP32 `info` command.
    ///
    /// Example output:
    /// ```
    /// ESP32-S3 Firmware v4.0 (BLE OTA)
    /// Chip:      ESP32-S3 rev 0
    /// Cores:     2
    /// Flash:     external
    /// WiFi MAC:  24:EC:4A:2B:05:C8
    /// Flash sz:  4 MB
    /// Free heap: 2279963 bytes
    /// PSRAM:     2094863 bytes
    /// Partition: app0 (0x10000, 1792 KB)
    /// BLE name:  ESP32-S3-OTA
    /// BLE conn:  no (0 clients)
    /// ```
    static func parse(from text: String) -> ESLRDeviceInfo? {
        guard !text.isEmpty else { return nil }
        var info = ESLRDeviceInfo()

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Firmware version line: "ESP32-S3 Firmware v4.0 (BLE OTA)"
            if trimmed.contains("Firmware") {
                info.firmwareVersion = trimmed
                info.variant = ESLRVariant.from(firmwareVersion: trimmed)
            }

            // "Chip:      ESP32-S3 rev 0"
            if trimmed.hasPrefix("Chip:") {
                if let match = trimmed.range(of: #"rev\s+(\d+)"#, options: .regularExpression) {
                    let revStr = trimmed[match].replacingOccurrences(of: "rev", with: "").trimmingCharacters(in: .whitespaces)
                    info.chipRevision = Int(revStr) ?? 0
                }
            }

            // "Cores:     2"
            if trimmed.hasPrefix("Cores:") {
                let val = trimmed.replacingOccurrences(of: "Cores:", with: "").trimmingCharacters(in: .whitespaces)
                info.cores = Int(val) ?? 0
            }

            // "Flash sz:  4 MB"
            if trimmed.hasPrefix("Flash sz:") {
                info.flashSize = trimmed.replacingOccurrences(of: "Flash sz:", with: "").trimmingCharacters(in: .whitespaces)
            }

            // "WiFi MAC:  24:EC:4A:2B:05:C8"
            if trimmed.hasPrefix("WiFi MAC:") {
                info.wifiMAC = trimmed.replacingOccurrences(of: "WiFi MAC:", with: "").trimmingCharacters(in: .whitespaces)
            }

            // "Free heap: 2279963 bytes"
            if trimmed.hasPrefix("Free heap:") {
                let val = trimmed.replacingOccurrences(of: "Free heap:", with: "")
                    .replacingOccurrences(of: "bytes", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.freeHeap = Int(val) ?? 0
            }

            // "PSRAM:     2094863 bytes"
            if trimmed.hasPrefix("PSRAM:") && trimmed.contains("bytes") {
                let val = trimmed.replacingOccurrences(of: "PSRAM:", with: "")
                    .replacingOccurrences(of: "bytes", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.psram = Int(val) ?? 0
            }

            // "BLE name:  ESP32-S3-OTA"
            if trimmed.hasPrefix("BLE name:") {
                info.bleName = trimmed.replacingOccurrences(of: "BLE name:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // Must have at least a MAC or firmware to be considered valid
        guard !info.wifiMAC.isEmpty || !info.firmwareVersion.isEmpty else { return nil }
        return info
    }
}

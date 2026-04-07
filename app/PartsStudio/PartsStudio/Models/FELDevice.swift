import Foundation

/// Connection state of the FEL device.
enum FELConnectionState: String {
    case disconnected
    case connecting
    case connected
    case error
}

/// Parsed response from AW_FEL_VERSION command (32 bytes).
struct FELVersion {
    let signature: String   // 8-byte ASCII signature (e.g. "AWUSBFEX")
    let socId: UInt32       // SoC ID (shifted from bytes 8-11)
    let firmware: UInt32    // Unknown field at offset 12
    let protocolVersion: UInt16
    let scratchpad: UInt32
    let padBytes: (UInt32, UInt32)

    /// Parse from raw 32-byte response data.
    init?(data: Data) {
        guard data.count >= 32 else { return nil }

        signature = String(data: data[0..<8], encoding: .ascii) ?? ""

        socId = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 8, as: UInt32.self).littleEndian >> 8
        }

        firmware = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 12, as: UInt32.self).littleEndian
        }

        protocolVersion = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 16, as: UInt16.self).littleEndian
        }

        scratchpad = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 20, as: UInt32.self).littleEndian
        }

        padBytes = data.withUnsafeBytes { ptr in
            (ptr.load(fromByteOffset: 24, as: UInt32.self).littleEndian,
             ptr.load(fromByteOffset: 28, as: UInt32.self).littleEndian)
        }
    }

    var socIdHex: String {
        String(format: "%x", socId)
    }
}

/// Combined device info after connecting: version + SoC info + SID.
struct FELDeviceInfo {
    let version: FELVersion
    let socInfo: SoCInfo
    var sid: String?

    var displayName: String {
        socInfo.name
    }
}

import Foundation

/// SRAM swap buffer entry — describes a memory region that must be swapped
/// during SPL execution to avoid clobbering FEL stacks.
struct SRAMSwapBuffer {
    let buf1: UInt32   // BROM buffer address
    let buf2: UInt32   // Backup storage address
    let size: UInt32   // Buffer size in bytes

    /// Serialize to 12-byte little-endian Data for the thunk code.
    var data: Data {
        var d = Data(count: 12)
        d.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: buf1.littleEndian, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: buf2.littleEndian, toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: size.littleEndian, toByteOffset: 8, as: UInt32.self)
        }
        return d
    }
}

/// Information about an Allwinner SoC, parsed from soc_info_table.json.
struct SoCInfo {
    let socId: UInt32
    let name: String
    let splAddr: UInt32
    let scratchAddr: UInt32
    let thunkAddr: UInt32
    let thunkSize: UInt32
    let needsL2EN: Bool
    let mmuTTAddr: UInt32
    let sidBase: UInt32
    let sidOffset: UInt32
    let rvbarReg: UInt32
    let sidFix: Bool
    let needsSMCWorkaroundAddr: UInt32
    let swapBuffers: [SRAMSwapBuffer]
}

/// Parses the bundled soc_info_table.json and resolves swap buffer names
/// to concrete SRAMSwapBuffer arrays.
enum SoCInfoTable {
    /// All known SoC entries keyed by hex ID string (e.g. "1689" for A64).
    private(set) static var entries: [String: SoCInfo] = {
        loadTable()
    }()

    /// Look up SoC info by the numeric ID from FEL version response.
    static func lookup(socId: UInt32) -> SoCInfo? {
        let key = String(socId, radix: 16)
        return entries[key]
    }

    // MARK: - Swap buffer definitions

    private static let swapBufferSets: [String: [SRAMSwapBuffer]] = [
        "a10_a13_a20": [
            SRAMSwapBuffer(buf1: 0x1C00, buf2: 0xA400, size: 0x0400),
            SRAMSwapBuffer(buf1: 0x5C00, buf2: 0xA800, size: 0x1400),
            SRAMSwapBuffer(buf1: 0x7C00, buf2: 0xBC00, size: 0x0400),
        ],
        "a31": [
            SRAMSwapBuffer(buf1: 0x1800, buf2: 0x20000, size: 0x800),
            SRAMSwapBuffer(buf1: 0x5C00, buf2: 0x20800, size: 0x8000 - 0x5C00),
        ],
        "a64": [
            SRAMSwapBuffer(buf1: 0x11C00, buf2: 0x1A400, size: 0x0400),
            SRAMSwapBuffer(buf1: 0x15C00, buf2: 0x1A800, size: 0x1400),
            SRAMSwapBuffer(buf1: 0x17C00, buf2: 0x1BC00, size: 0x0400),
        ],
        "ar100_abusing": [
            SRAMSwapBuffer(buf1: 0x1800, buf2: 0x44000, size: 0x800),
            SRAMSwapBuffer(buf1: 0x5C00, buf2: 0x44800, size: 0x8000 - 0x5C00),
        ],
        "a80": [
            SRAMSwapBuffer(buf1: 0x11800, buf2: 0x20000, size: 0x800),
            SRAMSwapBuffer(buf1: 0x15400, buf2: 0x20800, size: 0x18000 - 0x15400),
        ],
        "h6": [
            SRAMSwapBuffer(buf1: 0x21C00, buf2: 0x2A400, size: 0x0400),
            SRAMSwapBuffer(buf1: 0x25C00, buf2: 0x2A800, size: 0x1400),
            SRAMSwapBuffer(buf1: 0x27C00, buf2: 0x2BC00, size: 0x0400),
        ],
    ]

    private static func parseHex(_ s: String) -> UInt32 {
        let cleaned = s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s
        return UInt32(cleaned, radix: 16) ?? 0
    }

    private static func loadTable() -> [String: SoCInfo] {
        guard let url = Bundle.module.url(forResource: "soc_info_table", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else {
            return [:]
        }

        var result: [String: SoCInfo] = [:]
        for (key, entry) in json {
            let swapName = entry["swap_buffers"] as? String ?? ""
            let info = SoCInfo(
                socId: parseHex(entry["soc_id"] as? String ?? "0"),
                name: entry["name"] as? String ?? "Unknown",
                splAddr: parseHex(entry["spl_addr"] as? String ?? "0"),
                scratchAddr: parseHex(entry["scratch_addr"] as? String ?? "0x1000"),
                thunkAddr: parseHex(entry["thunk_addr"] as? String ?? "0"),
                thunkSize: parseHex(entry["thunk_size"] as? String ?? "0"),
                needsL2EN: entry["needs_l2en"] as? Bool ?? false,
                mmuTTAddr: parseHex(entry["mmu_tt_addr"] as? String ?? "0"),
                sidBase: parseHex(entry["sid_base"] as? String ?? "0"),
                sidOffset: parseHex(entry["sid_offset"] as? String ?? "0"),
                rvbarReg: parseHex(entry["rvbar_reg"] as? String ?? "0"),
                sidFix: entry["sid_fix"] as? Bool ?? false,
                needsSMCWorkaroundAddr: parseHex(entry["needs_smc_workaround_if_zero_word_at_addr"] as? String ?? "0"),
                swapBuffers: swapBufferSets[swapName] ?? []
            )
            result[key] = info
        }
        return result
    }
}

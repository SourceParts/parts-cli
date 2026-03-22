import Foundation

/// Validates memory addresses before FEL read/write operations.
/// Prevents accidental writes to BROM, FEL stacks, PMIC registers,
/// and other protected memory regions.
enum FELAddressValidator {
    struct MemoryRegion {
        let start: UInt32
        let end: UInt32
        let name: String
    }

    /// Protected regions that must never be written to.
    static let protectedRegions: [MemoryRegion] = [
        MemoryRegion(start: 0xFFFF0000, end: 0xFFFFFFFF, name: "BROM (high vectors)"),
        MemoryRegion(start: 0xFFF00000, end: 0xFFF0FFFF, name: "BROM"),
    ]

    /// Protected regions for A10/A13/A20 family (FEL stacks in SRAM).
    static let a10FamilyProtected: [MemoryRegion] = [
        MemoryRegion(start: 0x1C00, end: 0x2000, name: "IRQ stack"),
        MemoryRegion(start: 0x5C00, end: 0x7000, name: "FEL stack"),
        MemoryRegion(start: 0x7C00, end: 0x8000, name: "FEL data"),
    ]

    /// Safe memory regions by SoC type.
    static func safeRegions(for soc: SoCInfo) -> [MemoryRegion] {
        var regions: [MemoryRegion] = []

        // SRAM A (varies by SoC)
        if soc.splAddr > 0 {
            regions.append(MemoryRegion(
                start: soc.splAddr,
                end: soc.splAddr + 0x8000,
                name: "SRAM A"
            ))
        } else {
            regions.append(MemoryRegion(start: 0x0000, end: 0x8000, name: "SRAM A"))
        }

        // SRAM C (if thunk is beyond SRAM A)
        if soc.thunkAddr > 0x10000 {
            regions.append(MemoryRegion(
                start: soc.thunkAddr & 0xFFFFF000,
                end: (soc.thunkAddr & 0xFFFFF000) + 0x10000,
                name: "SRAM C"
            ))
        }

        // DRAM (0x40000000 - 0xBFFFFFFF)
        regions.append(MemoryRegion(start: 0x40000000, end: 0xC0000000, name: "DRAM"))

        return regions
    }

    enum ValidationResult {
        case safe
        case protected(String)
        case unmapped
    }

    /// Validate an address range for read access.
    static func validateRead(address: UInt32, length: UInt32, soc: SoCInfo) -> ValidationResult {
        // Allow reads from peripheral space (SID, etc.)
        if address >= 0x01C00000 && address < 0x02000000 { return .safe }
        if address >= 0x03000000 && address < 0x04000000 { return .safe }

        return validateAccess(address: address, length: length, soc: soc)
    }

    /// Validate an address range for write access.
    static func validateWrite(address: UInt32, length: UInt32, soc: SoCInfo) -> ValidationResult {
        for region in protectedRegions {
            if overlaps(address, length, region.start, region.end) {
                return .protected(region.name)
            }
        }

        // Allow writes to peripheral MMIO space (PIO, CCU, UART registers)
        // Required for GPIO pin config, UART init, backlight, etc.
        if address >= 0x01C00000 && (address &+ length) <= 0x02000000 { return .safe }

        return validateAccess(address: address, length: length, soc: soc)
    }

    private static func validateAccess(address: UInt32, length: UInt32, soc: SoCInfo) -> ValidationResult {
        let safe = safeRegions(for: soc)
        let end = address &+ length

        for region in safe {
            if address >= region.start && end <= region.end {
                return .safe
            }
        }

        // Scratch addr is always safe
        if address >= soc.scratchAddr && end <= soc.scratchAddr + 0x1000 {
            return .safe
        }

        return .unmapped
    }

    private static func overlaps(_ addr: UInt32, _ len: UInt32, _ start: UInt32, _ end: UInt32) -> Bool {
        let addrEnd = addr &+ len
        return addr < end && addrEnd > start
    }
}

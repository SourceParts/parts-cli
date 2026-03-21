import Foundation

/// Direct peripheral control via ARM thunk code executed through FEL.
/// Reads/writes Allwinner A64 memory-mapped I/O registers.
extension FELService {

    // MARK: - Register Read/Write

    /// Read a 32-bit register at the given MMIO address.
    func readRegister(address: UInt32, completion: @escaping (Result<UInt32, Error>) -> Void) {
        readMemory(address: address, length: 4) { result in
            switch result {
            case .success(let data):
                let value = data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
                completion(.success(value))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Write a 32-bit value to an MMIO register.
    func writeRegister(address: UInt32, value: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        var data = Data(count: 4)
        data.withUnsafeMutableBytes { $0.storeBytes(of: value.littleEndian, as: UInt32.self) }
        writeMemory(address: address, data: data, completion: completion)
    }

    // MARK: - GPIO Control (A64)

    /// A64 GPIO base addresses
    static let gpioBase: UInt32 = 0x01C20800
    static let gpioPorts = ["B", "C", "D", "E", "F", "G", "H", "L"]

    /// GPIO port register offsets (each port is 0x24 apart)
    static func gpioPortBase(_ port: Int) -> UInt32 {
        gpioBase + UInt32(port) * 0x24
    }

    /// Read GPIO port configuration and data.
    func readGPIOPort(port: Int, completion: @escaping (Result<GPIOPortState, Error>) -> Void) {
        let base = Self.gpioPortBase(port)
        // Read CFG0, CFG1, CFG2, CFG3, DATA (5 registers, 20 bytes)
        readMemory(address: base, length: 20) { result in
            switch result {
            case .success(let data):
                let state = data.withUnsafeBytes { ptr -> GPIOPortState in
                    GPIOPortState(
                        cfg0: ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian,
                        cfg1: ptr.load(fromByteOffset: 4, as: UInt32.self).littleEndian,
                        cfg2: ptr.load(fromByteOffset: 8, as: UInt32.self).littleEndian,
                        cfg3: ptr.load(fromByteOffset: 12, as: UInt32.self).littleEndian,
                        data: ptr.load(fromByteOffset: 16, as: UInt32.self).littleEndian,
                        port: port
                    )
                }
                completion(.success(state))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Set a GPIO pin high or low.
    func setGPIOPin(port: Int, pin: Int, high: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let dataReg = Self.gpioPortBase(port) + 0x10
        readRegister(address: dataReg) { [weak self] result in
            switch result {
            case .success(let current):
                let newValue = high ? (current | (1 << pin)) : (current & ~(1 << pin))
                self?.writeRegister(address: dataReg, value: newValue, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Configure a GPIO pin function (0=input, 1=output, 2-7=alt functions).
    func configureGPIOPin(port: Int, pin: Int, function: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        let cfgRegIndex = pin / 8
        let cfgReg = Self.gpioPortBase(port) + UInt32(cfgRegIndex) * 4
        let bitOffset = (pin % 8) * 4

        readRegister(address: cfgReg) { [weak self] result in
            switch result {
            case .success(let current):
                var newValue = current
                newValue &= ~(0xF << bitOffset)         // clear bits
                newValue |= (function & 0x7) << bitOffset // set function
                self?.writeRegister(address: cfgReg, value: newValue, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - UART Status

    /// A64 UART base addresses
    static let uartBases: [UInt32] = [
        0x01C28000, // UART0
        0x01C28400, // UART1
        0x01C28800, // UART2
        0x01C28C00, // UART3
        0x01C29000, // UART4
    ]

    /// Read UART line status register (LSR).
    func readUARTStatus(uart: Int, completion: @escaping (Result<UARTStatus, Error>) -> Void) {
        guard uart < Self.uartBases.count else {
            completion(.failure(FELError.protocolError("Invalid UART \(uart)")))
            return
        }
        let lsr = Self.uartBases[uart] + 0x14
        readRegister(address: lsr) { result in
            switch result {
            case .success(let value):
                completion(.success(UARTStatus(lsr: value, uart: uart)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - CCU (Clock Control Unit)

    /// Read the PLL_CPUX control register to get CPU frequency info.
    func readCPUClock(completion: @escaping (Result<UInt32, Error>) -> Void) {
        readRegister(address: 0x01C20000, completion: completion) // PLL_CPUX_CTRL
    }
}

// MARK: - Peripheral State Types

struct GPIOPortState {
    let cfg0: UInt32
    let cfg1: UInt32
    let cfg2: UInt32
    let cfg3: UInt32
    let data: UInt32
    let port: Int

    var portName: String { FELService.gpioPorts[port] }

    /// Get the function of a specific pin (0-31).
    func pinFunction(_ pin: Int) -> UInt32 {
        let cfgRegIndex = pin / 8
        let cfg: UInt32
        switch cfgRegIndex {
        case 0: cfg = cfg0
        case 1: cfg = cfg1
        case 2: cfg = cfg2
        default: cfg = cfg3
        }
        return (cfg >> ((pin % 8) * 4)) & 0x7
    }

    /// Get the data bit of a specific pin.
    func pinValue(_ pin: Int) -> Bool {
        (data >> pin) & 1 == 1
    }

    /// Human-readable function name.
    static func functionName(_ f: UInt32) -> String {
        switch f {
        case 0: return "IN"
        case 1: return "OUT"
        case 7: return "DIS"
        default: return "ALT\(f)"
        }
    }
}

struct UARTStatus {
    let lsr: UInt32
    let uart: Int

    var dataReady: Bool { lsr & 0x01 != 0 }
    var overrunError: Bool { lsr & 0x02 != 0 }
    var parityError: Bool { lsr & 0x04 != 0 }
    var framingError: Bool { lsr & 0x08 != 0 }
    var breakInterrupt: Bool { lsr & 0x10 != 0 }
    var txHoldingEmpty: Bool { lsr & 0x20 != 0 }
    var txEmpty: Bool { lsr & 0x40 != 0 }
    var fifoError: Bool { lsr & 0x80 != 0 }

    var summary: String {
        "UART\(uart) LSR=0x\(String(format: "%02x", lsr)): " +
        (dataReady ? "RX_RDY " : "") +
        (txHoldingEmpty ? "TX_RDY " : "") +
        (overrunError ? "OVR " : "") +
        (framingError ? "FRM " : "")
    }
}

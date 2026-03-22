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

    /// Write a 32-bit value to an MMIO register via ARM thunk.
    /// FEL's bulk write (awFELWrite) doesn't reliably write to MMIO peripherals.
    /// Instead, we load a tiny ARM program that does `str r1, [r0]; bx lr`.
    func writeRegister(address: UInt32, value: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        // ARM thunk: ldr r0, =addr; ldr r1, =val; str r1, [r0]; bx lr
        // PC-relative: at offset 0, PC=8. Load from offset 16: [pc, #8]
        //              at offset 4, PC=12. Load from offset 20: [pc, #8]
        var thunk = Data(count: 24)
        thunk.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(0xe59f0008).littleEndian, toByteOffset: 0, as: UInt32.self)  // ldr r0, [pc, #8] → offset 16
            ptr.storeBytes(of: UInt32(0xe59f1008).littleEndian, toByteOffset: 4, as: UInt32.self)  // ldr r1, [pc, #8] → offset 20
            ptr.storeBytes(of: UInt32(0xe5801000).littleEndian, toByteOffset: 8, as: UInt32.self)  // str r1, [r0]
            ptr.storeBytes(of: UInt32(0xe12fff1e).littleEndian, toByteOffset: 12, as: UInt32.self) // bx lr
            ptr.storeBytes(of: address.littleEndian, toByteOffset: 16, as: UInt32.self)            // .word address
            ptr.storeBytes(of: value.littleEndian, toByteOffset: 20, as: UInt32.self)              // .word value
        }
        runThunkNoRead(code: thunk, completion: completion)
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
            guard let self = self else { completion(.failure(FELError.deviceNotFound)); return }
            switch result {
            case .success(let current):
                var newValue = current
                newValue &= ~(0xF << bitOffset)         // clear bits
                newValue |= (function & 0x7) << bitOffset // set function
                self.appendLog("  GPIO: 0x\(String(format: "%08x", cfgReg)) read=0x\(String(format: "%08x", current)) write=0x\(String(format: "%08x", newValue))")
                self.writeRegister(address: cfgReg, value: newValue) { result in
                    if case .failure(let err) = result {
                        self.appendLog("  GPIO write FAILED: \(err)")
                    }
                    completion(result)
                }
            case .failure(let error):
                self.appendLog("  GPIO read FAILED: \(error)")
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

    // MARK: - UART Register Offsets

    private static let UART_RBR_THR: UInt32 = 0x00  // Receive Buffer (read) / Transmit Holding (write) / DLL (DLAB=1)
    private static let UART_DLH_IER: UInt32 = 0x04  // Divisor Latch High (DLAB=1) / Interrupt Enable (DLAB=0)
    private static let UART_FCR:     UInt32 = 0x08  // FIFO Control (write-only)
    private static let UART_LCR:     UInt32 = 0x0C  // Line Control
    private static let UART_LSR:     UInt32 = 0x14  // Line Status

    // GPIO port hardware indices (Port A=0, B=1, C=2, ... H=7)
    // Note: gpioPortBase uses these directly: base + portIndex * 0x24
    // Port A at 0x01C20800, Port B at 0x01C20824, etc.

    // UART2 (GPS): PB0=TX, PB1=RX — Port B = hardware index 1, function 2
    private static let UART2_PORT: Int = 1
    private static let UART2_TX_PIN: Int = 0
    private static let UART2_RX_PIN: Int = 1
    private static let UART2_PINMUX: UInt32 = 2

    // UART3 (LoRa): PH4=TX, PH5=RX — Port H = hardware index 7, function 2
    // PocketPC uses custom uart3_lora_pins on PH4/PH5, NOT default PH0/PH1
    private static let UART3_PORT: Int = 7
    private static let UART3_TX_PIN: Int = 4   // PH4 = UART3_TX
    private static let UART3_RX_PIN: Int = 5   // PH5 = UART3_RX
    private static let UART3_PINMUX: UInt32 = 2 // function 2 per A64 datasheet Table 4-2

    // RAK4200 reset: PG10 — Port G = hardware index 6, pin 10
    static let RAK_RESET_PORT: Int = 6
    static let RAK_RESET_PIN: Int = 10

    // MARK: - UART Initialization

    /// CCU register for PIO (GPIO) clock and reset.
    private static let CCU_BUS_CLK_GATE2: UInt32 = 0x01C2_0068
    private static let CCU_BUS_SOFT_RST2: UInt32 = 0x01C2_02D0
    private static let PIO_CCU_BIT: UInt32 = 5 // PIO gate/reset is bit 5

    /// Compute baud rate divisor for 24MHz oscillator.
    private static func uartDivisor(baud: UInt32) -> UInt32 {
        (24_000_000 + (8 * baud)) / (16 * baud) // rounded
    }

    /// Ensure PIO (GPIO controller) clock is enabled and reset is deasserted.
    /// Required before writing to any GPIO port configuration registers.
    func ensurePIOEnabled(completion: @escaping (Result<Void, Error>) -> Void) {
        // Enable PIO clock gate (bit 5 of BUS_CLK_GATING_REG2)
        readRegister(address: Self.CCU_BUS_CLK_GATE2) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err): completion(.failure(err)); return
            case .success(let val):
                self.writeRegister(address: Self.CCU_BUS_CLK_GATE2, value: val | (1 << Self.PIO_CCU_BIT)) { result in
                    if case .failure(let err) = result { completion(.failure(err)); return }

                    // Deassert PIO reset (bit 5 of BUS_SOFT_RST_REG2)
                    self.readRegister(address: Self.CCU_BUS_SOFT_RST2) { result in
                        switch result {
                        case .failure(let err): completion(.failure(err)); return
                        case .success(let val):
                            self.writeRegister(address: Self.CCU_BUS_SOFT_RST2, value: val | (1 << Self.PIO_CCU_BIT), completion: completion)
                        }
                    }
                }
            }
        }
    }

    /// Initialize a UART controller: enable PIO, enable clock, deassert reset, configure pins, set baud rate.
    func initUART(uart: Int, baud: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        guard uart >= 0 && uart < Self.uartBases.count else {
            completion(.failure(FELError.protocolError("Invalid UART \(uart)")))
            return
        }

        let base = Self.uartBases[uart]
        let ccuBit = UInt32(16 + uart) // UART0=bit16, UART1=bit17, etc.

        // Step 0: Ensure PIO (GPIO controller) is enabled
        ensurePIOEnabled { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result { completion(.failure(err)); return }

        // Step 1: Enable UART clock gate
        self.readRegister(address: Self.CCU_BUS_CLK_GATE3) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err): completion(.failure(err)); return
            case .success(let val):
                self.writeRegister(address: Self.CCU_BUS_CLK_GATE3, value: val | (1 << ccuBit)) { result in
                    if case .failure(let err) = result { completion(.failure(err)); return }

                    // Step 2: Deassert reset
                    self.readRegister(address: Self.CCU_BUS_SOFT_RST4) { result in
                        switch result {
                        case .failure(let err): completion(.failure(err)); return
                        case .success(let val):
                            self.writeRegister(address: Self.CCU_BUS_SOFT_RST4, value: val | (1 << ccuBit)) { result in
                                if case .failure(let err) = result { completion(.failure(err)); return }

                                // Step 3: Configure GPIO pins
                                self.configureUARTPins(uart: uart) {
                                    // Step 4: Set baud rate (LCR DLAB=1, write divisor, clear DLAB)
                                    let divisor = Self.uartDivisor(baud: baud)
                                    self.writeRegister(address: base + Self.UART_LCR, value: 0x83) { result in // 8N1 + DLAB
                                        if case .failure(let err) = result { completion(.failure(err)); return }
                                        self.writeRegister(address: base + Self.UART_RBR_THR, value: divisor & 0xFF) { result in // DLL
                                            if case .failure(let err) = result { completion(.failure(err)); return }
                                            self.writeRegister(address: base + Self.UART_DLH_IER, value: (divisor >> 8) & 0xFF) { result in // DLH
                                                if case .failure(let err) = result { completion(.failure(err)); return }

                                                // Step 5: Clear DLAB, set 8N1
                                                self.writeRegister(address: base + Self.UART_LCR, value: 0x03) { result in
                                                    if case .failure(let err) = result { completion(.failure(err)); return }

                                                    // Step 6: Enable + reset FIFOs
                                                    self.writeRegister(address: base + Self.UART_FCR, value: 0x07) { result in
                                                        if case .failure(let err) = result { completion(.failure(err)); return }

                                                        // Step 7: Disable interrupts
                                                        self.writeRegister(address: base + Self.UART_DLH_IER, value: 0x00, completion: completion)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        } // ensurePIOEnabled
    }

    /// Configure GPIO pins for UART TX/RX.
    private func configureUARTPins(uart: Int, completion: @escaping () -> Void) {
        switch uart {
        case 2:
            // UART2: PB0=TX (func 2), PB1=RX (func 2)
            configureGPIOPin(port: Self.UART2_PORT, pin: Self.UART2_TX_PIN, function: Self.UART2_PINMUX) { [weak self] _ in
                self?.configureGPIOPin(port: Self.UART2_PORT, pin: Self.UART2_RX_PIN, function: Self.UART2_PINMUX) { _ in
                    completion()
                }
            }
        case 3:
            // UART3: PH4=TX (func 2), PH5=RX (func 2)
            appendLog("  Pin config: PH\(Self.UART3_TX_PIN)=func\(Self.UART3_PINMUX), PH\(Self.UART3_RX_PIN)=func\(Self.UART3_PINMUX)")
            configureGPIOPin(port: Self.UART3_PORT, pin: Self.UART3_TX_PIN, function: Self.UART3_PINMUX) { [weak self] result in
                if case .failure(let err) = result { self?.appendLog("  PH\(Self.UART3_TX_PIN) config failed: \(err)") }
                self?.configureGPIOPin(port: Self.UART3_PORT, pin: Self.UART3_RX_PIN, function: Self.UART3_PINMUX) { result in
                    if case .failure(let err) = result { self?.appendLog("  PH\(Self.UART3_RX_PIN) config failed: \(err)") }
                    completion()
                }
            }
        default:
            completion()
        }
    }

    // MARK: - UART RX/TX via Precompiled ARM Thunks
    //
    // Source: Resources/thunks/uart_rx.S, uart_tx.S
    // Compiled: arm-none-eabi-as + objcopy -O binary
    // The literal pool values are patched at runtime before execution.

    // RX thunk: 104 bytes (code 0x00-0x53, literal pool 0x54-0x67)
    // Literal pool offsets for patching:
    //   0x54: UART base address
    //   0x58: max bytes
    //   0x5C: timeout loops
    //   0x60: buffer address (absolute)
    //   0x64: count address (absolute)
    // Result: [countAddr] = byte count, [bufferAddr...] = data
    private static let rxThunkCode: [UInt8] = [
        0x4c, 0x00, 0x9f, 0xe5, 0x4c, 0x10, 0x9f, 0xe5,  // ldr r0-r1 from pool
        0x4c, 0x20, 0x9f, 0xe5, 0x4c, 0x30, 0x9f, 0xe5,  // ldr r2-r3 from pool
        0x4c, 0x60, 0x9f, 0xe5, 0x00, 0x40, 0xa0, 0xe3,  // ldr r6, mov r4=#0
        0x02, 0x50, 0xa0, 0xe1, 0x14, 0x70, 0x90, 0xe5,  // mov r5=r2, ldr r7=[r0+0x14]
        0x01, 0x00, 0x17, 0xe3, 0x06, 0x00, 0x00, 0x0a,  // tst r7,#1, beq rx_no_data
        0x00, 0x70, 0x90, 0xe5, 0x04, 0x70, 0xc3, 0xe7,  // ldr r7=[r0], strb r7,[r3,r4]
        0x01, 0x40, 0x84, 0xe2, 0x02, 0x50, 0xa0, 0xe1,  // add r4,#1, mov r5=r2
        0x01, 0x00, 0x54, 0xe1, 0xf6, 0xff, 0xff, 0xba,  // cmp r4,r1, blt rx_loop
        0x01, 0x00, 0x00, 0xea, 0x01, 0x50, 0x55, 0xe2,  // b rx_done, subs r5,#1
        0xf3, 0xff, 0xff, 0x1a, 0x00, 0x40, 0x86, 0xe5,  // bne rx_loop, str r4,[r6]
        0x1e, 0xff, 0x2f, 0xe1,                            // bx lr
    ]
    private static let rxThunkSize = 0x54       // code ends here, literal pool starts
    private static let rxPoolUartBase  = 0x54   // patch offsets within thunk data
    private static let rxPoolMaxBytes  = 0x58
    private static let rxPoolTimeout   = 0x5C
    private static let rxPoolBufAddr   = 0x60
    private static let rxPoolCntAddr   = 0x64
    private static let rxPoolEnd       = 0x68   // total thunk + pool size
    // After the thunk+pool, we leave space for: count (4 bytes) + buffer (maxBytes)
    private static let rxCountOffset: UInt32 = 0x68   // where count is stored
    private static let rxBufferOffset: UInt32 = 0x6C  // where buffer data starts

    // TX thunk: 68 bytes (code 0x00-0x37, literal pool 0x38-0x43)
    // Literal pool offsets for patching:
    //   0x38: UART base address
    //   0x3C: byte count
    //   0x40: data buffer address (absolute)
    // TX data follows immediately at 0x44.
    private static let txThunkCode: [UInt8] = [
        0x30, 0x00, 0x9f, 0xe5, 0x30, 0x10, 0x9f, 0xe5,  // ldr r0-r1 from pool
        0x30, 0x20, 0x9f, 0xe5, 0x00, 0x30, 0xa0, 0xe3,  // ldr r2, mov r3=#0
        0x01, 0x00, 0x53, 0xe1, 0x06, 0x00, 0x00, 0xaa,  // cmp r3,r1, bge tx_done
        0x14, 0x40, 0x90, 0xe5, 0x20, 0x00, 0x14, 0xe3,  // ldr r4=[r0+0x14], tst r4,#0x20
        0xfc, 0xff, 0xff, 0x0a, 0x03, 0x40, 0xd2, 0xe7,  // beq tx_wait, ldrb r4,[r2,r3]
        0x00, 0x40, 0x80, 0xe5, 0x01, 0x30, 0x83, 0xe2,  // str r4,[r0], add r3,#1
        0xf6, 0xff, 0xff, 0xea, 0x1e, 0xff, 0x2f, 0xe1,  // b tx_loop, bx lr
    ]
    private static let txThunkSize = 0x38       // code ends here, literal pool starts
    private static let txPoolUartBase  = 0x38   // patch offsets
    private static let txPoolByteCount = 0x3C
    private static let txPoolDataAddr  = 0x40
    private static let txDataOffset    = 0x44   // TX payload starts here

    /// Build RX thunk image: precompiled code + patched literal pool.
    private static func buildRXThunk(uartBase: UInt32, maxBytes: UInt32, timeoutLoops: UInt32, scratchAddr: UInt32) -> Data {
        let countAddr = scratchAddr + rxCountOffset
        let bufferAddr = scratchAddr + rxBufferOffset
        let totalSize = Int(rxBufferOffset + maxBytes)
        var image = Data(count: totalSize)

        // Copy precompiled code
        image.replaceSubrange(0..<rxThunkCode.count, with: rxThunkCode)

        // Patch literal pool
        image.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: uartBase.littleEndian, toByteOffset: rxPoolUartBase, as: UInt32.self)
            ptr.storeBytes(of: maxBytes.littleEndian, toByteOffset: rxPoolMaxBytes, as: UInt32.self)
            ptr.storeBytes(of: timeoutLoops.littleEndian, toByteOffset: rxPoolTimeout, as: UInt32.self)
            ptr.storeBytes(of: bufferAddr.littleEndian, toByteOffset: rxPoolBufAddr, as: UInt32.self)
            ptr.storeBytes(of: countAddr.littleEndian, toByteOffset: rxPoolCntAddr, as: UInt32.self)
        }

        return image
    }

    /// Build TX thunk image: precompiled code + patched literal pool + data payload.
    private static func buildTXThunk(uartBase: UInt32, data: Data, scratchAddr: UInt32) -> Data {
        let dataAddr = scratchAddr + UInt32(txDataOffset)
        let totalSize = txDataOffset + data.count
        var image = Data(count: totalSize)

        // Copy precompiled code
        image.replaceSubrange(0..<txThunkCode.count, with: txThunkCode)

        // Patch literal pool
        image.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: uartBase.littleEndian, toByteOffset: txPoolUartBase, as: UInt32.self)
            ptr.storeBytes(of: UInt32(data.count).littleEndian, toByteOffset: txPoolByteCount, as: UInt32.self)
            ptr.storeBytes(of: dataAddr.littleEndian, toByteOffset: txPoolDataAddr, as: UInt32.self)
        }

        // Append TX data payload
        if !data.isEmpty {
            image.replaceSubrange(txDataOffset..<totalSize, with: data)
        }

        return image
    }

    /// Receive bytes from a UART. Runs ARM thunk on device, reads buffer back.
    func uartReceive(uart: Int, maxBytes: UInt32 = 512, timeoutLoops: UInt32 = 2_000_000, completion: @escaping (Result<Data, Error>) -> Void) {
        guard uart < Self.uartBases.count else {
            completion(.failure(FELError.protocolError("Invalid UART \(uart)")))
            return
        }
        guard let socInfo = deviceInfo?.socInfo else {
            completion(.failure(FELError.deviceNotFound))
            return
        }

        let uartBase = Self.uartBases[uart]
        let scratch = socInfo.scratchAddr
        let thunk = Self.buildRXThunk(uartBase: uartBase, maxBytes: maxBytes, timeoutLoops: timeoutLoops, scratchAddr: scratch)
        let readOffset = scratch + Self.rxCountOffset
        let readLen = 4 + maxBytes

        runThunk(code: thunk, readOffset: readOffset, readLength: readLen) { result in
            switch result {
            case .success(let raw):
                guard raw.count >= 4 else {
                    completion(.success(Data()))
                    return
                }
                let count: UInt32 = raw.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
                let byteCount = min(Int(count), Int(maxBytes))
                let received = byteCount > 0 ? raw.subdata(in: 4..<min(4 + byteCount, raw.count)) : Data()
                completion(.success(received))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    /// Transmit bytes to a UART. Runs ARM thunk on device.
    func uartTransmit(uart: Int, data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard uart < Self.uartBases.count else {
            completion(.failure(FELError.protocolError("Invalid UART \(uart)")))
            return
        }
        guard let socInfo = deviceInfo?.socInfo else {
            completion(.failure(FELError.deviceNotFound))
            return
        }

        let uartBase = Self.uartBases[uart]
        let scratch = socInfo.scratchAddr
        let thunk = Self.buildTXThunk(uartBase: uartBase, data: data, scratchAddr: scratch)
        runThunkNoRead(code: thunk, completion: completion)
    }

    // MARK: - RAK4200 LoRa

    /// Hardware reset RAK4200 by toggling PG10 low then high.
    func rakReset(completion: @escaping (Result<Void, Error>) -> Void) {
        configureGPIOPin(port: Self.RAK_RESET_PORT, pin: Self.RAK_RESET_PIN, function: 1) { [weak self] result in
            if case .failure(let err) = result { completion(.failure(err)); return }
            self?.setGPIOPin(port: Self.RAK_RESET_PORT, pin: Self.RAK_RESET_PIN, high: false) { result in
                if case .failure(let err) = result { completion(.failure(err)); return }
                // USB round-trip provides implicit ~2ms delay
                self?.setGPIOPin(port: Self.RAK_RESET_PORT, pin: Self.RAK_RESET_PIN, high: true, completion: completion)
            }
        }
    }

    /// Send an AT command to RAK4200 on UART3 and read the response.
    func rakCommand(_ command: String, responseDelay: TimeInterval = 0.3, completion: @escaping (Result<String, Error>) -> Void) {
        let cmdData = Data("\(command)\r\n".utf8)
        uartTransmit(uart: 3, data: cmdData) { [weak self] result in
            if case .failure(let err) = result { completion(.failure(err)); return }

            // Wait for device to process and respond
            DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) {
                self?.uartReceive(uart: 3, maxBytes: 512, timeoutLoops: 500_000) { result in
                    switch result {
                    case .success(let data):
                        let response = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(no response)"
                        completion(.success(response))
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
            }
        }
    }

    // MARK: - CCU (Clock Control Unit)

    /// Read the PLL_CPUX control register to get CPU frequency info.
    func readCPUClock(completion: @escaping (Result<UInt32, Error>) -> Void) {
        readRegister(address: 0x01C20000, completion: completion) // PLL_CPUX_CTRL
    }

    // MARK: - TWI / I2C (A64)

    /// TWI controller base addresses.
    static let twiBases: [UInt32] = [
        0x01C2_AC00, // TWI0 — PMIC (RSB/I2C, configured by BROM)
        0x01C2_B000, // TWI1 — LM3630A backlight, DW8769L LCD bias
        0x01C2_B400, // TWI2
    ]

    /// TWI register offsets (mvtwsi-compatible).
    private static let TWI_ADDR:  UInt32 = 0x00
    private static let TWI_XADDR: UInt32 = 0x04
    private static let TWI_DATA:  UInt32 = 0x08
    private static let TWI_CTRL:  UInt32 = 0x0C
    private static let TWI_STAT:  UInt32 = 0x10
    private static let TWI_CCR:   UInt32 = 0x14
    private static let TWI_SRST:  UInt32 = 0x18

    /// TWI control register bits.
    private static let TWI_ACK:    UInt32 = 0x04
    private static let TWI_IFLG:   UInt32 = 0x08 // write-clear on A64
    private static let TWI_STOP:   UInt32 = 0x10
    private static let TWI_START:  UInt32 = 0x20
    private static let TWI_ENABLE: UInt32 = 0x40
    private static let TWI_INTEN:  UInt32 = 0x80

    /// TWI status codes.
    private static let STAT_START:      UInt32 = 0x08
    private static let STAT_REP_START:  UInt32 = 0x10
    private static let STAT_ADDR_W_ACK: UInt32 = 0x18
    private static let STAT_ADDR_W_NAK: UInt32 = 0x20
    private static let STAT_DATA_W_ACK: UInt32 = 0x28
    private static let STAT_ADDR_R_ACK: UInt32 = 0x40
    private static let STAT_DATA_R_ACK: UInt32 = 0x50
    private static let STAT_DATA_R_NAK: UInt32 = 0x58
    private static let STAT_IDLE:       UInt32 = 0xF8

    /// CCU gate and reset registers for TWI.
    private static let CCU_BUS_CLK_GATE3: UInt32 = 0x01C2_006C
    private static let CCU_BUS_SOFT_RST4: UInt32 = 0x01C2_02D8

    /// TWI1 pin config: PH2=SCL, PH3=SDA, function 2 (i2c1).
    /// Port H = index 6 in gpioPorts array.
    private static let TWI1_PORT: Int = 6
    private static let TWI1_SCL_PIN: Int = 2
    private static let TWI1_SDA_PIN: Int = 3
    private static let TWI1_PINMUX: UInt32 = 2

    /// Initialize a TWI bus: enable clock, deassert reset, configure pins, set clock rate, enable.
    func initTWI(bus: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard bus >= 0 && bus < Self.twiBases.count else {
            completion(.failure(FELError.protocolError("Invalid TWI bus \(bus)")))
            return
        }

        let base = Self.twiBases[bus]
        let bit = UInt32(bus)

        // Step 1: Enable clock gate (CCU BUS_CLK_GATING3 bit 0/1/2 for TWI0/1/2)
        readRegister(address: Self.CCU_BUS_CLK_GATE3) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err): completion(.failure(err)); return
            case .success(let val):
                self.writeRegister(address: Self.CCU_BUS_CLK_GATE3, value: val | (1 << bit)) { result in
                    if case .failure(let err) = result { completion(.failure(err)); return }

                    // Step 2: Deassert reset (CCU BUS_SOFT_RST4 bit 0/1/2)
                    self.readRegister(address: Self.CCU_BUS_SOFT_RST4) { result in
                        switch result {
                        case .failure(let err): completion(.failure(err)); return
                        case .success(let val):
                            self.writeRegister(address: Self.CCU_BUS_SOFT_RST4, value: val | (1 << bit)) { result in
                                if case .failure(let err) = result { completion(.failure(err)); return }

                                // Step 3: Configure GPIO pins for TWI1
                                self.configureTWIPins(bus: bus) {
                                    // Step 4: Software reset the TWI controller
                                    self.writeRegister(address: base + Self.TWI_SRST, value: 1) { result in
                                        if case .failure(let err) = result { completion(.failure(err)); return }

                                        // Step 5: Set clock rate (100kHz: CLK_M=2, CLK_N=1 → ~97kHz)
                                        self.writeRegister(address: base + Self.TWI_CCR, value: 0x12) { result in
                                            if case .failure(let err) = result { completion(.failure(err)); return }

                                            // Step 6: Enable TWI controller
                                            self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE) { result in
                                                completion(result)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Configure GPIO pins for TWI bus.
    private func configureTWIPins(bus: Int, completion: @escaping () -> Void) {
        switch bus {
        case 1:
            // TWI1: PH2=SCL (func 2), PH3=SDA (func 2)
            configureGPIOPin(port: Self.TWI1_PORT, pin: Self.TWI1_SCL_PIN, function: Self.TWI1_PINMUX) { [weak self] _ in
                self?.configureGPIOPin(port: Self.TWI1_PORT, pin: Self.TWI1_SDA_PIN, function: Self.TWI1_PINMUX) { _ in
                    completion()
                }
            }
        default:
            // TWI0 is already configured by BROM, TWI2 not pinned on PocketPC
            completion()
        }
    }

    /// Poll TWI IFLG bit until set, then read status. Returns status code.
    private func twiWaitIFLG(base: UInt32, attempts: Int = 100, completion: @escaping (Result<UInt32, Error>) -> Void) {
        var remaining = attempts
        func poll() {
            readRegister(address: base + Self.TWI_CTRL) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let err): completion(.failure(err))
                case .success(let ctrl):
                    if ctrl & Self.TWI_IFLG != 0 {
                        // IFLG set — read status register
                        self.readRegister(address: base + Self.TWI_STAT, completion: completion)
                    } else {
                        remaining -= 1
                        if remaining <= 0 {
                            completion(.failure(FELError.timeout))
                        } else {
                            poll()
                        }
                    }
                }
            }
        }
        poll()
    }

    /// Send a START condition and slave address on the TWI bus.
    /// Returns true if the device ACKs.
    func i2cProbe(bus: Int, addr: UInt8, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard bus >= 0 && bus < Self.twiBases.count else {
            completion(.failure(FELError.protocolError("Invalid TWI bus \(bus)")))
            return
        }
        let base = Self.twiBases[bus]

        // Send START
        writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_START | Self.TWI_IFLG) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result { completion(.failure(err)); return }

            self.twiWaitIFLG(base: base) { result in
                switch result {
                case .failure(let err): completion(.failure(err)); return
                case .success(let stat):
                    guard stat == Self.STAT_START || stat == Self.STAT_REP_START else {
                        // Failed to get START, send STOP and report no device
                        self.twiSendStop(base: base) { completion(.success(false)) }
                        return
                    }

                    // Write slave address (write mode: addr << 1 | 0)
                    self.writeRegister(address: base + Self.TWI_DATA, value: UInt32(addr) << 1) { result in
                        if case .failure(let err) = result { completion(.failure(err)); return }

                        // Clear IFLG + START to send address
                        self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_IFLG) { result in
                            if case .failure(let err) = result { completion(.failure(err)); return }

                            self.twiWaitIFLG(base: base) { result in
                                switch result {
                                case .failure(let err): completion(.failure(err)); return
                                case .success(let stat):
                                    let ack = (stat == Self.STAT_ADDR_W_ACK)
                                    // Send STOP
                                    self.twiSendStop(base: base) { completion(.success(ack)) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Send STOP condition.
    private func twiSendStop(base: UInt32, completion: @escaping () -> Void) {
        writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_STOP | Self.TWI_IFLG) { _ in
            completion()
        }
    }

    /// Scan a TWI bus for responding devices (addresses 0x03–0x77).
    func i2cScan(bus: Int, completion: @escaping (Result<[UInt8], Error>) -> Void) {
        guard bus >= 0 && bus < Self.twiBases.count else {
            completion(.failure(FELError.protocolError("Invalid TWI bus \(bus)")))
            return
        }

        var found: [UInt8] = []
        var currentAddr: UInt8 = 0x03

        func probeNext() {
            if currentAddr > 0x77 {
                completion(.success(found))
                return
            }
            let addr = currentAddr
            currentAddr += 1
            i2cProbe(bus: bus, addr: addr) { result in
                switch result {
                case .success(let ack):
                    if ack { found.append(addr) }
                    probeNext()
                case .failure(let err):
                    // Report what we found so far plus the error
                    if found.isEmpty {
                        completion(.failure(err))
                    } else {
                        completion(.success(found))
                    }
                }
            }
        }
        probeNext()
    }

    /// Read register(s) from an I2C device.
    /// Sends: START → addr+W → reg → REP START → addr+R → read N bytes → STOP
    func i2cRead(bus: Int, addr: UInt8, reg: UInt8, length: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        guard bus >= 0 && bus < Self.twiBases.count else {
            completion(.failure(FELError.protocolError("Invalid TWI bus \(bus)")))
            return
        }
        let base = Self.twiBases[bus]

        // START
        writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_START | Self.TWI_IFLG) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result { completion(.failure(err)); return }

            self.twiWaitIFLG(base: base) { result in
                guard case .success(let stat) = result, stat == Self.STAT_START || stat == Self.STAT_REP_START else {
                    self.twiSendStop(base: base) { completion(.failure(FELError.protocolError("I2C START failed"))) }
                    return
                }

                // Write slave address (write)
                self.writeRegister(address: base + Self.TWI_DATA, value: UInt32(addr) << 1) { result in
                    if case .failure(let err) = result { completion(.failure(err)); return }
                    self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_IFLG) { result in
                        if case .failure(let err) = result { completion(.failure(err)); return }

                        self.twiWaitIFLG(base: base) { result in
                            guard case .success(let stat) = result, stat == Self.STAT_ADDR_W_ACK else {
                                self.twiSendStop(base: base) { completion(.failure(FELError.protocolError("I2C NAK on address write"))) }
                                return
                            }

                            // Write register address
                            self.writeRegister(address: base + Self.TWI_DATA, value: UInt32(reg)) { result in
                                if case .failure(let err) = result { completion(.failure(err)); return }
                                self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_IFLG) { result in
                                    if case .failure(let err) = result { completion(.failure(err)); return }

                                    self.twiWaitIFLG(base: base) { result in
                                        guard case .success(let stat) = result, stat == Self.STAT_DATA_W_ACK else {
                                            self.twiSendStop(base: base) { completion(.failure(FELError.protocolError("I2C NAK on register write"))) }
                                            return
                                        }

                                        // Repeated START for read
                                        self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_START | Self.TWI_IFLG) { result in
                                            if case .failure(let err) = result { completion(.failure(err)); return }

                                            self.twiWaitIFLG(base: base) { result in
                                                guard case .success(let stat) = result, stat == Self.STAT_REP_START || stat == Self.STAT_START else {
                                                    self.twiSendStop(base: base) { completion(.failure(FELError.protocolError("I2C repeated START failed"))) }
                                                    return
                                                }

                                                // Write slave address (read)
                                                self.writeRegister(address: base + Self.TWI_DATA, value: (UInt32(addr) << 1) | 1) { result in
                                                    if case .failure(let err) = result { completion(.failure(err)); return }
                                                    self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_IFLG) { result in
                                                        if case .failure(let err) = result { completion(.failure(err)); return }

                                                        self.twiWaitIFLG(base: base) { result in
                                                            guard case .success(let stat) = result, stat == Self.STAT_ADDR_R_ACK else {
                                                                self.twiSendStop(base: base) { completion(.failure(FELError.protocolError("I2C NAK on address read"))) }
                                                                return
                                                            }

                                                            // Read bytes
                                                            self.twiReadBytes(base: base, remaining: length, accumulated: Data()) { result in
                                                                self.twiSendStop(base: base) { completion(result) }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Read N bytes from TWI data register, sending ACK for all but the last byte.
    private func twiReadBytes(base: UInt32, remaining: Int, accumulated: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        if remaining <= 0 {
            completion(.success(accumulated))
            return
        }

        // Send ACK for all bytes except the last one (send NAK for last)
        let ackBit: UInt32 = remaining > 1 ? Self.TWI_ACK : 0
        writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_IFLG | ackBit) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result { completion(.failure(err)); return }

            self.twiWaitIFLG(base: base) { result in
                switch result {
                case .failure(let err): completion(.failure(err))
                case .success(let stat):
                    guard stat == Self.STAT_DATA_R_ACK || stat == Self.STAT_DATA_R_NAK else {
                        completion(.failure(FELError.protocolError("I2C read error: status 0x\(String(format: "%02x", stat))")))
                        return
                    }
                    // Read the data byte
                    self.readRegister(address: base + Self.TWI_DATA) { result in
                        switch result {
                        case .failure(let err): completion(.failure(err))
                        case .success(let val):
                            var data = accumulated
                            data.append(UInt8(val & 0xFF))
                            self.twiReadBytes(base: base, remaining: remaining - 1, accumulated: data, completion: completion)
                        }
                    }
                }
            }
        }
    }

    /// Write data to an I2C device register.
    /// Sends: START → addr+W → reg → data bytes → STOP
    func i2cWrite(bus: Int, addr: UInt8, reg: UInt8, data: [UInt8], completion: @escaping (Result<Void, Error>) -> Void) {
        guard bus >= 0 && bus < Self.twiBases.count else {
            completion(.failure(FELError.protocolError("Invalid TWI bus \(bus)")))
            return
        }
        let base = Self.twiBases[bus]

        // START
        writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_START | Self.TWI_IFLG) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result { completion(.failure(err)); return }

            self.twiWaitIFLG(base: base) { result in
                guard case .success(let stat) = result, stat == Self.STAT_START || stat == Self.STAT_REP_START else {
                    self.twiSendStop(base: base) { completion(.failure(FELError.protocolError("I2C START failed"))) }
                    return
                }

                // Write slave address (write)
                self.writeRegister(address: base + Self.TWI_DATA, value: UInt32(addr) << 1) { result in
                    if case .failure(let err) = result { completion(.failure(err)); return }
                    self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_IFLG) { result in
                        if case .failure(let err) = result { completion(.failure(err)); return }

                        self.twiWaitIFLG(base: base) { result in
                            guard case .success(let stat) = result, stat == Self.STAT_ADDR_W_ACK else {
                                self.twiSendStop(base: base) { completion(.failure(FELError.protocolError("I2C NAK on address"))) }
                                return
                            }

                            // Write register address + data bytes
                            let allBytes = [reg] + data
                            self.twiWriteBytes(base: base, bytes: allBytes, index: 0) { result in
                                self.twiSendStop(base: base) { completion(result) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Write bytes sequentially to TWI data register.
    private func twiWriteBytes(base: UInt32, bytes: [UInt8], index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        if index >= bytes.count {
            completion(.success(()))
            return
        }

        writeRegister(address: base + Self.TWI_DATA, value: UInt32(bytes[index])) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result { completion(.failure(err)); return }

            self.writeRegister(address: base + Self.TWI_CTRL, value: Self.TWI_ENABLE | Self.TWI_IFLG) { result in
                if case .failure(let err) = result { completion(.failure(err)); return }

                self.twiWaitIFLG(base: base) { result in
                    guard case .success(let stat) = result, stat == Self.STAT_DATA_W_ACK else {
                        completion(.failure(FELError.protocolError("I2C NAK on data byte \(index)")))
                        return
                    }
                    self.twiWriteBytes(base: base, bytes: bytes, index: index + 1, completion: completion)
                }
            }
        }
    }

    // MARK: - LM3630A Backlight

    /// Initialize LM3630A backlight controller on TWI1.
    /// 1. Set PD23 high (HWEN), 2. Wait, 3. Configure LM3630A registers.
    func initBacklight(brightness: UInt8, completion: @escaping (Result<Void, Error>) -> Void) {
        // PD23 = Port D (index 2), pin 23 — HWEN enable
        configureGPIOPin(port: 2, pin: 23, function: 1) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result { completion(.failure(err)); return }

            self.setGPIOPin(port: 2, pin: 23, high: true) { result in
                if case .failure(let err) = result { completion(.failure(err)); return }

                // Wait ~2ms for chip startup (USB round-trip provides implicit delay)
                // Init TWI1 then configure LM3630A
                self.initTWI(bus: 1) { result in
                    if case .failure(let err) = result { completion(.failure(err)); return }

                    // Reg 0x00 = 0x19: enable bank A+B, linear mode
                    self.i2cWrite(bus: 1, addr: 0x38, reg: 0x00, data: [0x19]) { result in
                        if case .failure(let err) = result { completion(.failure(err)); return }

                        // Reg 0x03 = brightness (bank A)
                        self.i2cWrite(bus: 1, addr: 0x38, reg: 0x03, data: [brightness]) { result in
                            if case .failure(let err) = result { completion(.failure(err)); return }

                            // Reg 0x06 = brightness (bank B)
                            self.i2cWrite(bus: 1, addr: 0x38, reg: 0x06, data: [brightness], completion: completion)
                        }
                    }
                }
            }
        }
    }

    // MARK: - BROM / Memory Dump

    /// Dump a region of memory via FEL reads. Reads in 4KB chunks with progress callback.
    func dumpMemory(address: UInt32, length: UInt32, progress: @escaping (Int, Int) -> Void, completion: @escaping (Result<Data, Error>) -> Void) {
        let chunkSize: UInt32 = 4096
        var accumulated = Data()
        let total = Int(length)

        func readChunk(offset: UInt32) {
            if offset >= length {
                completion(.success(accumulated))
                return
            }
            let thisLen = min(chunkSize, length - offset)
            readMemory(address: address + offset, length: thisLen) { result in
                switch result {
                case .success(let data):
                    accumulated.append(data)
                    progress(accumulated.count, total)
                    readChunk(offset: offset + thisLen)
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
        readChunk(offset: 0)
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

// MARK: - GPS NMEA Parser

struct GPSFix {
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var speed: Double?       // knots
    var course: Double?
    var time: String?        // HH:MM:SS UTC
    var date: String?
    var satellites: Int?
    var fix: Bool = false

    var summary: String {
        guard fix, let lat = latitude, let lon = longitude else {
            let sats = satellites.map { "\($0) sats" } ?? ""
            return "GPS: No fix\(sats.isEmpty ? "" : " (\(sats), searching...)")"
        }
        var parts: [String] = []
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        parts.append(String(format: "%.6f°%@ %.6f°%@", abs(lat), latDir, abs(lon), lonDir))
        if let alt = altitude { parts.append(String(format: "alt:%.1fm", alt)) }
        if let sats = satellites { parts.append("sats:\(sats)") }
        if let spd = speed, spd > 0.5 { parts.append(String(format: "spd:%.1fkn", spd)) }
        if let t = time { parts.append("\(t) UTC") }
        return "GPS: \(parts.joined(separator: "  "))"
    }

    /// Parse $GPRMC / $GNRMC sentence for position, speed, time, date.
    static func parseRMC(_ sentence: String) -> GPSFix? {
        let fields = sentence.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 10 else { return nil }

        var fix = GPSFix()
        fix.fix = fields[2] == "A"
        fix.time = formatTime(fields[1])
        fix.latitude = parseCoordinate(fields[3], direction: fields[4])
        fix.longitude = parseCoordinate(fields[5], direction: fields[6])
        fix.speed = Double(fields[7])
        fix.course = Double(fields[8])
        if fields.count > 9 && fields[9].count == 6 {
            let d = fields[9]
            fix.date = "\(d.prefix(2))/\(d.dropFirst(2).prefix(2))/\(d.suffix(2))"
        }
        return fix
    }

    /// Parse $GPGGA / $GNGGA sentence for altitude, satellite count.
    static func parseGGA(_ sentence: String) -> GPSFix? {
        let fields = sentence.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 10 else { return nil }

        var fix = GPSFix()
        fix.satellites = Int(fields[7])
        fix.altitude = Double(fields[9])
        return fix
    }

    /// Convert NMEA coordinate (ddmm.mmmm) + direction (N/S/E/W) to decimal degrees.
    private static func parseCoordinate(_ value: String, direction: String) -> Double? {
        guard !value.isEmpty else { return nil }
        guard let raw = Double(value) else { return nil }
        let degrees = Double(Int(raw / 100))
        let minutes = raw - degrees * 100
        var result = degrees + minutes / 60.0
        if direction == "S" || direction == "W" { result = -result }
        return result
    }

    /// Format NMEA time (hhmmss.ss) as HH:MM:SS.
    private static func formatTime(_ value: String) -> String? {
        guard value.count >= 6 else { return nil }
        let h = value.prefix(2)
        let m = value.dropFirst(2).prefix(2)
        let s = value.dropFirst(4).prefix(2)
        return "\(h):\(m):\(s)"
    }
}

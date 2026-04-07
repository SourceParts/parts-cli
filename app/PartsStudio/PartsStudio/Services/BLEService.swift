import Foundation
import CoreBluetooth

// Nordic UART Service UUIDs (same as ESP32 firmware)
private let NUS_SERVICE_UUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let NUS_TX_CHAR_UUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")  // Notify (device → host)
private let NUS_RX_CHAR_UUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")  // Write  (host → device)

// OTA Service UUIDs (same as ESP32 firmware)
private let OTA_SERVICE_UUID = CBUUID(string: "fb1e4001-54ae-4a28-9f74-dfccb248601d")
private let OTA_CONTROL_UUID = CBUUID(string: "fb1e4002-54ae-4a28-9f74-dfccb248601d")  // Write (start/finish/abort)
private let OTA_DATA_UUID    = CBUUID(string: "fb1e4003-54ae-4a28-9f74-dfccb248601d")  // Write (firmware chunks)
private let OTA_STATUS_UUID  = CBUUID(string: "fb1e4004-54ae-4a28-9f74-dfccb248601d")  // Notify (progress)

// MARK: - BLE Device

struct BLEDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool { lhs.id == rhs.id }
}

enum BLEConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
}

// MARK: - BLE Service

class BLEService: NSObject, ObservableObject {
    @Published var state: BLEConnectionState = .disconnected
    @Published var devices: [BLEDevice] = []
    @Published var connectedDevice: BLEDevice?
    @Published var log: [String] = []

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?  // NUS Notify (device → host)
    private var rxCharacteristic: CBCharacteristic?  // NUS Write  (host → device)
    private var otaControlChar: CBCharacteristic?    // OTA control (start/finish/abort)
    private var otaDataChar: CBCharacteristic?       // OTA data (firmware chunks)
    private var otaStatusChar: CBCharacteristic?     // OTA status (notify)

    // OTA state
    @Published var otaProgress: Double = 0
    @Published var otaActive: Bool = false
    private var otaCompletion: ((Result<Void, Error>) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScan() {
        guard centralManager?.state == .poweredOn else {
            appendLog("Bluetooth is not available")
            return
        }
        devices.removeAll()
        state = .scanning
        appendLog("Scanning for BLE devices...")
        centralManager?.scanForPeripherals(withServices: nil)

        // Auto-stop after 10s
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard self?.state == .scanning else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        centralManager?.stopScan()
        if state == .scanning {
            state = .disconnected
            appendLog("Scan complete — \(devices.count) device(s) found")
        }
    }

    func connect(device: BLEDevice) {
        stopScan()
        state = .connecting
        connectedPeripheral = device.peripheral
        appendLog("Connecting to \(device.name)...")
        centralManager?.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectedDevice = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        state = .disconnected
        appendLog("Disconnected")
    }

    func send(_ command: String) {
        guard let rx = rxCharacteristic, let peripheral = connectedPeripheral else {
            appendLog("Not connected")
            return
        }
        guard let data = (command + "\n").data(using: .utf8) else { return }
        peripheral.writeValue(data, for: rx, type: .withResponse)
        appendLog("> \(command)")
    }

    // MARK: - BLE OTA Firmware Update

    /// Flash firmware to the connected ESP32 via BLE OTA.
    /// The ESP32 firmware must have the OTA service running.
    func flashOTA(firmware: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let peripheral = connectedPeripheral,
              let controlChar = otaControlChar,
              let dataChar = otaDataChar else {
            completion(.failure(NSError(domain: "BLE", code: 1, userInfo: [NSLocalizedDescriptionKey: "OTA not available — connect to PocketPC-BLE first"])))
            return
        }

        otaActive = true
        otaProgress = 0
        otaCompletion = completion
        appendLog("[OTA] Starting firmware update (\(firmware.count) bytes)...")

        // Send OTA_CMD_START with firmware size
        var startCmd = Data([0x01]) // OTA_CMD_START
        var size = UInt32(firmware.count).littleEndian
        startCmd.append(Data(bytes: &size, count: 4))
        peripheral.writeValue(startCmd, for: controlChar, type: .withResponse)

        // Send firmware data in chunks (MTU-safe, ~500 bytes per write)
        let chunkSize = 500
        let totalChunks = (firmware.count + chunkSize - 1) / chunkSize

        appendLog("[OTA] Sending \(totalChunks) chunks...")

        func sendChunk(_ index: Int) {
            guard index < totalChunks else {
                // All chunks sent — send OTA_CMD_FINISH
                let finishCmd = Data([0x02]) // OTA_CMD_FINISH
                peripheral.writeValue(finishCmd, for: controlChar, type: .withResponse)
                self.appendLog("[OTA] All data sent, finishing...")
                return
            }

            let start = index * chunkSize
            let end = min(start + chunkSize, firmware.count)
            let chunk = firmware[start..<end]
            peripheral.writeValue(chunk, for: dataChar, type: .withoutResponse)

            self.otaProgress = Double(index + 1) / Double(totalChunks)

            if index % 50 == 0 {
                self.appendLog("[OTA] \(Int(self.otaProgress * 100))% (\(index)/\(totalChunks))")
            }

            // Pace writes to avoid BLE congestion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                sendChunk(index + 1)
            }
        }

        // Start sending after a brief delay (let ESP32 prepare)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sendChunk(0)
        }
    }

    /// Abort an in-progress OTA update.
    func abortOTA() {
        guard let peripheral = connectedPeripheral, let controlChar = otaControlChar else { return }
        let abortCmd = Data([0x03]) // OTA_CMD_ABORT
        peripheral.writeValue(abortCmd, for: controlChar, type: .withResponse)
        otaActive = false
        otaProgress = 0
        appendLog("[OTA] Aborted")
        otaCompletion?(.failure(NSError(domain: "BLE", code: 2, userInfo: [NSLocalizedDescriptionKey: "OTA aborted"])))
        otaCompletion = nil
    }

    func appendLog(_ message: String) {
        let ts = Self.timestamp()
        DispatchQueue.main.async {
            self.log.append("[\(ts)] \(message)")
            if self.log.count > 500 {
                self.log.removeFirst(self.log.count - 500)
            }
        }
    }

    private static func timestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt.string(from: Date())
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            appendLog("Bluetooth ready")
        case .poweredOff:
            appendLog("Bluetooth is off")
            state = .disconnected
        case .unauthorized:
            appendLog("Bluetooth unauthorized — check System Settings > Privacy")
        default:
            appendLog("Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard !name.isEmpty else { return }

        let device = BLEDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)

        DispatchQueue.main.async {
            if let idx = self.devices.firstIndex(where: { $0.id == device.id }) {
                self.devices[idx] = device
            } else {
                self.devices.append(device)
                self.appendLog("Found: \(name) (RSSI \(RSSI.intValue))")
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("Connected to \(peripheral.name ?? "unknown")")
        peripheral.delegate = self
        peripheral.discoverServices([NUS_SERVICE_UUID, OTA_SERVICE_UUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appendLog("Connection failed: \(error?.localizedDescription ?? "unknown")")
        state = .disconnected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        appendLog("Disconnected from \(peripheral.name ?? "unknown")")
        connectedPeripheral = nil
        connectedDevice = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        state = .disconnected
    }
}

// MARK: - CBPeripheralDelegate

extension BLEService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == NUS_SERVICE_UUID {
                appendLog("Found UART service")
                peripheral.discoverCharacteristics([NUS_TX_CHAR_UUID, NUS_RX_CHAR_UUID], for: service)
            } else if service.uuid == OTA_SERVICE_UUID {
                appendLog("Found OTA service")
                peripheral.discoverCharacteristics([OTA_CONTROL_UUID, OTA_DATA_UUID, OTA_STATUS_UUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case NUS_TX_CHAR_UUID:
                txCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                appendLog("UART TX ready (notify)")
            case NUS_RX_CHAR_UUID:
                rxCharacteristic = char
                appendLog("UART RX ready (write)")
            case OTA_CONTROL_UUID:
                otaControlChar = char
                appendLog("OTA control ready")
            case OTA_DATA_UUID:
                otaDataChar = char
                appendLog("OTA data ready")
            case OTA_STATUS_UUID:
                otaStatusChar = char
                peripheral.setNotifyValue(true, for: char)
                appendLog("OTA status ready (notify)")
            default:
                break
            }
        }
        if txCharacteristic != nil && rxCharacteristic != nil {
            state = .connected
            connectedDevice = devices.first(where: { $0.id == peripheral.identifier })
            appendLog("BLE console ready\(otaControlChar != nil ? " + OTA" : "")")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        if characteristic.uuid == NUS_TX_CHAR_UUID {
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                appendLog(text)
            }
        } else if characteristic.uuid == OTA_STATUS_UUID && data.count >= 5 {
            let status = data[0]
            let bytesWritten = data.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: 1, as: UInt32.self).littleEndian
            }
            let msg = data.count > 5 ? String(data: data[5...], encoding: .utf8) ?? "" : ""

            switch status {
            case 0x00: // IDLE
                appendLog("[OTA] Idle")
            case 0x01: // READY
                appendLog("[OTA] Device ready")
            case 0x02: // WRITING
                appendLog("[OTA] Writing: \(bytesWritten) bytes \(msg)")
            case 0x03: // DONE
                appendLog("[OTA] Complete! \(bytesWritten) bytes. Device rebooting...")
                otaActive = false
                otaProgress = 1.0
                otaCompletion?(.success(()))
                otaCompletion = nil
            case 0xFF: // ERROR
                appendLog("[OTA] ERROR: \(msg)")
                otaActive = false
                otaCompletion?(.failure(NSError(domain: "BLE", code: 3, userInfo: [NSLocalizedDescriptionKey: "OTA error: \(msg)"])))
                otaCompletion = nil
            default:
                appendLog("[OTA] Status: \(status) \(msg)")
            }
        }
    }
}

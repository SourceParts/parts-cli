import Foundation
import CoreBluetooth

// Nordic UART Service UUIDs (same as ESP32 firmware)
private let NUS_SERVICE_UUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let NUS_TX_CHAR_UUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")  // Notify (device → host)
private let NUS_RX_CHAR_UUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")  // Write  (host → device)

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
    private var txCharacteristic: CBCharacteristic?  // Notify (device → host)
    private var rxCharacteristic: CBCharacteristic?  // Write  (host → device)

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

    private func appendLog(_ message: String) {
        let ts = Self.timestamp()
        DispatchQueue.main.async {
            self.log.append("[\(ts)] \(message)")
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
        peripheral.discoverServices([NUS_SERVICE_UUID])
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
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == NUS_TX_CHAR_UUID {
                txCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                appendLog("UART TX ready (notify)")
            } else if char.uuid == NUS_RX_CHAR_UUID {
                rxCharacteristic = char
                appendLog("UART RX ready (write)")
            }
        }
        if txCharacteristic != nil && rxCharacteristic != nil {
            state = .connected
            connectedDevice = devices.first(where: { $0.id == peripheral.identifier })
            appendLog("BLE UART console ready")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == NUS_TX_CHAR_UUID, let data = characteristic.value else { return }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            appendLog(text)
        }
    }
}

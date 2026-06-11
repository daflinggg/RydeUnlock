import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    
    var body: some View {
        VStack(spacing: 40) {
            Text("🚀 Ryde E-Scooter Unlock").font(.largeTitle).bold()
            Text(bleManager.status).font(.title2).multilineTextAlignment(.center)
            
            Button("Scan & Auto Unlock") {
                bleManager.startScanning()
            }
            .font(.title)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(12)
            
            Button("Sende alle Unlock Commands") {
                bleManager.sendUnlockCommands()
            }
            .font(.title2)
            .padding()
        }
        .padding()
    }
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "Bereit – Drücke Scan"
    
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    
    let UART_SERVICE = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    let TX_CHAR = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    let RX_CHAR = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        status = "Scanne nach Ryde..."
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {}
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let name = peripheral.name?.lowercased(), (name.contains("ryde") || name.contains("scooter")) && RSSI.intValue > -78 {
            status = "Ryde gefunden! Verbinde..."
            central.stopScan()
            targetPeripheral = peripheral
            central.connect(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([UART_SERVICE])
        status = "Verbunden – sende Unlock..."
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == UART_SERVICE {
            peripheral.discoverCharacteristics([TX_CHAR, RX_CHAR], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == TX_CHAR {
                txCharacteristic = char
                sendUnlockCommands()
            }
            if char.uuid == RX_CHAR {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }
    
    func sendUnlockCommands() {
        guard let tx = txCharacteristic, let peripheral = targetPeripheral else { return }
        
        let commands: [[UInt8]] = [
            [0x00, 0xD4, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            [0x5A, 0xA5, 0x02, 0x3D, 0x20, 0x03, 0x7A, 0x00, 0x00],
            [0x5A, 0xA5, 0x01, 0x00, 0x00, 0x00],
            [0x5A, 0xA5, 0x02, 0x01, 0x00, 0x00]
        ]
        
        for cmd in commands {
            let data = Data(cmd)
            peripheral.writeValue(data, for: tx, type: .withResponse)
            Thread.sleep(forTimeInterval: 0.9)
        }
        status = "✅ Alle Unlock Commands gesendet! Scooter sollte offen sein."
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value {
            print("Response: \(value.map { String(format: "%02X", $0) }.joined())")
        }
    }
}

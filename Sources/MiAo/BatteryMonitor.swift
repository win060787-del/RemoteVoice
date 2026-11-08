@preconcurrency import CoreBluetooth
import Foundation

struct BatteryReading: Equatable {
    private(set) var deviceIdentifier: UUID?
    private(set) var percent: Int?
    mutating func select(_ identifier: UUID?) {
        if deviceIdentifier != identifier { percent = nil }
        deviceIdentifier = identifier
    }
    mutating func receive(_ data: Data, from identifier: UUID) {
        guard identifier == deviceIdentifier, data.count == 1, let level = data.first, level <= 100 else { return }
        percent = Int(level)
    }
    mutating func disconnect(_ identifier: UUID) {
        guard identifier == deviceIdentifier else { return }
        percent = nil
    }
}

/// Main-queue Battery Service client. It never touches ATVV, speech models or input permissions.
final class BatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var selected: UUID?
    private var reading = BatteryReading()
    private var lastAttempt = Date.distantPast
    private var lastRead = Date.distantPast
    private(set) var detail = "等待蓝牙授权后读取电量"
    var percent: Int? { peripheral?.state == .connected ? reading.percent : nil }

    func synchronize(preferred: UUID?, requestPermission: Bool = false) {
        if selected != preferred {
            releaseConnection()
            selected = preferred
            reading.select(preferred)
            lastAttempt = .distantPast
        }
        guard
            CBManager.authorization == .allowedAlways
                || (requestPermission && CBManager.authorization == .notDetermined)
        else {
            detail = "需要蓝牙权限；点击电池可重试或申请授权"
            return
        }
        if central == nil {
            central = CBCentralManager(
                delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        guard central?.state == .poweredOn else { return }
        if let peripheral, peripheral.state == .connected {
            if Date().timeIntervalSince(lastRead) >= 60 {
                lastRead = Date()
                if let characteristic {
                    peripheral.readValue(for: characteristic)
                } else {
                    peripheral.discoverServices([CBUUID(string: "180F")])
                }
            }
            return
        }
        if peripheral?.state == .connecting, Date().timeIntervalSince(lastAttempt) >= 20 {
            releaseConnection()
            lastAttempt = Date()
            detail = "遥控器暂未响应，等待自动重试"
        }
        guard peripheral == nil, Date().timeIntervalSince(lastAttempt) >= 10 else { return }
        connect()
    }
    func stop() {
        releaseConnection()
        central?.delegate = nil
        central = nil
        reading.select(nil)
    }
    private func releaseConnection() {
        if let peripheral {
            if let characteristic, characteristic.isNotifying { peripheral.setNotifyValue(false, for: characteristic) }
            central?.cancelPeripheralConnection(peripheral)
            peripheral.delegate = nil
            reading.disconnect(peripheral.identifier)
        }
        peripheral = nil; characteristic = nil
    }
    private func connect() {
        guard let central else { return }
        lastAttempt = Date()
        lastRead = Date()
        let candidates = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: ATVVProtocol.serviceUUID)])
        let target: CBPeripheral?
        if let selected {
            target =
                candidates.first { $0.identifier == selected }
                ?? central.retrievePeripherals(withIdentifiers: [selected]).first
        } else {
            target = candidates.sorted { $0.identifier.uuidString < $1.identifier.uuidString }.first
        }
        guard let target else { detail = "未找到已连接的兼容遥控器"; return }
        peripheral = target
        reading.select(target.identifier)
        target.delegate = self
        detail = "正在读取遥控器电量…"
        // Acquire our own CoreBluetooth reference even when macOS already holds the HID connection.
        central.connect(target)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            lastAttempt = .distantPast; synchronize(preferred: selected)
        } else {
            if let id = peripheral?.identifier { reading.disconnect(id) }
            peripheral = nil; characteristic = nil
            detail = central.state == .poweredOff ? "蓝牙已关闭" : "等待蓝牙权限或连接"
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        peripheral.discoverServices([CBUUID(string: "180F")])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnected(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnected(peripheral)
    }
    private func disconnected(_ peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier, peripheral.state == .disconnected else { return }
        reading.disconnect(peripheral.identifier)
        self.peripheral = nil; characteristic = nil
        detail = "遥控器已断开，电量暂不可用"
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: "180F") })
        else {
            detail = "未读取到电池服务，点击电池重试"; return
        }
        peripheral.discoverCharacteristics([CBUUID(string: "2A19")], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard error == nil, let value = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "2A19") })
        else {
            detail = "设备没有返回标准电量特征"; return
        }
        characteristic = value
        if value.properties.contains(.read) { lastRead = Date(); peripheral.readValue(for: value) }
        if value.properties.contains(.notify) { peripheral.setNotifyValue(true, for: value) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, characteristic.uuid == CBUUID(string: "2A19") else {
            return
        }
        guard error == nil, let data = characteristic.value else { detail = "电量读取失败，等待下次重试"; return }
        reading.receive(data, from: peripheral.identifier)
        detail = reading.percent.map { "电量 \($0)% · 独立蓝牙读取，无需语音服务" } ?? "设备返回的电量格式无效"
    }
    func refresh(preferred: UUID?) {
        lastRead = .distantPast
        if characteristic == nil { releaseConnection(); lastAttempt = .distantPast }
        synchronize(preferred: preferred, requestPermission: true)
    }
}

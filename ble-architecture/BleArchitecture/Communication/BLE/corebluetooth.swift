//
////
////  ConnectionService.swift
////  ble
////
////  Created by Marek Piotrowski on 25/07/2023.
////
//
//import Foundation
//import CoreBluetooth
//import Combine
//
//protocol ConnectionServiceProtocol: AnyObject {
//    func writeData(_ baseData: BaseData, response: Bool)
//    func readData(_ id: UUID)
//}
//
//enum ConnectionState: Equatable {
//    case scanning
//    case connecting
//    case connected
//    case disconnected
//}
//
//class ConnectionService: NSObject {
//    var cbCentralManager: CBCentralManager?
//    var peripheral: CBPeripheral?
//    var characteristics: [CBCharacteristic] = []
//    var deviceState: DeviceStateProtocol?
//    var connectionState = CurrentValueSubject<ConnectionState, Never>(.disconnected)
//    var connectionData = CurrentValueSubject<String, Never>(.init())
//    var fuundPeripherals = CurrentValueSubject<[CBPeripheral], Never>([])
//    private let store = PeripheralStore.shared
//    
//    init(cbCentralManager: CBCentralManager? = nil,
//         peripheral: CBPeripheral? = nil,
//         characteristics: [CBCharacteristic] = [],
//         deviceState: DeviceStateProtocol? = nil) {
//        self.cbCentralManager = cbCentralManager
//        self.peripheral = peripheral
//        self.characteristics = characteristics
//        self.deviceState = deviceState
//    }
//    
//    func start(automaticConnect: Bool = true) {
//        connectionState.send(automaticConnect ? .connecting : .scanning)
//        self.fuundPeripherals.send([])
//        if let peripheral = self.peripheral {
//            cbCentralManager?.cancelPeripheralConnection(peripheral)
//        }
//        cbCentralManager = CBCentralManager(delegate: self, queue: nil)
//        characteristics = []
//        deviceState?.clear()
//        deviceState?.setDelegate(delegate: self)
//    }
//    
//    func stop() {
//        cbCentralManager?.stopScan()
//    }
//    
//    func connect(id: String) {
//        guard let peripheral = fuundPeripherals.value.first(where: { element in
//            id == element.identifier.uuidString
//        }) else { return }
//        cbCentralManager?.stopScan()
//        cbCentralManager?.connect(peripheral, options: nil)
//        self.peripheral = peripheral
//        store.store(peripheral: peripheral)
//    }
//    
//    func read() {
//        characteristics.forEach { characteristic in
//            if characteristic.isNotifying {
//                peripheral?.setNotifyValue(true, for: characteristic)
//            } else {
//                peripheral?.readValue(for: characteristic)
//                guard let descriptors = characteristic.descriptors else { return }
//
//                for descr in descriptors {
//                    peripheral?.readValue(for: descr)
//                }
//            }
//        }
//    }
//}
//
//extension ConnectionService: ConnectionServiceProtocol {
//    func getCharacteristic(_ id: UUID) -> CBCharacteristic? {
//        characteristics.first { characteristic in
//            characteristic.uuid == CBUUID(nsuuid: id)
//        }
//    }
//    
//    func writeData(_ baseData: BaseData, response: Bool = true) {
//        guard let characteristicData = baseData.characteristicData,
//              let data = characteristicData.writeValue,
//              let characteristic = getCharacteristic(characteristicData.identifier)
//        else { return }
//        peripheral?.writeValue(
//            data,
//            for: characteristic,
//            type: response ? .withResponse : .withoutResponse
//        )
//    }
//    
//    func readData(_ id: UUID) {
//        guard let characteristic = getCharacteristic(id)
//        else { return }
//        peripheral?.readValue(for: characteristic)
//    }
//}
//
//extension ConnectionService:  CBCentralManagerDelegate {
//    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        if central.state == .poweredOn {
//            central.scanForPeripherals(withServices: nil, options: nil)
//            print("Scanning...")
//        }
//    }
//    
//    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        guard peripheral.name != nil else { return }
//
//        if connectionState.value == .scanning, !fuundPeripherals.value.contains(where: { element in
//            peripheral.identifier == element.identifier
//        }) {
//            var newFounds = fuundPeripherals.value
//            newFounds.append(peripheral)
//            fuundPeripherals.send(newFounds)
//            return
//        }
//        
//        if connectionState.value == .connecting {
//            let (name, id) = store.fetch()
//            
//            if peripheral.identifier.uuidString == id {
//                print("Connect to \(name) \(id)")
//                cbCentralManager?.stopScan()
//                cbCentralManager?.connect(peripheral, options: nil)
//                self.peripheral = peripheral
//            }
//        }
//    }
//    
//    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
//        //discover all service
//        peripheral.discoverServices(nil)
//        peripheral.delegate = self
//        connectionData.send(peripheral.name ?? .init())
//        connectionState.send(.connected)
//    }
//    
//    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
//        connectionState.send(.disconnected)
//    }
//}
//
//
//extension ConnectionService : CBPeripheralDelegate {
//    
//    
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
//        
//        if let services = peripheral.services {
//            ///discover characteristics of services
//            for service in services {
//                peripheral.discoverCharacteristics(nil, for: service)
//            }
//        }
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
//        
//        if let charac = service.characteristics {
//            self.characteristics.append(contentsOf: charac)
//            for characteristic in charac {
//                //MARK:- Light Value
//                print(characteristic.uuid.uuidString)
//                let _ : BaseData? = deviceState?.getProcessor(characteristic.uuid.uuid)
////                peripheral.setNotifyValue(true, for: characteristic)
//                //          if characteristic.uuid == Digital {
//                //          self.lighCharacteristics = characteristic
//                //          }
//            }
//        }
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
//        print("\(characteristic.uuid.uuidString) \(error?.localizedDescription ?? .init()) \(characteristic.value?.hexEncodedString() ?? .init())")
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
//        guard let data = characteristic.value else { return }
//        print("\(characteristic.uuid) \(data.hexEncodedString(options: .upperCase)) \(characteristic.descriptors?.first?.uuid.uuidString ?? .init())")
//        guard let processor: BaseData = deviceState?.getProcessor(characteristic.uuid.uuid) else { return }
//        processor.addData(CharacteristicData(identifier: characteristic.uuid.uuid, value: data, error: error))
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
//        guard let data = characteristic.value else { return }
//        print("\(characteristic.uuid) \(data.hexEncodedString(options: .upperCase)) \(characteristic.descriptors?.first?.uuid.uuidString ?? .init())")
//        guard let processor: BaseData = deviceState?.getProcessor(characteristic.uuid.uuid) else { return }
//        processor.addData(CharacteristicData(identifier: characteristic.uuid.uuid, value: data, error: error))
//    }
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
//        print("XXX \(descriptor.uuid.uuidString)")
//    }
//}
//
//extension Array where Element == CBPeripheral {
//    var peripheralData: [PeripheralData] {
//        self.compactMap { peripheral in
//            guard let name = peripheral.name else { return nil }
//            let id = peripheral.identifier.uuidString
//            return (name, id)
//        }
//    }
//}
//
//

// BLECentralManager.swift
// BLESample
//
// Kompletny manager roli Central — obsługuje cały cykl życia BLE po stronie
// urządzenia, które skanuje, łączy się i wymienia dane.
//
// ARCHITEKTURA:
// BLECentralManager jest ObservableObject — SwiftUI może automatycznie
// odświeżać widoki gdy zmieniają się @Published właściwości.
// Wszystkie callbacki Core Bluetooth przychodzą na bleQueue (background),
// a aktualizacje UI są zawsze przekazywane na DispatchQueue.main.
//
// PRZEPŁYW:
// init() → centralManagerDidUpdateState(.poweredOn)
//   → startScan() → didDiscover()
//     → connect() → didConnect()
//       → discoverServices() → didDiscoverServices()
//         → discoverCharacteristics() → didDiscoverCharacteristics()
//           → readValue() / writeValue() / setNotifyValue()
//             → didUpdateValueFor() / didWriteValueFor()

import Foundation
import CoreBluetooth
import Combine

// MARK: - Model danych

/// Reprezentuje odkryte urządzenie BLE z metadanymi z pakietu advertisementu.
struct DiscoveredPeripheral: Identifiable {
    let id: UUID                        // peripheral.identifier — unikalny per iPhone
    let peripheral: CBPeripheral
    let localName: String?              // CBAdvertisementDataLocalNameKey
    let rssi: Int                       // siła sygnału w dBm (im bliżej 0, tym silniej)
    let serviceUUIDs: [CBUUID]?         // UUID usług z pakietu advertisementu
    let manufacturerData: Data?         // surowe dane producenta
    let isConnectable: Bool             // czy urządzenie akceptuje połączenia
    let txPowerLevel: Int?              // moc nadajnika w dBm (do obliczenia odległości)
    let discoveredAt: Date
}

/// Reprezentuje charakterystykę z jej aktualną wartością i stanem.
struct CharacteristicInfo: Identifiable {
    let id: CBUUID
    let characteristic: CBCharacteristic
    var lastValue: Data?
    var isNotifying: Bool
    var mtuWithResponse: Int
    var mtuWithoutResponse: Int
}

// MARK: - BLECentralManager

class BLECentralManager: NSObject, ObservableObject {

    // MARK: Published — zmiany automatycznie odświeżają SwiftUI

    @Published var state: CBManagerState = .unknown
    @Published var isScanning: Bool = false
    @Published var discoveredPeripherals: [DiscoveredPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var services: [CBService] = []
    @Published var characteristics: [CBService: [CharacteristicInfo]] = [:]
    @Published var log: [String] = []   // dziennik zdarzeń do wyświetlenia w UI
    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failedToConnect(String)
    }

    // MARK: Prywatne właściwości

    private var centralManager: CBCentralManager!

    // WAŻNE: Silna referencja do peripheral.
    // Bez tego ARC zwolni obiekt i połączenie/discovery przestanie działać.
    private var peripheral: CBPeripheral?

    // Kolejka dla wszystkich operacji BLE.
    // DLACZEGO NIE .main?
    // BLE może generować wiele zdarzeń — osobna kolejka nie blokuje UI.
    // Aktualizacje @Published właściwości robimy przez DispatchQueue.main.async.
    private let bleQueue = DispatchQueue(label: "com.blesample.central", qos: .userInitiated)

    // Flaga "chciałem skanować, ale BLE jeszcze nie było gotowe"
    // DLACZEGO:
    // centralManager.state może być .unknown przy inicjalizacji.
    // Zapisujemy intent i realizujemy go gdy state == .poweredOn.
    private var pendingScan = false

    // Przywrócone peripheral z State Restoration
    // (uzupełniane w willRestoreState przed poweredOn)
    private var restoredPeripherals: [CBPeripheral] = []

    // MARK: - Inicjalizacja

    override init() {
        super.init()

        // CBCentralManagerOptionRestoreIdentifierKey — włącza State Restoration.
        //
        // Mechanizm: iOS zapamiętuje stan managera (skanowanie, połączenia) i gdy
        // aplikacja zostanie zabita w tle, wznawia ją przy następnym zdarzeniu BLE
        // (peripheral wraca w zasięg, wysyła dane itp.).
        //
        // WYMAGANIA (oba muszą być spełnione):
        //   a) Info.plist: UIBackgroundModes zawiera "bluetooth-central"
        //   b) Fizyczne urządzenie — symulator NIE obsługuje State Restoration
        //      (rzuca NSInternalInconsistencyException gdy klucz jest podany)
        //
        // CBCentralManagerOptionShowPowerAlertKey: true
        //   → iOS wyświetli systemowy alert "Włącz Bluetooth" gdy BT jest wyłączone
        #if targetEnvironment(simulator)
        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        #else
        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.centralRestoreIdentifier,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
        #endif
    }

    // MARK: - Publiczne API — Skanowanie

    /// Rozpoczyna skanowanie BLE.
    /// Jeśli BLE nie jest jeszcze gotowe, zapisuje intent i wykona skan po poweredOn.
    func startScan() {
        // BEST PRACTICE: Zawsze sprawdzaj state przed skanowaniem.
        // Wywołanie scanForPeripherals gdy state != .poweredOn rzuci wyjątek.
        guard centralManager.state == .poweredOn else {
            addLog("Scan pending — BLE not ready yet (state: \(centralManager.state.description))")
            pendingScan = true
            return
        }
        performScan()
    }

    private func performScan() {
        // Wyczyść poprzednie wyniki
        DispatchQueue.main.async {
            self.discoveredPeripherals = []
            self.isScanning = true
        }

        // FILTROWANIE PO UUID USŁUGI:
        // Skanowanie z [serviceUUID] → iOS zwraca tylko urządzenia oferujące tę usługę.
        // Skanowanie z nil → zwraca wszystkie urządzenia w zasięgu.
        //
        // W TLE: nil jest ZABLOKOWANE przez iOS — musisz podać konkretne UUID.
        // Na pierwszym planie: nil działa, ale zużywa więcej energii.
        //
        // CBCentralManagerScanOptionAllowDuplicatesKey:
        // false (default) — każde urządzenie raportowane raz (oszczędność baterii)
        // true  — każdy odebrany pakiet advertisementu raportowany osobno
        //         (przydatne do monitorowania RSSI w czasie rzeczywistym)
        centralManager.scanForPeripherals(
            withServices: nil, // nil = wszystkie, do demonstracji
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        addLog("Scanning started (all devices, no UUID filter)")
    }

    /// Zatrzymuje skanowanie.
    func stopScan() {
        // BEST PRACTICE: Zawsze zatrzymuj skan po znalezieniu urządzenia.
        // Ciągłe skanowanie znacząco drenauje baterię.
        centralManager.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
        addLog("Scanning stopped")
    }

    // MARK: - Publiczne API — Połączenie

    /// Łączy się z wskazanym peripheral.
    func connect(to discoveredPeripheral: DiscoveredPeripheral) {
        let p = discoveredPeripheral.peripheral

        // WAŻNE: Ustaw delegata PRZED wywołaniem connect.
        // Jeśli zrobisz to po connect, możesz przegapić callback didConnect
        // (szczególnie gdy połączenie jest bardzo szybkie).
        p.delegate = self

        // Zachowaj silną referencję — bez tego ARC zwolni obiekt
        // i połączenie zostanie przerwane lub callbacki przestaną działać.
        self.peripheral = p

        stopScan()

        DispatchQueue.main.async { self.connectionState = .connecting }

        // CBConnectPeripheralOptionNotifyOnConnectionKey: true
        // → gdy połączenie nastąpi w tle, iOS pokaże powiadomienie użytkownikowi.
        // CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        // → powiadomienie przy rozłączeniu w tle.
        centralManager.connect(p, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        addLog("Connecting to \(p.name ?? p.identifier.uuidString)")
    }

    /// Rozłącza aktualnie połączone urządzenie.
    func disconnect() {
        guard let p = peripheral else { return }
        // cancelPeripheralConnection jest idempotentne — bezpieczne nawet gdy
        // peripheral jest już rozłączony.
        //
        // WAŻNE: connectionState NIE zmienia się tu natychmiast.
        // Zmiana stanu na .disconnected nastąpi asynchronicznie w callbacku
        // centralManager(_:didDisconnectPeripheral:error:).
        // Nie aktualizuj UI przed tym callbackiem.
        centralManager.cancelPeripheralConnection(p)
        addLog("Disconnecting from \(p.name ?? p.identifier.uuidString)")
    }

    // MARK: - Publiczne API — Retrieve (bez skanowania)

    /// Pobiera znane peripheral po UUID (np. po restarcie aplikacji).
    /// NIE wymaga skanowania — iOS zwraca peripheral z cache.
    /// DLACZEGO: peripheral.identifier jest stabilny dla pary iPhone–urządzenie.
    /// Można zapisać go w UserDefaults i reconnect bez skanowania.
    func retrieveKnownPeripheral(uuid: UUID) -> CBPeripheral? {
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        addLog("Retrieved \(peripherals.count) known peripheral(s) for UUID \(uuid)")
        return peripherals.first
    }

    /// Pobiera peripheral aktualnie połączone z systemem (przez inną aplikację lub system).
    /// Przydatne np. dla Apple Watch, AirPods — zawsze połączonych z systemem.
    func retrieveConnectedPeripherals() -> [CBPeripheral] {
        let peripherals = centralManager.retrieveConnectedPeripherals(
            withServices: [BLEConstants.transferServiceUUID]
        )
        addLog("Found \(peripherals.count) system-connected peripheral(s)")
        return peripherals
    }

    // MARK: - Publiczne API — GATT

    /// Odczytuje wartość charakterystyki jednorazowo (pull model).
    func readValue(for characteristic: CBCharacteristic) {
        guard let p = peripheral else { return }
        // Wywołuje async callback didUpdateValueFor po otrzymaniu odpowiedzi
        p.readValue(for: characteristic)
        addLog("Read requested for \(characteristic.uuid)")
    }

    /// Zapisuje dane do charakterystyki Z potwierdzeniem.
    /// Wolniejsze niż withoutResponse, ale gwarantuje dostarczenie.
    /// Callback: didWriteValueFor
    func writeWithResponse(data: Data, to characteristic: CBCharacteristic) {
        guard let p = peripheral else { return }
        // LIMIT ROZMIARU: Nie przekraczaj wartości zwracanej przez:
        //   peripheral.maximumWriteValueLength(for: .withResponse)
        // Core Bluetooth dopuszcza max 512 bytes dla .withResponse,
        // ale rzeczywisty limit zależy od negocjacji ATT MTU z peripheral.
        // Przy większych danych — fragmentuj samodzielnie (analogicznie do sendLargeData).
        p.writeValue(data, for: characteristic, type: .withResponse)
        addLog("Write (with response) \(data.count) bytes to \(characteristic.uuid)")
    }

    /// Zapisuje dane BEZ potwierdzenia — szybszy, ale bez gwarancji dostarczenia.
    /// Brak callbacka didWriteValueFor.
    /// Sprawdź canSendWriteWithoutResponse przed wysyłką — jeśli false,
    /// poczekaj na peripheralIsReady(toSendWriteWithoutResponse:).
    func writeWithoutResponse(data: Data, to characteristic: CBCharacteristic) {
        guard let p = peripheral else { return }

        // FLOW CONTROL — kluczowe dla dużych transferów!
        // Jeśli wyślesz zbyt wiele pakietów naraz, iOS cicho je dropuje.
        guard p.canSendWriteWithoutResponse else {
            addLog("WARNING: canSendWriteWithoutResponse = false, dropping packet")
            return
        }
        p.writeValue(data, for: characteristic, type: .withoutResponse)
        addLog("Write (without response) \(data.count) bytes to \(characteristic.uuid)")
    }

    /// Wysyła duże dane fragmentując je według aktualnego MTU.
    /// MTU (Maximum Transmission Unit) to max rozmiar payload jednego pakietu BLE.
    ///
    /// Rozmiary MTU w praktyce:
    ///   • withoutResponse: domyślnie 20 bytes (bez negocjacji MTU Exchange).
    ///     Po negocjacji ATT MTU Exchange max ~244 bytes (BLE 4.2+).
    ///     Sprawdź aktualną wartość przez: peripheral.maximumWriteValueLength(for: .withoutResponse)
    ///   • withResponse: max 512 bytes (limit Core Bluetooth, niezależnie od negocjacji).
    ///     Sprawdź przez: peripheral.maximumWriteValueLength(for: .withResponse)
    ///
    /// WAŻNE: Nie zakładaj stałej wartości — MTU zależy od negocjacji między urządzeniami.
    /// Zawsze używaj maximumWriteValueLength(for:) jako jedynego źródła prawdy.
    func sendLargeData(_ data: Data, to characteristic: CBCharacteristic) {
        guard let p = peripheral else { return }

        let mtu = p.maximumWriteValueLength(for: .withoutResponse)
        addLog("MTU for withoutResponse: \(mtu) bytes. Sending \(data.count) bytes total.")

        var offset = 0
        while offset < data.count {
            guard p.canSendWriteWithoutResponse else {
                addLog("Flow control: bufor iOS pełny po \(offset)/\(data.count) bytes. Transfer przerwany.")
                // UWAGA: Ta implementacja jest celowo uproszczona dla celów edukacyjnych.
                // break przerywa pętlę — pozostałe dane NIE zostaną wysłane automatycznie.
                //
                // W produkcyjnym kodzie należy:
                //   1. Zapisać aktualny `offset` jako właściwość klasy
                //   2. Zapisać `data` i `characteristic` jako właściwości klasy
                //   3. W callbacku peripheralIsReady(toSendWriteWithoutResponse:) —
                //      który jest już zaimplementowany niżej — wznowić pętlę od zapisanego offsetu.
                // Bez tego mechanizmu transfer dużych danych jest niekompletny gdy
                // bufor iOS wypełni się przed wysłaniem całości.
                break
            }
            let end = min(offset + mtu, data.count)
            let chunk = data[offset..<end]
            p.writeValue(chunk, for: characteristic, type: .withoutResponse)
            offset = end
        }
        addLog("Large data send: \(offset)/\(data.count) bytes wysłano")
    }

    /// Włącza lub wyłącza notyfikacje dla charakterystyki (push model).
    /// iOS automatycznie pisze do CCCD (0x2902) na peripheral.
    /// Odbiór: didUpdateValueFor (ten sam callback co readValue)
    func setNotify(_ enabled: Bool, for characteristic: CBCharacteristic) {
        guard let p = peripheral else { return }
        p.setNotifyValue(enabled, for: characteristic)
        addLog("Notify \(enabled ? "enabled" : "disabled") for \(characteristic.uuid)")
    }

    // MARK: - Helpers

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async {
            self.log.append("[\(timestamp)] \(message)")
            // Ogranicz log do 200 wpisów
            if self.log.count > 200 { self.log.removeFirst() }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentralManager: CBCentralManagerDelegate {

    // MARK: Stan managera

    /// WYMAGANY — wywoływany przy każdej zmianie stanu Bluetooth.
    /// Jest to PIERWSZE miejsce gdzie możesz bezpiecznie zacząć skanować.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.state = central.state }
        addLog("CBCentralManager state: \(central.state.description)")

        switch central.state {
        case .poweredOn:
            // BLE gotowe — zrealizuj odłożony skan jeśli był
            if pendingScan {
                pendingScan = false
                performScan()
            }
            // State Restoration: po powrocie do poweredOn obsłuż przywrócone peripheral
            handleRestoredPeripherals()

        case .poweredOff:
            // Wyczyść stan UI — połączenie zostało utracone
            DispatchQueue.main.async {
                self.connectedPeripheral = nil
                self.connectionState = .disconnected
                self.services = []
                self.characteristics = [:]
            }
        case .unauthorized:
            // Użytkownik odmówił dostępu do BLE lub brakuje NSBluetoothAlwaysUsageDescription
            addLog("ERROR: Bluetooth unauthorized — check Info.plist and user permissions")
        case .unsupported:
            addLog("ERROR: BLE not supported on this device")
        default:
            break
        }
    }

    // MARK: State Restoration

    /// Wywoływany gdy iOS wznawia aplikację po zabiciu w tle (State Restoration).
    /// WAŻNE: Ten callback przychodzi PRZED centralManagerDidUpdateState.
    /// Nie próbuj tu łączyć ani skanować — BLE może jeszcze nie być gotowe.
    /// Zapisz dane i obsłuż je w centralManagerDidUpdateState(.poweredOn).
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        addLog("=== STATE RESTORATION TRIGGERED ===")

        // Przywróć peripheral które były połączone lub w trakcie łączenia
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            addLog("Restoring \(peripherals.count) peripheral(s)")
            for p in peripherals {
                // Ustaw delegata od razu — peripheral może być w stanie .connected
                p.delegate = self
                restoredPeripherals.append(p)
                addLog("  Restored: \(p.name ?? p.identifier.uuidString) state=\(p.state.description)")
            }
        }

        // Przywróć parametry skanowania (jeśli skanowanie było aktywne)
        if let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            addLog("Restoring scan for services: \(scanServices.map { $0.uuidString })")
            // Ustaw pendingScan — skanowanie wznowi się po poweredOn
            pendingScan = true
        }
    }

    /// Obsługa przywróconych peripheral po State Restoration (wołana z poweredOn).
    private func handleRestoredPeripherals() {
        for p in restoredPeripherals {
            // Zachowaj silną referencję do pierwszego przywróconego peripheral
            if self.peripheral == nil { self.peripheral = p }

            switch p.state {
            case .connected:
                // Peripheral jest już połączony — nie trzeba reconnect.
                // Musisz jednak ponownie odkryć usługi — dane GATT mogą być nieaktualne.
                addLog("Restored peripheral already connected: \(p.name ?? "?"), rediscovering services")
                DispatchQueue.main.async {
                    self.connectedPeripheral = p
                    self.connectionState = .connected
                }
                p.discoverServices(nil)

            case .connecting:
                // iOS kontynuuje próbę połączenia — poczekaj na didConnect
                addLog("Restored peripheral still connecting: \(p.name ?? "?")")

            case .disconnected:
                // Peripheral rozłączył się gdy aplikacja była zabita — spróbuj ponownie
                addLog("Restored peripheral disconnected, reconnecting: \(p.name ?? "?")")
                centralManager.connect(p, options: nil)

            default:
                break
            }
        }
        restoredPeripherals.removeAll()
    }

    // MARK: Discovery

    /// Wywoływany dla każdego wykrytego urządzenia BLE.
    /// advertisementData zawiera dane z pakietu broadcast peripheral.
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // RSSI w dBm:
        // -50 do -60 → bardzo blisko (< 1m)
        // -60 do -70 → blisko (1–3m)
        // -70 do -80 → średni zasięg (3–10m)
        // -80 do -90 → słaby sygnał (> 10m)
        // 127        → sentinel NSNumber "RSSI not available" — oznacza że sprzęt
        //              nie zwrócił pomiaru (np. chwilowy brak danych radiowych).
        //              Wartość 127 (INT8_MAX) jest zdefiniowana przez Core Bluetooth
        //              jako specjalny marker — nie interpretuj jej jako dBm.
        let rssiValue = RSSI.intValue

        // Parsowanie advertisementData — pełna lista kluczy:
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? false
        let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
        // CBAdvertisementDataServiceDataKey — słownik [CBUUID: Data] z danymi usługi
        // CBAdvertisementDataOverflowServiceUUIDsKey — UUID z "overflow" obszaru pakietu

        let discovered = DiscoveredPeripheral(
            id: peripheral.identifier,
            peripheral: peripheral,
            localName: localName ?? peripheral.name,
            rssi: rssiValue,
            serviceUUIDs: serviceUUIDs,
            manufacturerData: manufacturerData,
            isConnectable: isConnectable,
            txPowerLevel: txPower,
            discoveredAt: Date()
        )

        DispatchQueue.main.async {
            // Aktualizuj istniejący wpis lub dodaj nowy
            if let idx = self.discoveredPeripherals.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredPeripherals[idx] = discovered
            } else {
                self.discoveredPeripherals.append(discovered)
            }
        }
    }

    // MARK: Połączenie

    /// Połączenie udane.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("Connected to \(peripheral.name ?? peripheral.identifier.uuidString)")
        DispatchQueue.main.async {
            self.connectedPeripheral = peripheral
            self.connectionState = .connected
            self.services = []
            self.characteristics = [:]
        }
        // nil = odkryj WSZYSTKIE usługi.
        // Filtrowanie po [BLEConstants.transferServiceUUID] odkryłoby tylko własną usługę FFE0
        // i nic nie pokazywałoby dla innych urządzeń. Demo powinno działać z dowolnym peripheral.
        peripheral.discoverServices(nil)
    }

    /// Połączenie nieudane (np. timeout, urządzenie niedostępne).
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription ?? "unknown error"
        addLog("Failed to connect: \(msg)")
        DispatchQueue.main.async {
            self.connectionState = .failedToConnect(msg)
            self.peripheral = nil
        }
    }

    /// Rozłączenie — może być inicjowane przez nas (error == nil) lub nieoczekiwane (error != nil).
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if let error = error {
            // Nieoczekiwane rozłączenie (np. urządzenie wyszło z zasięgu)
            addLog("Unexpectedly disconnected: \(error.localizedDescription)")
            // STRATEGIA RECONNECT: spróbuj ponownie automatycznie
            // W produkcji rozważ exponential backoff zamiast natychmiastowego retry
            centralManager.connect(peripheral, options: nil)
        } else {
            // Czyste rozłączenie — inicjowane przez cancelPeripheralConnection
            addLog("Disconnected cleanly from \(peripheral.name ?? "?")")
            self.peripheral = nil
        }
        DispatchQueue.main.async {
            self.connectedPeripheral = nil
            self.connectionState = .disconnected
            self.services = []
            self.characteristics = [:]
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralManager: CBPeripheralDelegate {

    // MARK: GATT Discovery

    /// Wywoływany po zakończeniu discoverServices().
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            addLog("Service discovery error: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        addLog("Discovered \(services.count) service(s)")

        DispatchQueue.main.async { self.services = services }

        for service in services {
            addLog("  Service: \(service.uuid) (primary: \(service.isPrimary))")
            // Odkryj charakterystyki dla każdej usługi
            // nil = odkryj WSZYSTKIE charakterystyki usługi.
            // Filtrowanie po konkretnych UUID (readNotifyCharUUID, writeCharUUID) pokazuje tylko
            // własne charakterystyki FFE1/FFE2. Demo powinno działać z dowolnym peripheral.
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// Wywoływany po zakończeniu discoverCharacteristics(for:).
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            addLog("Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        guard let chars = service.characteristics else { return }
        addLog("Discovered \(chars.count) characteristic(s) for service \(service.uuid)")

        // Zbuduj listę CharacteristicInfo z aktualnymi wartościami MTU
        let infos = chars.map { char -> CharacteristicInfo in
            addLog("  Char: \(char.uuid) props=[\(char.properties.description)]")
            return CharacteristicInfo(
                id: char.uuid,
                characteristic: char,
                lastValue: char.value,
                isNotifying: char.isNotifying,
                mtuWithResponse: peripheral.maximumWriteValueLength(for: .withResponse),
                mtuWithoutResponse: peripheral.maximumWriteValueLength(for: .withoutResponse)
            )
        }

        DispatchQueue.main.async {
            self.characteristics[service] = infos
        }
    }

    // MARK: Odczyt / Notyfikacje

    /// Wywoływany gdy:
    /// 1. Odpowiedź na readValue() nadeszła
    /// 2. Peripheral wysłał notyfikację (po setNotifyValue(true))
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            addLog("Read/notify error for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else {
            addLog("No data for \(characteristic.uuid)")
            return
        }
        addLog("Value updated for \(characteristic.uuid): \(data.hexString) (\(data.count) bytes)")

        // Zaktualizuj CharacteristicInfo w słowniku
        DispatchQueue.main.async {
            for (service, infos) in self.characteristics {
                if let idx = infos.firstIndex(where: { $0.id == characteristic.uuid }) {
                    self.characteristics[service]?[idx].lastValue = data
                    self.characteristics[service]?[idx].isNotifying = characteristic.isNotifying
                }
            }
        }
    }

    /// Wywoływany tylko dla writeValue(type: .withResponse) — potwierdzenie od peripheral.
    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            addLog("Write error for \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            addLog("Write confirmed by \(characteristic.uuid)")
        }
    }

    /// Wywoływany gdy iOS potwierdzi zmianę stanu notyfikacji (setNotifyValue).
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            addLog("Notify state change error: \(error.localizedDescription)")
            return
        }
        let state = characteristic.isNotifying ? "ON" : "OFF"
        addLog("Notifications \(state) for \(characteristic.uuid)")

        DispatchQueue.main.async {
            for (service, infos) in self.characteristics {
                if let idx = infos.firstIndex(where: { $0.id == characteristic.uuid }) {
                    self.characteristics[service]?[idx].isNotifying = characteristic.isNotifying
                }
            }
        }
    }

    /// Flow control dla writeWithoutResponse.
    /// Wywoływany gdy peripheral jest znowu gotowy na przyjęcie danych.
    /// Wznów tutaj wysyłanie danych po przerwie z powodu canSendWriteWithoutResponse == false.
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        addLog("Peripheral ready to receive writeWithoutResponse")
        // W tej aplikacji logujemy tylko — w produkcji wznów tu przerwany transfer
    }
}

// MARK: - CBManagerState extension

extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

extension CBPeripheralState {
    var description: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }
}

extension CBCharacteristicProperties {
    var description: String {
        var parts: [String] = []
        if contains(.read) { parts.append("read") }
        if contains(.write) { parts.append("write") }
        if contains(.writeWithoutResponse) { parts.append("writeNoRsp") }
        if contains(.notify) { parts.append("notify") }
        if contains(.indicate) { parts.append("indicate") }
        if contains(.broadcast) { parts.append("broadcast") }
        return parts.joined(separator: "|")
    }
}

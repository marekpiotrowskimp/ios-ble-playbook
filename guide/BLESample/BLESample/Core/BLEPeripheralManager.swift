// BLEPeripheralManager.swift
// BLESample
//
// Kompletny manager roli Peripheral — iPhone rozgłasza się jako urządzenie BLE,
// obsługuje zapytania od Central (odczyt/zapis) i wysyła notyfikacje.
//
// ARCHITEKTURA:
// Analogiczna do BLECentralManager — ObservableObject z @Published właściwościami.
// Callbacki CBPeripheralManagerDelegate przychodzą na bleQueue, UI na main queue.
//
// PRZEPŁYW:
// init() → peripheralManagerDidUpdateState(.poweredOn)
//   → setupService() → peripheralManager(_:didAdd:)
//     → startAdvertising() → peripheralManagerDidStartAdvertising()
//       → [Central się łączy i pyta]
//         → didReceiveRead / didReceiveWrite
//           → respond(to:withResult:)
//         → didSubscribeTo → updateValue() → [Central otrzymuje notyfikację]

import Foundation
import CoreBluetooth
import Combine

// MARK: - Model

/// Informacja o Central która subskrybuje notyfikacje.
struct SubscribedCentral: Identifiable {
    let id: UUID        // central.identifier
    let central: CBCentral
    let maximumUpdateValueLength: Int   // max rozmiar notyfikacji dla tego Central
}

/// Odebrany zapis od Central.
struct ReceivedWrite: Identifiable {
    let id = UUID()
    let data: Data
    let characteristicUUID: CBUUID
    let timestamp: Date
}

// MARK: - BLEPeripheralManager

class BLEPeripheralManager: NSObject, ObservableObject {

    // MARK: Published

    @Published var state: CBManagerState = .unknown
    @Published var isAdvertising: Bool = false
    @Published var subscribedCentrals: [SubscribedCentral] = []
    @Published var receivedWrites: [ReceivedWrite] = []
    @Published var log: [String] = []

    // Wartość, którą Peripheral zwraca na żądanie odczytu.
    // W realnej aplikacji byłby to pomiar sensora, stan urządzenia itp.
    @Published var readableValue: String = "Hello from BLESample Peripheral!"

    // MARK: Prywatne

    private var peripheralManager: CBPeripheralManager!

    // Mutowalne charakterystyki — tylko CBMutableCharacteristic można modyfikować i używać
    // do wysyłania notyfikacji. CBCharacteristic (niemutowalna) to tylko odczyt.
    private var readNotifyCharacteristic: CBMutableCharacteristic?
    private var writeCharacteristic: CBMutableCharacteristic?

    // Dane czekające na wysłanie gdy peripheralManagerIsReady(toUpdateSubscribers:)
    private var pendingNotificationData: Data?

    private let bleQueue = DispatchQueue(label: "com.blesample.peripheral", qos: .userInitiated)

    // MARK: - Inicjalizacja

    override init() {
        super.init()

        // CBPeripheralManagerOptionRestoreIdentifierKey — włącza State Restoration.
        // iOS może wznowić aplikację w tle gdy Central spróbuje się połączyć.
        // Tylko na fizycznym urządzeniu — symulator rzuca NSInternalInconsistencyException.
        // CBPeripheralManagerOptionShowPowerAlertKey: true → systemowy alert "Włącz Bluetooth".
        #if targetEnvironment(simulator)
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: bleQueue,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
        )
        #else
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: bleQueue,
            options: [
                CBPeripheralManagerOptionRestoreIdentifierKey: BLEConstants.peripheralRestoreIdentifier,
                CBPeripheralManagerOptionShowPowerAlertKey: true
            ]
        )
        #endif
    }

    // MARK: - Setup GATT

    /// Tworzy i rejestruje usługę BLE z charakterystykami.
    /// Wywoływać dopiero po state == .poweredOn.
    private func setupService() {
        // CHARAKTERYSTYKA DO ODCZYTU I NOTYFIKACJI
        // properties:
        //   .read    → Central może jednorazowo pobrać wartość (pull)
        //   .notify  → Peripheral może push'ować zmiany bez pytania (wymaga CCCD)
        //
        // .notify vs .indicate — kluczowa różnica:
        //   .notify   — "fire and forget": Peripheral wysyła dane, nie czeka na ACK od Central.
        //               Szybsze, ale brak gwarancji dostarczenia na poziomie GATT.
        //   .indicate — "reliable": Peripheral wysyła dane i CZEKA na potwierdzenie od Central
        //               (ATT Handle Value Confirmation). Wolniejsze, ale gwarantuje dostarczenie.
        //               Callback didUpdateNotificationStateFor wywołuje się tak samo dla obu.
        //               Jeśli Central nie potwierdzi, iOS ponawia wysyłkę lub informuje o błędzie.
        //
        // W tej aplikacji używamy .notify — wystarczające do demonstracji push modelu.
        // permissions:
        //   .readable → Central może czytać bez szyfrowania
        // value: nil → dynamiczna — wartość jest zwracana w didReceiveRead callback
        //             (gdyby value != nil, iOS cache'uje ją i nie woła callbacka)
        readNotifyCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.readNotifyCharUUID,
            properties: [.read, .notify],
            value: nil,             // nil = dynamiczna wartość!
            permissions: [.readable]
        )

        // CHARAKTERYSTYKA DO ZAPISU
        // properties:
        //   .write                → zapis z ACK (Central czeka na odpowiedź)
        //   .writeWithoutResponse → zapis bez ACK (szybszy, nie gwarantuje dostarczenia)
        // permissions:
        //   .writeable → Central może pisać bez szyfrowania
        writeCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.writeCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        // USŁUGA (Service)
        // primary: true → główna usługa urządzenia
        // primary: false → pomocnicza (np. included service)
        let service = CBMutableService(type: BLEConstants.transferServiceUUID, primary: true)
        service.characteristics = [readNotifyCharacteristic!, writeCharacteristic!]

        // Dodaj usługę do GATT serwera.
        // Callback: peripheralManager(_:didAdd:error:)
        peripheralManager.add(service)
        addLog("Service added: \(BLEConstants.transferServiceUUID)")
    }

    // MARK: - Publiczne API — Advertising

    /// Rozpoczyna rozgłaszanie (advertising).
    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            addLog("Cannot advertise — state: \(peripheralManager.state.description)")
            return
        }
        guard !isAdvertising else { return }

        // Pakiet advertisementu zawiera:
        //   CBAdvertisementDataServiceUUIDsKey — UUID usług (widoczne dla skanerów)
        //   CBAdvertisementDataLocalNameKey    — nazwa urządzenia
        //
        // W TLE: iOS automatycznie skraca pakiet do samych ServiceUUIDs.
        // Nazwa lokalna NIE jest rozgłaszana w tle.
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.transferServiceUUID],
            CBAdvertisementDataLocalNameKey: BLEConstants.peripheralLocalName
        ])
        addLog("Advertising started")
    }

    /// Zatrzymuje rozgłaszanie.
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        DispatchQueue.main.async { self.isAdvertising = false }
        addLog("Advertising stopped")
    }

    // MARK: - Publiczne API — Notyfikacje

    /// Wysyła dane do wszystkich subskrybentów notyfikacji.
    /// Używać tylko dla charakterystyki z właściwością .notify lub .indicate.
    func sendNotification(text: String) {
        guard let char = readNotifyCharacteristic else {
            addLog("ERROR: readNotifyCharacteristic not set up yet")
            return
        }
        guard let data = text.data(using: .utf8) else { return }
        sendNotificationData(data, for: char)
    }

    private func sendNotificationData(_ data: Data, for characteristic: CBMutableCharacteristic) {
        // updateValue zwraca false gdy wewnętrzna kolejka jest pełna.
        // W takim przypadku iOS wywoła peripheralManagerIsReady(toUpdateSubscribers:)
        // gdy będzie znowu gotowy — wtedy wznów wysyłkę.
        let sent = peripheralManager.updateValue(
            data,
            for: characteristic,
            onSubscribedCentrals: nil   // nil = wyślij do wszystkich subskrybentów
            // Można podać konkretne [CBCentral] aby wysłać tylko do wybranych
        )
        if sent {
            addLog("Notification sent: \(data.hexString) (\(data.count) bytes)")
            pendingNotificationData = nil
        } else {
            // Kolejka pełna — zachowaj dane i wznów w peripheralManagerIsReady
            addLog("Notification queued (peripheral manager busy)")
            pendingNotificationData = data
        }
    }

    /// Aktualizuje wartość zwracaną przy odczycie.
    func updateReadableValue(_ value: String) {
        DispatchQueue.main.async { self.readableValue = value }
        addLog("Readable value updated: \(value)")
    }

    // MARK: - Helpers

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async {
            self.log.append("[\(timestamp)] \(message)")
            if self.log.count > 200 { self.log.removeFirst() }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralManager: CBPeripheralManagerDelegate {

    // MARK: Stan

    /// WYMAGANY — analogiczny do centralManagerDidUpdateState.
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        DispatchQueue.main.async { self.state = peripheral.state }
        addLog("CBPeripheralManager state: \(peripheral.state.description)")

        switch peripheral.state {
        case .poweredOn:
            // BLE gotowe — skonfiguruj GATT tylko jeśli jeszcze nie było
            if readNotifyCharacteristic == nil {
                setupService()
            }
        case .poweredOff:
            DispatchQueue.main.async {
                self.isAdvertising = false
                self.subscribedCentrals = []
            }
        default:
            break
        }
    }

    // MARK: State Restoration

    /// Wywoływany gdy iOS wznawia aplikację po zabiciu — Peripheral rola.
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        addLog("=== PERIPHERAL STATE RESTORATION ===")

        // Przywróć usługi które były zarejestrowane
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            addLog("Restoring \(services.count) service(s)")
            for service in services {
                addLog("  Service: \(service.uuid)")
                // Przywróć referencje do charakterystyk
                for char in (service.characteristics ?? []) {
                    if let mutableChar = char as? CBMutableCharacteristic {
                        if mutableChar.uuid == BLEConstants.readNotifyCharUUID {
                            readNotifyCharacteristic = mutableChar
                        } else if mutableChar.uuid == BLEConstants.writeCharUUID {
                            writeCharacteristic = mutableChar
                        }
                    }
                }
            }
        }

        // Sprawdź czy advertising był aktywny
        if let advertisementData = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] as? [String: Any] {
            addLog("Restoring advertising: \(advertisementData)")
            // Advertising zostanie wznowiony automatycznie przez system
            DispatchQueue.main.async { self.isAdvertising = true }
        }
    }

    // MARK: Service Setup

    /// Callback po dodaniu usługi (peripheralManager.add(service)).
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            addLog("Failed to add service: \(error.localizedDescription)")
            return
        }
        addLog("Service added successfully: \(service.uuid)")
        // Usługa gotowa — możemy teraz zacząć advertising
        startAdvertising()
    }

    /// Callback po uruchomieniu advertisingu (peripheralManager.startAdvertising).
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            addLog("Advertising failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.isAdvertising = false }
        } else {
            addLog("Advertising active")
            DispatchQueue.main.async { self.isAdvertising = true }
        }
    }

    // MARK: Obsługa połączeń (subskrypcje)

    /// Wywoływany gdy Central włączy notyfikacje dla charakterystyki (setNotifyValue(true)).
    /// Od tego momentu możemy wysyłać dane do tego Central przez updateValue.
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        addLog("Central subscribed to \(characteristic.uuid): \(central.identifier)")

        // maximumUpdateValueLength — max rozmiar jednego pakietu notyfikacji dla tego Central
        // Może się różnić dla różnych Central (różne negocjacje MTU)
        let subscribedCentral = SubscribedCentral(
            id: central.identifier,
            central: central,
            maximumUpdateValueLength: central.maximumUpdateValueLength
        )
        DispatchQueue.main.async {
            self.subscribedCentrals.append(subscribedCentral)
        }

        // Opcjonalnie: wyślij aktualną wartość od razu po subskrypcji
        if let data = readableValue.data(using: .utf8),
           let char = readNotifyCharacteristic {
            sendNotificationData(data, for: char)
        }
    }

    /// Wywoływany gdy Central wyłączy notyfikacje (setNotifyValue(false) lub rozłączenie).
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        addLog("Central unsubscribed from \(characteristic.uuid): \(central.identifier)")
        DispatchQueue.main.async {
            self.subscribedCentrals.removeAll { $0.id == central.identifier }
        }
    }

    // MARK: Obsługa zapytań Read

    /// Wywoływany gdy Central wywoła readValue(for:) lub połączy się i czyta wartość.
    /// WAŻNE: Musisz zawsze wywołać respond(to:withResult:) — inaczej Central dostanie timeout.
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        addLog("Read request for \(request.characteristic.uuid) from \(request.central.identifier)")

        if request.characteristic.uuid == BLEConstants.readNotifyCharUUID {
            // request.offset — Central może czytać od dowolnego offsetu (dla długich wartości)
            // Sprawdź czy offset nie przekracza danych
            guard let data = readableValue.data(using: .utf8) else {
                peripheral.respond(to: request, withResult: .unlikelyError)
                return
            }
            guard request.offset <= data.count else {
                // Błędny offset — zwróć błąd ATT
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            // Zwróć dane od żądanego offsetu
            request.value = data.subdata(in: request.offset..<data.count)
            peripheral.respond(to: request, withResult: .success)
        } else {
            // Nieznana charakterystyka
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }

    // MARK: Obsługa zapytań Write

    /// Wywoływany gdy Central zapisze dane przez writeValue(type: .withResponse).
    /// Tablica requests — iOS może zgrupować wiele zapisów w jednej transakcji ATT.
    /// WAŻNE: Odpowiedz na ostatni request — to zamyka transakcję.
    ///
    /// KLUCZOWA UWAGA — writeWithoutResponse NIE trafia tutaj:
    /// Zapis typu .withoutResponse (CBCharacteristicWriteType.withoutResponse) jest wysyłany
    /// przez Central bez oczekiwania na potwierdzenie. System BLE go przyjmuje, ale
    /// NIE generuje żadnego callbacka didReceiveWrite po stronie Peripheral.
    /// Dane są po prostu ignorowane przez Core Bluetooth jeśli charakterystyka ma tylko
    /// .writeWithoutResponse — nie istnieje mechanizm ich odebrania przez Peripheral!
    /// (W praktyce urządzenia sprzętowe obsługują to na poziomie firmware poza Core Bluetooth.)
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        addLog("Received \(requests.count) write request(s)")

        for request in requests {
            guard let data = request.value else { continue }
            addLog("  Write to \(request.characteristic.uuid): \(data.hexString) (\(data.count) bytes)")

            if request.characteristic.uuid == BLEConstants.writeCharUUID {
                // Przetwórz odebranie dane
                let received = ReceivedWrite(
                    data: data,
                    characteristicUUID: request.characteristic.uuid,
                    timestamp: Date()
                )
                DispatchQueue.main.async {
                    self.receivedWrites.append(received)
                    // Opcja: zaktualizuj readableValue na odebrane dane
                    if let text = String(data: data, encoding: .utf8) {
                        self.readableValue = "Echo: \(text)"
                    }
                }
            }
        }

        // Zawsze odpowiedz na ostatni request — iOS czeka na respond() zanim wyśle ACK do Central
        if let last = requests.last {
            peripheral.respond(to: last, withResult: .success)
        }
    }

    // MARK: Flow Control

    /// Wywoływany gdy peripheralManager jest znowu gotowy na wysyłanie notyfikacji.
    /// Wznów tutaj wysyłanie danych które zostały odrzucone przez updateValue (zwróciło false).
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        addLog("Peripheral manager ready — resuming notifications")
        if let data = pendingNotificationData, let char = readNotifyCharacteristic {
            sendNotificationData(data, for: char)
        }
    }
}

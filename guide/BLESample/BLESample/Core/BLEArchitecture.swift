// BLEArchitecture.swift
// BLESample
//
// Ten plik nie zawiera kodu wykonywalnego — jest dokumentacją architekturalną projektu.
// Opisuje decyzje projektowe, przepływ danych, wątki i wzorce używane w BLESample.
//
// ============================================================
// PRZEGLĄD ARCHITEKTURY
// ============================================================
//
// BLESample demonstruje jednoczesne pełnienie obu ról BLE na jednym iPhonie:
//
//   ┌─────────────────────────────────────────────────────┐
//   │                   BLESample App                     │
//   │                                                     │
//   │  ┌──────────────────┐   ┌────────────────────────┐  │
//   │  │ BLECentralManager│   │ BLEPeripheralManager   │  │
//   │  │  (rola: Central) │   │  (rola: Peripheral)    │  │
//   │  └──────────────────┘   └────────────────────────┘  │
//   │          │                         │                 │
//   │          └──────────┬──────────────┘                 │
//   │                     │                                │
//   │              ContentView (TabView)                   │
//   │           [Central] [Peripheral] [Log]               │
//   └─────────────────────────────────────────────────────┘
//
// Obie role działają równolegle — iPhone jednocześnie skanuje (Central)
// i rozgłasza się (Peripheral). Jest to możliwe w BLE od iOS 6+.
//
// ============================================================
// WZORZEC: ObservableObject + @Published
// ============================================================
//
// Oba managery są klasami dziedziczącymi po NSObject (wymaganie delegatów CB)
// i implementują ObservableObject (wymaganie SwiftUI).
//
// Dlaczego klasa, nie struct?
//   • CBCentralManager/CBPeripheralManager wymagają delegata — referencja musi być stabilna.
//   • Stan BLE żyje tak długo jak aplikacja — singleton-like lifecycle.
//   • @Published nie działa ze struct w ObservableObject.
//
// Przepływ danych (unidirectional):
//
//   Core Bluetooth (OS) → delegate callback (bleQueue)
//       → DispatchQueue.main.async { self.@Published = ... }
//           → SwiftUI automatycznie odświeża widoki
//
// ============================================================
// WĄTKI (THREADING MODEL)
// ============================================================
//
//   bleQueue (DispatchQueue, .userInitiated, serial)
//   ├─ Wszystkie callbacki CBCentralManagerDelegate
//   ├─ Wszystkie callbacki CBPeripheralDelegate
//   └─ Wszystkie callbacki CBPeripheralManagerDelegate
//
//   DispatchQueue.main (serial)
//   └─ Wszystkie aktualizacje @Published właściwości → UI
//
// DLACZEGO OSOBNA KOLEJKA DLA BLE?
//   BLE może generować bardzo wiele zdarzeń (każdy pakiet advertisementu,
//   każda notyfikacja). Osobna kolejka zapewnia że:
//   a) UI (main queue) nie jest blokowane przez przetwarzanie BLE,
//   b) BLE callbacki nie są blokowane przez rendering UI.
//
// ZASADA: Nigdy nie modyfikuj @Published właściwości poza main queue.
//         Nigdy nie wywołuj operacji BLE z main queue (może deadlock przy
//         używaniu .sync na bleQueue z main).
//
// ============================================================
// CYKL ŻYCIA MANAGERA
// ============================================================
//
// BLECentralManager:
//
//   init()
//     └─ CBCentralManager(delegate:queue:options:)
//           │
//           ▼  (asynchronicznie, może po chwili)
//   centralManagerDidUpdateState(.poweredOn)
//     └─ startScan() → didDiscover() × N
//           └─ connect() → didConnect()
//                 └─ discoverServices() → didDiscoverServices()
//                       └─ discoverCharacteristics() × N → didDiscoverCharacteristics()
//                             ├─ readValue() → didUpdateValueFor()
//                             ├─ writeValue() → didWriteValueFor() (tylko .withResponse)
//                             └─ setNotifyValue(true) → didUpdateNotificationStateFor()
//                                   └─ [periodic] didUpdateValueFor()  ← notyfikacje
//
// BLEPeripheralManager:
//
//   init()
//     └─ CBPeripheralManager(delegate:queue:options:)
//           │
//           ▼
//   peripheralManagerDidUpdateState(.poweredOn)
//     └─ setupService() → peripheralManager(_:didAdd:)
//           └─ startAdvertising() → peripheralManagerDidStartAdvertising()
//                 │
//                 ▼  [Central się łączy i wykonuje operacje]
//                 ├─ didReceiveRead → respond(to:withResult:.success)
//                 ├─ didReceiveWrite → respond(to:withResult:.success)
//                 └─ didSubscribeTo
//                       └─ updateValue() → [Central odbiera notyfikację]
//                             └─ (jeśli false) → peripheralManagerIsReady → updateValue()
//
// ============================================================
// STATE RESTORATION
// ============================================================
//
// Mechanizm iOS pozwalający wznowić aplikację w tle gdy nastąpi zdarzenie BLE.
//
// WYMAGANIA:
//   1. Info.plist: UIBackgroundModes zawiera "bluetooth-central" i/lub "bluetooth-peripheral"
//   2. Opcja RestoreIdentifierKey przy inicjalizacji managera
//   3. TYLKO fizyczne urządzenie (symulator nie obsługuje)
//
// KOLEJNOŚĆ CALLBACKÓW po wznowieniu:
//
//   1. application(_:didFinishLaunchingWithOptions:) z kluczem UIApplicationLaunchOptionsKey
//   2. willRestoreState(_:dict:)           ← dane o poprzednim stanie BLE
//   3. centralManagerDidUpdateState(.poweredOn)  ← dopiero tu można działać
//
// DLACZEGO willRestoreState przed poweredOn?
//   iOS gwarantuje że willRestoreState jest wołany przed poweredOn,
//   żebyś mógł przywrócić referencje do peripheral/usług zanim zaczniesz z nich korzystać.
//
// ============================================================
// MTU I FRAGMENTACJA DANYCH
// ============================================================
//
// MTU (Maximum Transmission Unit) = maksymalny rozmiar payload jednego pakietu ATT.
//
//   Bez negocjacji MTU Exchange:  23 bytes ATT = 20 bytes payload
//   Po negocjacji (BLE 4.2+):     max 512 bytes ATT = 244–509 bytes payload
//
//   Dla .withoutResponse:  sprawdź peripheral.maximumWriteValueLength(for: .withoutResponse)
//   Dla .withResponse:     sprawdź peripheral.maximumWriteValueLength(for: .withResponse)
//   Dla notyfikacji:       sprawdź central.maximumUpdateValueLength (po stronie Peripheral)
//
// Nigdy nie zakładaj stałej wartości — zawsze pytaj API o aktualny MTU.
// iOS negocjuje MTU automatycznie — wynik zależy od obu urządzeń.
//
// ============================================================
// PRZEPŁYW DANYCH W PROJEKCIE
// ============================================================
//
// Central → Peripheral (zapis):
//   CharacteristicView → BLECentralManager.writeWithResponse/writeWithoutResponse
//       → CBPeripheral.writeValue()
//           → [BLE radio]
//               → CBPeripheralManager.didReceiveWrite (tylko .withResponse!)
//                   → BLEPeripheralManager.receivedWrites (@Published)
//                       → PeripheralView (UI)
//
// Peripheral → Central (notyfikacje):
//   NotificationView → BLEPeripheralManager.sendNotification()
//       → CBPeripheralManager.updateValue()
//           → [BLE radio]
//               → CBPeripheral.didUpdateValueFor
//                   → BLECentralManager.characteristics[@Published]
//                       → CharacteristicView (UI)
//
// ============================================================
// STRUKTURA PLIKÓW
// ============================================================
//
//   Core/
//   ├─ BLEArchitecture.swift     ← ten plik (dokumentacja)
//   ├─ BLEConstants.swift        ← UUID, identyfikatory (jedno miejsce dla wszystkich stałych)
//   ├─ BLECentralManager.swift   ← CBCentralManagerDelegate + CBPeripheralDelegate
//   └─ BLEPeripheralManager.swift← CBPeripheralManagerDelegate
//
//   Views/
//   ├─ ContentView.swift          ← TabView: zakładki Central / Peripheral / Log
//   ├─ Central/
//   │   ├─ ScanView.swift         ← lista wykrytych urządzeń BLE
//   │   ├─ PeripheralDetailView.swift ← usługi i charakterystyki połączonego peripheral
//   │   └─ CharacteristicView.swift   ← odczyt / zapis / notyfikacje dla jednej charakterystyki
//   └─ Peripheral/
//       ├─ PeripheralView.swift   ← status advertising, subskrybenci, odebrane dane
//       └─ NotificationView.swift ← wysyłanie notyfikacji do Central
//
//   Extensions/
//   └─ Data+Hex.swift             ← Data.hexString do debugowania bajtów
//
// ============================================================
// KLUCZOWE PUŁAPKI (LESSONS LEARNED)
// ============================================================
//
// 1. STRONG REFERENCE DO PERIPHERAL
//    CBPeripheral musi być trzymany przez silną referencję (self.peripheral = p).
//    Bez tego ARC zwalnia obiekt i callbacki przestają działać — bez błędu!
//
// 2. DELEGATE PRZED CONNECT
//    peripheral.delegate = self PRZED centralManager.connect().
//    Możesz przegapić bardzo szybki didConnect callback.
//
// 3. DYNAMICZNA WARTOŚĆ CHARAKTERYSTYKI
//    CBMutableCharacteristic.value = nil → dynamiczna (callback didReceiveRead).
//    CBMutableCharacteristic.value != nil → statyczna (iOS cache, brak callbacka).
//
// 4. CCCD (Client Characteristic Configuration Descriptor)
//    Dla .notify/.indicate iOS automatycznie dodaje descriptor 0x2902.
//    Central woła setNotifyValue(true) — iOS zapisuje CCCD przez ATT.
//    Nie musisz zarządzać CCCD ręcznie w Core Bluetooth.
//
// 5. SYMULATOR A FIZYCZNE URZĄDZENIE
//    Symulator: brak State Restoration, brak background BLE, ograniczone BLE ogólnie.
//    Do produkcyjnych testów zawsze używaj fizycznego iPhone.
//
// 6. BACKGROUND SCANNING — WYMAGANY FILTR UUID
//    centralManager.scanForPeripherals(withServices: nil) jest zablokowane w tle.
//    W tle MUSISZ podać konkretne [serviceUUID] — inaczej iOS nie dostarcza zdarzeń.

// Plik jest czystą dokumentacją — brak importów i kodu wykonywalnego.

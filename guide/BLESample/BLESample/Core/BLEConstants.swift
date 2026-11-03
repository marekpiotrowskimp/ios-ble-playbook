// BLEConstants.swift
// BLESample
//
// Centralne miejsce dla wszystkich UUID używanych w projekcie.
//
// DLACZEGO TU?
// Trzymanie UUID w jednym miejscu eliminuje błędy typograficzne i ułatwia
// zmianę UUID bez przeszukiwania całego projektu.
//
// RODZAJE UUID:
// - 16-bit (np. "180D") — standardy Bluetooth SIG (Heart Rate, Battery itp.)
//   Pełny 128-bit zapis to: 0000xxxx-0000-1000-8000-00805F9B34FB
//   Core Bluetooth akceptuje krótki zapis "180D" i automatycznie rozszerza go do 128 bitów.
// - 128-bit (własne) — niestandardowe UUID dla własnych profili BLE.
//   Używane gdy nie istnieje standardowy profil Bluetooth SIG dla danej funkcji.
//
// UWAGA do UUID FFE0/FFE1/FFE2 poniżej:
// CBUUID(string: "FFE0") tworzy UUID 16-bitowy (zapis 4-cyfrowy hex = 16 bit).
// Zakres 0xF000–0xFFFF jest zarezerwowany przez Bluetooth SIG dla "prywatnych" celów
// i nie jest oficjalnie przydzielony żadnej usłudze. Moduły HM-10 i klony CC2540/CC2541
// powszechnie używają FFE0/FFE1 jako "custom UART-over-BLE" — stąd popularność tych UUID.
// W profesjonalnych produktach należy używać własnych UUID 128-bitowych
// (np. wygenerowanych przez uuidgen) aby uniknąć konfliktów.

import CoreBluetooth

enum BLEConstants {

    // MARK: - Własna usługa transferu danych
    //
    // UUID 16-bitowe z zakresu FFE0–FFE2 (prywatny zakres Bluetooth SIG).
    // Używane przez HM-10 i klony CC2540/CC2541 jako "UART over BLE".
    // W tej aplikacji demonstrujemy własny profil o tej samej strukturze.
    // Składa się z:
    //   • transferServiceUUID     — kontener (Service)
    //   • readNotifyCharUUID      — Central może czytać i subskrybować notyfikacje
    //   • writeCharUUID           — Central może zapisywać dane do Peripheral

    /// UUID usługi głównej. Peripheral będzie ją rozgłaszał w pakiecie advertisementu.
    static let transferServiceUUID = CBUUID(string: "FFE0")

    /// Charakterystyka do odczytu i notyfikacji (READ | NOTIFY).
    /// Peripheral wysyła tutaj dane do Central bez pytania (push model).
    static let readNotifyCharUUID = CBUUID(string: "FFE1")

    /// Charakterystyka do zapisu (WRITE | WRITE WITHOUT RESPONSE).
    /// Central wysyła tutaj polecenia/dane do Peripheral.
    static let writeCharUUID = CBUUID(string: "FFE2")

    // MARK: - Standardowe UUID Bluetooth SIG (przykłady)
    //
    // Poniższe UUID są zdefiniowane przez Bluetooth SIG i obsługiwane
    // przez większość urządzeń BLE (opaski fitness, czujniki itp.)

    /// Heart Rate Service — 0x180D
    /// Charakterystyka 0x2A37 zawiera pomiar BPM.
    static let heartRateServiceUUID = CBUUID(string: "180D")

    /// Battery Service — 0x180F
    /// Charakterystyka 0x2A19 zawiera poziom baterii (0–100%).
    static let batteryServiceUUID = CBUUID(string: "180F")

    /// Device Information Service — 0x180A
    /// Zawiera model, producenta, wersję firmware.
    static let deviceInfoServiceUUID = CBUUID(string: "180A")

    // MARK: - State Restoration Identifier
    //
    // Ten string MUSI być stały — iOS używa go do wznowienia aplikacji
    // po tym jak zostanie zabita w tle przez system.
    // Jeśli zmienisz ten string, State Restoration przestanie działać.

    /// Identyfikator używany przez CBCentralManager do State Restoration.
    static let centralRestoreIdentifier = "com.blesample.central-restore"

    /// Identyfikator używany przez CBPeripheralManager do State Restoration.
    static let peripheralRestoreIdentifier = "com.blesample.peripheral-restore"

    // MARK: - Advertising

    /// Nazwa lokalna rozgłaszana przez Peripheral w pakiecie advertisementu.
    /// Widoczna w skanerach BLE (LightBlue, nRF Connect) jako nazwa urządzenia.
    static let peripheralLocalName = "BLESample"
}

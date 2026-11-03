// BLESampleApp.swift
// BLESample
//
// Punkt wejścia aplikacji.
//
// DLACZEGO AppDelegate + @UIApplicationDelegateAdaptor?
// State Restoration Core Bluetooth wymaga dostępu do UIApplicationDelegate
// w celu obsługi application(_:didFinishLaunchingWithOptions:).
// SwiftUI domyślnie nie używa AppDelegate — musimy go wstrzyknąć.
//
// STATE RESTORATION — PEŁNY CYKL:
// 1. Aplikacja jest połączona z peripheral i przechodzi w tło
// 2. iOS zabija aplikację (brak pamięci lub timeout tła)
// 3. Peripheral rozłącza się / wysyła dane / wraca w zasięg
// 4. iOS sprawdza czy aplikacja ma CBCentralManagerOptionRestoreIdentifierKey
// 5. Jeśli tak: iOS wznawia aplikację w tle
// 6. Wywołuje AppDelegate.application(_:didFinishLaunchingWithOptions:)
//    z kluczem UIApplication.LaunchOptionsKey.bluetoothCentrals (lub .bluetoothPeripherals)
// 7. Tworzymy CBCentralManager z TYM SAMYM RestoreIdentifierKey
// 8. iOS wywołuje centralManager(_:willRestoreState:) z zachowanym stanem
// 9. Potem: centralManagerDidUpdateState(.poweredOn) gdzie możemy wznowić operacje

import SwiftUI

@main
struct BLESampleApp: App {

    // Wstrzykuje AppDelegate do cyklu życia SwiftUI
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Wstrzyknij managery jako EnvironmentObject — dostępne w całym drzewie widoków
                .environmentObject(appDelegate.centralManager)
                .environmentObject(appDelegate.peripheralManager)
        }
    }
}

// MARK: - AppDelegate

/// AppDelegate obsługuje:
/// 1. Inicjalizację managerów BLE (musi być przed pierwszym widokiem)
/// 2. Wykrywanie wznowienia przez State Restoration (LaunchOptions)
class AppDelegate: NSObject, UIApplicationDelegate {

    // Managery są tworzone w AppDelegate, nie w widokach —
    // dzięki temu żyją przez cały cykl życia aplikacji,
    // nawet gdy widoki są odtworzone (np. po rotacji).
    let centralManager = BLECentralManager()
    let peripheralManager = BLEPeripheralManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // SPRAWDZENIE WZNOWIENIA PRZEZ BLE:
        // iOS przekazuje w launchOptions informację czy aplikacja
        // została wznowiona przez zdarzenie BLE.
        //
        // iOS 26+ — LaunchOptionsKey.bluetoothCentrals / .bluetoothPeripherals są deprecated.
        // Nowe podejście: zapisz RestoreIdentifierKey w UserDefaults i odtwórz managery przy starcie.
        // Poniżej zachowane dla kompatybilności z iOS <26 (w warunkach #available).
        //
        // Na iOS 26+ wystarczy samo tworzenie managera z RestoreIdentifierKey w init() —
        // iOS automatycznie wywoła willRestoreState bez potrzeby sprawdzania launchOptions.
        #if !swift(>=6.0)
        // Ten blok nie jest potrzebny na iOS 26+ — kompilator usuwa go przez #available
        #endif
        if #available(iOS 26, *) {
            // Na iOS 26 state restoration jest obsługiwane przez samo tworzenie managera
            // z CBCentralManagerOptionRestoreIdentifierKey. LaunchOptionsKey.bluetoothCentrals
            // jest deprecated — nie używamy go.
        } else {
            // UIApplication.LaunchOptionsKey.bluetoothCentrals:
            //   Tablica RestoreIdentifierKey — które CBCentralManager wymagają przywrócenia.
            if let centralIDs = launchOptions?[UIApplication.LaunchOptionsKey.bluetoothCentrals] as? [String] {
                print("[AppDelegate] Launched by BLE Central restoration for: \(centralIDs)")
            }
            // UIApplication.LaunchOptionsKey.bluetoothPeripherals: analogicznie
            if let peripheralIDs = launchOptions?[UIApplication.LaunchOptionsKey.bluetoothPeripherals] as? [String] {
                print("[AppDelegate] Launched by BLE Peripheral restoration for: \(peripheralIDs)")
            }
        }

        return true
    }

    // MARK: Background Task

    /// Gdy aplikacja przechodzi w tło, iOS daje ograniczony czas na dokończenie operacji.
    /// Dla BLE z background mode — operacje BLE działają dalej bez beginBackgroundTask.
    /// beginBackgroundTask przydaje się dla innych operacji (np. zapis do bazy danych).
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("[AppDelegate] App entered background — BLE continues if background mode enabled")
    }
}

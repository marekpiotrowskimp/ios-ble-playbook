// ContentView.swift
// BLESample
//
// Główny widok — przełącznik między rolą Central i Peripheral.
// iPhone może być jednocześnie Central i Peripheral — tutaj wybieramy
// który tryb chcemy demonstrować w UI.

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var centralManager: BLECentralManager
    @EnvironmentObject var peripheralManager: BLEPeripheralManager

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: - Central Tab
            // Rola Central: skanuje, łączy się, czyta/pisze dane
            NavigationStack {
                ScanView()
            }
            .tabItem {
                Label("Central", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tag(0)

            // MARK: - Peripheral Tab
            // Rola Peripheral: rozgłasza się, obsługuje zapytania
            NavigationStack {
                PeripheralView()
            }
            .tabItem {
                Label("Peripheral", systemImage: "dot.radiowaves.right")
            }
            .tag(1)

            // MARK: - Log Tab
            // Unified log z obu managerów
            NavigationStack {
                LogView()
            }
            .tabItem {
                Label("Log", systemImage: "list.bullet.rectangle")
            }
            .tag(2)
        }
    }
}

// MARK: - LogView

/// Unified log ze wszystkich zdarzeń BLE (Central + Peripheral).
/// Przydatne do debugowania — widać pełny flow w czasie rzeczywistym.
struct LogView: View {

    @EnvironmentObject var centralManager: BLECentralManager
    @EnvironmentObject var peripheralManager: BLEPeripheralManager

    var allLogs: [String] {
        // Połącz logi z obu managerów i posortuj chronologicznie
        (centralManager.log.map { "[C] \($0)" } +
         peripheralManager.log.map { "[P] \($0)" })
            .sorted()
    }

    var body: some View {
        List(allLogs.reversed(), id: \.self) { entry in
            Text(entry)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.contains("[C]") ? .blue : .orange)
        }
        .navigationTitle("BLE Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    centralManager.log.removeAll()
                    peripheralManager.log.removeAll()
                }
            }
        }
    }
}

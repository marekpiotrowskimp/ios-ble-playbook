// ScanView.swift
// BLESample
//
// Widok skanowania BLE — demonstruje:
//   • Inicjalizację skanowania (startScan / stopScan)
//   • Wyświetlanie wyników z advertisementData
//   • RSSI — siła sygnału jako wizualny wskaźnik
//   • allowDuplicates — monitorowanie zmian RSSI
//   • Filtrowanie po UUID (przełącznik w UI)
//   • Retrieve bez skanowania (retrieveConnectedPeripherals)

import SwiftUI
import CoreBluetooth

struct ScanView: View {

    @EnvironmentObject var central: BLECentralManager

    var body: some View {
        List {
            // MARK: Stan managera
            Section("Bluetooth State") {
                StateRow(state: central.state)
            }

            // MARK: Kontrolki skanowania
            Section("Scanning") {
                ScanControlRow()
            }

            // MARK: Wyniki skanowania
            Section("Discovered (\(central.discoveredPeripherals.count))") {
                if central.discoveredPeripherals.isEmpty {
                    Text(central.isScanning ? "Scanning..." : "Tap Scan to start")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(central.discoveredPeripherals) { item in
                        NavigationLink(destination: PeripheralDetailView(discovered: item)) {
                            DiscoveredPeripheralRow(item: item)
                        }
                        // Nawigacja do PeripheralDetailView po tapnięciu
                    }
                }
            }
        }
        .navigationTitle("BLE Central")
        .onDisappear {
            // Zatrzymaj skanowanie gdy widok znika — oszczędność baterii
            if central.isScanning { central.stopScan() }
        }
    }
}

// MARK: - StateRow

/// Wiersz pokazujący aktualny stan CBCentralManager z kolorowym indykatorem.
struct StateRow: View {
    let state: CBManagerState

    var body: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(stateLabel)
            Spacer()
            Text(stateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // Mapowanie stanu na kolor dla szybkiej orientacji wizualnej
    var stateColor: Color {
        switch state {
        case .poweredOn: return .green
        case .poweredOff: return .red
        case .unauthorized: return .orange
        case .unsupported: return .red
        default: return .gray
        }
    }

    var stateLabel: String {
        switch state {
        case .poweredOn: return "Ready"
        case .poweredOff: return "Bluetooth Off"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        case .resetting: return "Resetting"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    var stateDescription: String {
        switch state {
        case .poweredOn: return "Can scan & connect"
        case .unauthorized: return "Check Info.plist"
        default: return ""
        }
    }
}

// MARK: - ScanControlRow

struct ScanControlRow: View {
    @EnvironmentObject var central: BLECentralManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(central.isScanning ? "Stop Scan" : "Start Scan") {
                    if central.isScanning {
                        central.stopScan()
                    } else {
                        central.startScan()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(central.isScanning ? .red : .blue)
                .disabled(central.state != .poweredOn)

                if central.isScanning {
                    ProgressView()
                        .padding(.leading, 8)
                }
            }

            // Informacja o ograniczeniach tła
            Text("Note: Scanning without UUID filter is blocked in background mode.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DiscoveredPeripheralRow

/// Wiersz dla odkrytego urządzenia — pokazuje wszystkie kluczowe dane z advertisementu.
struct DiscoveredPeripheralRow: View {
    let item: DiscoveredPeripheral

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Nazwa urządzenia
            HStack {
                Text(item.localName ?? item.peripheral.name ?? "Unknown")
                    .font(.headline)
                Spacer()
                // RSSI jako pasek siły sygnału
                RSSIIndicator(rssi: item.rssi)
            }

            // UUID urządzenia (specyficzny dla tej pary iPhone–urządzenie)
            Text(item.peripheral.identifier.uuidString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Dane z pakietu advertisementu
            HStack(spacing: 12) {
                // Czy urządzenie akceptuje połączenia
                Label(
                    item.isConnectable ? "Connectable" : "Not connectable",
                    systemImage: item.isConnectable ? "checkmark.circle" : "xmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(item.isConnectable ? .green : .red)

                // UUID usług z advertisementu
                if let uuids = item.serviceUUIDs, !uuids.isEmpty {
                    Text(uuids.map { $0.uuidString }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }

            // Dane producenta (raw bytes) — np. Apple iBeacon, Tile
            if let mfr = item.manufacturerData {
                Text("Manufacturer: \(mfr.hexPreview)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // TX Power — służy do szacowania odległości gdy znamy moc nadajnika
            if let txPower = item.txPowerLevel {
                Text("TX Power: \(txPower) dBm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - RSSIIndicator

/// Wizualny wskaźnik siły sygnału BLE (analogiczny do WiFi).
/// RSSI (Received Signal Strength Indicator) wyrażony w dBm:
///   > -60 dBm  → silny (blisko)
///   -60 to -75 → średni
///   < -75 dBm  → słaby (daleko lub przeszkody)
///   127        → nieznany
struct RSSIIndicator: View {
    let rssi: Int

    var bars: Int {
        switch rssi {
        case ...(-90): return 1
        case -90 ..< -75: return 2
        case -75 ..< -60: return 3
        default: return 4   // > -60 lub 127 (nieznany traktujemy jako "coś")
        }
    }

    var color: Color {
        switch bars {
        case 4: return .green
        case 3: return .yellow
        case 2: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 4, height: CGFloat(i * 4))
                    .foregroundStyle(i <= bars ? color : Color.gray.opacity(0.3))
            }
            Text("\(rssi)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 30)
        }
    }
}

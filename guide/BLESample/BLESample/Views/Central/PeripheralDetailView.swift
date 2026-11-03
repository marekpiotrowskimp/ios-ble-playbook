// PeripheralDetailView.swift
// BLESample
//
// Widok szczegółów połączonego peripheral — demonstruje:
//   • Connect / Disconnect
//   • Retrieve peripheral bez skanowania
//   • Discovery Services i Characteristics
//   • Wyświetlanie właściwości (CBCharacteristicProperties)
//   • Nawigację do operacji read/write/notify dla wybranej charakterystyki

import SwiftUI
import CoreBluetooth

struct PeripheralDetailView: View {

    @EnvironmentObject var central: BLECentralManager
    let discovered: DiscoveredPeripheral

    var body: some View {
        List {
            // MARK: Sekcja połączenia
            Section("Connection") {
                ConnectionSection(discovered: discovered)
            }

            // MARK: Retrieve bez skanowania
            // Demonstracja retrievePeripherals / retrieveConnectedPeripherals
            Section("Retrieve (no scan needed)") {
                RetrieveSection(peripheral: discovered.peripheral)
            }

            // MARK: GATT — Services & Characteristics
            // Pokazuje hierarchię: Service → Characteristic → właściwości
            if central.connectionState == .connected {
                if central.services.isEmpty {
                    Section("GATT") {
                        Text("Discovering services...")
                            .foregroundStyle(.secondary)
                        ProgressView()
                    }
                } else {
                    ForEach(central.services, id: \.uuid) { service in
                        ServiceSection(service: service)
                    }
                }
            }
        }
        .navigationTitle(discovered.localName ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ConnectionSection

struct ConnectionSection: View {
    @EnvironmentObject var central: BLECentralManager
    let discovered: DiscoveredPeripheral

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Stan połączenia z kolorowym indykatorem
            HStack {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 10, height: 10)
                Text(connectionLabel)
                    .font(.headline)
            }

            // Przyciski Connect / Disconnect
            HStack {
                Button("Connect") {
                    central.connect(to: discovered)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!discovered.isConnectable || central.connectionState == .connected)

                Button("Disconnect") {
                    central.disconnect()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(central.connectionState != .connected)
            }

            // Błąd połączenia
            if case .failedToConnect(let msg) = central.connectionState {
                Text("Error: \(msg)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    var connectionColor: Color {
        switch central.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .failedToConnect: return .red
        }
    }

    var connectionLabel: String {
        switch central.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .failedToConnect: return "Failed"
        }
    }
}

// MARK: - RetrieveSection

/// Demonstruje retrievePeripherals i retrieveConnectedPeripherals.
/// Pozwala połączyć się ze znaniem urządzeniem BEZ ponownego skanowania.
struct RetrieveSection: View {
    @EnvironmentObject var central: BLECentralManager
    let peripheral: CBPeripheral
    @State private var retrievedCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // retrievePeripherals(withIdentifiers:)
            // Pobiera peripheral po UUID zapisanym wcześniej (np. w UserDefaults).
            // Działa nawet gdy peripheral jest poza zasięgiem — zwraca obiekt z cache iOS.
            Button("Retrieve by UUID (cached)") {
                if let p = central.retrieveKnownPeripheral(uuid: peripheral.identifier) {
                    // Można połączyć od razu bez skanowania
                    _ = p
                }
            }
            .font(.caption)

            // retrieveConnectedPeripherals(withServices:)
            // Pobiera urządzenia aktualnie połączone z systemem iOS
            // (np. Apple Watch, słuchawki).
            Button("Retrieve system-connected") {
                let peripherals = central.retrieveConnectedPeripherals()
                retrievedCount = peripherals.count
            }
            .font(.caption)

            if let count = retrievedCount {
                Text("Found \(count) system-connected peripheral(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("UUID (per-device, not universal): \(peripheral.identifier.uuidString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ServiceSection

/// Sekcja jednej usługi GATT z jej charakterystykami.
struct ServiceSection: View {
    @EnvironmentObject var central: BLECentralManager
    let service: CBService

    var characteristics: [CharacteristicInfo] {
        central.characteristics[service] ?? []
    }

    var body: some View {
        Section {
            // Lista charakterystyk
            if characteristics.isEmpty {
                Text("Discovering characteristics...")
                    .foregroundStyle(.secondary)
                ProgressView()
            } else {
                ForEach(characteristics) { info in
                    NavigationLink(
                        destination: CharacteristicView(charInfo: info)
                    ) {
                        CharacteristicRow(info: info)
                    }
                }
            }
        } header: {
            // Nagłówek sekcji — UUID usługi + czy primary
            VStack(alignment: .leading) {
                Text("Service: \(service.uuid.uuidString)")
                Text(service.isPrimary ? "Primary" : "Secondary")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - CharacteristicRow

/// Wiersz jednej charakterystyki — pokazuje UUID i właściwości (read/write/notify).
struct CharacteristicRow: View {
    let info: CharacteristicInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.id.uuidString)
                .font(.footnote)
                .fontWeight(.medium)

            // Tagi właściwości — szybki podgląd co dana charakterystyka potrafi
            HStack(spacing: 4) {
                let props = info.characteristic.properties
                if props.contains(.read) { PropertyTag(label: "R", color: .blue) }
                if props.contains(.write) { PropertyTag(label: "W", color: .green) }
                if props.contains(.writeWithoutResponse) { PropertyTag(label: "WNR", color: .teal) }
                if props.contains(.notify) { PropertyTag(label: "N", color: .orange) }
                if props.contains(.indicate) { PropertyTag(label: "I", color: .purple) }
            }

            // Ostatnia wartość
            if let data = info.lastValue {
                Text("Last: \(data.utf8OrHex)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // MTU info
            Text("MTU: \(info.mtuWithResponse)B (resp) / \(info.mtuWithoutResponse)B (no-resp)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PropertyTag

struct PropertyTag: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

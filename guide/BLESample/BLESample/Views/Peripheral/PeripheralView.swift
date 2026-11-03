// PeripheralView.swift
// BLESample
//
// Widok roli Peripheral — demonstruje:
//   • Konfigurację CBPeripheralManager
//   • Tworzenie usługi i charakterystyk (CBMutableService, CBMutableCharacteristic)
//   • Rozpoczęcie i zatrzymanie advertisingu
//   • Obsługę subskrypcji od Central (didSubscribeTo / didUnsubscribeFrom)
//   • Wyświetlanie odebranych zapisów od Central
//   • Background advertising (info)
//   • State Restoration dla Peripheral

import SwiftUI
import CoreBluetooth

struct PeripheralView: View {

    @EnvironmentObject var peripheral: BLEPeripheralManager

    var body: some View {
        List {
            // MARK: Stan managera
            Section("Bluetooth State") {
                PeripheralStateRow(state: peripheral.state)
            }

            // MARK: Advertising
            // Kontrola rozgłaszania — start/stop, info o pakiecie
            Section {
                AdvertisingSection()
            } header: {
                SectionHeader(
                    title: "Advertising",
                    subtitle: "startAdvertising / stopAdvertising"
                )
            }

            // MARK: Readable Value
            // Wartość zwracana na żądanie odczytu od Central
            Section {
                ReadableValueSection()
            } header: {
                SectionHeader(
                    title: "Readable Value",
                    subtitle: "Returned on CBATTRequest (didReceiveRead)"
                )
            }

            // MARK: Subskrybenci notyfikacji + wysyłanie
            Section {
                SubscribersSection()
                // Nawigacja do NotificationView — flow control, burst test, itp.
                NavigationLink(destination: NotificationView()) {
                    Label("Send Notifications", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.callout)
                }
                .disabled(!peripheral.isAdvertising && peripheral.subscribedCentrals.isEmpty)
            } header: {
                SectionHeader(
                    title: "Subscribed Centrals (\(peripheral.subscribedCentrals.count))",
                    subtitle: "didSubscribeTo / didUnsubscribeFrom"
                )
            }

            // MARK: Odebrane zapisy
            // Dane zapisane przez Central do writeCharacteristic
            Section {
                ReceivedWritesSection()
            } header: {
                SectionHeader(
                    title: "Received Writes (\(peripheral.receivedWrites.count))",
                    subtitle: "peripheralManager(_:didReceiveWrite:)"
                )
            }

            // MARK: Background info
            Section("Background Mode Info") {
                BackgroundInfoSection()
            }
        }
        .navigationTitle("BLE Peripheral")
    }
}

// MARK: - PeripheralStateRow

struct PeripheralStateRow: View {
    let state: CBManagerState

    var body: some View {
        HStack {
            Circle()
                .fill(state == .poweredOn ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(state == .poweredOn ? "Ready to advertise" : "BLE not ready")
        }
    }
}

// MARK: - AdvertisingSection

/// Kontroluje advertising + pokazuje zawartość pakietu.
struct AdvertisingSection: View {
    @EnvironmentObject var peripheral: BLEPeripheralManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Start / Stop advertising
            HStack {
                Button(peripheral.isAdvertising ? "Stop Advertising" : "Start Advertising") {
                    if peripheral.isAdvertising {
                        peripheral.stopAdvertising()
                    } else {
                        peripheral.startAdvertising()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(peripheral.isAdvertising ? .red : .blue)
                .disabled(peripheral.state != .poweredOn)

                if peripheral.isAdvertising {
                    Image(systemName: "dot.radiowaves.right")
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse)
                }
            }

            Divider()

            // Zawartość pakietu advertisementu
            // FOREGROUND: pełny pakiet (ServiceUUID + LocalName)
            // BACKGROUND: iOS skraca do samych ServiceUUIDs — LocalName jest usuwana
            VStack(alignment: .leading, spacing: 4) {
                Text("Advertisement packet contents:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AdvertPacketRow(key: "ServiceUUIDs",
                    value: BLEConstants.transferServiceUUID.uuidString,
                    note: "Visible in background too")
                AdvertPacketRow(key: "LocalName",
                    value: BLEConstants.peripheralLocalName,
                    note: "Foreground only — stripped in background")
            }
        }
    }
}

struct AdvertPacketRow: View {
    let key: String
    let value: String
    let note: String

    var body: some View {
        HStack(alignment: .top) {
            Text(key + ":")
                .font(.caption2)
                .fontWeight(.medium)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading) {
                Text(value).font(.caption2)
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ReadableValueSection

/// Kontroluje wartość zwracaną przez Peripheral na żądanie odczytu.
/// Demonstruje dynamiczną wartość (value: nil w CBMutableCharacteristic).
struct ReadableValueSection: View {
    @EnvironmentObject var peripheral: BLEPeripheralManager
    @State private var editText: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Aktualna wartość
            Text("Current value:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(peripheral.readableValue)
                .font(.system(.body, design: .monospaced))
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Edycja wartości
            if isEditing {
                TextField("New value", text: $editText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        peripheral.updateReadableValue(editText)
                        isEditing = false
                        editText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") { isEditing = false }
                        .buttonStyle(.bordered)
                }
            } else {
                Button("Edit") {
                    editText = peripheral.readableValue
                    isEditing = true
                }
                .buttonStyle(.bordered)
            }

            // Wyjaśnienie dlaczego value: nil w CBMutableCharacteristic
            Text("CBMutableCharacteristic(value: nil) = dynamic value. iOS calls didReceiveRead for each request instead of caching a static value.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SubscribersSection

/// Lista Central które subskrybują notyfikacje.
struct SubscribersSection: View {
    @EnvironmentObject var peripheral: BLEPeripheralManager

    var body: some View {
        if peripheral.subscribedCentrals.isEmpty {
            Text("No centrals subscribed yet")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            ForEach(peripheral.subscribedCentrals) { sub in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sub.central.identifier.uuidString)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Max update value: \(sub.maximumUpdateValueLength) bytes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - ReceivedWritesSection

/// Historia zapisów odebranych od Central.
/// Pokazuje surowe dane + próbę dekodowania UTF-8.
struct ReceivedWritesSection: View {
    @EnvironmentObject var peripheral: BLEPeripheralManager

    var body: some View {
        if peripheral.receivedWrites.isEmpty {
            Text("No writes received yet")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            ForEach(peripheral.receivedWrites.suffix(10).reversed()) { write in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(write.characteristicUUID.uuidString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(write.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Pokaż jako text jeśli UTF-8, inaczej hex
                    Text(write.data.utf8OrHex)
                        .font(.system(.caption, design: .monospaced))
                    Text("\(write.data.count) bytes — hex: \(write.data.hexPreview)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - BackgroundInfoSection

/// Informacje o zachowaniu Peripheral w trybie tła.
struct BackgroundInfoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoBullet(
                icon: "checkmark.circle",
                color: .green,
                text: "Background key required: UIBackgroundModes → bluetooth-peripheral"
            )
            InfoBullet(
                icon: "exclamationmark.triangle",
                color: .orange,
                text: "Advertisement in background: ServiceUUIDs only (LocalName stripped by iOS)"
            )
            InfoBullet(
                icon: "info.circle",
                color: .blue,
                text: "State Restoration: CBPeripheralManagerOptionRestoreIdentifierKey enables iOS to relaunch app for BLE events"
            )
            InfoBullet(
                icon: "clock",
                color: .purple,
                text: "Background execution: ~15 seconds after BLE event triggers relaunch"
            )
        }
    }
}

struct InfoBullet: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.caption2)
        }
    }
}

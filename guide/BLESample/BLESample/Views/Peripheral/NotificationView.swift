// NotificationView.swift
// BLESample
//
// Widok wysyłania notyfikacji z roli Peripheral — demonstruje:
//   • updateValue(_:for:onSubscribedCentrals:)
//   • Flow control: updateValue zwraca Bool (false = kolejka pełna)
//   • peripheralManagerIsReady(toUpdateSubscribers:) — wznowienie po przeciążeniu
//   • Wysyłanie do wszystkich vs. wybranych Central
//   • maximumUpdateValueLength — limit dla konkretnego Central

import SwiftUI
import CoreBluetooth

struct NotificationView: View {

    @EnvironmentObject var peripheral: BLEPeripheralManager

    @State private var notificationText: String = "Hello from Peripheral!"
    @State private var sendCount: Int = 0

    var body: some View {
        List {
            // MARK: Subskrybenci
            Section("Subscribed Centrals (\(peripheral.subscribedCentrals.count))") {
                if peripheral.subscribedCentrals.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No subscribers yet.")
                            .foregroundStyle(.secondary)
                        Text("From Central tab: connect → open characteristic → Subscribe")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(peripheral.subscribedCentrals) { sub in
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(sub.central.identifier.uuidString)
                                    .font(.caption)
                                // maximumUpdateValueLength — max rozmiar pakietu notyfikacji
                                // dla tego konkretnego Central (wynika z negocjacji MTU)
                                Text("Max packet: \(sub.maximumUpdateValueLength) bytes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: Wysyłanie notyfikacji
            Section {
                NotificationSendSection(text: $notificationText, sendCount: $sendCount)
            } header: {
                SectionHeader(
                    title: "Send Notification",
                    subtitle: "updateValue(_:for:onSubscribedCentrals:)"
                )
            }

            // MARK: Flow Control
            Section {
                FlowControlInfoSection()
            } header: {
                SectionHeader(
                    title: "Flow Control",
                    subtitle: "What happens when updateValue returns false"
                )
            }
        }
        .navigationTitle("Notifications")
    }
}

// MARK: - NotificationSendSection

struct NotificationSendSection: View {
    @EnvironmentObject var peripheral: BLEPeripheralManager
    @Binding var text: String
    @Binding var sendCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Notification payload", text: $text)
                .textFieldStyle(.roundedBorder)

            Text("\(text.data(using: .utf8)?.count ?? 0) bytes")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Wyślij do WSZYSTKICH subskrybentów
            // onSubscribedCentrals: nil → iOS roześle do wszystkich
            Button("Send to All (\(peripheral.subscribedCentrals.count) subscribers)") {
                peripheral.sendNotification(text: text)
                sendCount += 1
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(peripheral.subscribedCentrals.isEmpty)

            if sendCount > 0 {
                Text("Sent \(sendCount) notification(s) this session")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Burst test — wysyła wiele notyfikacji szybko aby zademonstrować flow control
            Button("Burst Test (10 rapid notifications)") {
                // DEMONSTRACJA FLOW CONTROL:
                // Jeśli wyślesz zbyt wiele pakietów bez czekania,
                // updateValue zacznie zwracać false.
                // BLEPeripheralManager zapisuje ostatni pakiet w pendingNotificationData
                // i wznawia w peripheralManagerIsReady(toUpdateSubscribers:)
                for i in 1...10 {
                    let msg = "Burst #\(i) — \(text)"
                    peripheral.sendNotification(text: msg)
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(peripheral.subscribedCentrals.isEmpty)

            Text("Burst test demonstrates flow control — updateValue may return false for rapid sends.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - FlowControlInfoSection

/// Wyjaśnienie mechanizmu flow control dla notyfikacji.
struct FlowControlInfoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Schemat flow control
            VStack(alignment: .leading, spacing: 4) {
                Text("Flow control diagram:")
                    .font(.caption)
                    .fontWeight(.medium)

                CodeBlock(code: """
updateValue(data, for: char, onSubscribedCentrals: nil)
  → returns true  → packet sent ✓
  → returns false → queue full!
      → save data as pending
      → wait for:
          peripheralManagerIsReady(toUpdateSubscribers:)
      → retry updateValue with pending data
""")
            }

            Divider()

            InfoBullet(
                icon: "checkmark.circle",
                color: .green,
                text: "updateValue returns true: packet is in the send queue"
            )
            InfoBullet(
                icon: "xmark.circle",
                color: .red,
                text: "updateValue returns false: internal queue full — MUST wait for peripheralManagerIsReady"
            )
            InfoBullet(
                icon: "clock.arrow.circlepath",
                color: .orange,
                text: "peripheralManagerIsReady(toUpdateSubscribers:) fires when queue drains — resume sending here"
            )
            InfoBullet(
                icon: "exclamationmark.triangle",
                color: .yellow,
                text: "Ignoring flow control causes silent data loss — packets are silently dropped"
            )
        }
    }
}

// MARK: - CodeBlock

struct CodeBlock: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(.caption2, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

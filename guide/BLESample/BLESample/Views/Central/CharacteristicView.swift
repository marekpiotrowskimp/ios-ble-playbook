// CharacteristicView.swift
// BLESample
//
// Widok operacji na charakterystyce — demonstruje:
//   • Read (jednorazowy odczyt)
//   • Write With Response (z potwierdzeniem)
//   • Write Without Response (bez potwierdzenia, flow control)
//   • Notifications / Indications (subskrypcja push)
//   • MTU — wyświetlanie i fragmentacja dużych danych
//   • canSendWriteWithoutResponse — flow control

import SwiftUI
import CoreBluetooth

struct CharacteristicView: View {

    @EnvironmentObject var central: BLECentralManager
    let charInfo: CharacteristicInfo

    @State private var writeText: String = ""
    @State private var writeHex: String = ""
    @State private var useHexInput: Bool = false
    @State private var largeSendText: String = "Hello BLE! This is a large message that will be fragmented across multiple BLE packets."

    var characteristic: CBCharacteristic { charInfo.characteristic }
    var props: CBCharacteristicProperties { characteristic.properties }

    var body: some View {
        List {
            // MARK: Info
            Section("Characteristic Info") {
                InfoSection(charInfo: charInfo)
            }

            // MARK: Read
            // Dostępne gdy charakterystyka ma właściwość .read
            if props.contains(.read) {
                Section {
                    ReadSection(characteristic: characteristic)
                } header: {
                    SectionHeader(title: "Read", subtitle: "One-shot pull: readValue → didUpdateValueFor")
                }
            }

            // MARK: Notifications
            // Dostępne gdy charakterystyka ma .notify lub .indicate
            if props.contains(.notify) || props.contains(.indicate) {
                Section {
                    NotifySection(characteristic: characteristic, charInfo: charInfo)
                } header: {
                    let type = props.contains(.indicate) ? "Indicate (with ACK)" : "Notify (no ACK)"
                    SectionHeader(title: "Subscribe", subtitle: "Push model — \(type)")
                }
            }

            // MARK: Write With Response
            if props.contains(.write) {
                Section {
                    WriteSection(
                        characteristic: characteristic,
                        writeText: $writeText,
                        useHex: $useHexInput,
                        writeHex: $writeHex,
                        withResponse: true
                    )
                } header: {
                    SectionHeader(
                        title: "Write (with response)",
                        subtitle: "Guaranteed delivery — slower"
                    )
                }
            }

            // MARK: Write Without Response
            if props.contains(.writeWithoutResponse) {
                Section {
                    WriteSection(
                        characteristic: characteristic,
                        writeText: $writeText,
                        useHex: $useHexInput,
                        writeHex: $writeHex,
                        withResponse: false
                    )
                } header: {
                    SectionHeader(
                        title: "Write (no response)",
                        subtitle: "Fast, no ACK — check canSendWriteWithoutResponse"
                    )
                }
            }

            // MARK: Large Data / MTU
            // Demonstracja fragmentacji dużych danych
            if props.contains(.write) || props.contains(.writeWithoutResponse) {
                Section {
                    LargeDataSection(characteristic: characteristic, text: $largeSendText)
                } header: {
                    SectionHeader(
                        title: "Large Data Transfer",
                        subtitle: "Auto-fragments by MTU: \(charInfo.mtuWithoutResponse) bytes/packet"
                    )
                }
            }

            // MARK: Ostatnia wartość
            if let data = charInfo.lastValue {
                Section("Last Received Value") {
                    ValueDisplaySection(data: data)
                }
            }
        }
        .navigationTitle(charInfo.id.uuidString)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - InfoSection

struct InfoSection: View {
    let charInfo: CharacteristicInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // UUID
            LabeledContent("UUID", value: charInfo.id.uuidString)
                .font(.caption)

            // Właściwości — pełne wyjaśnienie każdej
            VStack(alignment: .leading, spacing: 2) {
                Text("Properties:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let props = charInfo.characteristic.properties
                if props.contains(.read) {
                    PropertyExplainRow(symbol: "arrow.down.circle", color: .blue,
                        name: "Read", desc: "One-time pull. Central asks, Peripheral responds.")
                }
                if props.contains(.write) {
                    PropertyExplainRow(symbol: "arrow.up.circle", color: .green,
                        name: "Write", desc: "Write with ACK — slower but guaranteed delivery.")
                }
                if props.contains(.writeWithoutResponse) {
                    PropertyExplainRow(symbol: "arrow.up.circle.fill", color: .teal,
                        name: "Write No Response", desc: "Fast write — no ACK, may drop if queue full.")
                }
                if props.contains(.notify) {
                    PropertyExplainRow(symbol: "bell", color: .orange,
                        name: "Notify", desc: "Push from Peripheral. Central subscribes via CCCD.")
                }
                if props.contains(.indicate) {
                    PropertyExplainRow(symbol: "bell.badge", color: .purple,
                        name: "Indicate", desc: "Like Notify but with ACK from Central.")
                }
            }

            // MTU info
            Group {
                LabeledContent("MTU (withResponse)", value: "\(charInfo.mtuWithResponse) bytes")
                LabeledContent("MTU (withoutResponse)", value: "\(charInfo.mtuWithoutResponse) bytes")
            }
            .font(.caption)
        }
    }
}

struct PropertyExplainRow: View {
    let symbol: String
    let color: Color
    let name: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.caption).fontWeight(.medium)
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ReadSection

struct ReadSection: View {
    @EnvironmentObject var central: BLECentralManager
    let characteristic: CBCharacteristic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // DLACZEGO readValue:
            // Pull model — Central inicjuje odczyt.
            // Callback: didUpdateValueFor (ten sam co dla notyfikacji)
            // Gdy wartość jest statyczna (non-changing), użyj read.
            // Gdy zmienia się często, użyj notify.
            Button("Read Value") {
                central.readValue(for: characteristic)
            }
            .buttonStyle(.borderedProminent)

            Text("Triggers: peripheral(_:didUpdateValueFor:error:)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - NotifySection

struct NotifySection: View {
    @EnvironmentObject var central: BLECentralManager
    let characteristic: CBCharacteristic
    let charInfo: CharacteristicInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // DLACZEGO setNotifyValue:
                // Push model — Peripheral wysyła dane gdy mają zmianę.
                // iOS automatycznie pisze do CCCD (0x2902 descriptor).
                // Odbiór: ten sam callback didUpdateValueFor co przy read.
                // Wyłącz notyfikacje gdy nie są potrzebne — oszczędność baterii!
                Button(charInfo.isNotifying ? "Unsubscribe" : "Subscribe") {
                    central.setNotify(!charInfo.isNotifying, for: characteristic)
                }
                .buttonStyle(.borderedProminent)
                .tint(charInfo.isNotifying ? .red : .orange)

                if charInfo.isNotifying {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse)
                }
            }

            Text(charInfo.isNotifying
                 ? "Active — data arrives via didUpdateValueFor"
                 : "Not subscribed — peripheral will not push data")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("iOS writes CCCD (0x2902) automatically when you call setNotifyValue.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - WriteSection

struct WriteSection: View {
    @EnvironmentObject var central: BLECentralManager
    let characteristic: CBCharacteristic
    @Binding var writeText: String
    @Binding var useHex: Bool
    @Binding var writeHex: String
    let withResponse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Przełącznik między wpisem tekstowym a hex
            Picker("Input", selection: $useHex) {
                Text("Text (UTF-8)").tag(false)
                Text("Hex bytes").tag(true)
            }
            .pickerStyle(.segmented)

            if useHex {
                // Wejście hex — np. "01 FF A0"
                TextField("Hex bytes (e.g. 01 FF A0)", text: $writeHex)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
            } else {
                TextField("Text to send", text: $writeText)
                    .textFieldStyle(.roundedBorder)
            }

            Button("Write \(withResponse ? "(with response)" : "(no response)")") {
                let data: Data?
                if useHex {
                    data = writeHex.hexData
                } else {
                    data = writeText.data(using: .utf8)
                }
                guard let data else { return }

                if withResponse {
                    // Wolniejszy, gwarantowany — callback didWriteValueFor
                    central.writeWithResponse(data: data, to: characteristic)
                } else {
                    // Szybszy, bez ACK — sprawdza canSendWriteWithoutResponse
                    central.writeWithoutResponse(data: data, to: characteristic)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(withResponse ? .green : .teal)
            .disabled(writeText.isEmpty && writeHex.isEmpty)

            if !withResponse {
                // Flow control info — ważne dla dużych transferów
                Text("canSendWriteWithoutResponse is checked before each packet. If false, wait for peripheralIsReady(toSendWriteWithoutResponse:).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - LargeDataSection

/// Demonstruje fragmentację dużych danych według MTU.
struct LargeDataSection: View {
    @EnvironmentObject var central: BLECentralManager
    let characteristic: CBCharacteristic
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))

            let dataSize = text.data(using: .utf8)?.count ?? 0
            Text("Data size: \(dataSize) bytes")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Send (auto-fragment by MTU)") {
                if let data = text.data(using: .utf8) {
                    // Automatycznie fragmentuje dane według MTU
                    // i sprawdza canSendWriteWithoutResponse przed każdym pakietem
                    central.sendLargeData(data, to: characteristic)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Text("Each packet ≤ MTU bytes. Flow control via canSendWriteWithoutResponse.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ValueDisplaySection

struct ValueDisplaySection: View {
    let data: Data

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Podgląd jako UTF-8 jeśli możliwe
            if let text = String(data: data, encoding: .utf8) {
                LabeledContent("UTF-8") {
                    Text(text).font(.system(.body, design: .monospaced))
                }
            }
            // Zawsze pokazuj hex
            LabeledContent("Hex") {
                Text(data.hexString)
                    .font(.system(.caption, design: .monospaced))
            }
            LabeledContent("Size", value: "\(data.count) bytes")
                .font(.caption)
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }
}

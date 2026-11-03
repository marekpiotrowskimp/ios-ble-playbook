// Data+Hex.swift
// BLESample
//
// Rozszerzenia na Data ułatwiające debugowanie surowych bajtów BLE.
// BLE przesyła dane jako surowe bajty — bez konwersji są nieczytelne.

import Foundation

extension Data {

    /// Konwertuje Data na string szesnastkowy, np. Data([0x01, 0xFF]) → "01 FF"
    /// Przydatne do logowania wartości charakterystyk.
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Krótki podgląd — max 8 bajtów + "..." jeśli dłuższe.
    var hexPreview: String {
        let preview = prefix(8)
        let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
        return count > 8 ? "\(hex) ... (\(count) bytes total)" : hex
    }

    /// Próbuje zdekodować jako UTF-8 string. Jeśli nie uda się — zwraca hex.
    var utf8OrHex: String {
        String(data: self, encoding: .utf8) ?? hexString
    }
}

extension String {
    /// Konwertuje hex string ("01FF" lub "01 FF") na Data.
    /// Przydatne przy wpisywaniu danych do wysłania w UI.
    var hexData: Data? {
        let cleaned = replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}

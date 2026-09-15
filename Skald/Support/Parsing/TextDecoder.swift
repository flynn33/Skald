import Foundation

nonisolated protocol TextDecoding {
    func read(_ url: URL, choice: TextEncodingChoice) throws -> DecodedText
    func decode(_ data: Data, choice: TextEncodingChoice) throws -> DecodedText
}

nonisolated final class TextDecoder: TextDecoding {
    private let maximumInputBytes: Int
    private let readChunkSize: Int
    init(maximumInputBytes: Int = 64 * 1_024 * 1_024, readChunkSize: Int = 64 * 1_024) {
        self.maximumInputBytes = max(1, maximumInputBytes)
        self.readChunkSize = max(1, readChunkSize)
    }

    func read(_ url: URL, choice: TextEncodingChoice) throws -> DecodedText {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
            guard chunk.count <= maximumInputBytes - data.count else {
                throw DelimitedInputError(code: "inputLimitExceeded", stage: "read", summary: "Delimited input exceeds the configured byte limit.")
            }
            data.append(chunk)
        }
        return try decode(data, choice: choice)
    }

    func decode(_ data: Data, choice: TextEncodingChoice) throws -> DecodedText {
        guard data.count <= maximumInputBytes else {
            throw DelimitedInputError(code: "inputLimitExceeded", stage: "decode", summary: "Delimited input exceeds the configured byte limit.")
        }
        let bytes = [UInt8](data)
        let marker: (TextEncodingChoice, Int)?
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { marker = (.utf32BigEndian, 4) }
        else if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { marker = (.utf32LittleEndian, 4) }
        else if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { marker = (.utf8, 3) }
        else if bytes.starts(with: [0xFE, 0xFF]) { marker = (.utf16BigEndian, 2) }
        else if bytes.starts(with: [0xFF, 0xFE]) { marker = (.utf16LittleEndian, 2) }
        else { marker = nil }

        if let marker, choice != .automatic && choice != marker.0 {
            throw DelimitedInputError(code: "invalidEncoding", stage: "decode", summary: "The encoding choice conflicts with the file's leading BOM.")
        }
        let selected = marker?.0 ?? (choice == .automatic ? .utf8 : choice)
        let payload = Array(bytes.dropFirst(marker?.1 ?? 0))
        let text: String
        switch selected {
        case .utf8, .automatic:
            text = try decodeUTF8(payload)
        case .utf16LittleEndian:
            text = try decodeUTF16(payload, littleEndian: true)
        case .utf16BigEndian:
            text = try decodeUTF16(payload, littleEndian: false)
        case .utf32LittleEndian:
            text = try decodeUTF32(payload, littleEndian: true)
        case .utf32BigEndian:
            text = try decodeUTF32(payload, littleEndian: false)
        case .windows1252:
            text = try decodeSingleByte(payload, windows1252: true)
        case .latin1:
            text = try decodeSingleByte(payload, windows1252: false)
        }
        let name: String
        switch selected {
        case .utf8, .automatic: name = "utf-8"
        case .utf16LittleEndian: name = "utf-16-le"
        case .utf16BigEndian: name = "utf-16-be"
        case .utf32LittleEndian: name = "utf-32-le"
        case .utf32BigEndian: name = "utf-32-be"
        case .windows1252: name = "windows-1252"
        case .latin1: name = "iso-8859-1"
        }
        return DecodedText(text: text, encoding: name, provenance: marker == nil ? (choice == .automatic ? "automatic-utf8" : "explicit") : "bom")
    }

    private func decodeUTF8(_ bytes: [UInt8]) throws -> String {
        var offset = 0
        while offset < bytes.count {
            let first = bytes[offset]
            if first < 0x80 { offset += 1; continue }
            let length: Int
            if first >= 0xC2 && first <= 0xDF { length = 2 }
            else if first >= 0xE0 && first <= 0xEF { length = 3 }
            else if first >= 0xF0 && first <= 0xF4 { length = 4 }
            else { throw invalidByte(offset) }
            guard offset + length <= bytes.count else { throw invalidByte(offset) }
            for position in 1..<length where bytes[offset + position] & 0xC0 != 0x80 { throw invalidByte(offset + position) }
            if length == 3 {
                if first == 0xE0 && bytes[offset + 1] < 0xA0 { throw invalidByte(offset) }
                if first == 0xED && bytes[offset + 1] >= 0xA0 { throw invalidByte(offset) }
            }
            if length == 4 {
                if first == 0xF0 && bytes[offset + 1] < 0x90 { throw invalidByte(offset) }
                if first == 0xF4 && bytes[offset + 1] > 0x8F { throw invalidByte(offset) }
            }
            offset += length
        }
        guard let text = String(data: Data(bytes), encoding: .utf8) else { throw invalidByte(0) }
        return text
    }

    private func decodeUTF16(_ bytes: [UInt8], littleEndian: Bool) throws -> String {
        guard bytes.count.isMultiple(of: 2) else { throw invalidByte(bytes.count - 1) }
        var scalars = String.UnicodeScalarView()
        var offset = 0
        while offset < bytes.count {
            let first = unit16(bytes, offset: offset, littleEndian: littleEndian)
            var value = UInt32(first)
            if first >= 0xD800 && first <= 0xDBFF {
                guard offset + 4 <= bytes.count else { throw invalidByte(offset) }
                let second = unit16(bytes, offset: offset + 2, littleEndian: littleEndian)
                guard second >= 0xDC00 && second <= 0xDFFF else { throw invalidByte(offset + 2) }
                value = 0x10000 + ((UInt32(first) - 0xD800) << 10) + (UInt32(second) - 0xDC00)
                offset += 2
            } else if first >= 0xDC00 && first <= 0xDFFF { throw invalidByte(offset) }
            guard let scalar = Unicode.Scalar(value) else { throw invalidByte(offset) }
            scalars.append(scalar)
            offset += 2
        }
        return String(scalars)
    }

    private func decodeUTF32(_ bytes: [UInt8], littleEndian: Bool) throws -> String {
        guard bytes.count.isMultiple(of: 4) else { throw invalidByte(bytes.count - bytes.count % 4) }
        var scalars = String.UnicodeScalarView()
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let value: UInt32
            if littleEndian {
                value = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            } else {
                value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
            }
            guard let scalar = Unicode.Scalar(value) else { throw invalidByte(offset) }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private func decodeSingleByte(_ bytes: [UInt8], windows1252: Bool) throws -> String {
        let map: [UInt8: UInt32] = [
            0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
            0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
            0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
            0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
            0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
            0x9E: 0x017E, 0x9F: 0x0178
        ]
        var scalars = String.UnicodeScalarView()
        for (offset, byte) in bytes.enumerated() {
            let value = windows1252 && byte >= 0x80 && byte <= 0x9F ? map[byte] : UInt32(byte)
            guard let value, let scalar = Unicode.Scalar(value) else { throw invalidByte(offset) }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private func unit16(_ bytes: [UInt8], offset: Int, littleEndian: Bool) -> UInt16 {
        littleEndian ? UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 : UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private func invalidByte(_ offset: Int) -> DelimitedInputError {
        DelimitedInputError(code: "invalidEncoding", stage: "decode", scalarOffset: offset, summary: "Invalid byte sequence at byte offset \(offset).")
    }
}

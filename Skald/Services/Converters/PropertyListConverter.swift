import Foundation

nonisolated final class PropertyListConverter: DocumentConverter {
    let supportedExtensions = ["plist"]

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let data = try Data(contentsOf: url)
        var plistFormat = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &plistFormat)
        let readableValue = normalize(plist)

        switch format {
        case .markdown:
            let blocks = ReadableOutputFormatter.blocks(from: readableValue)
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: blocks
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: url.pathExtension,
                    blocks: [],
                    data: readableValue
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }

    private func normalize(_ value: Any) -> ReadableValue {
        if let dict = value as? [String: Any] {
            var mapped: [String: ReadableValue] = [:]
            for (key, nestedValue) in dict {
                mapped[key] = normalize(nestedValue)
            }
            return .object(mapped)
        }

        if let array = value as? [Any] {
            return .array(array.map { normalize($0) })
        }

        if let stringValue = value as? String {
            return .string(stringValue)
        }

        if let numberValue = value as? NSNumber {
            if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
                return .bool(numberValue.boolValue)
            }
            return .number(numberValue.doubleValue)
        }

        if let dateValue = value as? Date {
            let formatter = ISO8601DateFormatter()
            return .string(formatter.string(from: dateValue))
        }

        if let dataValue = value as? Data {
            return .string(dataValue.base64EncodedString())
        }

        if let urlValue = value as? URL {
            return .string(urlValue.absoluteString)
        }

        return .string(String(describing: value))
    }
}

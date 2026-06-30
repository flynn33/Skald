import Foundation

/// Converts JSON documents into the shared readable model. The parsed value is
/// preserved structurally (objects, arrays, scalars) so JSON output round-trips
/// and Markdown output renders as a readable nested list.
nonisolated final class JSONConverter: DocumentConverter {
    let supportedExtensions = ["json"]

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let data = try Data(contentsOf: url)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ConversionError.invalidDocument
        }
        let value = normalize(object)

        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: ReadableOutputFormatter.blocks(from: value)
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: url.pathExtension,
                    blocks: [],
                    data: value
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }

    private func normalize(_ value: Any) -> ReadableValue {
        if value is NSNull {
            return .null
        }

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

        if let numberValue = value as? NSNumber {
            if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
                return .bool(numberValue.boolValue)
            }
            return .number(numberValue.doubleValue)
        }

        if let stringValue = value as? String {
            return .string(stringValue)
        }

        return .string(String(describing: value))
    }
}

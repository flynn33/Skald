import Foundation
import CoreFoundation

nonisolated final class PropertyListConverter: DocumentConverter {
    let supportedExtensions = ["plist"]
    private let maximumInputBytes: Int
    private let maximumNodes: Int
    private let maximumDepth: Int

    init(maximumInputBytes: Int = 16 * 1_024 * 1_024, maximumNodes: Int = 100_000, maximumDepth: Int = 64) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        guard maximumNodes > 0, maximumDepth > 0 else {
            throw InputDiagnostic(code: "invalidLimitConfiguration", stage: "configure", summary: "Property-list limits must be positive.")
        }
        let data = try BoundedInputReader.read(url, maximumBytes: maximumInputBytes)
        var plistFormat = PropertyListSerialization.PropertyListFormat.xml
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &plistFormat)
        } catch {
            throw InputDiagnostic(code: "malformedPropertyList", stage: "parse", fileName: url.lastPathComponent,
                                  summary: "Property list could not be parsed.", underlying: error)
        }
        var nodes = 0
        let readableValue = try normalize(plist, depth: 1, nodes: &nodes)
        let source = SourceFileDescriptor(url: url)
        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: ReadableOutputFormatter.blocks(from: readableValue))
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(fileName: url.lastPathComponent,
                    sourceExtension: source.fileExtension, blocks: [], data: readableValue)
            } catch {
                throw InputDiagnostic(code: "outputSerializationFailed", stage: "render", fileName: url.lastPathComponent,
                                      summary: "Readable JSON output could not be encoded.", underlying: error)
            }
        }
    }

    private func normalize(_ value: Any, depth: Int, nodes: inout Int) throws -> ReadableValue {
        if Task.isCancelled { throw OutputPublicationError.cancelled }
        guard depth <= maximumDepth else {
            throw InputDiagnostic(code: "depthLimitExceeded", stage: "normalize", summary: "Property-list nesting exceeds the configured limit.")
        }
        nodes += 1
        guard nodes <= maximumNodes else {
            throw InputDiagnostic(code: "nodeLimitExceeded", stage: "normalize", summary: "Property-list value count exceeds the configured limit.")
        }
        if let dict = value as? [String: Any] {
            var mapped: [String: ReadableValue] = [:]
            for (key, nestedValue) in dict { mapped[key] = try normalize(nestedValue, depth: depth + 1, nodes: &nodes) }
            return .object(mapped)
        }
        if let array = value as? [Any] {
            var mapped: [ReadableValue] = []
            mapped.reserveCapacity(min(array.count, maximumNodes - nodes))
            for nestedValue in array { mapped.append(try normalize(nestedValue, depth: depth + 1, nodes: &nodes)) }
            return .array(mapped)
        }
        if let stringValue = value as? String { return .string(stringValue) }
        if let numberValue = value as? NSNumber {
            if CFGetTypeID(numberValue) == CFBooleanGetTypeID() { return .bool(numberValue.boolValue) }
            let numberText = numberValue.stringValue
            if let decimalValue = Decimal(string: numberText, locale: Locale(identifier: "en_US_POSIX")) {
                return .number(decimalValue)
            }
            return .string(numberText)
        }
        if let dateValue = value as? Date { return .string(ISO8601DateFormatter().string(from: dateValue)) }
        if let dataValue = value as? Data { return .string(dataValue.base64EncodedString()) }
        if let urlValue = value as? URL { return .string(urlValue.absoluteString) }
        return .string(String(describing: value))
    }
}

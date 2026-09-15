import Foundation
import CoreFoundation

nonisolated final class JSONConverter: DocumentConverter {
    let supportedExtensions = ["json"]
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
            throw InputDiagnostic(code: "invalidLimitConfiguration", stage: "configure", summary: "JSON limits must be positive.")
        }
        let data = try BoundedInputReader.read(url, maximumBytes: maximumInputBytes)
        try preflightNesting(data)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw InputDiagnostic(code: "malformedJSON", stage: "parse", fileName: url.lastPathComponent,
                                  summary: "JSON syntax could not be parsed.", underlying: error)
        }
        var nodes = 0
        let value = try normalize(object, depth: 1, nodes: &nodes)
        let source = SourceFileDescriptor(url: url)
        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: ReadableOutputFormatter.blocks(from: value)
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(fileName: url.lastPathComponent,
                    sourceExtension: source.fileExtension, blocks: [], data: value)
            } catch {
                throw InputDiagnostic(code: "outputSerializationFailed", stage: "render", fileName: url.lastPathComponent,
                                      summary: "Readable JSON output could not be encoded.", underlying: error)
            }
        }
    }

    private func preflightNesting(_ data: Data) throws {
        var depth = 0
        var inString = false
        var escaped = false
        for (offset, byte) in data.enumerated() {
            if offset.isMultiple(of: 65_536), Task.isCancelled { throw OutputPublicationError.cancelled }
            if inString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { inString = false }
            } else if byte == 0x22 {
                inString = true
            } else if byte == 0x7B || byte == 0x5B {
                depth += 1
                guard depth <= maximumDepth else {
                    throw InputDiagnostic(code: "depthLimitExceeded", stage: "preflight", summary: "JSON nesting exceeds the configured limit.")
                }
            } else if byte == 0x7D || byte == 0x5D {
                depth = max(0, depth - 1)
            }
        }
    }

    private func normalize(_ value: Any, depth: Int, nodes: inout Int) throws -> ReadableValue {
        if Task.isCancelled { throw OutputPublicationError.cancelled }
        guard depth <= maximumDepth else {
            throw InputDiagnostic(code: "depthLimitExceeded", stage: "normalize", summary: "JSON nesting exceeds the configured limit.")
        }
        nodes += 1
        guard nodes <= maximumNodes else {
            throw InputDiagnostic(code: "nodeLimitExceeded", stage: "normalize", summary: "JSON value count exceeds the configured limit.")
        }
        if value is NSNull { return .null }
        if let dict = value as? [String: Any] {
            var mapped: [String: ReadableValue] = [:]
            for (key, nestedValue) in dict {
                mapped[key] = try normalize(nestedValue, depth: depth + 1, nodes: &nodes)
            }
            return .object(mapped)
        }
        if let array = value as? [Any] {
            var mapped: [ReadableValue] = []
            mapped.reserveCapacity(min(array.count, maximumNodes - nodes))
            for nestedValue in array {
                mapped.append(try normalize(nestedValue, depth: depth + 1, nodes: &nodes))
            }
            return .array(mapped)
        }
        if let numberValue = value as? NSNumber {
            if CFGetTypeID(numberValue) == CFBooleanGetTypeID() { return .bool(numberValue.boolValue) }
            let numberText = numberValue.stringValue
            if let decimalValue = Decimal(string: numberText, locale: Locale(identifier: "en_US_POSIX")) {
                return .number(decimalValue)
            }
            return .string(numberText)
        }
        if let stringValue = value as? String { return .string(stringValue) }
        return .string(String(describing: value))
    }
}

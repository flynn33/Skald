import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

nonisolated struct XMLInputError: Error, LocalizedError {
    let code: String
    let stage: String
    let summary: String
    var errorDescription: String? { "\(code) (\(stage)): \(summary)" }
}

/// XML schema 2.0 retains the exact mixed-content sequence rather than grouping
/// same-name children in a dictionary or trimming significant text.
nonisolated final class XMLConverter: DocumentConverter {
    let supportedExtensions = ["xml"]
    private let maximumInputBytes: Int
    private let maximumNodes: Int
    private let maximumDepth: Int
    private let maximumTextBytes: Int

    init(maximumInputBytes: Int = 16 * 1_024 * 1_024, maximumNodes: Int = 10_000, maximumDepth: Int = 64, maximumTextBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumInputBytes = max(1, maximumInputBytes)
        self.maximumNodes = max(1, maximumNodes)
        self.maximumDepth = max(1, maximumDepth)
        self.maximumTextBytes = max(1, maximumTextBytes)
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumInputBytes {
            throw XMLInputError(code: "inputLimitExceeded", stage: "read", summary: "XML input exceeds the configured byte limit.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumInputBytes else {
            throw XMLInputError(code: "inputLimitExceeded", stage: "read", summary: "XML input exceeds the configured byte limit.")
        }
        guard !containsForbiddenDeclaration(data) else {
            throw XMLInputError(code: "externalEntityDenied", stage: "preflight", summary: "DTD and entity declarations are not accepted.")
        }
        let builder = OrderedXMLBuilder(maximumNodes: maximumNodes, maximumDepth: maximumDepth, maximumTextBytes: maximumTextBytes)
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = builder.documentValue() else {
            if let failure = builder.failure { throw failure }
            throw XMLInputError(code: "malformedXML", stage: "parse", summary: "XML parse failed at line \(parser.lineNumber), column \(parser.columnNumber).")
        }
        let value: ReadableValue = .object(["$xml": root])
        switch format {
        case .markdown:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var json = String(decoding: try encoder.encode(value), as: UTF8.self)
            for (literal, escape) in [("&", "\\u0026"), ("<", "\\u003C"), (">", "\\u003E")] {
                json = json.replacingOccurrences(of: literal, with: escape)
            }
            var longest = 0
            var run = 0
            for character in json {
                if character == "~" { run += 1; longest = max(longest, run) } else { run = 0 }
            }
            let fence = String(repeating: "~", count: max(3, longest + 1))
            return "# XML data\n\nOrdered XML nodes and text (JSON schema 2.0):\n\n\(fence)json\n\(json)\n\(fence)\n"
        case .json:
            return try ReadableOutputFormatter.jsonDocument(
                fileName: url.lastPathComponent,
                sourceExtension: "xml",
                blocks: [],
                data: value,
                schemaVersion: "2.0"
            )
        }
    }

    private func containsForbiddenDeclaration(_ data: Data) -> Bool {
        let declarations = [Array("<!DOCTYPE".utf8), Array("<!ENTITY".utf8)]
        var offsets = [0, 0]
        // ASCII markup bytes in UTF-16/UTF-32 have intervening zero bytes.
        // Ignore those bytes so the same denial applies before XMLParser sees
        // an internal or external DTD in any of its supported encodings.
        for byte in data where byte != 0 {
            let upper = byte >= 97 && byte <= 122 ? byte - 32 : byte
            for index in declarations.indices {
                let marker = declarations[index]
                offsets[index] = upper == marker[offsets[index]] ? offsets[index] + 1 : (upper == marker[0] ? 1 : 0)
                if offsets[index] == marker.count { return true }
            }
        }
        return false
    }
}

private nonisolated final class OrderedXMLBuilder: NSObject, XMLParserDelegate {
    private nonisolated final class Node {
        let name: String
        let namespaceURI: String?
        let attributes: [(name: String, namespaceURI: String?, value: String)]
        var content: [Segment] = []
        init(name: String, namespaceURI: String?, attributes: [(String, String?, String)]) {
            self.name = name
            self.namespaceURI = namespaceURI
            self.attributes = attributes
        }
    }
    private nonisolated enum Segment {
        case text(String, cdata: Bool)
        case element(Node)
    }
    let maximumNodes: Int
    let maximumDepth: Int
    let maximumTextBytes: Int
    private var nodeCount = 0
    private var textBytes = 0
    private var stack: [Node] = []
    private var root: Node?
    private var prefixBindings: [String: [String]] = ["xml": ["http://www.w3.org/XML/1998/namespace"]]
    private(set) var failure: XMLInputError?

    init(maximumNodes: Int, maximumDepth: Int, maximumTextBytes: Int) {
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
        self.maximumTextBytes = maximumTextBytes
    }

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        prefixBindings[prefix, default: []].append(namespaceURI)
    }

    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        _ = prefixBindings[prefix]?.popLast()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard failure == nil else { parser.abortParsing(); return }
        nodeCount += 1
        guard nodeCount <= maximumNodes else { reject(parser, code: "nodeLimitExceeded", summary: "XML node count exceeds the configured limit."); return }
        guard stack.count < maximumDepth else { reject(parser, code: "depthLimitExceeded", summary: "XML nesting exceeds the configured limit."); return }
        let attributes = attributeDict.keys.sorted().map { name -> (String, String?, String) in
            let prefix = name.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            let uri = name.contains(":") ? prefixBindings[prefix]?.last : nil
            return (name, uri, attributeDict[name] ?? "")
        }
        let node = Node(name: qName ?? elementName, namespaceURI: namespaceURI?.isEmpty == true ? nil : namespaceURI, attributes: attributes)
        if let parent = stack.last { parent.content.append(.element(node)) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string, cdata: false, parser: parser)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else {
            reject(parser, code: "invalidCDATA", summary: "CDATA is not valid UTF-8.")
            return
        }
        appendText(string, cdata: true, parser: parser)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        reject(parser, code: "externalEntityDenied", summary: "External entity resolution is disabled.")
        return nil
    }

    private func appendText(_ text: String, cdata: Bool, parser: XMLParser) {
        guard failure == nil, let node = stack.last else { return }
        textBytes += text.utf8.count
        guard textBytes <= maximumTextBytes else { reject(parser, code: "textLimitExceeded", summary: "XML text exceeds the configured limit."); return }
        if let last = node.content.last, case .text(let previous, let wasCDATA) = last, wasCDATA == cdata {
            node.content[node.content.count - 1] = .text(previous + text, cdata: cdata)
        } else {
            node.content.append(.text(text, cdata: cdata))
        }
    }

    private func reject(_ parser: XMLParser, code: String, summary: String) {
        failure = XMLInputError(code: code, stage: "parse", summary: summary)
        parser.abortParsing()
    }

    func documentValue() -> ReadableValue? {
        guard let root else { return nil }
        return value(for: root)
    }

    private func value(for node: Node) -> ReadableValue {
        .object([
            "name": .string(node.name),
            "namespaceURI": node.namespaceURI.map(ReadableValue.string) ?? .null,
            "attributes": .array(node.attributes.map { attribute in
                .object([
                    "name": .string(attribute.name),
                    "namespaceURI": attribute.namespaceURI.map(ReadableValue.string) ?? .null,
                    "value": .string(attribute.value)
                ])
            }),
            "content": .array(node.content.map { segment in
                switch segment {
                case .text(let text, let cdata):
                    return .object(["kind": .string(cdata ? "cdata" : "text"), "text": .string(text)])
                case .element(let child):
                    return .object(["kind": .string("element"), "element": value(for: child)])
                }
            })
        ])
    }
}

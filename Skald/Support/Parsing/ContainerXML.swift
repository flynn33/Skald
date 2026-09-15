import Foundation

nonisolated enum ContainerXMLContent {
    case text(String)
    case element(ContainerXMLNode)
}

nonisolated final class ContainerXMLNode {
    let name: String
    let namespace: String?
    let attributes: [String: String]
    var contents: [ContainerXMLContent] = []

    init(name: String, namespace: String?, attributes: [String: String]) {
        self.name = name
        self.namespace = namespace
        self.attributes = attributes
    }

    func attribute(_ key: String) -> String? {
        attributes[key] ?? attributes.first { $0.key.hasSuffix(":" + key) }?.value
    }

    func children(_ name: String) -> [ContainerXMLNode] {
        contents.compactMap { content in
            guard case .element(let node) = content, node.name == name else { return nil }
            return node
        }
    }

    func first(_ name: String) -> ContainerXMLNode? { children(name).first }

    func descendants(_ name: String) -> [ContainerXMLNode] {
        var found: [ContainerXMLNode] = []
        for content in contents {
            guard case .element(let node) = content else { continue }
            if node.name == name { found.append(node) }
            found.append(contentsOf: node.descendants(name))
        }
        return found
    }

    var text: String {
        var value = String()
        for content in contents {
            switch content {
            case .text(let segment): value += segment
            case .element(let node): value += node.text
            }
        }
        return value
    }
}

nonisolated enum ContainerXML {
    static func parse(_ data: Data, maximumBytes: Int = 16 * 1_024 * 1_024,
                      maximumNodes: Int = 100_000, maximumDepth: Int = 64,
                      maximumTextBytes: Int = 8 * 1_024 * 1_024) throws -> ContainerXMLNode {
        guard maximumBytes > 0, maximumNodes > 0, maximumDepth > 0, maximumTextBytes > 0 else {
            throw InputDiagnostic(code: "invalidLimitConfiguration", stage: "configure", summary: "Container XML limits must be positive.")
        }
        guard data.count <= maximumBytes else {
            throw InputDiagnostic(code: "inputLimitExceeded", stage: "read", summary: "Container XML part exceeds the configured byte limit.")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw InputDiagnostic(code: "xmlEncodingUnsupported", stage: "preflight", summary: "Container XML parts must use UTF-8 in this subset.")
        }
        let lower = text.lowercased()
        guard !lower.contains("<!doctype"), !lower.contains("<!entity") else {
            throw InputDiagnostic(code: "externalEntityDenied", stage: "preflight", summary: "Container XML DTD and entity declarations are denied.")
        }
        let collector = XMLCollector(maximumNodes: maximumNodes, maximumDepth: maximumDepth,
                                     maximumTextBytes: maximumTextBytes)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = collector.root else {
            throw collector.diagnostic ?? InputDiagnostic(code: "malformedContainerXML", stage: "parse",
                                                          summary: "Container XML part could not be parsed.",
                                                          underlying: parser.parserError)
        }
        return root
    }
}

private nonisolated final class XMLCollector: NSObject, XMLParserDelegate {
    let maximumNodes: Int
    let maximumDepth: Int
    let maximumTextBytes: Int
    var root: ContainerXMLNode?
    var diagnostic: InputDiagnostic?
    private var stack: [ContainerXMLNode] = []
    private var nodes = 0
    private var textBytes = 0

    init(maximumNodes: Int, maximumDepth: Int, maximumTextBytes: Int) {
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
        self.maximumTextBytes = maximumTextBytes
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if Task.isCancelled { reject(parser, code: "cancelled", summary: "Container XML parse was cancelled."); return }
        nodes += 1
        guard nodes <= maximumNodes, stack.count < maximumDepth else {
            reject(parser, code: nodes > maximumNodes ? "nodeLimitExceeded" : "depthLimitExceeded",
                   summary: "Container XML structure exceeds the configured limit.")
            return
        }
        let node = ContainerXMLNode(name: elementName, namespace: namespaceURI, attributes: attributeDict)
        if let parent = stack.last { parent.contents.append(.element(node)) }
        else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        append(string, parser: parser)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { append(text, parser: parser) }
        else { reject(parser, code: "invalidCDATA", summary: "Container XML CDATA is not UTF-8.") }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        reject(parser, code: "externalEntityDenied", summary: "External XML entities are denied.")
        return nil
    }

    private func append(_ text: String, parser: XMLParser) {
        guard let node = stack.last else { return }
        guard text.utf8.count <= maximumTextBytes - textBytes else {
            reject(parser, code: "textLimitExceeded", summary: "Container XML text exceeds the configured limit.")
            return
        }
        textBytes += text.utf8.count
        node.contents.append(.text(text))
    }

    private func reject(_ parser: XMLParser, code: String, summary: String) {
        diagnostic = InputDiagnostic(code: code, stage: "parse", summary: summary)
        parser.abortParsing()
    }
}

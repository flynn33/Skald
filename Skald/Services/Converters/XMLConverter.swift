import Foundation

/// Converts XML into the shared readable model using Foundation's streaming
/// `XMLParser`. Elements become objects; attributes are keyed with an `@` prefix;
/// repeated child tags collapse into arrays; leaf text becomes a string.
nonisolated final class XMLConverter: DocumentConverter {
    let supportedExtensions = ["xml"]

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let data = try Data(contentsOf: url)
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder

        guard parser.parse(), let value = builder.documentValue() else {
            throw ConversionError.invalidDocument
        }

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
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private final class Node {
        var attributes: [String: String]
        var children: [(name: String, node: Node)] = []
        var text: String = ""

        init(attributes: [String: String]) {
            self.attributes = attributes
        }
    }

    private var stack: [Node] = []
    private var root: Node?
    private var rootName: String?

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let node = Node(attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append((elementName, node))
        } else {
            root = node
            rootName = elementName
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            stack.last?.text += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        stack.removeLast()
    }

    func documentValue() -> ReadableValue? {
        guard let root, let rootName else { return nil }
        return .object([rootName: value(for: root)])
    }

    private func value(for node: Node) -> ReadableValue {
        let trimmedText = node.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if node.children.isEmpty && node.attributes.isEmpty {
            return .string(trimmedText)
        }

        var object: [String: ReadableValue] = [:]

        for (key, attributeValue) in node.attributes {
            object["@\(key)"] = .string(attributeValue)
        }

        var grouped: [String: [ReadableValue]] = [:]
        var order: [String] = []
        for (name, child) in node.children {
            if grouped[name] == nil { order.append(name) }
            grouped[name, default: []].append(value(for: child))
        }
        for name in order {
            let values = grouped[name] ?? []
            object[name] = values.count == 1 ? values[0] : .array(values)
        }

        if !trimmedText.isEmpty {
            object["#text"] = .string(trimmedText)
        }

        return .object(object)
    }
}

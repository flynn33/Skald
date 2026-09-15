import Foundation

nonisolated final class DelimitedTextInterpreter {
    func interpret(rows: [[String]], headerMode: HeaderMode) -> InterpretedDelimitedText {
        guard !rows.isEmpty else {
            return InterpretedDelimitedText(originalHeader: nil, dataRows: [], diagnostics: [DelimitedDiagnostic(code: "emptyInput")], headerConfirmed: false)
        }
        var diagnostics: [DelimitedDiagnostic] = []
        let headerConfirmed = headerMode == .present
        let originalHeader = headerConfirmed ? rows[0] : nil
        let dataRows = headerConfirmed ? Array(rows.dropFirst()) : rows
        if headerMode == .automatic { diagnostics.append(DelimitedDiagnostic(code: "headerUnconfirmed")) }
        if let originalHeader {
            if originalHeader.contains("") { diagnostics.append(DelimitedDiagnostic(code: "blankHeader")) }
            let nonempty = originalHeader.filter { !$0.isEmpty }
            if Set(nonempty).count != nonempty.count { diagnostics.append(DelimitedDiagnostic(code: "duplicateHeader")) }
        }
        let expectedWidth = originalHeader?.count ?? rows[0].count
        if dataRows.contains(where: { $0.count != expectedWidth }) { diagnostics.append(DelimitedDiagnostic(code: "rowWidthMismatch")) }
        return InterpretedDelimitedText(originalHeader: originalHeader, dataRows: dataRows, diagnostics: diagnostics, headerConfirmed: headerConfirmed)
    }
}

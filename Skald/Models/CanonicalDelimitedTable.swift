import Foundation

nonisolated struct CanonicalDelimitedColumn: Codable {
    let id: String
    let label: String
    let origin: String
}

nonisolated struct CanonicalDelimitedRecord: Codable {
    let index: Int
    let fieldCount: Int
    let cells: [String?]
}

nonisolated struct CanonicalDelimitedTable: Codable {
    let columns: [CanonicalDelimitedColumn]
    let records: [CanonicalDelimitedRecord]

    init(header: [String]?, rows: [[String]]) {
        let width = max(header?.count ?? 0, rows.map(\.count).max() ?? 0)
        columns = (0..<width).map { index in
            CanonicalDelimitedColumn(
                id: "c\(index + 1)",
                label: index < (header?.count ?? 0) ? header![index] : "Column \(index + 1)",
                origin: index < (header?.count ?? 0) ? "header" : "generated"
            )
        }
        records = rows.enumerated().map { index, row in
            CanonicalDelimitedRecord(
                index: index + 1,
                fieldCount: row.count,
                cells: (0..<width).map { $0 < row.count ? row[$0] : nil }
            )
        }
    }

    func dataProjection() -> ReadableValue {
        .array(records.map { record in
            .object(Dictionary(uniqueKeysWithValues: zip(columns, record.cells).map { column, cell in
                (column.id, cell.map(ReadableValue.string) ?? .null)
            }))
        })
    }
}

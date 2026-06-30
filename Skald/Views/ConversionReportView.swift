import SwiftUI

struct ConversionReportView: View {
    let report: ConversionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversion Report")
                .font(.headline)

            Text(report.summaryLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(report.entries) { entry in
                        ConversionReportRow(entry: entry)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConversionReportRow: View {
    let entry: ConversionEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.status.label.uppercased())
                .font(.caption)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(statusColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(fileLabel)
                    .font(.body)

                if let message = entry.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileLabel: String {
        if entry.fileExtension.isEmpty {
            return entry.fileName
        }
        return "\(entry.fileName).\(entry.fileExtension)"
    }

    private var statusColor: Color {
        switch entry.status {
        case .converted:
            return .green
        case .skipped:
            return .gray
        case .failed:
            return .red
        }
    }
}

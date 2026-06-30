import SwiftUI

struct StatusMessageView: View {
    let message: String
    let status: ConversionViewModel.Status

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        switch status {
        case .idle, .converting:
            return .secondary
        case let .completed(hasFailures):
            return hasFailures ? .orange : .secondary
        case .failed:
            return .red
        }
    }
}

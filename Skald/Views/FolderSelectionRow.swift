import SwiftUI

struct FolderSelectionRow: View {
    let title: String
    let url: URL?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .frame(width: 80, alignment: .leading)

            Button(action: action) {
                Label("Choose", systemImage: "folder")
            }

            Text(url?.path(percentEncoded: false) ?? "Nothing selected")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

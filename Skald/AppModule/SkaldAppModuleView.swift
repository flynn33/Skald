import SwiftUI

struct SkaldAppModuleView: View {
    @StateObject private var viewModel = ConversionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 12) {
                FolderSelectionRow(
                    title: "Source",
                    url: viewModel.sourceFolderURL,
                    action: viewModel.selectSourceFolder
                )

                FolderSelectionRow(
                    title: "Target",
                    url: viewModel.targetFolderURL,
                    action: viewModel.selectTargetFolder
                )
            }

            HStack(spacing: 12) {
                Picker("Output", selection: $viewModel.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                Button {
                    viewModel.convertFiles()
                } label: {
                    Label(viewModel.isConverting ? "Converting" : "Convert", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!viewModel.canConvert)
                .keyboardShortcut(.defaultAction)
            }

            StatusMessageView(message: viewModel.statusMessage, status: viewModel.status)

            if let report = viewModel.report {
                ConversionReportView(report: report)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skald")
                .font(.title.bold())

            Text("Convert document folders into Markdown or JSON.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SkaldAppModuleView()
}

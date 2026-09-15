import SwiftUI
import UniformTypeIdentifiers

struct SkaldAppModuleView: View {
    @StateObject private var viewModel = ConversionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    FolderSelectionRow(
                        title: "Sources",
                        url: viewModel.sourceFolderURL,
                        action: viewModel.selectSourceFolder
                    )
                    Text("\(viewModel.sourceURLs.count) selected. Drop source files or folders here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                    for provider in providers {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                            guard let url else { return }
                            Task { @MainActor in viewModel.acceptDroppedSources(viewModel.sourceURLs + [url]) }
                        }
                    }
                    return !providers.isEmpty
                }

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
                if viewModel.isConverting {
                    Button("Cancel") { viewModel.cancelConversion() }
                }
            }

            HStack(spacing: 14) {
                Toggle("Include nested folders", isOn: $viewModel.recursive)
                Toggle("Include hidden files", isOn: $viewModel.includeHidden)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CSV / TSV interpretation").font(.headline)
                HStack(spacing: 12) {
                    Picker("Encoding", selection: $viewModel.textEncoding) {
                        ForEach(TextEncodingChoice.allCases) { choice in Text(choice.label).tag(choice) }
                    }
                    Picker("Delimiter", selection: $viewModel.delimiterChoice) {
                        ForEach(DelimiterChoice.pickerChoices, id: \.self) { choice in Text(choice.label).tag(choice) }
                    }
                    Picker("Header", selection: $viewModel.headerMode) {
                        ForEach(HeaderMode.allCases) { mode in Text(mode.label).tag(mode) }
                    }
                }
                .pickerStyle(.menu)
                HStack(spacing: 12) {
                    Toggle("Custom delimiter", isOn: $viewModel.usesCustomDelimiter)
                    if viewModel.usesCustomDelimiter {
                        TextField("One character", text: $viewModel.customDelimiter)
                            .frame(width: 100)
                    }
                    Toggle("Use sep= preamble", isOn: $viewModel.allowsSepPreamble)
                }
            }

            StatusMessageView(message: viewModel.statusMessage, status: viewModel.status)

            if let report = viewModel.report {
                ConversionReportView(report: report)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 500)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skald")
                .font(.title.bold())

            Text("Convert selected files and folders into Markdown or JSON.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SkaldAppModuleView()
}

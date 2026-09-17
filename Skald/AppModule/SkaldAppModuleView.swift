import SwiftUI
import UniformTypeIdentifiers

struct SkaldAppModuleView: View {
    @StateObject private var viewModel = ConversionViewModel()

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    FolderSelectionRow(
                        title: "Sources",
                        url: viewModel.sourceFolderURL,
                        action: { Task { @MainActor in viewModel.selectSourceFolder() } }
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
                    action: { Task { @MainActor in viewModel.selectTargetFolder() } }
                )
            }

            HStack(spacing: 12) {
                Picker("Output", selection: Binding(
                    get: { viewModel.outputMode },
                    set: { mode in Task { @MainActor in viewModel.outputMode = mode } }
                )) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                Button {
                    Task { @MainActor in viewModel.convertFiles() }
                } label: {
                    Label(viewModel.isConverting ? "Converting" : "Convert", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!viewModel.canConvert)
                .keyboardShortcut(.defaultAction)
                if viewModel.isConverting {
                    Button("Cancel") { Task { @MainActor in viewModel.cancelConversion() } }
                }
            }

            HStack(spacing: 14) {
                Toggle("Bundle original with outputs", isOn: $viewModel.bundleOriginal)
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
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 780, minHeight: 500)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skald")
                .font(.title.bold())

            Text("Convert selected files and folders into Markdown, JSON, or both.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SkaldAppModuleView()
}

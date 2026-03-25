import SwiftUI

struct AssemblySidebarSection: View {
    @EnvironmentObject var appState: AppState

    private var groupedDocs: [(String, [AssemblyDocument])] {
        let categories = ["BOM", "Assembly", "Schematic", "Fab", "3D Model"]
        return categories.compactMap { cat in
            let docs = appState.assemblyStore.documents.filter { $0.category == cat }
            return docs.isEmpty ? nil : (cat, docs)
        }
    }

    var body: some View {
        ForEach(groupedDocs, id: \.0) { category, docs in
            DisclosureGroup {
                ForEach(docs) { doc in
                    HStack(spacing: 6) {
                        Image(systemName: doc.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 4) {
                                if !doc.revision.isEmpty {
                                    Text(doc.revision)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                Text(doc.formattedSize)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openAssemblyDoc(doc)
                    }
                    .contextMenu {
                        Button("Open in Preview") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: doc.path))
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(doc.path, inFileViewerRootedAtPath: "")
                        }
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(doc.path, forType: .string)
                        }
                    }
                }
            } label: {
                Label("\(category) (\(docs.count))", systemImage: docs.first?.icon ?? "doc")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
    }

    private func isGerberFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["gbr", "gtl", "gbl", "gts", "gbs", "gto", "gbo", "gtp", "gbp", "gm1", "gko", "drl", "xln"].contains(ext)
    }

    private func openAssemblyDoc(_ doc: AssemblyDocument) {
        appState.selectedAssemblyDoc = doc
        appState.selectedDatasheet = nil
        appState.selectedECO = nil
        appState.selectedIQCItem = nil
        appState.showCredits = false
        appState.showFEL = false
        appState.showUSBMonitor = false

        if doc.path.lowercased().hasSuffix(".pdf") {
            appState.loadPDF(at: doc.path)
        } else if doc.path.lowercased().hasSuffix(".csv") {
            appState.pdfDocument = nil
        } else if isGerberFile(doc.path) {
            appState.pdfDocument = nil
        } else if doc.path.lowercased().hasSuffix(".md") {
            appState.pdfDocument = nil
        } else if doc.path.lowercased().hasSuffix(".dxf") {
            appState.pdfDocument = nil
        } else if doc.path.lowercased().hasSuffix(".json") {
            appState.pdfDocument = nil
        } else if ["step", "stp"].contains(URL(fileURLWithPath: doc.path).pathExtension.lowercased()) {
            appState.pdfDocument = nil
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: doc.path))
        }
    }
}

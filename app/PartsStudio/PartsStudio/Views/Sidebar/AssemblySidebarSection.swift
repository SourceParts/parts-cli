import SwiftUI

struct AssemblySidebarSection: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("assembly.groupByFolder") private var groupByFolder: Bool = false

    private var groupedByCategory: [(String, [AssemblyDocument])] {
        let categories = ["BOM", "Assembly", "Schematic", "Fab", "3D Model"]
        return categories.compactMap { cat in
            let docs = appState.assemblyStore.documents.filter { $0.category == cat }
            return docs.isEmpty ? nil : (cat, docs)
        }
    }

    private var groupedByFolder: [(String, [AssemblyDocument])] {
        var folders: [String: [AssemblyDocument]] = [:]
        for doc in appState.assemblyStore.documents {
            let dir = URL(fileURLWithPath: doc.path).deletingLastPathComponent().lastPathComponent
            folders[dir, default: []].append(doc)
        }
        return folders.sorted { $0.key < $1.key }
    }

    private var activeGroups: [(String, [AssemblyDocument])] {
        groupByFolder ? groupedByFolder : groupedByCategory
    }

    private func iconForGroup(_ name: String, docs: [AssemblyDocument]) -> String {
        if groupByFolder { return "folder" }
        return docs.first?.icon ?? "doc"
    }

    var body: some View {
        // Group mode toggle
        HStack(spacing: 4) {
            Spacer()
            Button(action: { groupByFolder.toggle() }) {
                Image(systemName: groupByFolder ? "folder" : "square.grid.2x2")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(groupByFolder ? "Group by category" : "Group by folder")
        }
        .padding(.horizontal, 4)

        ForEach(activeGroups, id: \.0) { group, docs in
            DisclosureGroup {
                ForEach(docs) { doc in
                    assemblyDocRow(doc)
                }
            } label: {
                Label("\(group) (\(docs.count))", systemImage: iconForGroup(group, docs: docs))
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
    }

    @ViewBuilder
    private func assemblyDocRow(_ doc: AssemblyDocument) -> some View {
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
                    if groupByFolder {
                        Text(doc.category)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
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

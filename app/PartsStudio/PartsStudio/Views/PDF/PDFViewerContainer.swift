#if os(macOS)
import SwiftUI
import PDFKit

struct PDFViewerContainer: View {
    @EnvironmentObject var appState: AppState
    @State private var annotationRefresh: UUID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            PDFToolbarView()

            if let document = appState.pdfDocument {
                PDFViewerView(
                    document: document,
                    currentPage: $appState.currentPage,
                    toolMode: appState.currentTool,
                    annotationStore: appState.annotationStore.annotations,
                    conversationStore: appState.annotationStore.conversations,
                    dataLabelStore: appState.dataLabelStore,
                    onAnnotationAdded: {
                        annotationRefresh = UUID()
                    },
                    onCommentAdded: {
                        annotationRefresh = UUID()
                    },
                    onLabelAdded: {
                        annotationRefresh = UUID()
                    }
                )
                .id(annotationRefresh)
            }

            // Bottom file info bar
            if let ds = appState.selectedDatasheet {
                Divider()
                HStack {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(ds.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(action: {
                        NSWorkspace.shared.selectFile(ds.path, inFileViewerRootedAtPath: "")
                    }) {
                        Image(systemName: "folder")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reveal in Finder")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
            } else if let asmDoc = appState.selectedAssemblyDoc {
                Divider()
                HStack {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(asmDoc.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(action: {
                        NSWorkspace.shared.selectFile(asmDoc.path, inFileViewerRootedAtPath: "")
                    }) {
                        Image(systemName: "folder")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reveal in Finder")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}

struct PDFToolbarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Tool mode picker
            ForEach(ToolMode.allCases) { mode in
                Button(action: { appState.currentTool = mode }) {
                    VStack(spacing: 1) {
                        Image(systemName: mode.icon)
                            .frame(width: 24, height: 24)
                        Text(mode.label)
                            .font(.system(size: 9))
                    }
                }
                .buttonStyle(.bordered)
                .tint(appState.currentTool == mode ? .accentColor : .secondary)
                .help(mode.tooltip)
            }

            Divider()
                .frame(height: 28)

            // Page navigation
            Button(action: { appState.goToPage(appState.currentPage - 1) }) {
                Image(systemName: "chevron.left")
            }
            .disabled(appState.currentPage <= 0)
            .help("Previous page")

            Text("Page \(appState.currentPage + 1) of \(appState.pageCount)")
                .font(.caption)
                .monospacedDigit()
                .frame(minWidth: 120)

            Button(action: { appState.goToPage(appState.currentPage + 1) }) {
                Image(systemName: "chevron.right")
            }
            .disabled(appState.currentPage >= appState.pageCount - 1)
            .help("Next page")

            Divider()
                .frame(height: 28)

            // Go to page
            PageJumpField(pageCount: appState.pageCount) { page in
                appState.goToPage(page - 1)
            }

            Divider()
                .frame(height: 28)

            // Zoom controls
            Button(action: { NotificationCenter.default.post(name: .zoomOut, object: nil) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out (Cmd+-)")
            .keyboardShortcut("-", modifiers: [.command])

            Button(action: { NotificationCenter.default.post(name: .zoomFit, object: nil) }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit to window")

            Button(action: { NotificationCenter.default.post(name: .zoomIn, object: nil) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in (Cmd++)")
            .keyboardShortcut("+", modifiers: [.command])

            Spacer()

            // Annotation count for current page
            let pageAnnotations = appState.annotationStore.annotations.annotationsForPage(appState.currentPage)
            if !pageAnnotations.isEmpty {
                Text("\(pageAnnotations.count) annotation\(pageAnnotations.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }

            // Data label count for current page
            let pageLabels = appState.dataLabelStore.labelsForPage(appState.currentPage)
            if !pageLabels.isEmpty {
                Text("\(pageLabels.count) label\(pageLabels.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.teal.opacity(0.15)))
            }

            // Datasheet name
            if let ds = appState.selectedDatasheet {
                Text(ds.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Currently viewing: \(ds.filename)\nHash: sha256_\(ds.contentHash)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct PageJumpField: View {
    let pageCount: Int
    let onSubmit: (Int) -> Void
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text("Go to:")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("pg #", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .font(.caption)
                .onSubmit {
                    if let page = Int(text), page >= 1, page <= pageCount {
                        onSubmit(page)
                        text = ""
                    }
                }
                .help("Type a page number and press Enter to jump")
        }
    }
}
#endif

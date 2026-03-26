#if os(macOS)
import SwiftUI

struct DatasheetSidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var newProjectName: String = ""
    @State private var showNewProject: Bool = false
    @State private var renamingProjectId: String?
    @State private var renameText: String = ""
    @AppStorage("sidebar.datasheetsExpanded") private var datasheetsExpanded: Bool = true
    @AppStorage("sidebar.iqcExpanded") private var iqcExpanded: Bool = true
    @AppStorage("sidebar.ecoExpanded") private var ecoExpanded: Bool = true
    @AppStorage("sidebar.reportsExpanded") private var reportsExpanded: Bool = true
    @AppStorage("sidebar.assemblyExpanded") private var assemblyExpanded: Bool = true

    private var projectStore: ProjectStore { appState.projectStore }

    var filteredDatasheets: [CachedDatasheet] {
        let query = appState.sidebarSearchText.lowercased()
        let all = appState.cacheService.datasheets
        if query.isEmpty { return all }
        return all.filter { ds in
            ds.displayName.lowercased().contains(query) ||
            ds.filename.lowercased().contains(query) ||
            ds.aliases.contains(where: { $0.lowercased().contains(query) })
        }
    }

    /// Datasheets not assigned to any project
    var unassignedDatasheets: [CachedDatasheet] {
        let allAssigned = Set(projectStore.projects.flatMap { $0.datasheetIds })
        return filteredDatasheets.filter { !allAssigned.contains($0.id) }
    }

    /// Navigation title changes based on selected project
    private var navigationTitle: String {
        if let project = projectStore.selectedProject {
            return "Parts Studio \u{2014} \(project.name)"
        }
        return "Parts Studio"
    }

    /// Datasheets visible in the sidebar based on selected project filter
    private var visibleDatasheets: [CachedDatasheet] {
        if let project = projectStore.selectedProject {
            return projectStore.datasheetsForProject(project, allDatasheets: filteredDatasheets)
        }
        return filteredDatasheets
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appState.selectedDatasheet) {
                // When a project is selected, show a "Show All" button and only that project's datasheets
                if let selectedProject = projectStore.selectedProject {
                    Button(action: { projectStore.selectedProject = nil }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text("Show All")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)

                    projectSection(selectedProject)
                } else {
                    // Projects section
                    ForEach(projectStore.projects) { project in
                        projectSection(project)
                    }

                    // New project row
                    if showNewProject {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            TextField("Project name", text: $newProjectName)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onSubmit { createProject() }
                            Button(action: createProject) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(newProjectName.isEmpty)
                            Button(action: { showNewProject = false; newProjectName = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }

                    // Unassigned datasheets
                    if !unassignedDatasheets.isEmpty {
                        DisclosureGroup(isExpanded: $datasheetsExpanded) {
                            ForEach(unassignedDatasheets) { datasheet in
                                DatasheetRowView(datasheet: datasheet)
                                    .tag(datasheet)
                                    .contextMenu {
                                        datasheetContextMenu(datasheet)
                                    }
                            }
                        } label: {
                            Label("Datasheets (\(unassignedDatasheets.count))", systemImage: "doc.text")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }

                    // No-results hint when filtering
                    if filteredDatasheets.isEmpty && !appState.sidebarSearchText.isEmpty {
                        VStack(spacing: 6) {
                            Text("No matches for \"\(appState.sidebarSearchText)\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Press Enter to search source.parts")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }

                    // IQC Reports
                    if !appState.effectiveIQCItems.isEmpty {
                        DisclosureGroup(isExpanded: $iqcExpanded) {
                            IQCSidebarSection()
                        } label: {
                            IQCSidebarSectionHeader()
                        }
                    }

                    // Assembly Documents
                    if !appState.assemblyStore.documents.isEmpty {
                        DisclosureGroup(isExpanded: $assemblyExpanded) {
                            AssemblySidebarSection()
                        } label: {
                            Label("Assembly (\(appState.assemblyStore.documents.count))", systemImage: "hammer")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }

                    // ECO Tracker
                    if !appState.ecoStore.documents.isEmpty {
                        DisclosureGroup(isExpanded: $ecoExpanded) {
                            ECOSidebarSection()
                        } label: {
                            Label("ECO Tracker (\(appState.ecoStore.documents.count))", systemImage: "doc.badge.gearshape")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }

                    // Reports
                    if !appState.reportsStore.documents.isEmpty {
                        DisclosureGroup(isExpanded: $reportsExpanded) {
                            ReportsSidebarSection()
                        } label: {
                            Label("Reports (\(appState.reportsStore.documents.count))", systemImage: "chart.bar.doc.horizontal")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }

                    // FEL Device
                    Divider()
                        .padding(.vertical, 4)

                    FELSidebarSection()
                    ESLRSidebarSection()

                    // Tools & Services
                    Divider()
                        .padding(.vertical, 4)

                    Button(action: {
                        appState.showCAMProcessor = true
                        appState.showPCBEditor = false
                        appState.showFEL = false
                        appState.showUSBMonitor = false
                        appState.showCredits = false
                        appState.showBLE = false
                        appState.showBotInbox = false
                        appState.selectedDatasheet = nil
                        appState.selectedECO = nil
                        appState.selectedIQCItem = nil
                        appState.selectedAssemblyDoc = nil
                        appState.pdfDocument = nil
                    }) {
                        Label("CAM Processor", systemImage: "gearshape.2")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.showCAMProcessor ? Color.accentColor : .primary)

                    Button(action: {
                        appState.showPCBEditor = true
                        appState.showCAMProcessor = false
                        appState.showFEL = false
                        appState.showUSBMonitor = false
                        appState.showCredits = false
                        appState.showBLE = false
                        appState.showBotInbox = false
                        appState.selectedDatasheet = nil
                        appState.selectedECO = nil
                        appState.selectedIQCItem = nil
                        appState.selectedAssemblyDoc = nil
                        appState.pdfDocument = nil
                    }) {
                        Label("PCB Editor", systemImage: "cpu")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.showPCBEditor ? Color.accentColor : .primary)

                    Button(action: {
                        appState.showCredits = true
                        appState.showFEL = false
                        appState.showUSBMonitor = false
                        appState.showPCBEditor = false
                        appState.showCAMProcessor = false
                        appState.selectedDatasheet = nil
                        appState.selectedECO = nil
                        appState.selectedIQCItem = nil
                        appState.pdfDocument = nil
                        appState.lastActiveView = "credits"
                    }) {
                        Label("Credits & Services", systemImage: "creditcard")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.showCredits ? Color.accentColor : .primary)

                    Button(action: {
                        appState.showUSBMonitor = true
                        appState.showCredits = false
                        appState.showFEL = false
                        appState.showCAMProcessor = false
                        appState.showPCBEditor = false
                        appState.selectedDatasheet = nil
                        appState.selectedECO = nil
                        appState.selectedIQCItem = nil
                        appState.pdfDocument = nil
                        appState.lastActiveView = "usb"
                    }) {
                        Label("USB Monitor", systemImage: "cable.connector")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.showUSBMonitor ? Color.accentColor : .primary)

                    Button(action: {
                        appState.showBotInbox = true
                        appState.showUSBMonitor = false
                        appState.showCredits = false
                        appState.showFEL = false
                        appState.showBLE = false
                        appState.showCAMProcessor = false
                        appState.showPCBEditor = false
                        appState.selectedDatasheet = nil
                        appState.selectedECO = nil
                        appState.selectedIQCItem = nil
                        appState.selectedAssemblyDoc = nil
                        appState.pdfDocument = nil
                    }) {
                        Label("Bot Inbox", systemImage: "envelope.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.showBotInbox ? Color.accentColor : .primary)
                }
            }
            .searchable(text: $appState.sidebarSearchText, prompt: "Filter datasheets")
            .onSubmit(of: .search) {
                guard !appState.sidebarSearchText.isEmpty else { return }
                // Navigate to Parts Q — clear all selections so ContentView falls through to PartsQView
                appState.selectedDatasheet = nil
                appState.selectedECO = nil
                appState.selectedIQCItem = nil
                appState.selectedAssemblyDoc = nil
                appState.pdfDocument = nil
                appState.showFEL = false
                appState.showUSBMonitor = false
                appState.showCredits = false
            }
            .onChange(of: appState.selectedDatasheet) { _, newValue in
                if let ds = newValue {
                    appState.selectDatasheet(ds)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showNewProject = true }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Create a new project to group datasheets together")

                Button(action: { appState.cacheService.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload datasheets from ~/.cache/parts/datasheets/")
            }
        }
    }

    // MARK: - Project Section

    @ViewBuilder
    private func projectSection(_ project: Project) -> some View {
        let datasheets = projectStore.datasheetsForProject(project, allDatasheets: filteredDatasheets)

        DisclosureGroup {
            ForEach(datasheets) { datasheet in
                DatasheetRowView(datasheet: datasheet)
                    .tag(datasheet)
                    .contextMenu {
                        datasheetContextMenu(datasheet)

                        Divider()

                        Button("Remove from \(project.name)") {
                            projectStore.removeDatasheet(datasheet, from: project.id)
                        }
                    }
            }
        } label: {
            projectHeader(project, count: datasheets.count)
        }
    }

    @ViewBuilder
    private func projectHeader(_ project: Project, count: Int) -> some View {
        if renamingProjectId == project.id {
            HStack(spacing: 4) {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        projectStore.renameProject(id: project.id, name: renameText)
                        renamingProjectId = nil
                    }
                Button(action: {
                    projectStore.renameProject(id: project.id, name: renameText)
                    renamingProjectId = nil
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                Text(project.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.none)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                projectStore.selectedProject = project
            }
            .contextMenu {
                Button("Open Project") {
                    projectStore.selectedProject = project
                }
                Button("Rename") {
                    renameText = project.name
                    renamingProjectId = project.id
                }
                Divider()
                Button("Delete Project", role: .destructive) {
                    projectStore.deleteProject(id: project.id)
                }
            }
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func datasheetContextMenu(_ datasheet: CachedDatasheet) -> some View {
        if !projectStore.projects.isEmpty {
            Menu("Add to Project") {
                ForEach(projectStore.projects) { project in
                    Button(project.name) {
                        projectStore.addDatasheet(datasheet, to: project.id)
                    }
                    .disabled(project.contains(datasheet))
                }
            }
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(datasheet.path, inFileViewerRootedAtPath: "")
        }

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(datasheet.path, forType: .string)
        }
    }

    // MARK: - Actions

    private func createProject() {
        guard !newProjectName.isEmpty else { return }
        _ = projectStore.createProject(name: newProjectName)
        newProjectName = ""
        showNewProject = false
    }
}

struct DatasheetRowView: View {
    let datasheet: CachedDatasheet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(datasheet.displayName)
                .font(.body)
                .fontWeight(datasheet.aliases.isEmpty ? .regular : .medium)
                .lineLimit(1)

            HStack(spacing: 4) {
                if !datasheet.aliases.isEmpty {
                    Text(datasheet.aliases.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }

                Spacer()

                Text(datasheet.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if datasheet.displayName != datasheet.filename {
                Text(datasheet.filename)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .help("Click to open \(datasheet.filename)\nRight-click to add to a project, reveal in Finder, or copy path")
    }
}
#endif

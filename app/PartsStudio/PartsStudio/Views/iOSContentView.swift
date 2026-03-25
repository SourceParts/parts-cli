#if os(iOS)
import SwiftUI

struct iOSContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            // Datasheets tab
            NavigationStack {
                DatasheetListView()
                    .environmentObject(appState)
            }
            .tabItem {
                Label("Datasheets", systemImage: "doc.text")
            }

            // ECO / IQC tab
            NavigationStack {
                ECOIQCListView()
                    .environmentObject(appState)
            }
            .tabItem {
                Label("ECO / IQC", systemImage: "checklist")
            }

            // Parts Search tab
            NavigationStack {
                PartsSearchView()
                    .environmentObject(appState)
            }
            .tabItem {
                Label("Parts", systemImage: "magnifyingglass")
            }

            // BLE tab
            NavigationStack {
                BLEView()
                    .environmentObject(appState)
            }
            .tabItem {
                Label("BLE", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }
}

// MARK: - Datasheet List

struct DatasheetListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(appState.cacheService.datasheets, id: \.filename) { ds in
            Button {
                appState.selectDatasheet(ds)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ds.filename)
                        .font(.headline)
                    if ds.cached {
                        Text("Cached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Datasheets")
    }
}

// MARK: - ECO / IQC List

struct ECOIQCListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section("ECO Documents") {
                ForEach(appState.ecoStore.documents) { eco in
                    Button {
                        appState.selectedECO = eco
                    } label: {
                        VStack(alignment: .leading) {
                            Text(eco.id)
                                .font(.headline)
                            Text(eco.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("IQC Items") {
                ForEach(appState.effectiveIQCItems) { item in
                    Button {
                        appState.selectedIQCItem = item
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.code)
                                .font(.headline)
                            Text(item.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("ECO / IQC")
    }
}

// MARK: - Parts Search

struct PartsSearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    var body: some View {
        VStack {
            if let partNumber = appState.selectedPartNumber {
                PartDetailView(partNumber: partNumber)
            } else {
                ContentUnavailableView(
                    "Search Parts",
                    systemImage: "magnifyingglass",
                    description: Text("Search for electronic components by part number or description")
                )
            }
        }
        .navigationTitle("Parts")
        .searchable(text: $searchText, prompt: "Search parts...")
        .onSubmit(of: .search) {
            if !searchText.isEmpty {
                appState.selectPart(searchText)
            }
        }
    }
}
#endif

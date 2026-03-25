import SwiftUI

struct PartDetailView: View {
    let partNumber: String
    @EnvironmentObject var appState: AppState
    @State private var gathered: PartsAPIClient.GatheredPart?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Back bar
            HStack {
                Button(action: { appState.selectedPartNumber = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back to Search")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading \(partNumber)...")
                    .font(.caption)
                Spacer()
            } else if let error {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Failed to load part")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    Button("Try Again") { loadPart() }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                }
                Spacer()
            } else if let gathered {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(gathered.part)
                        pricingSection(gathered)
                        specsSection(gathered.part)
                        datasheetSection(gathered)
                        alternativesSection(gathered)
                    }
                    .padding(20)
                }
            }
        }
        .task(id: partNumber) {
            loadPart()
        }
    }

    private func loadPart() {
        isLoading = true
        error = nil
        Task {
            do {
                let result = try await PartsAPIClient.shared.gatherPart(sku: partNumber)
                await MainActor.run {
                    gathered = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ part: PartsAPIClient.PartDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                // Product image
                if !part.imageURL.isEmpty, let url = URL(string: part.imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.1), radius: 4)
                        case .failure:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 120, height: 120)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.tertiary)
                                }
                        default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.05))
                                .frame(width: 120, height: 120)
                                .overlay { ProgressView().controlSize(.small) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(part.partNumber)
                        .font(.title)
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                    if !part.manufacturer.isEmpty {
                        Text(part.manufacturer)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                stockBadge(part)
            }

            if !part.description.isEmpty {
                Text(part.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if !part.category.isEmpty {
                    Text(part.category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if part.unitPrice > 0 {
                    Text(String(format: "$%.4f", part.unitPrice))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private func stockBadge(_ part: PartsAPIClient.PartDetails) -> some View {
        if part.available {
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("\(part.stock) in stock")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Out of stock")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Pricing

    @ViewBuilder
    private func pricingSection(_ gathered: PartsAPIClient.GatheredPart) -> some View {
        if !gathered.priceBreaks.isEmpty {
            sectionCard(title: "Volume Pricing", icon: "dollarsign.circle") {
                HStack(spacing: 0) {
                    ForEach(Array(gathered.priceBreaks.enumerated()), id: \.offset) { i, pb in
                        VStack(spacing: 4) {
                            Text("\(pb.qty)+")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.4f", pb.unitPrice))
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(i == 0 ? Color.accentColor.opacity(0.08) : Color.clear)
                    }
                }
            }
        }
    }

    // MARK: - Specifications

    @ViewBuilder
    private func specsSection(_ part: PartsAPIClient.PartDetails) -> some View {
        if !part.specs.isEmpty {
            sectionCard(title: "Specifications", icon: "list.bullet.rectangle") {
                VStack(spacing: 0) {
                    ForEach(Array(part.specs.enumerated()), id: \.offset) { i, spec in
                        HStack {
                            Text(formatSpecKey(spec.0))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)
                            Text(spec.1)
                                .font(.caption)
                                .fontWeight(.medium)
                                .textSelection(.enabled)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(i % 2 == 0 ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    }
                }
            }
        }

        if !part.features.isEmpty {
            sectionCard(title: "Features", icon: "checkmark.circle") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(part.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\u{2022}")
                                .foregroundStyle(.secondary)
                            Text(feature)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Datasheet

    @ViewBuilder
    private func datasheetSection(_ gathered: PartsAPIClient.GatheredPart) -> some View {
        if let url = gathered.datasheetURL, !url.isEmpty {
            sectionCard(title: "Datasheet", icon: "doc.text") {
                HStack {
                    Button(action: { openDatasheet(url) }) {
                        Label("Open Datasheet", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(URL(string: url)?.lastPathComponent ?? url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func openDatasheet(_ urlString: String) {
        // Check if the datasheet is cached locally
        let filename = URL(string: urlString)?.lastPathComponent ?? ""
        if let cached = appState.cacheService.datasheets.first(where: { $0.filename.lowercased() == filename.lowercased() }) {
            appState.selectDatasheet(cached)
            return
        }
        // Fall back to opening in browser
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Alternatives

    @ViewBuilder
    private func alternativesSection(_ gathered: PartsAPIClient.GatheredPart) -> some View {
        if !gathered.alternatives.isEmpty {
            sectionCard(title: "Alternatives", icon: "arrow.triangle.swap") {
                VStack(spacing: 0) {
                    ForEach(Array(gathered.alternatives.enumerated()), id: \.offset) { _, alt in
                        Button(action: {
                            let sku = alt.sku.isEmpty ? alt.name : alt.sku
                            if !sku.isEmpty { appState.selectPart(sku) }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alt.name.isEmpty ? alt.sku : alt.name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    if !alt.description.isEmpty {
                                        Text(alt.description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if !alt.manufacturer.isEmpty {
                                    Text(alt.manufacturer)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if alt.sku != gathered.alternatives.last?.sku {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            content()
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06)))
    }

    private func formatSpecKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
           .split(separator: " ")
           .map { $0.prefix(1).uppercased() + $0.dropFirst() }
           .joined(separator: " ")
    }
}

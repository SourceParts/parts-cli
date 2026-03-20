import SwiftUI

struct IQCDetailView: View {
    let item: IQCItem
    @EnvironmentObject var appState: AppState

    private var badgeColor: Color {
        switch item.status {
        case "accepted": return .green
        case "rejected": return .red
        case "inspected": return .blue
        case "pending_inspection": return .orange
        default: return .gray
        }
    }

    private var statusLabel: String {
        switch item.status {
        case "pending_inspection": return "Pending Inspection"
        case "accepted": return "Accepted"
        case "rejected": return "Rejected"
        case "inspected": return "Inspected"
        default: return item.status.capitalized
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("IQC")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.2))
                        .foregroundStyle(.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(item.code)
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Text(statusLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(badgeColor.opacity(0.15))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                }

                if !item.createdAt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text("Received: \(item.createdAt)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Inspection notes
                    if let notes = item.inspectionNotes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Inspection Notes", systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(notes)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                        }
                    }

                    // Images placeholder
                    if !item.images.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Images (\(item.images.count))", systemImage: "photo.stack")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 8) {
                                ForEach(item.images) { img in
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.1))
                                        .aspectRatio(4/3, contentMode: .fit)
                                        .overlay(
                                            VStack(spacing: 4) {
                                                Image(systemName: "photo")
                                                    .font(.title2)
                                                    .foregroundStyle(.tertiary)
                                                Text(img.id)
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        )
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Images", systemImage: "photo.stack")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text("No images uploaded yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                        }
                    }

                    // Status details
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Details", systemImage: "info.circle")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            detailRow("Code", item.code)
                            Divider()
                            detailRow("Status", statusLabel)
                            Divider()
                            detailRow("Received", item.createdAt)
                            Divider()
                            detailRow("Images", "\(item.images.count)")
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

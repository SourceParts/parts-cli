import SwiftUI

struct ECODetailView: View {
    let document: ECODocument

    private var typeColor: Color {
        switch document.type {
        case .eco: return .purple
        case .ecr: return .blue
        case .ecn: return .teal
        }
    }

    private var severityColor: Color {
        switch document.severity.uppercased() {
        case "CRITICAL": return .red
        case "HIGH": return .orange
        case "MEDIUM": return .yellow
        case "LOW": return .green
        default: return .gray
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with frontmatter fields
            headerBar

            Divider()

            // Markdown body as monospaced plain text
            ScrollView {
                Text(document.body)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Divider()

            // File path footer
            HStack {
                Image(systemName: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(document.filePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Type badge
                Text(document.type.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(typeColor.opacity(0.2))
                    .foregroundStyle(typeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(document.id)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Severity badge
                if !document.severity.isEmpty {
                    Text(document.severity)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(severityColor.opacity(0.15))
                        .foregroundStyle(severityColor)
                        .clipShape(Capsule())
                }

                // Status badge
                Text(document.status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }

            Text(document.title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

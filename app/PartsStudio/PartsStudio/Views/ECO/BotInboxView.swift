#if os(macOS)
import SwiftUI

struct BotInboxView: View {
    @StateObject private var service = BotInboxService()
    @State private var selectedEmail: BotEmail?
    @State private var replyText: String = ""
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Bot Inbox")
                    .font(.headline)
                Spacer()

                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Text("\(service.emails.count) emails")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: { Task { await service.fetchEmails() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh inbox")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let error = service.error {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Cannot load inbox")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    Text("Set BOT_API_TOKEN and BOT_WORKER_URL environment variables,\nor launch with: BOT_API_TOKEN=xxx .build/debug/PartsStudio")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                    Button("Retry") { Task { await service.fetchEmails() } }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if service.emails.isEmpty && !service.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "envelope.open")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No emails")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Forward emails to bot@bot.source.parts")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                HSplitView {
                    // Email list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(service.emails) { email in
                                EmailRow(email: email, isSelected: selectedEmail?.id == email.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedEmail = email
                                        Task { await service.fetchEmailContent(key: email.key) }
                                    }
                            }
                        }
                    }
                    .frame(minWidth: 280, idealWidth: 350)

                    // Email detail
                    VStack(spacing: 0) {
                        if let email = selectedEmail {
                            // Email header
                            VStack(alignment: .leading, spacing: 6) {
                                Text(email.subject)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .textSelection(.enabled)
                                HStack {
                                    directionBadge(email)
                                    Text(email.displayFrom)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Text(email.formattedDate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let orig = email.originalSender, !orig.isEmpty, orig != email.from {
                                    Text("Original sender: \(orig)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(16)
                            .background(Color(nsColor: .controlBackgroundColor))

                            Divider()

                            // Email body
                            ScrollView {
                                if let content = service.selectedEmailContent {
                                    Text(content)
                                        .font(.system(size: 13, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    ProgressView()
                                        .padding(20)
                                }
                            }

                            Divider()

                            // Reply bar
                            if email.isInbound || email.isNotification {
                                HStack(spacing: 8) {
                                    TextField("Reply as bot...", text: $replyText)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .onSubmit { sendReply(email) }

                                    Button(action: { sendReply(email) }) {
                                        if isSending {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                        }
                                    }
                                    .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                                    .help("Send reply as bot@source.parts")
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor))
                            }
                        } else {
                            VStack {
                                Spacer()
                                Image(systemName: "envelope")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tertiary)
                                Text("Select an email")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .task { await service.fetchEmails() }
    }

    private func sendReply(_ email: BotEmail) {
        let text = replyText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSending = true
        Task {
            let success = await service.replyToEmail(key: email.key, text: text)
            await MainActor.run {
                isSending = false
                if success {
                    replyText = ""
                }
            }
        }
    }

    @ViewBuilder
    private func directionBadge(_ email: BotEmail) -> some View {
        if email.isOutbound {
            Text("Sent")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else if email.isNotification {
            Text("Notification")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        } else {
            Text("Inbound")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.12))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Email Row

struct EmailRow: View {
    let email: BotEmail
    var isSelected: Bool = false

    private var accentColor: Color {
        if email.isOutbound { return .green }
        if email.isNotification { return .orange }
        return .blue
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accentColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(email.displayFrom)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(email.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(email.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}
#endif

import SwiftUI

struct ECOChatView: View {
    let document: ECODocument
    @EnvironmentObject var appState: AppState
    @State private var messageText: String = ""
    @State private var refreshId: UUID = UUID()

    private var chatStore: ECOChatStore { appState.ecoChatStore }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.id)
                        .font(.headline)
                    Text("Feedback")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Copy thread as text") {
                        copyThread()
                    }
                    Divider()
                    Button("Clear all messages", role: .destructive) {
                        chatStore.clearMessages(for: document.id)
                        refreshId = UUID()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Messages
            let messages = chatStore.messages(for: document.id)

            if messages.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.bubble")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No feedback yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Type below to add a comment, question, or action item")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { msg in
                                ChatBubbleView(message: msg, onDelete: {
                                    chatStore.deleteMessage(for: document.id, messageId: msg.id)
                                    refreshId = UUID()
                                })
                                .id(msg.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                FocusableTextView(text: $messageText, placeholder: "Add feedback...")
                    .frame(minHeight: 32, maxHeight: 80)

                VStack(spacing: 4) {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(messageText.isEmpty ? .secondary : Color.accentColor)
                    .disabled(messageText.isEmpty)
                    .help("Send feedback (Cmd+Return)")
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .id(refreshId)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatStore.addMessage(for: document.id, text: text)
        messageText = ""
        refreshId = UUID()
    }

    private func copyThread() {
        let messages = chatStore.messages(for: document.id)
        let text = messages.map { "[\($0.author) \($0.timestamp)] \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ChatBubbleView: View {
    let message: ECOChatMessage
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Text(String(message.author.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(message.author)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var avatarColor: Color {
        let hash = message.author.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let colors: [Color] = [.blue, .green, .orange, .purple, .teal, .pink, .indigo]
        return colors[hash % colors.count]
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: message.timestamp) else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

import SwiftUI

struct ConversationPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var newThreadText: String = ""
    @State private var showNewThread: Bool = false
    @State private var refreshId: UUID = UUID()

    private var conversations: ConversationStore {
        appState.annotationStore.conversations
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Page \(appState.currentPage + 1)")
                    .font(.headline)
                Spacer()
                Button(action: { showNewThread.toggle() }) {
                    Image(systemName: "plus.bubble")
                }
                .help("Start a new discussion thread on this page")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            let threads = conversations.threadsForPage(appState.currentPage)

            if threads.isEmpty && !showNewThread {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No threads on this page")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Start a thread") {
                        showNewThread = true
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if showNewThread {
                            NewThreadView(text: $newThreadText) {
                                guard !newThreadText.isEmpty else { return }
                                conversations.addThread(
                                    page: appState.currentPage,
                                    anchorX: 0, anchorY: 0,
                                    text: newThreadText
                                )
                                newThreadText = ""
                                showNewThread = false
                                refreshId = UUID()
                            } onCancel: {
                                newThreadText = ""
                                showNewThread = false
                            }
                        }

                        ForEach(threads) { thread in
                            ThreadView(
                                threadId: thread.id,
                                store: conversations,
                                onMutate: { refreshId = UUID() }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .id(refreshId)  // Force refresh when threads mutate
    }
}

struct ThreadView: View {
    let threadId: String
    let store: ConversationStore
    let onMutate: () -> Void
    @State private var replyText: String = ""
    @State private var showReply: Bool = false

    private var thread: ConversationThread? {
        store.threads.first(where: { $0.id == threadId })
    }

    var body: some View {
        if let thread = thread {
            VStack(alignment: .leading, spacing: 8) {
                // Selected text quote
                if let quote = thread.selectedText, !quote.isEmpty {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 3)
                        Text(quote)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.06))
                    )
                }

                ForEach(thread.comments) { comment in
                    CommentView(comment: comment)
                }

                if showReply {
                    HStack(spacing: 4) {
                        FocusableTextView(text: $replyText, placeholder: "Reply...")
                            .frame(minHeight: 30, maxHeight: 60)
                        Button(action: submitReply) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(replyText.isEmpty ? .secondary : Color.accentColor)
                        .disabled(replyText.isEmpty)
                    }
                }

                HStack(spacing: 8) {
                    Button(action: { showReply.toggle() }) {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                    .help("Add a reply to this thread")

                    if !thread.resolved {
                        Button(action: {
                            store.resolveThread(id: thread.id)
                            onMutate()
                        }) {
                            Label("Resolve", systemImage: "checkmark.circle")
                                .font(.caption2)
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(.green)
                        .help("Mark this thread as resolved")
                    } else {
                        Button(action: {
                            store.unresolveThread(id: thread.id)
                            onMutate()
                        }) {
                            Label("Resolved", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(.green)
                        .help("Click to reopen this thread")
                    }

                    Spacer()

                    Button(action: {
                        store.deleteThread(id: thread.id)
                        onMutate()
                    }) {
                        Image(systemName: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.secondary)
                    .help("Delete this thread")
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .opacity(thread.resolved ? 0.6 : 1.0)
        }
    }

    private func submitReply() {
        guard !replyText.isEmpty else { return }
        store.addReply(threadId: threadId, text: replyText)
        replyText = ""
        showReply = false
        onMutate()
    }
}

struct CommentView: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(comment.author)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(comment.text)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: comment.timestamp) else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

struct NewThreadView: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New thread")
                .font(.caption)
                .fontWeight(.semibold)
            FocusableTextView(text: $text, placeholder: "What's on your mind?")
                .frame(minHeight: 50, maxHeight: 100)
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                Button("Post", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                    .disabled(text.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

/// NSTextView wrapper that reliably claims first responder on appear.
struct FocusableTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.isEditable = true
        textView.isSelectable = true

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        func claimFocus(attempts: Int = 0) {
            guard attempts < 5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempts) * 0.1 + 0.05) {
                if textView.window?.firstResponder !== textView {
                    textView.window?.makeFirstResponder(textView)
                    claimFocus(attempts: attempts + 1)
                }
            }
        }
        claimFocus()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusableTextView

        init(_ parent: FocusableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

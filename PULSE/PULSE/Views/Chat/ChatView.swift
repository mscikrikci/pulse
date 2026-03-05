import SwiftUI

struct ChatView: View {
    @Binding var pendingChat: PendingChatContext?

    @State private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    private let suggestedQuestions = [
        "How is my HRV trending this week?",
        "Am I getting enough sleep?",
        "What should I prioritize for recovery today?",
        "How am I progressing toward my goals?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                if let err = viewModel.error {
                    Text(err.userMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
                inputBar
                    .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("Chat")
        }
        .task { await viewModel.loadContext() }
        .onAppear {
            if let ctx = pendingChat {
                pendingChat = nil
                viewModel.prepareContext(
                    uiPreamble: ctx.uiPreamble,
                    checkInContext: ctx.checkInContext,
                    prefillText: ctx.prefillText
                )
                isInputFocused = true
            }
        }
        .onChange(of: pendingChat) { _, ctx in
            guard let ctx else { return }
            pendingChat = nil
            viewModel.prepareContext(
                uiPreamble: ctx.uiPreamble,
                checkInContext: ctx.checkInContext,
                prefillText: ctx.prefillText
            )
            isInputFocused = true
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.messages.isEmpty {
                        suggestedView
                    }
                    ForEach(viewModel.messages) { msg in
                        MessageBubbleView(message: msg)
                            .id(msg.id)
                    }
                    if viewModel.isLoading {
                        loadingBubble
                            .id("loading")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.isLoading) { _, loading in
                if loading { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Suggested Questions

    private var suggestedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about your health data")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(suggestedQuestions, id: \.self) { q in
                    Button(q) {
                        viewModel.inputText = q
                        Task { await viewModel.send() }
                    }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Loading Bubble

    private var loadingBubble: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.tertiarySystemBackground)))
            Spacer(minLength: 60)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your health…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemBackground)))
                .lineLimit(4)
                .focused($isInputFocused)
                .onSubmit { Task { await viewModel.send() } }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isInputFocused = false }
                    }
                }

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding(12)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }
}

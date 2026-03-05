import SwiftUI

struct MessageBubbleView: View {
    let message: ChatViewModel.Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                if message.role == .user { Spacer(minLength: 60) }
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubble)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                if message.role == .assistant { Spacer(minLength: 60) }
            }

            // Tool call summary shown below agentic assistant responses
            if let summary = message.toolSummary, message.role == .assistant {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                    Text(summary)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            }
        }
    }

    private var bubble: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(message.role == .user
                  ? Color.blue
                  : Color(.tertiarySystemBackground))
    }
}

import SwiftUI

/// Renders Markdown text using iOS's built-in AttributedString(markdown:).
/// Falls back to plain text if parsing fails.
struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Renders a full Markdown document with proper section spacing.
/// Splits on double-newlines to create distinct paragraph blocks.
struct MarkdownDocumentView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [String] {
        markdown
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func blockView(for block: String) -> some View {
        if block.hasPrefix("## ") {
            Text(block.dropFirst(3))
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.top, 4)
        } else if block.hasPrefix("# ") {
            Text(block.dropFirst(2))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.top, 4)
        } else if block.hasPrefix("### ") {
            Text(block.dropFirst(4))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        } else {
            MarkdownContentView(markdown: block)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

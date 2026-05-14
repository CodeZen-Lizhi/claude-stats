import SwiftUI

/// Footnote that puts the user's total tokens into a human-relatable frame
/// ("~3,052× more tokens than Animal Farm"). Picks the largest reference in
/// the table where the ratio is meaningful (≥ 1.5×); falls back to the
/// smallest reference for tiny totals so we always have something to say.
struct ComparisonFooter: View {
    let totalTokens: Int

    /// Reference works, with rough token counts. Roughly cl100k-tokenizer
    /// equivalents for the underlying word count — these are deliberate
    /// approximations meant to be conversational, not statistical.
    private static let references: [(name: String, tokens: Int)] = [
        ("Animal Farm", 39_000),
        ("Hamlet", 32_000),
        ("Pride and Prejudice", 160_000),
        ("Harry Potter (book 1)", 100_000),
        ("Bible (KJV)", 1_100_000),
        ("Lord of the Rings", 580_000),
    ]

    var body: some View {
        Text(message)
            .font(.sora(11))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        guard totalTokens > 0 else {
            return "Start a session and we'll measure your output against the classics."
        }
        // Largest reference where the user has spent ≥ 1.5× its tokens.
        let sorted = Self.references.sorted { $0.tokens > $1.tokens }
        if let pick = sorted.first(where: { Double(totalTokens) >= Double($0.tokens) * 1.5 }) {
            return "You've used ~\(Self.ratio(totalTokens, pick.tokens))× more tokens than \(pick.name)."
        }
        // Fall back to the smallest reference so the user always gets a comparison.
        if let smallest = sorted.last {
            let ratio = Double(totalTokens) / Double(smallest.tokens)
            if ratio >= 0.05 {
                return "You're at about \(Self.shortRatio(ratio))× \(smallest.name)."
            }
        }
        return "Keep going — the comparisons get fun after a few sessions."
    }

    private static func ratio(_ user: Int, _ book: Int) -> String {
        let r = Double(user) / Double(book)
        if r >= 100 { return String(format: "%.0f", r) }
        if r >= 10 { return String(format: "%.1f", r) }
        return String(format: "%.2f", r)
    }

    private static func shortRatio(_ r: Double) -> String {
        if r >= 1 { return String(format: "%.1f", r) }
        return String(format: "%.2f", r)
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 10) {
        ComparisonFooter(totalTokens: 0)
        ComparisonFooter(totalTokens: 5_000)
        ComparisonFooter(totalTokens: 80_000)
        ComparisonFooter(totalTokens: 119_000_000)
        ComparisonFooter(totalTokens: 2_500_000_000)
    }
    .padding(24)
    .frame(width: 600)
    .background(Color.stxBackground)
}
#endif

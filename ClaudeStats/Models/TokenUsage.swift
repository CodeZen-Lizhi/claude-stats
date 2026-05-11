import Foundation

/// Token counts from a single assistant turn or summed across many.
struct TokenUsage: Sendable, Hashable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreation5mTokens: Int = 0
    var cacheCreation1hTokens: Int = 0

    static let zero = TokenUsage()

    /// All tokens that flowed, cached or not — the headline figure.
    var total: Int {
        inputTokens + outputTokens + cacheReadTokens
            + cacheCreation5mTokens + cacheCreation1hTokens
    }

    var cacheCreationTotalTokens: Int { cacheCreation5mTokens + cacheCreation1hTokens }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            cacheCreation5mTokens: lhs.cacheCreation5mTokens + rhs.cacheCreation5mTokens,
            cacheCreation1hTokens: lhs.cacheCreation1hTokens + rhs.cacheCreation1hTokens
        )
    }

    static func += (lhs: inout TokenUsage, rhs: TokenUsage) { lhs = lhs + rhs }
}

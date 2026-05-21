import Foundation

enum TownEconomy {
    static let dailyCoinCap = 160
    static let linearTokenLimit = 50_000
    static let tokensPerLinearCoin = 500

    static func coins(forEffectiveTokens tokens: Int) -> Int {
        guard tokens > 0 else { return 0 }
        let linearTokens = min(tokens, linearTokenLimit)
        let linearCoins = linearTokens / tokensPerLinearCoin
        let excess = max(0, tokens - linearTokenLimit)
        let softCoins = Int(Double(excess) / 1_000.0).squareRootFloor()
        return min(dailyCoinCap, linearCoins + softCoins)
    }

    static func reconcile(
        state: inout TownState,
        provider: ProviderKind,
        day: Date,
        effectiveTokens: Int,
        calendar: Calendar = .current
    ) -> Int {
        let key = TownLedgerDayKey.make(provider: provider, date: day, calendar: calendar)
        let nextCoins = coins(forEffectiveTokens: effectiveTokens)
        let previous = state.ledger.days[key] ?? TownLedgerEntry(effectiveTokens: 0, coinsMinted: 0)
        let delta = max(0, nextCoins - previous.coinsMinted)
        guard delta > 0 || effectiveTokens > previous.effectiveTokens else { return 0 }

        state.ledger.days[key] = TownLedgerEntry(
            effectiveTokens: max(previous.effectiveTokens, effectiveTokens),
            coinsMinted: max(previous.coinsMinted, nextCoins)
        )
        state.balance += delta
        return delta
    }
}

private extension Int {
    func squareRootFloor() -> Int {
        guard self > 0 else { return 0 }
        return Int(Double(self).squareRoot())
    }
}

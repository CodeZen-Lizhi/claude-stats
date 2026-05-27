import Testing
@testable import ClaudeStats

@Suite("GitActivityViewModel")
struct GitActivityViewModelTests {
    @MainActor
    @Test("defaults to today's personal commits")
    func defaultsToTodayAndMine() {
        let viewModel = GitActivityViewModel()

        #expect(viewModel.range == .today)
        #expect(viewModel.onlyMyCommits)
        #expect(GitRange.allCases.first == .today)
        #expect(GitRange.today.shortLabel == "今天")
        #expect(GitRange.today.dayCount == 1)
    }
}

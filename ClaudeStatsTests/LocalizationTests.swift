import Foundation
import Testing
@testable import ClaudeStats

@Suite("Localization")
@MainActor
struct LocalizationTests {
    @Test("App language preference persists and updates app language defaults")
    func appLanguagePreferencePersists() {
        let (defaults, suiteName) = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.appLanguagePreference == .system)
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == nil)

        prefs.appLanguagePreference = .simplifiedChinese
        #expect(defaults.string(forKey: "appLanguagePreference") == AppLanguagePreference.simplifiedChinese.rawValue)
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == ["zh-Hans"])

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.appLanguagePreference == .simplifiedChinese)
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == ["zh-Hans"])

        reloaded.appLanguagePreference = .system
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == nil)
    }

    @Test("Language metadata exposes expected locale identifiers and labels")
    func appLanguagePreferenceMetadata() {
        #expect(AppLanguagePreference.system.localeIdentifier == nil)
        #expect(AppLanguagePreference.english.localeIdentifier == "en")
        #expect(AppLanguagePreference.simplifiedChinese.localeIdentifier == "zh-Hans")
        #expect(AppLanguagePreference.system.displayName(locale: Locale(identifier: "en")) == "Follow System")
        #expect(AppLanguagePreference.system.displayName(locale: Locale(identifier: "zh-Hans")) == "跟随系统")
        #expect(AppLanguagePreference.simplifiedChinese.displayName(locale: Locale(identifier: "en")) == "简体中文")
    }

    @Test("Dynamic localized strings handle plural and interpolation differences")
    func dynamicLocalizedStrings() {
        let en = Locale(identifier: "en")
        let zh = Locale(identifier: "zh-Hans")

        #expect(L10n.refreshInterval(minutes: 1, locale: en) == "1 minute")
        #expect(L10n.refreshInterval(minutes: 5, locale: en) == "5 minutes")
        #expect(L10n.refreshInterval(minutes: 1, locale: zh) == "1 分钟")
        #expect(L10n.refreshInterval(minutes: 5, locale: zh) == "5 分钟")
        #expect(L10n.contributionCount(2, locale: zh) == "2 次贡献")
        #expect(L10n.format("stats.header.provider_stats", defaultValue: "%@ STATS", locale: zh, "Claude") == "Claude 统计")
    }

    @Test("General settings descriptions are localized in Chinese")
    func generalSettingsDescriptionsAreLocalizedInChinese() {
        let zh = Locale(identifier: "zh-Hans")
        let descriptions = [
            (
                "Show the main window when Codex Statistics starts, including when you double-click the app.",
                "Codex Statistics 启动时显示主窗口，包括双击应用打开时。"
            ),
            (
                "Some APIs re-report cached context on assistant turns, so the same tokens can be counted many times. Turn off to show only “new” traffic (input + output + cache writes). Estimated cost is unaffected.",
                "部分 API 会在助手响应时重复报告缓存上下文，因此同一批令牌可能被多次计入。关闭后仅显示“新增”流量（输入 + 输出 + 缓存写入）。估算成本不受影响。"
            ),
            (
                "API estimate uses standard first-party token prices. Detailed billing is kept for compatible imported data and currently matches the standard Codex estimate.",
                "API 估算使用标准官方令牌价格。详细账单保留给兼容的导入数据，目前与标准 Codex 估算一致。"
            ),
        ]

        for (key, expected) in descriptions {
            #expect(L10n.string(key, defaultValue: key, locale: zh) == expected)
        }
    }

    @Test("Typography chooses Sora for English and system font for Chinese")
    func typographyLanguageSelection() {
        #expect(Theme.appFontKind(for: Locale(identifier: "en")) == .sora)
        #expect(Theme.appFontKind(for: Locale(identifier: "en_US")) == .sora)
        #expect(Theme.appFontKind(for: Locale(identifier: "zh-Hans")) == .system)
        #expect(Theme.appFontKind(forLanguageIdentifier: "zh_CN") == .system)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "com.codexstats.localization.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func appLanguageOverride(in defaults: UserDefaults, suiteName: String) -> [String]? {
        defaults.persistentDomain(forName: suiteName)?[AppLanguagePreference.appleLanguagesDefaultsKey] as? [String]
    }
}

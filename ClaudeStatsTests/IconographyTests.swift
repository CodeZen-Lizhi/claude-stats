import Testing
import ClaudeStatsIconography

@Suite("Iconography")
struct IconographyTests {
    @Test("Every migrated SF Symbol resolves to a real functional icon")
    func migratedSystemNamesResolve() {
        for systemName in FunctionalIcon.migratedSystemNames {
            #expect(FunctionalIcon.fromSystemName(systemName) != .placeholder)
        }
    }

    @Test("Key functional icons map to expected Phosphor assets")
    func phosphorRawValues() {
        #expect(FunctionalIcon.fromSystemName("arrow.clockwise").phosphorRawValue == "arrow-clockwise")
        #expect(FunctionalIcon.fromSystemName("gearshape").phosphorRawValue == "gear-six")
        #expect(FunctionalIcon.fromSystemName("square.and.arrow.up").phosphorRawValue == "upload-simple")
        #expect(FunctionalIcon.fromSystemName("terminal").phosphorRawValue == "terminal")
        #expect(FunctionalIcon.fromSystemName("network").phosphorRawValue == "network")
        #expect(FunctionalIcon.fromSystemName("exclamationmark.triangle").phosphorRawValue == "warning")
        #expect(FunctionalIcon.fromSystemName("sidebar.left").phosphorRawValue == "sidebar")
    }

    @Test("LinuxDo symbols that render from live topic data migrate")
    func linuxDoLiveTopicSymbolsMigrate() {
        #expect(FunctionalIcon.fromSystemName("bubble.left").phosphorRawValue == "chat-text")
    }
}

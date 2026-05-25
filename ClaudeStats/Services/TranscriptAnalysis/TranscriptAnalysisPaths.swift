import Foundation

enum TranscriptAnalysisPaths {
    static func embeddingIndexURL() -> URL {
        supportDirectory().appendingPathComponent("embeddings.sqlite")
    }

    private static func supportDirectory() -> URL {
        let manager = FileManager.default
        let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root
            .appendingPathComponent("ClaudeStats", isDirectory: true)
            .appendingPathComponent("TranscriptAnalysis", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

import Foundation

struct LegacyFeatureDataCleaner {
    private let applicationSupportDirectory: URL
    private let fileManager: FileManager

    init(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    func cleanRemovedFeatureData() {
        removeLegacyTokenTownData()
    }

    private func removeLegacyTokenTownData() {
        let tokenTownDirectory = applicationSupportDirectory
            .appendingPathComponent("Codex Statistics", isDirectory: true)
            .appendingPathComponent("TokenTown", isDirectory: true)
        guard fileManager.fileExists(atPath: tokenTownDirectory.path) else { return }

        do {
            try fileManager.removeItem(at: tokenTownDirectory)
            Log.app.info("Removed legacy TokenTown data at \(tokenTownDirectory.path, privacy: .public)")
        } catch {
            Log.app.error("Failed to remove legacy TokenTown data: \(error.localizedDescription, privacy: .public)")
        }
    }
}

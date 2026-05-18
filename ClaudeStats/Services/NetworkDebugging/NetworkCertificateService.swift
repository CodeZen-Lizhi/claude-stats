import Foundation

struct NetworkCertificateService: Sendable {
    func generateRootCA() async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let directory = try certificateDirectory()
            let keyURL = directory.appendingPathComponent("claude-stats-network-root.key")
            let certURL = directory.appendingPathComponent("claude-stats-network-root.pem")
            if FileManager.default.fileExists(atPath: certURL.path) {
                return certURL.path
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = [
                "req", "-x509",
                "-newkey", "rsa:2048",
                "-days", "825",
                "-nodes",
                "-subj", "/CN=Claude Stats Network Debugger Root CA",
                "-keyout", keyURL.path,
                "-out", certURL.path,
            ]
            let error = Pipe()
            process.standardError = error
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "openssl failed"
                throw NetworkCertificateError.commandFailed(message)
            }
            return certURL.path
        }.value
    }

    func trustRootCA(path: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = [
                "add-trusted-cert",
                "-d",
                "-r", "trustRoot",
                "-k", "\(NSHomeDirectory())/Library/Keychains/login.keychain-db",
                path,
            ]
            let error = Pipe()
            process.standardError = error
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "security failed"
                throw NetworkCertificateError.commandFailed(message)
            }
        }.value
    }
}

private func certificateDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let directory = base
        .appendingPathComponent("Claude Stats", isDirectory: true)
        .appendingPathComponent("NetworkCertificates", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private enum NetworkCertificateError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}


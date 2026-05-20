import Foundation

struct OpsCommandInvocation: Sendable, Hashable {
    var executablePath: String
    var arguments: [String] = []
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var timeout: TimeInterval = 8
    var standardInput: Data?
}

struct OpsCommandResult: Sendable, Hashable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var launchError: String?
    var timedOut: Bool

    var isSuccess: Bool {
        exitCode == 0 && launchError == nil && !timedOut
    }

    var outputText: String {
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStdout.isEmpty { return trimmedStdout }
        return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var errorText: String {
        if timedOut { return "command timed out" }
        if let launchError { return launchError }
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStderr.isEmpty { return trimmedStderr }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol OpsCommandRunning: Sendable {
    func run(_ invocation: OpsCommandInvocation) async -> OpsCommandResult
}

struct DefaultOpsCommandRunner: OpsCommandRunning {
    func run(_ invocation: OpsCommandInvocation) async -> OpsCommandResult {
        await Self.runProcess(invocation)
    }

    private static func runProcess(_ invocation: OpsCommandInvocation) async -> OpsCommandResult {
        await Task.detached(priority: .utility) {
            runProcessSync(invocation)
        }.value
    }

    private static func runProcessSync(_ invocation: OpsCommandInvocation) -> OpsCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executablePath)
        process.arguments = invocation.arguments
        process.environment = invocation.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        if invocation.standardInput != nil {
            process.standardInput = Pipe()
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return OpsCommandResult(
                exitCode: -1,
                stdout: "",
                stderr: "",
                launchError: error.localizedDescription,
                timedOut: false
            )
        }

        if let input = invocation.standardInput,
           let stdin = process.standardInput as? Pipe {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }

        var timedOut = false
        if semaphore.wait(timeout: .now() + invocation.timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 1)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        return OpsCommandResult(
            exitCode: timedOut ? -2 : process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            launchError: nil,
            timedOut: timedOut
        )
    }
}

enum OpsCommandError: LocalizedError, Sendable {
    case failed(executable: String, arguments: [String], result: OpsCommandResult)

    var errorDescription: String? {
        switch self {
        case .failed(let executable, let arguments, let result):
            let command = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
            let detail = result.errorText
            return detail.isEmpty ? "\(command) failed." : "\(command) failed: \(detail)"
        }
    }
}

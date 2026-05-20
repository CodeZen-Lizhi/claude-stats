import Darwin
import Foundation

struct OpsCommandInvocation: Sendable, Hashable {
    var executablePath: String
    var arguments: [String] = []
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var timeout: TimeInterval = 8
    var standardInput: Data?
    var maxOutputBytes: Int = 2 * 1024 * 1024
    var maxStandardInputBytes: Int = 1024 * 1024
}

struct OpsCommandResult: Sendable, Hashable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var launchError: String?
    var timedOut: Bool
    var stdoutTruncated: Bool = false
    var stderrTruncated: Bool = false

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
        let processBox = OpsRunningProcessBox()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                Self.runProcessSync(invocation, processBox: processBox)
            }.value
        } onCancel: {
            processBox.terminate(forceAfter: true)
        }
    }

    private static func runProcessSync(_ invocation: OpsCommandInvocation, processBox: OpsRunningProcessBox) -> OpsCommandResult {
        if let input = invocation.standardInput,
           input.count > invocation.maxStandardInputBytes {
            return OpsCommandResult(
                exitCode: -1,
                stdout: "",
                stderr: "",
                launchError: "standard input exceeds \(invocation.maxStandardInputBytes) bytes",
                timedOut: false
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executablePath)
        process.arguments = invocation.arguments
        process.environment = sanitizedEnvironment(invocation.environment)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdin: Pipe?
        if invocation.standardInput != nil {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            stdin = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
            stdin = nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        processBox.set(process)

        do {
            try process.run()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            try? stdin?.fileHandleForReading.close()
        } catch {
            processBox.clear()
            return OpsCommandResult(
                exitCode: -1,
                stdout: "",
                stderr: "",
                launchError: error.localizedDescription,
                timedOut: false
            )
        }

        let stdoutBuffer = OpsPipeBuffer(limit: invocation.maxOutputBytes)
        let stderrBuffer = OpsPipeBuffer(limit: invocation.maxOutputBytes)
        let pipeGroup = DispatchGroup()
        drain(stdout.fileHandleForReading, into: stdoutBuffer, group: pipeGroup)
        drain(stderr.fileHandleForReading, into: stderrBuffer, group: pipeGroup)

        if let input = invocation.standardInput,
           let stdin {
            pipeGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                if !input.isEmpty {
                    stdin.fileHandleForWriting.write(input)
                }
                try? stdin.fileHandleForWriting.close()
                pipeGroup.leave()
            }
        }

        var timedOut = false
        let deadline = Date().addingTimeInterval(invocation.timeout)
        while process.isRunning, semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            if Date() >= deadline {
                timedOut = true
                processBox.terminate(forceAfter: true)
                _ = semaphore.wait(timeout: .now() + 1)
                break
            }
        }

        processBox.clear()

        if timedOut {
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            try? stdin?.fileHandleForWriting.close()
        }

        _ = pipeGroup.wait(timeout: .now() + 2)
        let stdoutSnapshot = stdoutBuffer.snapshot()
        let stderrSnapshot = stderrBuffer.snapshot()

        return OpsCommandResult(
            exitCode: timedOut ? -2 : process.terminationStatus,
            stdout: decode(stdoutSnapshot.data, truncated: stdoutSnapshot.truncated),
            stderr: decode(stderrSnapshot.data, truncated: stderrSnapshot.truncated),
            launchError: nil,
            timedOut: timedOut,
            stdoutTruncated: stdoutSnapshot.truncated,
            stderrTruncated: stderrSnapshot.truncated
        )
    }

    private static func drain(_ handle: FileHandle, into buffer: OpsPipeBuffer, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = handle.readData(ofLength: 8192)
                if data.isEmpty { break }
                buffer.append(data)
            }
            group.leave()
        }
    }

    private static func decode(_ data: Data, truncated: Bool) -> String {
        var text = String(decoding: data, as: UTF8.self)
        if truncated {
            if !text.hasSuffix("\n") { text += "\n" }
            text += "[output truncated]"
        }
        return text
    }

    private static func sanitizedEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { key, _ in
            let upper = key.uppercased()
            if upper.hasPrefix("DYLD_") || upper.hasPrefix("LD_") { return false }
            let secretMarkers = ["TOKEN", "SECRET", "PASSWORD", "PASS", "API_KEY", "ACCESS_KEY", "CREDENTIAL", "AUTH"]
            return !secretMarkers.contains { upper.contains($0) }
        }
    }
}

private final class OpsPipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var truncated = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = limit - data.count
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        if chunk.count > max(remaining, 0) {
            truncated = true
        }
    }

    func snapshot() -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}

private final class OpsRunningProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func terminate(forceAfter: Bool) {
        lock.lock()
        let process = self.process
        lock.unlock()

        guard let process, process.isRunning else { return }
        process.terminate()
        guard forceAfter else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) {
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
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

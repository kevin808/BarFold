import Foundation

final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()

    static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BarFold", isDirectory: true)
            .appendingPathComponent("barfold.log")
    }

    private let lock = NSLock()
    private let maximumLogSize: UInt64 = 1_048_576

    private init() {}

    func log(_ message: @autoclosure () -> String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message())\n"
        lock.lock()
        defer { lock.unlock() }

        do {
            try prepareLogFile()
            let data = Data(line.utf8)
            let handle = try FileHandle(forWritingTo: Self.logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("BarFold diagnostic logging failed: %@", error.localizedDescription)
        }
    }

    func ensureLogFile() {
        lock.lock()
        defer { lock.unlock() }
        try? prepareLogFile()
    }

    private func prepareLogFile() throws {
        let fileManager = FileManager.default
        let directory = Self.logURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if let size = try? Self.logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           UInt64(size) >= maximumLogSize {
            let previousURL = directory.appendingPathComponent("barfold.previous.log")
            try? fileManager.removeItem(at: previousURL)
            try fileManager.moveItem(at: Self.logURL, to: previousURL)
        }

        if !fileManager.fileExists(atPath: Self.logURL.path) {
            fileManager.createFile(atPath: Self.logURL.path, contents: nil)
        }
    }
}

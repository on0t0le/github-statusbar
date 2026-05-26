import Foundation
import Combine

final class DiagnosticLogger: ObservableObject, @unchecked Sendable {
    static let shared = DiagnosticLogger()

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let message: String

        var formatted: String {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            return "[\(df.string(from: timestamp))] \(message)"
        }
    }

    @Published private(set) var entries: [LogEntry] = []
    let fileURL: URL?

    private let writeQueue = DispatchQueue(label: "com.githubstatusbar.logger", qos: .utility)
    private let maxEntries = 1000

    private init() {
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs/GitHubStatusbar", isDirectory: true)
        if let dir = logDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("diagnostics.log")
        } else {
            fileURL = nil
        }
    }

    func log(_ message: String) {
        let entry = LogEntry(timestamp: Date(), message: message)
        writeQueue.async { [weak self] in self?.appendToFile(entry) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clearLogs() {
        DispatchQueue.main.async { [weak self] in self?.entries.removeAll() }
        writeQueue.async { [weak self] in
            guard let url = self?.fileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    var allText: String {
        entries.map(\.formatted).joined(separator: "\n")
    }

    private func appendToFile(_ entry: LogEntry) {
        guard let url = fileURL else { return }
        let line = entry.formatted + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

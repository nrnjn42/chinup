import Foundation

class Logging {
    private static let logFileQueue = DispatchQueue(label: "dev.nsgcoder.chinup.logFileQueue")

    private static let maxLogFileSize = 5 * 1024 * 1024

    static var defaultLogFileURL: URL? = {
        guard let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let logDir = containerURL.appendingPathComponent("ChinUp")
        do {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
            let url = logDir.appendingPathComponent("chinup.log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
            }
            return url
        } catch {
            print("Failed to setup log file: \(error)")
            return nil
        }
    }()

    static func log(_ message: String) {
        if let url = defaultLogFileURL {
            logToFile(message, logFileURL: url)
        } else {
            // Fallback if file logging fails setup
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone.current
            let timestamp = formatter.string(from: Date())
            print("[\(timestamp)] \(message)")
        }
    }

    static func logToFile(_ message: String, logFileURL: URL) {
        logFileQueue.async {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone.current
            let timestamp = formatter.string(from: Date())
            let logMessage = "[" + timestamp + "] " + message + "\n"
            print(logMessage)

            guard let logData = logMessage.data(using: .utf8) else {
                print("Failed to encode log message as UTF-8")
                return
            }

            do {
                if !FileManager.default.fileExists(atPath: logFileURL.path) {
                    try Data().write(to: logFileURL, options: .atomic)
                }
                rotateIfNeeded(logFileURL)

                let fileHandle = try FileHandle(forWritingTo: logFileURL)
                defer { try? fileHandle.close() }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: logData)
            } catch {
                print("Failed to write to log file: " + String(describing: error.localizedDescription))
            }
        }
    }

    /// Rotates the log once it exceeds `maxLogFileSize`, keeping a single previous
    /// generation as `chinup.log.1`. Callers must already be on `logFileQueue` —
    /// rotation and the append that follows it have to be one atomic unit, or a
    /// concurrent writer can hold a handle to the file we just moved aside.
    private static func rotateIfNeeded(_ logFileURL: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)
        guard let size = attributes?[.size] as? Int, size >= maxLogFileSize else { return }

        let archiveURL = logFileURL.appendingPathExtension("1")
        do {
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try FileManager.default.removeItem(at: archiveURL)
            }
            try FileManager.default.moveItem(at: logFileURL, to: archiveURL)
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        } catch {
            print("Failed to rotate log file: " + String(describing: error.localizedDescription))
        }
    }
}

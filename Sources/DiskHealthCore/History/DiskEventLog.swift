import Foundation

/// Notable event in a drive's life, as seen by Aman.
public struct DiskEvent: Codable, Equatable, Hashable {
    public enum Kind: String, Codable {
        /// S.M.A.R.T. was disabled; Aman turned it on.
        case smartEnabled
    }

    public let date: Date
    public let kind: Kind

    public init(date: Date = Date(), kind: Kind) {
        self.date = date
        self.kind = kind
    }
}

/// Event log, one JSON file per drive (same key as the history).
/// In its own folder: clearing the temperature history doesn't clear it.
public final class DiskEventLog: @unchecked Sendable {
    public static var shared = DiskEventLog()

    private let folderURL: URL
    private let queue = DispatchQueue(label: "io.github.aman-disk.events")

    public init(baseURL: URL? = nil) {
        let base = baseURL ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(HistoryStore.defaultFolderName)
        folderURL = base.appendingPathComponent("Events")
    }

    private func fileURL(for key: String) -> URL {
        folderURL.appendingPathComponent("\(key).jsonl")
    }
    
    private func oldFileURL(for key: String) -> URL {
        folderURL.appendingPathComponent("\(key).json")
    }

    public func events(for key: String) -> [DiskEvent] {
        queue.sync { return load(key) }
    }

    public func append(_ event: DiskEvent, for key: String) {
        queue.sync {
            try? FileManager.default.createDirectory(at: self.folderURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(event),
                  var str = String(data: data, encoding: .utf8) else { return }
            str.append("\n")
            
            let url = self.fileURL(for: key)
            if #available(macOS 10.15.4, *) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    if let lineData = str.data(using: .utf8) {
                        try? handle.write(contentsOf: lineData)
                    }
                } else {
                    try? str.write(to: url, atomically: true, encoding: .utf8)
                }
            } else {
                // macOS 10.13 to 10.15.3 (Aman Legacy): the older FileHandle API raises an Objective-C
                // exception on a write error instead of throwing. The file is small: read it, add the
                // line, write it back.
                var contents = (try? Data(contentsOf: url)) ?? Data()
                contents.append(Data(str.utf8))
                try? contents.write(to: url, options: .atomic)
            }
        }
    }

    private func load(_ key: String) -> [DiskEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var results: [DiskEvent] = []
        if let data = try? Data(contentsOf: oldFileURL(for: key)) {
            if let oldEvents = try? decoder.decode([DiskEvent].self, from: data) {
                results.append(contentsOf: oldEvents)
            }
        }
        
        if let string = try? String(contentsOf: fileURL(for: key)) {
            for line in string.split(whereSeparator: \.isNewline) {
                if let data = line.data(using: .utf8),
                   let event = try? decoder.decode(DiskEvent.self, from: data) {
                    results.append(event)
                }
            }
        }
        return results
    }
}
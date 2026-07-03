import AppKit

struct ShelfItem: Codable, Equatable {
    let id: UUID
    let path: String

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.lastPathComponent }
    var subtitle: String {
        url.deletingLastPathComponent().lastPathComponent
    }
}

enum Store {
    static let baseDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ledge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Holds files we had to copy in: promised files from browsers or mail
    /// clients, text snippets, clipboard images, and iPhone imports.
    static let filesDir: URL = {
        let dir = baseDir.appendingPathComponent("Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var itemsFile: URL { baseDir.appendingPathComponent("items.json") }

    static func save(_ items: [ShelfItem]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: itemsFile, options: .atomic)
        }
    }

    static func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: itemsFile),
              let items = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return [] }
        return items.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func newIncomingDir() -> URL {
        let dir = filesDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func stampedName(prefix: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(fmt.string(from: Date()))"
    }

    private static func uniqueURL(name: String, ext: String) -> URL {
        var url = filesDir.appendingPathComponent("\(name).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = filesDir.appendingPathComponent("\(name) \(n).\(ext)")
            n += 1
        }
        return url
    }

    static func saveSnippet(_ text: String) -> URL? {
        let url = uniqueURL(name: stampedName(prefix: "Snippet"), ext: "txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func saveData(_ data: Data, ext: String, prefix: String) -> URL? {
        let url = uniqueURL(name: stampedName(prefix: prefix), ext: ext)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Removes anything in the Files dir that no restored item references.
    static func sweepOrphans(keeping items: [ShelfItem]) {
        let keep = items.map { $0.path }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: filesDir, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            let p = entry.path
            let referenced = keep.contains { $0 == p || $0.hasPrefix(p + "/") }
            if !referenced {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}

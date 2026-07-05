import AppKit

struct ShelfItem: Codable, Equatable {
    let id: UUID
    let path: String

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.lastPathComponent }

    /// Real files show their parent folder. Items living in Ledge's own
    /// storage (snippets, clipboard images, promised files) would all show
    /// the meaningless "Files", so they show kind and size instead.
    var subtitle: String {
        if path.hasPrefix(Store.filesDir.path + "/") {
            let ext = url.pathExtension
            let kind = ext.isEmpty ? "File" : ext.uppercased()
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                let bytes = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                return "\(kind) · \(bytes)"
            }
            return kind
        }
        return url.deletingLastPathComponent().lastPathComponent
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

    /// Filename derived from the text itself, so snippets on the shelf are
    /// recognizable at a glance instead of all reading "Snippet <timestamp>".
    static func snippetName(for text: String) -> String {
        var name = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        for prefix in ["https://", "http://", "www."] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        let disallowed = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        name = String(name.unicodeScalars.map { disallowed.contains($0) ? "-" : Character($0) })
        if name.count > 40 {
            name = String(name.prefix(40)).trimmingCharacters(in: .whitespaces) + "…"
        }
        // A leading dot would make the file invisible in Finder
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? stampedName(prefix: "Snippet") : name
    }

    static func saveSnippet(_ text: String) -> URL? {
        let url = uniqueURL(name: snippetName(for: text), ext: "txt")
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

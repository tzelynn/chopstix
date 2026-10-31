import Foundation
import Observation

/// Owns all notes and persists them, debouncing writes while the user types.
///
/// `notes.json` is a small index (metadata plus sticky-note text). Each markdown note's body is
/// its own `markdown/<id>.md` file, so typing in one only rewrites that file and the index.
/// Bodies are written before the index and removed after it, so the index never refers to a
/// body that isn't there; a body the index has lost is adopted back on the next load.
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    /// Menu descriptions the user has rewritten, keyed by flavour.
    private(set) var blurbs: [Flavor: String] = [:]
    /// The user's own notes about what each flavour's section is for, keyed by flavour.
    private(set) var descriptions: [Flavor: String] = [:]

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored let backupURL: URL
    @ObservationIgnored let markdownDirectory: URL
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    /// Markdown bodies changed since the last save.
    @ObservationIgnored private var dirtyBodies: Set<UUID> = []
    /// Markdown bodies of deleted notes, removed once the index no longer lists them.
    @ObservationIgnored private var deletedBodies: Set<UUID> = []

    private struct Archive: Codable {
        var version = 2
        var notes: [Note]
        /// Custom flavour descriptions, keyed by `Flavor.rawValue`. Absent in older files.
        var blurbs: [String: String]?
        /// Section descriptions, keyed by `Flavor.rawValue`. Absent in older files.
        var descriptions: [String: String]?
    }

    static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CHOPSTIX_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chopstix", isDirectory: true)
    }

    init(directory: URL = NoteStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("notes.json")
        backupURL = directory.appendingPathComponent("notes.backup.json")
        markdownDirectory = directory.appendingPathComponent("markdown", isDirectory: true)
    }

    func bodyURL(_ id: UUID) -> URL {
        markdownDirectory.appendingPathComponent("\(id.uuidString).md")
    }

    /// `true` if there were notes to load (even none) — used to seed a first-run welcome.
    @discardableResult
    func load() -> Bool {
        let fm = FileManager.default
        var found = fm.fileExists(atPath: fileURL.path)
        if found {
            if let archive = readArchive(at: fileURL) {
                apply(archive)
                // A known-good copy, in case a later write is ever damaged.
                try? fm.removeItem(at: backupURL)
                try? fm.copyItem(at: fileURL, to: backupURL)
            } else {
                // Never silently overwrite notes we couldn't read: set the file aside first.
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let aside = fileURL.deletingLastPathComponent().appendingPathComponent("notes.unreadable-\(stamp).json")
                try? fm.moveItem(at: fileURL, to: aside)
                NSLog("chopstix: could not read notes; moved to \(aside.path)")
                if let backup = readArchive(at: backupURL) {
                    NSLog("chopstix: restored notes from \(backupURL.path)")
                    apply(backup)
                }
            }
        }
        loadBodies()
        if adoptOrphanBodies() { found = true }
        return found
    }

    private func readArchive(at url: URL) -> Archive? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder.chopstix.decode(Archive.self, from: data)
        } catch {
            NSLog("chopstix: \(url.lastPathComponent) is unreadable: \(error)")
            return nil
        }
    }

    private func apply(_ archive: Archive) {
        notes = archive.notes
        blurbs = Self.byFlavor(archive.blurbs)
        descriptions = Self.byFlavor(archive.descriptions)
    }

    private func loadBodies() {
        for index in notes.indices where notes[index].kind == .markdown {
            let url = bodyURL(notes[index].id)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                notes[index].markdown = text
            } else if FileManager.default.fileExists(atPath: url.path) {
                NSLog("chopstix: could not read \(url.path)")
            }
        }
    }

    /// Bodies with no note in the index (e.g. the index was lost) come back as notes in the board.
    private func adoptOrphanBodies() -> Bool {
        let known = Set(notes.map(\.id))
        let files = (try? FileManager.default.contentsOfDirectory(at: markdownDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var adopted = false
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "md" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), !known.contains(id),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            var note = Note(id: id, number: nextNumber, flavor: .udon, kind: .markdown, markdown: text, isOnScreen: false)
            note.createdAt = modified
            note.updatedAt = modified
            notes.append(note)
            adopted = true
            NSLog("chopstix: recovered markdown note \(id) from \(url.path)")
        }
        if adopted { scheduleSave() }
        return adopted
    }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    var nextNumber: Int { (notes.map(\.number).max() ?? 0) + 1 }

    func add(_ note: Note) {
        notes.append(note)
        if note.kind == .markdown { dirtyBodies.insert(note.id) }
        scheduleSave()
    }

    /// Mutates a note in place. `touch` bumps `updatedAt` (skip it for window moves).
    func update(_ id: UUID, touch: Bool = true, _ change: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let old = notes[index]
        var note = old
        change(&note)
        guard note != old else { return }
        if touch { note.updatedAt = Date() }
        if note.kind == .markdown && (note.markdown != old.markdown || old.kind != .markdown) {
            dirtyBodies.insert(id)
        }
        notes[index] = note
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let note = note(id) else { return }
        notes.removeAll { $0.id == id }
        dirtyBodies.remove(id)
        if note.kind == .markdown { deletedBodies.insert(id) }
        scheduleSave()
    }

    /// Sets a flavour's menu description; `nil` or blank restores the default.
    func setBlurb(_ flavor: Flavor, _ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = trimmed.isEmpty || trimmed == flavor.blurb ? nil : trimmed
        guard blurbs[flavor] != value else { return }
        blurbs[flavor] = value
        scheduleSave()
    }

    /// Sets a flavour's section description; `nil` or blank removes it.
    func setDescription(_ flavor: Flavor, _ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = trimmed.isEmpty ? nil : trimmed
        guard descriptions[flavor] != value else { return }
        descriptions[flavor] = value
        scheduleSave()
    }

    private static func byFlavor(_ raw: [String: String]?) -> [Flavor: String] {
        Dictionary(uniqueKeysWithValues: (raw ?? [:]).compactMap { key, text in
            Flavor(rawValue: key).map { ($0, text) }
        })
    }

    private static func byRawValue(_ map: [Flavor: String]) -> [String: String]? {
        map.isEmpty ? nil : Dictionary(uniqueKeysWithValues: map.map { ($0.rawValue, $1) })
    }

    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            // 1. Bodies first, so the index never lists a note whose body isn't on disk yet.
            if !dirtyBodies.isEmpty {
                try fm.createDirectory(at: markdownDirectory, withIntermediateDirectories: true)
            }
            for id in dirtyBodies {
                guard let note = note(id), note.kind == .markdown else { dirtyBodies.remove(id); continue }
                do {
                    try Data(note.markdown.utf8).write(to: bodyURL(id), options: .atomic)
                    dirtyBodies.remove(id)
                } catch {
                    // Stays dirty and is retried on the next save; the rest still get saved.
                    NSLog("chopstix: failed to save \(bodyURL(id).lastPathComponent): \(error)")
                }
            }

            // 2. The index.
            let data = try JSONEncoder.chopstix.encode(Archive(notes: notes, blurbs: Self.byRawValue(blurbs), descriptions: Self.byRawValue(descriptions)))
            try data.write(to: fileURL, options: .atomic)

            // 3. Only now that the index has forgotten them, deleted notes' bodies.
            for id in deletedBodies { try? fm.removeItem(at: bodyURL(id)) }
            deletedBodies.removeAll()
        } catch {
            NSLog("chopstix: failed to save notes: \(error)")
        }
    }
}

extension JSONEncoder {
    static var chopstix: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var chopstix: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

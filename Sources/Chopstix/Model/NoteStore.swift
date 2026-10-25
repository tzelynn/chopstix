import Foundation
import Observation

/// Owns all notes and persists them as JSON, debouncing writes while the user types.
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    /// Menu descriptions the user has rewritten, keyed by flavour.
    private(set) var blurbs: [Flavor: String] = [:]
    /// The user's own notes about what each flavour's section is for, keyed by flavour.
    private(set) var descriptions: [Flavor: String] = [:]

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    private struct Archive: Codable {
        var version = 1
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
    }

    /// `true` if a notes file existed (even an empty one) — used to seed a first-run welcome.
    @discardableResult
    func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        do {
            let archive = try JSONDecoder.chopstix.decode(Archive.self, from: data)
            notes = archive.notes
            blurbs = Self.byFlavor(archive.blurbs)
            descriptions = Self.byFlavor(archive.descriptions)
        } catch {
            // Never silently overwrite notes we couldn't read: set the file aside first.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("notes.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("chopstix: could not read notes (\(error)); moved to \(backup.path)")
            notes = []
        }
        return true
    }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    var nextNumber: Int { (notes.map(\.number).max() ?? 0) + 1 }

    func add(_ note: Note) {
        notes.append(note)
        scheduleSave()
    }

    /// Mutates a note in place. `touch` bumps `updatedAt` (skip it for window moves).
    func update(_ id: UUID, touch: Bool = true, _ change: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        change(&note)
        if touch { note.updatedAt = Date() }
        guard note != notes[index] else { return }
        notes[index] = note
        scheduleSave()
    }

    func remove(_ id: UUID) {
        notes.removeAll { $0.id == id }
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
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.chopstix.encode(Archive(notes: notes, blurbs: Self.byRawValue(blurbs), descriptions: Self.byRawValue(descriptions)))
            try data.write(to: fileURL, options: .atomic)
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

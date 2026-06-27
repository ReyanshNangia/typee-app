import Foundation

struct Note: Codable {
    var id: UUID
    var content: String
    var rtfData: Data?
    var colorName: String?

    init(content: String = "", colorName: String? = nil) {
        id = UUID()
        self.content = content
        self.colorName = colorName
    }
}

// MARK: - NoteStore

final class NoteStore {
    private(set) var notes: [Note]
    private(set) var activeIndex: Int

    /// Called after a folder switch that loaded different notes.
    var onReloaded: (() -> Void)?

    private var saveTimer: Timer?

    // MARK: - Folder management

    static let defaultFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask)[0]
        return base.appendingPathComponent("Typee", isDirectory: true)
    }()

    private let folderKey = "typee.notesFolder"

    var folder: URL {
        get {
            if let p = UserDefaults.standard.string(forKey: folderKey) {
                return URL(fileURLWithPath: p, isDirectory: true)
            }
            return NoteStore.defaultFolder
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: folderKey)
        }
    }

    var notesFileURL: URL { folder.appendingPathComponent("notes.json") }

    // MARK: - On-disk format

    private struct Snapshot: Codable {
        var version: Int = 1
        var activeIndex: Int
        var notes: [Note]
    }

    // MARK: - Init

    init() {
        // 1. Try the current notes file.
        if let snap = NoteStore.load(from: NoteStore.defaultFolder.appendingPathComponent("notes.json"),
                                     orFolder: UserDefaults.standard.string(forKey: "typee.notesFolder")) {
            notes       = snap.notes.isEmpty ? [Note()] : snap.notes
            activeIndex = max(0, min(snap.activeIndex, snap.notes.count - 1))
            return
        }

        // 2. Migrate from UserDefaults (legacy storage).
        if let data  = UserDefaults.standard.data(forKey: "typee.notes.v2"),
           let old   = try? JSONDecoder().decode([Note].self, from: data),
           !old.isEmpty {
            notes       = old
            let saved   = UserDefaults.standard.integer(forKey: "typee.activeIndex")
            activeIndex = max(0, min(saved, old.count - 1))
            // Persist to file now so next launch reads from file.
            scheduleSave()
            return
        }

        // 3. Fresh start.
        notes       = [Note()]
        activeIndex = 0
        scheduleSave()
    }

    private static func load(from primary: URL, orFolder storedPath: String?) -> Snapshot? {
        // Try the stored folder first if different from default.
        if let p = storedPath {
            let url = URL(fileURLWithPath: p).appendingPathComponent("notes.json")
            if let snap = decode(from: url) { return snap }
        }
        return decode(from: primary)
    }

    private static func decode(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              !snap.notes.isEmpty
        else { return nil }
        return snap
    }

    // MARK: - Folder switch

    /// Change where notes are saved.
    /// - Parameters:
    ///   - newFolder: The new directory.
    ///   - copyCurrentNotes: true → write current notes to the new folder (move);
    ///                       false → load whatever notes.json already exists there (import).
    func switchFolder(to newFolder: URL, copyCurrentNotes: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(at: newFolder, withIntermediateDirectories: true)

        if copyCurrentNotes {
            // Write current notes to the new location.
            persistNow(to: newFolder.appendingPathComponent("notes.json"))
            folder = newFolder
        } else {
            // Import: load from the existing file.
            folder = newFolder
            let snap = NoteStore.decode(from: notesFileURL)
            if let snap, !snap.notes.isEmpty {
                notes       = snap.notes
                activeIndex = max(0, min(snap.activeIndex, snap.notes.count - 1))
                DispatchQueue.main.async { self.onReloaded?() }
            }
        }
    }

    // MARK: - CRUD

    func updateNote(at index: Int, content: String, rtfData: Data?) {
        guard notes.indices.contains(index) else { return }
        notes[index].content = content
        notes[index].rtfData = rtfData
        scheduleSave()
    }

    func updateColor(at index: Int, colorName: String?) {
        guard notes.indices.contains(index) else { return }
        notes[index].colorName = colorName
        scheduleSave()
    }

    @discardableResult
    func addNote() -> Int {
        notes.append(Note())
        activeIndex = notes.count - 1
        scheduleSave()
        return activeIndex
    }

    func setActiveIndex(_ index: Int) {
        guard notes.indices.contains(index) else { return }
        activeIndex = index
        scheduleSave()
    }

    func deleteNote(at index: Int) {
        guard notes.count > 1, notes.indices.contains(index) else { return }
        notes.remove(at: index)
        if activeIndex >= index { activeIndex = max(0, activeIndex - 1) }
        scheduleSave()
    }

    func moveNote(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              notes.indices.contains(fromIndex),
              notes.indices.contains(toIndex) else { return }
        let note = notes.remove(at: fromIndex)
        notes.insert(note, at: toIndex)
        if activeIndex == fromIndex {
            activeIndex = toIndex
        } else if fromIndex < toIndex {
            if activeIndex > fromIndex && activeIndex <= toIndex { activeIndex -= 1 }
        } else {
            if activeIndex < fromIndex && activeIndex >= toIndex { activeIndex += 1 }
        }
        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.persist()
        }
    }

    func persist() {
        persistNow(to: notesFileURL)
    }

    private func persistNow(to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snap = Snapshot(activeIndex: activeIndex, notes: notes)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

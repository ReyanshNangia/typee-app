import Foundation

struct Note: Codable {
    var id: UUID
    var content: String

    init(content: String = "") {
        id = UUID()
        self.content = content
    }
}

final class NoteStore {
    private(set) var notes: [Note]
    private(set) var activeIndex: Int
    private var saveTimer: Timer?

    private let notesKey = "typee.notes.v2"
    private let indexKey  = "typee.activeIndex"

    init() {
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data),
           !decoded.isEmpty {
            notes = decoded
        } else {
            notes = [Note()]
        }
        let saved = UserDefaults.standard.integer(forKey: indexKey)
        activeIndex = max(0, min(saved, notes.count - 1))
    }

    func updateContent(_ content: String, at index: Int) {
        guard (0..<notes.count).contains(index) else { return }
        notes[index].content = content
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
        guard (0..<notes.count).contains(index) else { return }
        activeIndex = index
        UserDefaults.standard.set(index, forKey: indexKey)
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.persist()
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: notesKey)
        }
        UserDefaults.standard.set(activeIndex, forKey: indexKey)
    }
}

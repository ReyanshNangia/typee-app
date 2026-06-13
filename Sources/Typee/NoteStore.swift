import Foundation

struct Note: Codable {
    var id: UUID
    var content: String  // plain-text fallback / search text
    var rtfData: Data?   // rich text (bold, italic, underline)

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

    func updateNote(at index: Int, content: String, rtfData: Data?) {
        guard (0..<notes.count).contains(index) else { return }
        notes[index].content = content
        notes[index].rtfData = rtfData
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

    func deleteNote(at index: Int) {
        guard notes.count > 1 else { return }
        guard (0..<notes.count).contains(index) else { return }
        notes.remove(at: index)
        if activeIndex >= index {
            activeIndex = max(0, activeIndex - 1)
        }
        scheduleSave()
    }

    func moveNote(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex else { return }
        guard (0..<notes.count).contains(fromIndex),
              (0..<notes.count).contains(toIndex) else { return }
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

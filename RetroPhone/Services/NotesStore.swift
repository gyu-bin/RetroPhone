import Foundation
import Observation

struct Note: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var created = Date()
    var modified = Date()

    /// First non-empty line, like the classic Notes list.
    var title: String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? L("새로운 메모")
    }
}

/// RetroPhone's own notes (Apple Notes data is not accessible via public API and is never read).
@Observable
final class NotesStore {
    static let shared = NotesStore()
    private static let fileName = "notes.json"
    private let persist: Bool

    private(set) var notes: [Note]

    init(persist: Bool = true) {
        self.persist = persist
        notes = (persist ? FileStore.load([Note].self, from: Self.fileName) : nil) ?? []
        sort()
    }

    @discardableResult
    func create(_ text: String = "") -> Note {
        let note = Note(text: text)
        notes.insert(note, at: 0)
        save()
        return note
    }

    func update(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].modified = Date()
        sort()
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// Removes notes that were left empty.
    func pruneEmpty() {
        let before = notes.count
        notes.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if notes.count != before { save() }
    }

    private func sort() { notes.sort { $0.modified > $1.modified } }
    private func save() { if persist { FileStore.save(notes, to: Self.fileName) } }
}

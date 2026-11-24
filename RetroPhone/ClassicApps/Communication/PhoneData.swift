import Foundation
import Observation
import SwiftUI

nonisolated struct PhoneFavorite: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var number: String
    var label: String?
    var contactID: String?
}

/// A call that RetroPhone handed to iOS (iOS doesn't expose the system call history to apps).
nonisolated struct DialedCall: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var number: String
    var name: String?
    var date: Date
}

/// Local-only favorites and "dialed from RetroPhone" log, stored as JSON via FileStore.
@Observable
final class PhoneLocalStore {
    static let shared = PhoneLocalStore()

    private static let favoritesFile = "phone_favorites.json"
    private static let dialedFile = "phone_dialed.json"

    private(set) var favorites: [PhoneFavorite]
    private(set) var dialed: [DialedCall]

    private init() {
        favorites = FileStore.load([PhoneFavorite].self, from: Self.favoritesFile) ?? []
        dialed = FileStore.load([DialedCall].self, from: Self.dialedFile) ?? []
    }

    // MARK: Favorites

    func isFavorite(number: String) -> Bool {
        let key = CommPhone.matchKey(number)
        return favorites.contains { CommPhone.matchKey($0.number) == key }
    }

    func addFavorite(name: String, number: String, label: String?, contactID: String?) {
        guard !isFavorite(number: number) else { return }
        favorites.append(PhoneFavorite(name: name, number: number, label: label, contactID: contactID))
        saveFavorites()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveFavorites()
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    private func saveFavorites() { FileStore.save(favorites, to: Self.favoritesFile) }

    // MARK: Dialed log

    func logDial(number: String, name: String?) {
        let resolvedName = name ?? ContactsStore.shared.contact(forNumber: number).map { contactDisplayName($0.0) }
        dialed.insert(DialedCall(number: number, name: resolvedName, date: Date()), at: 0)
        if dialed.count > 100 { dialed.removeLast(dialed.count - 100) }
        FileStore.save(dialed, to: Self.dialedFile)
    }

    func removeDialed(at offsets: IndexSet) {
        dialed.remove(atOffsets: offsets)
        FileStore.save(dialed, to: Self.dialedFile)
    }

    func clearDialed() {
        dialed = []
        FileStore.save(dialed, to: Self.dialedFile)
    }
}

import Contacts
import Foundation
import Observation

// MARK: - Models (plain values, safe to build off the main actor)

nonisolated struct ContactLabeledValue: Hashable, Sendable {
    var label: String?
    var value: String
}

nonisolated struct ContactSummary: Identifiable, Hashable, Sendable {
    var id: String
    /// Formatted full name (may be empty for company-only cards).
    var name: String
    var organization: String
    var phones: [ContactLabeledValue]
    var emails: [ContactLabeledValue]
    var hasImage: Bool
    /// Hangul initial / A–Z / "#".
    var sectionKey: String

    /// Name used for sorting / sectioning (name, else company, else first number/email).
    var sortName: String {
        if !name.isEmpty { return name }
        if !organization.isEmpty { return organization }
        return phones.first?.value ?? emails.first?.value ?? ""
    }
}

nonisolated struct ContactExtraDetail: Sendable {
    var thumbnail: Data?
    var addresses: [ContactLabeledValue]
    var urls: [ContactLabeledValue]
    var birthday: DateComponents?
    var jobTitle: String
    var department: String
}

/// Contacts framework access. Every call creates its own `CNContactStore` so it can run on a
/// background task. Nothing is logged.
nonisolated enum ContactsFetcher {
    static func listKeys() -> [CNKeyDescriptor] {
        [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]
    }

    static func fetchAll() -> [ContactSummary] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: listKeys())
        request.sortOrder = .userDefault
        var out: [ContactSummary] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                out.append(summary(contact))
            }
        } catch {
            return []
        }
        let locale = Locale(identifier: "ko_KR")
        out.sort { a, b in
            a.sortName.compare(b.sortName, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
        }
        return out
    }

    static func summary(_ c: CNContact) -> ContactSummary {
        let name = CNContactFormatter.string(from: c, style: .fullName) ?? ""
        let phones = c.phoneNumbers.map { ContactLabeledValue(label: $0.label, value: $0.value.stringValue) }
        let emails = c.emailAddresses.map { ContactLabeledValue(label: $0.label, value: $0.value as String) }
        var s = ContactSummary(id: c.identifier, name: name, organization: c.organizationName,
                               phones: phones, emails: emails, hasImage: c.imageDataAvailable, sectionKey: "#")
        s.sectionKey = CommIndex.sectionKey(for: s.sortName)
        return s
    }

    static func extraDetail(id: String) -> ContactExtraDetail? {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
        ]
        guard let c = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys) else { return nil }
        let addresses = c.postalAddresses.map { lv in
            ContactLabeledValue(label: lv.label,
                                value: CNPostalAddressFormatter.string(from: lv.value, style: .mailingAddress))
        }
        let urls = c.urlAddresses.map { ContactLabeledValue(label: $0.label, value: $0.value as String) }
        return ContactExtraDetail(thumbnail: c.thumbnailImageData, addresses: addresses, urls: urls,
                                  birthday: c.birthday, jobTitle: c.jobTitle, department: c.departmentName)
    }
}

// MARK: - Store

/// Shared, observable contact list used by Contacts, Phone and Messages.
@Observable
final class ContactsStore {
    static let shared = ContactsStore()

    enum Access { case notDetermined, denied, restricted, limited, authorized }

    private(set) var access: Access
    private(set) var contacts: [ContactSummary] = []
    private(set) var isLoading = false
    private(set) var loadedOnce = false
    @ObservationIgnored private var loadGeneration = 0

    var canRead: Bool { access == .authorized || access == .limited }

    private init() {
        access = Self.currentAccess()
        NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.loadedOnce else { return }
                self.reload()
            }
        }
    }

    static func currentAccess() -> Access {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .limited: return .limited
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }

    func requestAccess() async {
        let store = CNContactStore()
        _ = try? await store.requestAccess(for: .contacts)
        access = Self.currentAccess()
        if canRead { reload() }
    }

    /// Call from `.task` of every screen that shows contacts.
    func loadIfNeeded() {
        access = Self.currentAccess()
        if canRead && !loadedOnce && !isLoading { reload() }
        if !canRead { contacts = [] }
    }

    func reload() {
        access = Self.currentAccess()
        guard canRead else {
            contacts = []
            return
        }
        isLoading = true
        loadGeneration += 1
        let generation = loadGeneration
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ContactsFetcher.fetchAll()
            }.value
            guard generation == self.loadGeneration else { return }
            self.contacts = result
            self.isLoading = false
            self.loadedOnce = true
        }
    }

    func contact(id: String) -> ContactSummary? { contacts.first { $0.id == id } }

    /// Finds the contact owning a phone number (exact match after normalization).
    func contact(forNumber number: String) -> (ContactSummary, ContactLabeledValue)? {
        let key = CommPhone.matchKey(number)
        guard key.count >= 3 else { return nil }
        for c in contacts {
            if let p = c.phones.first(where: { CommPhone.matchKey($0.value) == key }) { return (c, p) }
        }
        return nil
    }
}

// MARK: - Display helpers (main actor; use app localization)

func contactDisplayName(_ c: ContactSummary) -> String {
    let s = c.sortName
    return s.isEmpty ? L("이름 없음") : s
}

/// Localized label for a Contacts labeled value (mobile, home, work…).
func contactLabel(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return L("기타") }
    switch raw {
    case CNLabelPhoneNumberMobile: return L("휴대전화")
    case CNLabelPhoneNumberiPhone: return "iPhone"
    case CNLabelPhoneNumberMain: return L("기본")
    case CNLabelHome: return L("집")
    case CNLabelWork: return L("직장")
    case CNLabelOther: return L("기타")
    case CNLabelPhoneNumberHomeFax: return L("집 팩스")
    case CNLabelPhoneNumberWorkFax: return L("직장 팩스")
    case CNLabelPhoneNumberPager: return L("호출기")
    case CNLabelEmailiCloud: return "iCloud"
    case CNLabelURLAddressHomePage: return L("홈페이지")
    case CNLabelSchool: return L("학교")
    default: return CNLabeledValue<NSString>.localizedString(forLabel: raw)
    }
}

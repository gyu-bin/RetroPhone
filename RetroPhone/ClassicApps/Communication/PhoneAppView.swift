import SwiftUI

/// iOS 4 Phone: black tab bar with Favorites / Recents / Contacts / Keypad / Voicemail.
/// Calls are placed for real through `tel:` (iOS shows its own confirmation).
struct PhoneAppView: View {
    enum Tab: Hashable { case favorites, recents, contacts, keypad, voicemail }

    @State private var tab: Tab = .keypad
    @State private var digits = ""

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .favorites: PhoneFavoritesView()
                case .recents: PhoneRecentsView()
                case .contacts: PhoneContactsTab()
                case .keypad: PhoneKeypadView(digits: $digits)
                case .voicemail: PhoneVoicemailView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CommTabBar(items: [
                CommTabItem(tag: Tab.favorites, title: L("즐겨찾기"), systemImage: "star.fill"),
                CommTabItem(tag: Tab.recents, title: L("최근 통화"), systemImage: "clock.fill"),
                CommTabItem(tag: Tab.contacts, title: L("연락처"), systemImage: "person.crop.circle.fill"),
                CommTabItem(tag: Tab.keypad, title: L("키패드"), systemImage: "circle.grid.3x3.fill"),
                CommTabItem(tag: Tab.voicemail, title: L("음성 사서함"), systemImage: "recordingtape"),
            ], selection: $tab)
        }
        .background(Color.black)
    }
}

// MARK: - Keypad

struct PhoneKeypadView: View {
    @Binding var digits: String

    @State private var callFailed = false
    @State private var favoriteAdded = false
    @State private var plusEnteredAt: Date? = nil
    @State private var clearedAt: Date? = nil

    private static let keys: [(digit: Character, letters: String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", ""),
    ]

    var body: some View {
        GeometryReader { geo in
            let displayHeight = max(76, geo.size.height * 0.19)
            let keyHeight = max(44, (geo.size.height - displayHeight) / 5)
            VStack(spacing: 0) {
                display
                    .frame(height: displayHeight)
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { col in
                            keyButton(Self.keys[row * 3 + col])
                        }
                    }
                    .frame(height: keyHeight)
                }
                bottomRow(height: keyHeight)
            }
        }
        .background(Color.black)
        .task { ContactsStore.shared.loadIfNeeded() }
        .retroAlert(L("통화할 수 없음"), isPresented: $callFailed,
                    message: L("이 기기에서는 전화를 걸 수 없습니다."))
        .retroAlert(L("즐겨찾기에 추가됨"), isPresented: $favoriteAdded)
    }

    // MARK: Display

    private var matchedName: String? {
        guard digits.count >= 3, let match = ContactsStore.shared.contact(forNumber: digits) else { return nil }
        return contactDisplayName(match.0) + "  " + contactLabel(match.1.label)
    }

    private var display: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x111111)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 4) {
                Text(CommPhone.format(digits))
                    .font(.retroFixed(34, .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, y: -1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 16)
                    .accessibilityLabel(digits.isEmpty ? L("번호 없음") : digits)
                if let name = matchedName {
                    Text(name)
                        .font(.retroFixed(14, .bold))
                        .foregroundStyle(Color(hex: 0x9FB4D6))
                        .lineLimit(1)
                }
            }
            VStack { Spacer(); Rectangle().fill(Color.black).frame(height: 1) }
        }
    }

    // MARK: Keys

    private func keyButton(_ key: (digit: Character, letters: String)) -> some View {
        Button {
            press(key.digit)
        } label: {
            VStack(spacing: 0) {
                Text(String(key.digit))
                    .font(.retroFixed(key.digit == "*" ? 40 : 34, .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 0, y: -1)
                    .offset(y: key.digit == "*" ? 6 : 0)
                if !key.letters.isEmpty {
                    Text(key.letters)
                        .font(.retroFixed(11, .bold))
                        .foregroundStyle(Color(hex: 0xA6A6A6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeypadKeyStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                if key.digit == "0" { longPressZero() }
            }
        )
        .accessibilityLabel(String(key.digit))
    }

    private func bottomRow(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button {
                addFavorite()
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(digits.isEmpty ? Color(hex: 0x5A5A5A) : Color(hex: 0xD0D0D0))
                    .shadow(color: .black, radius: 0, y: -1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeypadKeyStyle())
            .accessibilityLabel(L("즐겨찾기에 추가"))

            GlossyButton(title: L("통화"), systemImage: "phone.fill", tint: .green, height: max(36, height - 14)) {
                callTapped()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeypadKeyBackground())

            Button {
                deleteTapped()
            } label: {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xD0D0D0))
                    .shadow(color: .black, radius: 0, y: -1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeypadKeyStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                    clearedAt = Date()
                    if !digits.isEmpty { Haptics.tap(.medium) }
                    digits = ""
                }
            )
            .accessibilityLabel(L("지우기"))
        }
        .frame(height: height)
    }

    // MARK: Actions

    private func press(_ digit: Character) {
        if let t = plusEnteredAt, Date().timeIntervalSince(t) < 3 {
            plusEnteredAt = nil
            return
        }
        plusEnteredAt = nil
        guard digits.count < 32 else { return }
        SoundService.shared.playDTMF(digit)
        Haptics.tap()
        digits.append(digit)
    }

    private func longPressZero() {
        guard digits.count < 32 else { return }
        plusEnteredAt = Date()
        SoundService.shared.playDTMF("0")
        Haptics.tap(.medium)
        digits.append("+")
    }

    private func deleteTapped() {
        if let t = clearedAt, Date().timeIntervalSince(t) < 3 {
            clearedAt = nil
            return
        }
        clearedAt = nil
        guard !digits.isEmpty else { return }
        SoundService.shared.play(.tock)
        digits.removeLast()
    }

    private func callTapped() {
        if digits.isEmpty {
            // iOS behavior: an empty Call press recalls the last number dialed (from RetroPhone).
            if let last = PhoneLocalStore.shared.dialed.first { digits = last.number }
            return
        }
        let number = digits
        let name = ContactsStore.shared.contact(forNumber: number).map { contactDisplayName($0.0) }
        Task {
            if !(await CommDialer.call(number, name: name)) { callFailed = true }
        }
    }

    private func addFavorite() {
        guard !digits.isEmpty else { return }
        let match = ContactsStore.shared.contact(forNumber: digits)
        PhoneLocalStore.shared.addFavorite(name: match.map { contactDisplayName($0.0) } ?? CommPhone.format(digits),
                                           number: digits, label: match?.1.label, contactID: match?.0.id)
        Haptics.success()
        favoriteAdded = true
    }
}

private struct KeypadKeyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4F4F4F), Color(hex: 0x262626)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
                Spacer()
                Rectangle().fill(Color.black).frame(height: 1)
            }
            HStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                Spacer()
                Rectangle().fill(Color.black.opacity(0.9)).frame(width: 1)
            }
        }
    }
}

private struct KeypadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    KeypadKeyBackground()
                    if configuration.isPressed {
                        LinearGradient(colors: [Color(hex: 0x6F9BEA), Color(hex: 0x2357C4)], startPoint: .top, endPoint: .bottom)
                            .opacity(0.85)
                    }
                }
            }
    }
}

// MARK: - Favorites

struct PhoneFavoritesView: View {
    @State private var editMode: EditMode = .inactive
    @State private var showPicker = false
    @State private var callFailed = false

    private var store: PhoneLocalStore { PhoneLocalStore.shared }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("즐겨찾기"), background: AnyView(Color.white), leading: {
                if !store.favorites.isEmpty {
                    ClassicBarButton(title: editMode.isEditing ? L("완료") : L("편집"),
                                     kind: editMode.isEditing ? .done : .plain) {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }, trailing: {
                ClassicBarButton(title: L("추가"), systemImage: "plus") { showPicker = true }
            }) {
                if store.favorites.isEmpty {
                    CommEmptyState(systemImage: "star",
                                   title: L("즐겨찾기 없음"),
                                   message: L("+ 버튼으로 연락처의 전화번호를 추가하세요. 즐겨찾기는 이 기기의 RetroPhone에만 저장됩니다."))
                } else {
                    List {
                        ForEach(store.favorites) { fav in
                            Button {
                                guard !editMode.isEditing else { return }
                                Task {
                                    if !(await CommDialer.call(fav.number, name: fav.name)) { callFailed = true }
                                }
                            } label: {
                                HStack {
                                    Text(fav.name)
                                        .font(.retro(19, .bold))
                                        .foregroundStyle(.black)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(fav.label.map { contactLabel($0) } ?? CommPhone.format(CommPhone.dialable(fav.number)))
                                        .font(.retro(14))
                                        .foregroundStyle(Color(hex: 0x8A8A8A))
                                        .lineLimit(1)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        }
                        .onDelete { store.removeFavorites(at: $0) }
                        .onMove { store.moveFavorites(from: $0, to: $1) }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, $editMode)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            ContactPhonePickerSheet(title: L("즐겨찾기 추가")) { contact, phone in
                store.addFavorite(name: contactDisplayName(contact), number: phone.value,
                                  label: phone.label, contactID: contact.id)
            }
        }
        .retroAlert(L("통화할 수 없음"), isPresented: $callFailed, message: L("이 기기에서는 전화를 걸 수 없습니다."))
    }
}

// MARK: - Recents (only calls placed from RetroPhone)

struct PhoneRecentsView: View {
    @State private var confirmClear = false
    @State private var callFailed = false

    private var store: PhoneLocalStore { PhoneLocalStore.shared }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("최근 통화"), leading: { EmptyView() }, trailing: {
                if !store.dialed.isEmpty {
                    ClassicBarButton(title: L("지우기")) { confirmClear = true }
                }
            }) {
                ScrollView {
                    VStack(spacing: 0) {
                        CommNote(text: L("iOS는 다른 앱에 기기의 통화 기록을 제공하지 않습니다. 이곳에는 RetroPhone에서 건 전화만 표시됩니다."))
                            .padding(.top, 6)
                        if store.dialed.isEmpty {
                            CommNote(text: L("RetroPhone에서 건 전화가 없습니다."))
                                .padding(.top, 30)
                        } else {
                            GroupedSection(header: L("RetroPhone에서 건 전화")) {
                                ForEach(store.dialed) { call in
                                    Button {
                                        Task {
                                            if !(await CommDialer.call(call.number, name: call.name)) { callFailed = true }
                                        }
                                    } label: {
                                        recentRow(call)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .commActionSheet(isPresented: $confirmClear, buttons: [
            CommSheetButton(title: L("최근 기록 지우기"), role: .destructive) { store.clearDialed() },
            CommSheetButton(title: L("취소"), role: .cancel),
        ])
        .retroAlert(L("통화할 수 없음"), isPresented: $callFailed, message: L("이 기기에서는 전화를 걸 수 없습니다."))
    }

    private func recentRow(_ call: DialedCall) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "phone.arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x7A8494))
            VStack(alignment: .leading, spacing: 1) {
                Text(call.name ?? CommPhone.format(call.number))
                    .font(.retro(17, .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                if call.name != nil {
                    Text(CommPhone.format(call.number))
                        .font(.retro(13))
                        .foregroundStyle(Color(hex: 0x8A8A8A))
                }
            }
            Spacer(minLength: 6)
            Text(commRelativeDate(call.date))
                .font(.retro(14))
                .foregroundStyle(Color(hex: 0x385487))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

// MARK: - Contacts tab

struct PhoneContactsTab: View {
    @State private var path: [ContactSummary] = []

    var body: some View {
        NavigationStack(path: $path) {
            ClassicPage(title: L("연락처"), background: AnyView(Color.white),
                        leading: { EmptyView() }, trailing: { EmptyView() }) {
                ContactsBrowser { contact in path.append(contact) }
            }
            .navigationDestination(for: ContactSummary.self) { contact in
                ContactDetailView(contact: contact)
            }
        }
    }
}

// MARK: - Voicemail

struct PhoneVoicemailView: View {
    var body: some View {
        NavigationStack {
            ClassicPage(title: L("음성 사서함"), leading: { EmptyView() }, trailing: { EmptyView() }) {
                PermissionPlaceholder(systemImage: "recordingtape",
                                      title: L("음성 사서함을 표시할 수 없음"),
                                      message: L("iOS는 다른 앱이 음성 사서함에 접근하도록 허용하지 않습니다. 음성 사서함은 기본 전화 앱에서 확인하세요."))
            }
        }
    }
}

// MARK: - Shared date label

/// iOS 4 list date: time for today, "Yesterday", weekday within a week, otherwise a short date.
func commRelativeDate(_ date: Date, now: Date = Date()) -> String {
    let cal = Calendar.current
    if cal.isDate(date, inSameDayAs: now) { return RetroFormat.time(date) }
    if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) {
        return L("어제")
    }
    if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day,
       days > 0 && days < 7 {
        return RetroFormat.date(date, template: "EEEE")
    }
    return RetroFormat.date(date, template: "yyMd")
}

import SwiftUI
import Contacts
import ContactsUI

// MARK: - Reusable contact list (permission handling, sections, index, search)

/// iOS 4 "All Contacts" list. Used by Contacts, the Phone app's Contacts tab and pickers.
struct ContactsBrowser: View {
    var onSelect: (ContactSummary) -> Void

    @State private var query = ""
    @State private var showLimitedPicker = false
    @State private var lastIndexKey: String? = nil

    private var store: ContactsStore { ContactsStore.shared }

    var body: some View {
        Group {
            switch store.access {
            case .notDetermined:
                PermissionPlaceholder(systemImage: "person.crop.circle",
                                      title: L("연락처 접근"),
                                      message: L("기기의 연락처를 보려면 접근을 허용하세요. 연락처는 기기 밖으로 전송되지 않습니다."),
                                      requestTitle: L("접근 허용"),
                                      request: { Task { await store.requestAccess() } })
                    .background(PinstripeBackground())
            case .denied:
                PermissionPlaceholder(systemImage: "person.crop.circle.badge.xmark",
                                      title: L("연락처 접근이 거부됨"),
                                      message: L("iOS 설정 > RetroPhone에서 연락처 접근을 허용하세요."),
                                      denied: true)
                    .background(PinstripeBackground())
            case .restricted:
                PermissionPlaceholder(systemImage: "lock",
                                      title: L("연락처 접근이 제한됨"),
                                      message: L("이 기기에서는 연락처 접근이 제한되어 있습니다(스크린 타임 또는 기기 관리)."))
                    .background(PinstripeBackground())
            case .limited, .authorized:
                list
            }
        }
        .task { store.loadIfNeeded() }
        .contactAccessPicker(isPresented: $showLimitedPicker) { _ in
            store.reload()
        }
    }

    // MARK: List

    private struct IndexSection: Identifiable {
        var key: String
        var items: [ContactSummary]
        var id: String { key }
    }

    private var filtered: [ContactSummary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.contacts }
        let digits = q.filter { $0.isASCII && $0.isNumber }
        return store.contacts.filter { c in
            if c.name.localizedCaseInsensitiveContains(q) || c.organization.localizedCaseInsensitiveContains(q) { return true }
            if digits.count >= 2 && digits.count == q.filter({ !$0.isWhitespace && $0 != "-" }).count {
                return c.phones.contains { phone in
                    phone.value.filter { ch in ch.isASCII && ch.isNumber }.contains(digits)
                }
            }
            return c.emails.contains { $0.value.localizedCaseInsensitiveContains(q) }
        }
    }

    private var sections: [IndexSection] {
        let koreanFirst = Localizer.shared.language == .ko
        let grouped = Dictionary(grouping: filtered, by: { $0.sectionKey })
        return grouped.keys
            .sorted { CommIndex.rank($0, koreanFirst: koreanFirst) < CommIndex.rank($1, koreanFirst: koreanFirst) }
            .map { IndexSection(key: $0, items: grouped[$0] ?? []) }
    }

    private var list: some View {
        let sections = self.sections
        let total = filtered.count
        return ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        RetroSearchBar(text: $query, placeholder: L("검색"))
                        if store.access == .limited {
                            limitedBanner
                        }
                        if store.isLoading && store.contacts.isEmpty {
                            Text(L("불러오는 중…"))
                                .font(.retro(15))
                                .foregroundStyle(Color(hex: 0x8A8A8A))
                                .padding(.top, 40)
                        } else if sections.isEmpty {
                            Text(query.isEmpty ? L("연락처 없음") : L("검색 결과 없음"))
                                .font(.retro(17, .bold))
                                .foregroundStyle(Color(hex: 0x9A9A9A))
                                .padding(.top, 40)
                        }
                        ForEach(sections) { section in
                            SwiftUI.Section {
                                ForEach(section.items) { c in
                                    Button {
                                        Haptics.selection()
                                        onSelect(c)
                                    } label: {
                                        ContactListRow(contact: c)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                PlainSectionHeader(title: section.key)
                                    .id("section-" + section.key)
                            }
                        }
                        if total > 0 {
                            Text(LF("%d개의 연락처", total))
                                .font(.retro(17))
                                .foregroundStyle(Color(hex: 0x8A8A8A))
                                .frame(maxWidth: .infinity, minHeight: 60)
                        }
                    }
                    .padding(.trailing, (query.isEmpty && sections.count > 1) ? 18 : 0)
                }
                .scrollDismissesKeyboard(.immediately)
                if query.isEmpty && sections.count > 1 {
                    indexBar(keys: sections.map(\.key), proxy: proxy)
                }
            }
        }
        .background(Color.white)
    }

    private var limitedBanner: some View {
        VStack(spacing: 6) {
            Text(L("선택한 연락처만 RetroPhone에서 볼 수 있습니다."))
                .font(.retro(13))
                .foregroundStyle(Color(hex: 0x4C566C))
                .multilineTextAlignment(.center)
            Button {
                SoundService.shared.play(.tock)
                showLimitedPicker = true
            } label: {
                Text(L("연락처 더 선택…"))
                    .font(.retro(14, .bold))
                    .foregroundStyle(Color(hex: 0x2F6BDB))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0xEEF1F5))
    }

    private func indexBar(keys: [String], proxy: ScrollViewProxy) -> some View {
        let rowHeight: CGFloat = 15
        return VStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.retroFixed(11, .bold))
                    .foregroundStyle(Color(hex: 0x5E6B7D))
                    .frame(width: 20, height: rowHeight)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let index = Int((value.location.y - 4) / rowHeight)
                    let clamped = min(max(index, 0), keys.count - 1)
                    let key = keys[clamped]
                    if key != lastIndexKey {
                        lastIndexKey = key
                        Haptics.selection()
                        proxy.scrollTo("section-" + key, anchor: .top)
                    }
                }
                .onEnded { _ in lastIndexKey = nil }
        )
        .padding(.trailing, 2)
        .accessibilityHidden(true)
    }
}

struct ContactListRow: View {
    var contact: ContactSummary
    var body: some View {
        PlainRow {
            HStack(spacing: 6) {
                Text(contactDisplayName(contact))
                    .font(.retro(19, .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                if !contact.name.isEmpty && !contact.organization.isEmpty {
                    Text(contact.organization)
                        .font(.retro(14))
                        .foregroundStyle(Color(hex: 0x8A8A8A))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Contact detail ("Info")

struct ContactDetailView: View {
    var contact: ContactSummary

    @State private var extra: ContactExtraDetail? = nil
    @State private var photo: UIImage? = nil
    @State private var cannotOpen = false
    @State private var showSMSChoices = false
    @State private var showFavoriteChoices = false
    @State private var favoriteAdded = false

    private var current: ContactSummary { ContactsStore.shared.contact(id: contact.id) ?? contact }

    var body: some View {
        let c = current
        ClassicPage(title: L("정보"), leading: { ClassicBackButton() }, trailing: { EmptyView() }) {
            ScrollView {
                VStack(spacing: 0) {
                    header(c)
                    if !c.phones.isEmpty {
                        GroupedSection {
                            ForEach(Array(c.phones.enumerated()), id: \.offset) { _, p in
                                Button { call(p.value, name: contactDisplayName(c)) } label: {
                                    CommDetailRow(label: contactLabel(p.label), value: p.value)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !c.emails.isEmpty {
                        GroupedSection {
                            ForEach(Array(c.emails.enumerated()), id: \.offset) { _, e in
                                Button { open { await CommDialer.openMail(e.value) } } label: {
                                    CommDetailRow(label: contactLabel(e.label), value: e.value)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let extra, !extra.urls.isEmpty {
                        GroupedSection {
                            ForEach(Array(extra.urls.enumerated()), id: \.offset) { _, u in
                                Button { open { await CommDialer.openWeb(u.value) } } label: {
                                    CommDetailRow(label: contactLabel(u.label), value: u.value)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let extra, !extra.addresses.isEmpty {
                        GroupedSection {
                            ForEach(Array(extra.addresses.enumerated()), id: \.offset) { _, a in
                                CommDetailRow(label: contactLabel(a.label), value: a.value)
                            }
                        }
                    }
                    if let birthday = extra?.birthday, let text = birthdayText(birthday) {
                        GroupedSection {
                            CommDetailRow(label: L("생일"), value: text)
                        }
                    }
                    actionButtons(c)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
            }
        }
        .task(id: contact.id) { await loadExtra() }
        .retroAlert(L("열 수 없음"), isPresented: $cannotOpen, message: L("이 기기에서는 이 작업을 할 수 없습니다."))
        .commActionSheet(L("문자 보내기"), isPresented: $showSMSChoices, buttons: smsButtons(c))
        .commActionSheet(L("즐겨찾기에 추가"), isPresented: $showFavoriteChoices, buttons: favoriteButtons(c))
        .retroAlert(L("즐겨찾기에 추가됨"), isPresented: $favoriteAdded)
    }

    private func header(_ c: ContactSummary) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white)
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color(hex: 0xB9BFC8))
                }
            }
            .frame(width: 64, height: 64)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(hex: 0x9A9EA4), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(contactDisplayName(c))
                    .font(.retro(20, .bold))
                    .foregroundStyle(Color(hex: 0x1E1E1E))
                    .embossed()
                    .lineLimit(2)
                let subtitle = subtitleText(c)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.retro(14))
                        .foregroundStyle(Color(hex: 0x4C566C))
                        .embossed()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func subtitleText(_ c: ContactSummary) -> String {
        var parts: [String] = []
        if let extra, !extra.jobTitle.isEmpty { parts.append(extra.jobTitle) }
        if let extra, !extra.department.isEmpty { parts.append(extra.department) }
        if !c.name.isEmpty && !c.organization.isEmpty { parts.append(c.organization) }
        return parts.joined(separator: " · ")
    }

    private func actionButtons(_ c: ContactSummary) -> some View {
        HStack(spacing: 10) {
            if !c.phones.isEmpty {
                whiteButton(L("문자 보내기")) {
                    if c.phones.count == 1 {
                        open { await CommDialer.openSMS(c.phones[0].value) }
                    } else {
                        showSMSChoices = true
                    }
                }
                whiteButton(L("즐겨찾기에 추가")) {
                    if c.phones.count == 1 {
                        addFavorite(c, c.phones[0])
                    } else {
                        showFavoriteChoices = true
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }

    /// iOS 4 white rounded "Text Message" / "Add to Favorites" buttons.
    private func whiteButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundService.shared.play(.tock)
            action()
        } label: {
            Text(title)
                .font(.retro(14, .bold))
                .foregroundStyle(Color(hex: 0x385487))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0xA8ABAE), lineWidth: 1))
                .shadow(color: .white.opacity(0.8), radius: 0, y: 1)
        }
        .buttonStyle(PressDimStyle())
    }

    private func smsButtons(_ c: ContactSummary) -> [CommSheetButton] {
        c.phones.map { p in
            CommSheetButton(title: contactLabel(p.label) + "  " + p.value) {
                open { await CommDialer.openSMS(p.value) }
            }
        } + [CommSheetButton(title: L("취소"), role: .cancel)]
    }

    private func favoriteButtons(_ c: ContactSummary) -> [CommSheetButton] {
        c.phones.map { p in
            CommSheetButton(title: contactLabel(p.label) + "  " + p.value) {
                addFavorite(c, p)
            }
        } + [CommSheetButton(title: L("취소"), role: .cancel)]
    }

    private func addFavorite(_ c: ContactSummary, _ p: ContactLabeledValue) {
        PhoneLocalStore.shared.addFavorite(name: contactDisplayName(c), number: p.value, label: p.label, contactID: c.id)
        Haptics.success()
        favoriteAdded = true
    }

    private func call(_ number: String, name: String) {
        Task {
            if !(await CommDialer.call(number, name: name)) { cannotOpen = true }
        }
    }

    private func open(_ operation: @escaping () async -> Bool) {
        Task {
            if !(await operation()) { cannotOpen = true }
        }
    }

    private func birthdayText(_ comps: DateComponents) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        var c = comps
        let hasYear = c.year != nil
        if !hasYear { c.year = 2000 }
        guard let date = cal.date(from: c) else { return nil }
        return RetroFormat.date(date, template: hasYear ? "yMMMMd" : "MMMMd")
    }

    private func loadExtra() async {
        let id = contact.id
        let detail = await Task.detached(priority: .userInitiated) {
            ContactsFetcher.extraDetail(id: id)
        }.value
        extra = detail
        if let data = detail?.thumbnail { photo = UIImage(data: data) }
    }
}

// MARK: - Picker sheet: choose a contact's phone number

struct ContactPhonePickerSheet: View {
    var title: String
    var onPick: (ContactSummary, ContactLabeledValue) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pending: ContactSummary? = nil
    @State private var showChoices = false
    @State private var noPhone = false

    var body: some View {
        NavigationStack {
            ClassicPage(title: title, background: AnyView(Color.white), leading: { EmptyView() }, trailing: {
                ClassicBarButton(title: L("취소")) { dismiss() }
            }) {
                ContactsBrowser { c in
                    if c.phones.count == 1 {
                        onPick(c, c.phones[0])
                        dismiss()
                    } else if c.phones.isEmpty {
                        noPhone = true
                    } else {
                        pending = c
                        showChoices = true
                    }
                }
            }
        }
        .commActionSheet(pending.map { contactDisplayName($0) }, isPresented: $showChoices, buttons: choiceButtons)
        .retroAlert(L("전화번호 없음"), isPresented: $noPhone, message: L("이 연락처에는 전화번호가 없습니다."))
    }

    private var choiceButtons: [CommSheetButton] {
        guard let c = pending else { return [CommSheetButton(title: L("취소"), role: .cancel)] }
        return c.phones.map { p in
            CommSheetButton(title: contactLabel(p.label) + "  " + p.value) {
                onPick(c, p)
                dismiss()
            }
        } + [CommSheetButton(title: L("취소"), role: .cancel)]
    }
}

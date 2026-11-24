import SwiftUI
import UIKit

/// iOS 4 Notes: leather-bound top bar, yellow lined legal paper, Marker Felt handwriting.
/// Notes are RetroPhone's own (NotesStore, local JSON); Apple Notes is never read.
struct NotesAppView: View {
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            NotesListView(path: $path)
                .navigationDestination(for: UUID.self) { id in
                    NoteEditorView(initialID: id)
                }
        }
        .onAppear { NotesStore.shared.pruneEmpty() }
    }
}

// MARK: - Shared look

private enum NotesStyle {
    static let paper = Color(hex: 0xFCF2AE)
    static let rule = Color(hex: 0xC9B98A)
    static let ink = Color(hex: 0x2A1E0E)
    static let brownText = Color(hex: 0x8A5A2A)
    static let fontName = "MarkerFelt-Thin"

    static var fontSize: CGFloat { 20 * SettingsStore.shared.value.textScale }
    static var font: Font { .custom(fontName, fixedSize: fontSize) }
    static var uiFont: UIFont { UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize) }
    /// Ruled-line pitch. The editor forces exactly this line height (paragraph style), so the
    /// rules drawn at the bottom of every line fragment always line up with the text.
    static var lineHeight: CGFloat { (uiFont.lineHeight + 6).rounded(.up) }

    static func dateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return L("오늘") }
        if Calendar.current.isDateInYesterday(date) { return L("어제") }
        return RetroFormat.date(date, template: "MMMdEEE")
    }

    static func rowDate(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? RetroFormat.time(date) : RetroFormat.date(date, template: "MMMd")
    }
}

/// Yellow paper with horizontal rules at `offset + k * lineHeight` and a double margin line.
private struct NotePaper: View {
    var lineHeight: CGFloat
    var offset: CGFloat
    var margin: Bool = true

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(NotesStyle.paper))
            guard lineHeight > 4 else { return }
            var y = offset
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(NotesStyle.rule.opacity(0.85)))
                y += lineHeight
            }
            if margin {
                for x in [CGFloat(7), 10] {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color(hex: 0xD48A72).opacity(0.45)))
                }
            }
        }
    }
}

/// Brown leather with a little grain and a stitched seam.
private struct LeatherBackground: View {
    var seamAtBottom = true

    var body: some View {
        ZStack(alignment: seamAtBottom ? .bottom : .top) {
            LinearGradient(colors: [Color(hex: 0x9C6B3D), Color(hex: 0x7A4D27), Color(hex: 0x5D391B)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
                let count = Int(size.width * size.height / 28)
                for _ in 0..<count {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let x = CGFloat((seed >> 40) & 0xFFFF) / 65_535 * size.width
                    let y = CGFloat((seed >> 20) & 0xFFFF) / 65_535 * size.height
                    let dark = (seed >> 7) & 1 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                             with: .color(dark ? Color.black.opacity(0.13) : Color.white.opacity(0.07)))
                }
            }
            .allowsHitTesting(false)
            SeamLine()
                .stroke(Color(hex: 0xF0D3A6).opacity(0.75), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                .frame(height: 2)
                .padding(seamAtBottom ? .bottom : .top, 5)
            Rectangle().fill(Color(hex: 0x2B1706)).frame(height: 1)
        }
    }
}

private struct SeamLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private struct LeatherBar<Leading: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            LeatherBackground()
            Text(title)
                .font(.retroFixed(20, .bold))
                .foregroundStyle(.white)
                .shadow(color: Color(hex: 0x3A1E0A), radius: 0, y: -1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 90)
            HStack {
                leading()
                Spacer()
                trailing()
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 44)
    }
}

private struct LeatherBarButton: View {
    var title: String
    var systemImage: String? = nil
    var isBack = false
    var action: () -> Void

    var body: some View {
        Button {
            SoundService.shared.play(.tock)
            action()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .bold))
                } else {
                    Text(title).font(.retroFixed(12.5, .bold)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
            .padding(.leading, isBack ? 16 : 9)
            .padding(.trailing, 9)
            .frame(minWidth: 44, minHeight: 30)
            .background(background)
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder private var background: some View {
        let fill = LinearGradient(colors: [Color(hex: 0x9A6A40), Color(hex: 0x6E4422), Color(hex: 0x4E2C12)],
                                  startPoint: .top, endPoint: .bottom)
        if isBack {
            BackButtonShape().fill(fill)
                .overlay(BackButtonShape().stroke(Color.black.opacity(0.55), lineWidth: 1))
                .shadow(color: .white.opacity(0.25), radius: 0, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.black.opacity(0.55), lineWidth: 1))
                .shadow(color: .white.opacity(0.25), radius: 0, y: 1)
        }
    }
}

// MARK: - List

private struct NotesListView: View {
    @Binding var path: [UUID]
    @State var query = ""
    private var store: NotesStore { .shared }

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.notes }
        return store.notes.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            LeatherBar(title: store.notes.isEmpty ? L("메모") : LF("메모 (%d)", store.notes.count), leading: {
                EmptyView()
            }, trailing: {
                LeatherBarButton(title: L("새로운 메모"), systemImage: "plus") {
                    store.pruneEmpty()
                    let note = store.create()
                    path.append(note.id)
                }
            })
            .zIndex(1)
            RetroSearchBar(text: $query, placeholder: L("검색"))
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        if filtered.isEmpty && !query.isEmpty {
                            Text(L("결과 없음"))
                                .font(NotesStyle.font)
                                .foregroundStyle(NotesStyle.brownText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        ForEach(filtered) { note in
                            Button {
                                SoundService.shared.play(.tock)
                                path.append(note.id)
                            } label: {
                                NoteRow(note: note)
                            }
                            .buttonStyle(NoteRowButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(note.id)
                                } label: {
                                    Label(L("삭제"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                    .background(alignment: .top) {
                        NotePaper(lineHeight: 44, offset: 43, margin: false)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(NotesStyle.paper)
        }
        .background(NotesStyle.paper.ignoresSafeArea(edges: .bottom))
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct NoteRow: View {
    var note: Note

    var body: some View {
        HStack(spacing: 8) {
            Text(note.title)
                .font(NotesStyle.font)
                .foregroundStyle(NotesStyle.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(NotesStyle.rowDate(note.modified))
                .font(.retroFixed(14, .bold))
                .foregroundStyle(NotesStyle.brownText)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotesStyle.brownText.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
}

private struct NoteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(hex: 0xD9B85A).opacity(0.45) : Color.clear)
    }
}

// MARK: - Editor

private struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var noteID: UUID
    @State private var text: String
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var editing = false
    private var store: NotesStore { .shared }

    init(initialID: UUID) {
        _noteID = State(initialValue: initialID)
        _text = State(initialValue: NotesStore.shared.notes.first { $0.id == initialID }?.text ?? "")
    }

    private var note: Note? { store.notes.first { $0.id == noteID } }
    private var index: Int? { store.notes.firstIndex { $0.id == noteID } }

    private var barTitle: String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? L("새로운 메모") : first
    }

    var body: some View {
        VStack(spacing: 0) {
            LeatherBar(title: barTitle, leading: {
                LeatherBarButton(title: L("메모"), isBack: true) { leave() }
            }, trailing: {
                if editing {
                    LeatherBarButton(title: L("완료")) { editing = false }
                } else {
                    LeatherBarButton(title: L("새로운 메모"), systemImage: "plus") { newNote() }
                }
            })
            .zIndex(1)

            GeometryReader { geo in
                ScrollView {
                    paper(minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(NotesStyle.paper)

            bottomBar
        }
        .background(NotesStyle.paper.ignoresSafeArea(edges: .bottom))
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: text) { _, newValue in scheduleSave(newValue) }
        .onAppear {
            if note == nil { dismiss() }
            else if text.isEmpty { editing = true }
        }
        .onDisappear {
            flush()
            store.pruneEmpty()
        }
        .retroAlert(L("메모 삭제"), isPresented: $confirmDelete, message: L("이 메모를 삭제하시겠습니까?"), buttons: [
            RetroAlertButton(title: L("취소")),
            RetroAlertButton(title: L("삭제"), isPreferred: true, action: { deleteCurrent() }),
        ])
    }

    private func paper(minHeight: CGFloat) -> some View {
        let lineH = NotesStyle.lineHeight
        let date = note?.modified ?? Date()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                Text(NotesStyle.dateLabel(date))
                Spacer()
                Text(RetroFormat.time(date))
            }
            .font(NotesStyle.font)
            .foregroundStyle(NotesStyle.brownText)
            .lineLimit(1)
            .frame(height: lineH, alignment: .bottom)
            .padding(.horizontal, 18)

            LinedTextView(text: $text, isFocused: $editing, font: NotesStyle.uiFont, lineHeight: lineH,
                          textColor: UIColor(red: 0.16, green: 0.12, blue: 0.05, alpha: 1),
                          tintColor: UIColor(red: 0.42, green: 0.24, blue: 0.08, alpha: 1))
                .padding(.horizontal, 18)
                .accessibilityLabel(L("메모 내용"))
        }
        .padding(.bottom, lineH * 3)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(alignment: .top) {
            NotePaper(lineHeight: lineH, offset: lineH - 1)
                .contentShape(Rectangle())
                .onTapGesture { editing = true }
        }
    }

    private var bottomBar: some View {
        let i = index
        let count = store.notes.count
        let canPrev = (i ?? 0) > 0
        let canNext = i.map { $0 < count - 1 } ?? false
        return ZStack {
            LeatherBackground(seamAtBottom: false)
            HStack {
                ToolbarIconButton(systemImage: "arrowtriangle.left.fill", label: L("이전 메모"), enabled: canPrev) { step(-1) }
                Spacer()
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                        .frame(width: 44, height: 40)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .accessibilityLabel(L("공유"))
                Spacer()
                ToolbarIconButton(systemImage: "trash", label: L("삭제")) {
                    editing = false
                    confirmDelete = true
                }
                Spacer()
                ToolbarIconButton(systemImage: "arrowtriangle.right.fill", label: L("다음 메모"), enabled: canNext) { step(1) }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
    }

    // MARK: Actions

    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        let id = noteID
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NotesStore.shared.update(id, text: value)
        }
    }

    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        if note != nil { store.update(noteID, text: text) }
    }

    /// Leaves the current note, deleting it if it was left empty.
    private func closeCurrent() {
        flush()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.delete(noteID) }
    }

    private func show(_ id: UUID) {
        noteID = id
        text = store.notes.first { $0.id == id }?.text ?? ""
    }

    private func step(_ delta: Int) {
        guard let i = index else { return }
        let j = i + delta
        guard store.notes.indices.contains(j) else { return }
        let target = store.notes[j].id
        editing = false
        closeCurrent()
        withAnimation(.easeInOut(duration: 0.25)) { show(target) }
    }

    private func newNote() {
        closeCurrent()
        let created = store.create()
        show(created.id)
        editing = true
    }

    private func deleteCurrent() {
        saveTask?.cancel()
        let notes = store.notes
        var target: UUID?
        if let i = index {
            if i + 1 < notes.count { target = notes[i + 1].id }
            else if i > 0 { target = notes[i - 1].id }
        }
        store.delete(noteID)
        Haptics.success()
        if let target {
            show(target)
        } else {
            dismiss()
        }
    }

    private func leave() {
        editing = false
        flush()
        dismiss()
    }
}

// MARK: - Lined text view

/// Non-scrolling UITextView with a fixed line height so text sits exactly on the paper rules.
/// It grows with its content inside the surrounding SwiftUI ScrollView.
private struct LinedTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var font: UIFont
    var lineHeight: CGFloat
    var textColor: UIColor
    var tintColor: UIColor

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.attributedText = NSAttributedString(string: text, attributes: attributes)
        view.typingAttributes = attributes
        view.tintColor = tintColor
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            let selection = view.selectedRange
            view.attributedText = NSAttributedString(string: text, attributes: attributes)
            let length = (text as NSString).length
            view.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }
        view.typingAttributes = attributes
        view.tintColor = tintColor
        if isFocused && !view.isFirstResponder {
            Task { @MainActor in view.becomeFirstResponder() }
        } else if !isFocused && view.isFirstResponder {
            Task { @MainActor in view.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(lineHeight, ceil(fit.height)))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LinedTextView

        init(parent: LinedTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}

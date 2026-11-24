import SwiftUI
import MessageUI

/// iOS 4 Messages. Existing SMS/iMessage history is not accessible to apps, so the list only shows
/// messages sent through the iOS composer from RetroPhone (clearly labeled).
struct MessagesAppView: View {
    @State private var path: [String] = []
    @State private var showCompose = false
    @State private var editMode: EditMode = .inactive

    private var log: MessageLogStore { MessageLogStore.shared }

    var body: some View {
        NavigationStack(path: $path) {
            ClassicPage(title: L("메시지"), background: AnyView(Color.white), leading: {
                if !log.threads.isEmpty {
                    ClassicBarButton(title: editMode.isEditing ? L("완료") : L("편집"),
                                     kind: editMode.isEditing ? .done : .plain) {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }, trailing: {
                ClassicBarButton(title: L("새로운 메시지"), systemImage: "square.and.pencil") { showCompose = true }
            }) {
                if log.threads.isEmpty {
                    emptyState
                } else {
                    threadList
                }
            }
            .navigationDestination(for: String.self) { id in
                MessageThreadView(threadID: id)
            }
        }
        .sheet(isPresented: $showCompose) {
            NewMessageView { threadID in
                path = [threadID]
            }
        }
    }

    private var emptyState: some View {
        ZStack {
            PinstripeBackground()
            PermissionPlaceholder(systemImage: "bubble.left.and.bubble.right",
                                  title: L("기존 대화는 표시할 수 없음"),
                                  message: L("iOS는 다른 앱이 문자·iMessage 기록을 읽도록 허용하지 않습니다. 오른쪽 위 버튼으로 새 메시지를 작성하면 iOS 메시지 작성 화면을 통해 전송되고, 보낸 내용만 이 기기의 RetroPhone에 기록됩니다."),
                                  requestTitle: L("새로운 메시지"),
                                  request: { showCompose = true })
        }
    }

    private var threadList: some View {
        VStack(spacing: 0) {
            Text(L("RetroPhone에서 보낸 메시지만 표시됩니다"))
                .font(.retro(12))
                .foregroundStyle(Color(hex: 0x5C6678))
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Color(hex: 0xE6EAF0))
            List {
                ForEach(log.threads) { thread in
                    Button {
                        guard !editMode.isEditing else { return }
                        path.append(thread.id)
                    } label: {
                        threadRow(thread)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10))
                }
                .onDelete { log.deleteThreads(at: $0) }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
        }
    }

    private func threadRow(_ thread: MessageThread) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.displayName)
                    .font(.retro(17, .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(commRelativeDate(thread.lastDate))
                    .font(.retro(14))
                    .foregroundStyle(Color(hex: 0x385487))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x9A9A9A))
            }
            Text(thread.messages.last?.body ?? "")
                .font(.retro(14))
                .foregroundStyle(Color(hex: 0x7F7F7F))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - Conversation (sent-from-RetroPhone log)

struct MessageThreadView: View {
    var threadID: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var composer: MessageComposeRequest? = nil
    @State private var cannotSend = false
    @State private var callFailed = false

    private var thread: MessageThread? { MessageLogStore.shared.thread(id: threadID) }

    var body: some View {
        let thread = self.thread
        ClassicPage(title: thread?.displayName ?? L("메시지"),
                    background: AnyView(Color(hex: 0xDBE2ED)),
                    leading: { ClassicBackButton(title: L("메시지")) },
                    trailing: {
                        if let thread, thread.recipients.count == 1 {
                            ClassicBarButton(title: L("통화")) {
                                let number = thread.recipients[0]
                                Task {
                                    if !(await CommDialer.call(number, name: thread.displayName)) { callFailed = true }
                                }
                            }
                        }
                    }) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            Text(L("RetroPhone에서 iOS 메시지 작성 화면으로 전송한 내용입니다. 작성 화면에서 수정한 내용과 상대방의 답장은 표시되지 않습니다."))
                                .font(.retro(12))
                                .foregroundStyle(Color(hex: 0x6A7486))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                            ForEach(Array((thread?.messages ?? []).enumerated()), id: \.element.id) { index, message in
                                if shouldShowTimestamp(index: index, messages: thread?.messages ?? []) {
                                    Text(RetroFormat.date(message.date, template: "yMMMdjmm"))
                                        .font(.retro(12, .bold))
                                        .foregroundStyle(Color(hex: 0x7A8494))
                                        .padding(.top, 6)
                                }
                                SentBubble(text: message.body)
                                    .id(message.id)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    .onAppear {
                        if let last = thread?.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                    .onChange(of: thread?.messages.count ?? 0) {
                        if let last = self.thread?.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                MessageInputBar(text: $draft) {
                    send(thread)
                }
            }
        }
        .messageComposer($composer) { _ in draft = "" }
        .retroAlert(L("메시지를 보낼 수 없음"), isPresented: $cannotSend,
                    message: L("이 기기에서는 문자 메시지를 보낼 수 없습니다."))
        .retroAlert(L("통화할 수 없음"), isPresented: $callFailed, message: L("이 기기에서는 전화를 걸 수 없습니다."))
    }

    private func shouldShowTimestamp(index: Int, messages: [SentMessage]) -> Bool {
        guard index > 0 else { return true }
        return messages[index].date.timeIntervalSince(messages[index - 1].date) > 15 * 60
    }

    private func send(_ thread: MessageThread?) {
        guard let thread else { return }
        guard MFMessageComposeViewController.canSendText() else {
            cannotSend = true
            return
        }
        composer = MessageComposeRequest(recipients: thread.recipients, displayName: thread.displayName, body: draft)
    }
}

/// iOS 4 green SMS bubble (sent side).
struct SentBubble: View {
    var text: String
    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.retro(16))
                .foregroundStyle(.black)
                .padding(.vertical, 7)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .background(
                    ZStack {
                        LinearGradient(colors: [Color(hex: 0xD3F5B0), Color(hex: 0x8ED65F)], startPoint: .top, endPoint: .bottom)
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 14)
                            Spacer(minLength: 0)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0x6AA846), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
    }
}

/// Bottom bar with a rounded text field and the "Send" button.
struct MessageInputBar: View {
    @Binding var text: String
    var onSend: () -> Void

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(L("문자 메시지"), text: $text, axis: .vertical)
                .font(.retro(16))
                .lineLimit(1...5)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().stroke(Color(hex: 0x8A96A6), lineWidth: 1))
            Button {
                SoundService.shared.play(.tock)
                onSend()
            } label: {
                Text(L("보내기"))
                    .font(.retroFixed(15, .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        LinearGradient(colors: canSend ? [Color(hex: 0x7AA3F2), Color(hex: 0x2D63DA)] : [Color(hex: 0xB4BCC8), Color(hex: 0x8C96A4)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(PressDimStyle())
            .disabled(!canSend)
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0xE4E8EE), Color(hex: 0xB9C2CE)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(hex: 0x8A96A6)).frame(height: 1)
            }
        )
    }
}

// MARK: - New message

struct NewMessageView: View {
    /// Called with the thread id after a message is sent, so the list can open the conversation.
    var onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipients: [Recipient] = []
    @State private var typed = ""
    @State private var draft = ""
    @State private var showPicker = false
    @State private var composer: MessageComposeRequest? = nil
    @State private var cannotSend = false
    @State private var invalidNumber = false
    @FocusState private var recipientFocused: Bool

    struct Recipient: Identifiable, Hashable {
        let id = UUID()
        var name: String?
        var number: String
        var title: String { name ?? CommPhone.format(CommPhone.dialable(number)) }
    }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("새로운 메시지"), background: AnyView(Color.white), leading: { EmptyView() }, trailing: {
                ClassicBarButton(title: L("취소")) { dismiss() }
            }) {
                VStack(spacing: 0) {
                    recipientField
                    Rectangle().fill(Color(hex: 0xC8CDD4)).frame(height: 1)
                    Color(hex: 0xDBE2ED)
                        .overlay(alignment: .top) {
                            Text(L("메시지는 iOS 메시지 작성 화면을 통해 전송됩니다."))
                                .font(.retro(12))
                                .foregroundStyle(Color(hex: 0x6A7486))
                                .multilineTextAlignment(.center)
                                .padding(16)
                        }
                        .onTapGesture { recipientFocused = false }
                    MessageInputBar(text: $draft) { send() }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            ContactPhonePickerSheet(title: L("받는 사람 선택")) { contact, phone in
                addRecipient(Recipient(name: contactDisplayName(contact), number: phone.value))
            }
        }
        .messageComposer($composer) { req in
            let id = MessageLogStore.key(for: req.recipients)
            dismiss()
            onSent(id)
        }
        .retroAlert(L("메시지를 보낼 수 없음"), isPresented: $cannotSend,
                    message: L("이 기기에서는 문자 메시지를 보낼 수 없습니다."))
        .retroAlert(L("받는 사람 없음"), isPresented: $invalidNumber,
                    message: L("받는 사람의 전화번호나 이메일을 입력하세요."))
    }

    private var recipientField: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(L("받는 사람:"))
                .font(.retro(15))
                .foregroundStyle(Color(hex: 0x8A8A8A))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(recipients) { r in
                        Button {
                            recipients.removeAll { $0.id == r.id }
                        } label: {
                            HStack(spacing: 3) {
                                Text(r.title).font(.retro(14, .bold)).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x7AA3F2), Color(hex: 0x2D63DA)], startPoint: .top, endPoint: .bottom)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LF("%@ 삭제", r.title))
                    }
                    TextField("", text: $typed)
                        .font(.retro(15))
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.telephoneNumber)
                        .focused($recipientFocused)
                        .frame(minWidth: 120)
                        .onSubmit { commitTyped() }
                }
            }
            Button {
                SoundService.shared.play(.tock)
                showPicker = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(hex: 0x2F6BDB))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("연락처에서 선택"))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .onAppear { recipientFocused = true }
    }

    private func addRecipient(_ r: Recipient) {
        guard !recipients.contains(where: { MessageLogStore.key(for: [$0.number]) == MessageLogStore.key(for: [r.number]) }) else { return }
        recipients.append(r)
    }

    private func commitTyped() {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let match = ContactsStore.shared.contact(forNumber: trimmed)
        addRecipient(Recipient(name: match.map { contactDisplayName($0.0) }, number: trimmed))
        typed = ""
    }

    private func send() {
        commitTyped()
        guard !recipients.isEmpty else {
            invalidNumber = true
            return
        }
        guard MFMessageComposeViewController.canSendText() else {
            cannotSend = true
            return
        }
        let numbers = recipients.map(\.number)
        let name = recipients.map(\.title).joined(separator: ", ")
        composer = MessageComposeRequest(recipients: numbers, displayName: name, body: draft)
    }
}

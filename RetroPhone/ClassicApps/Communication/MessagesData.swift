import Foundation
import MessageUI
import Observation
import SwiftUI
import UIKit

// MARK: - Local log of messages handed to iOS from RetroPhone

nonisolated struct SentMessage: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var body: String
    var date: Date
}

nonisolated struct MessageThread: Codable, Identifiable, Hashable, Sendable {
    /// Normalized, sorted recipient key.
    var id: String
    var recipients: [String]
    var displayName: String
    var messages: [SentMessage]

    var lastDate: Date { messages.last?.date ?? .distantPast }
}

/// iOS doesn't let apps read SMS/iMessage history. RetroPhone only remembers messages the user
/// sent through the iOS composer from inside RetroPhone (stored on device as JSON).
@Observable
final class MessageLogStore {
    static let shared = MessageLogStore()
    private static let file = "messages_sent_log.json"

    private(set) var threads: [MessageThread]

    private init() {
        threads = (FileStore.load([MessageThread].self, from: Self.file) ?? []).sorted { $0.lastDate > $1.lastDate }
    }

    static func key(for recipients: [String]) -> String {
        recipients.map { CommPhone.matchKey($0).isEmpty ? $0.lowercased() : CommPhone.matchKey($0) }
            .sorted()
            .joined(separator: ",")
    }

    func thread(id: String) -> MessageThread? { threads.first { $0.id == id } }

    func record(recipients: [String], displayName: String, body: String) {
        let key = Self.key(for: recipients)
        let message = SentMessage(body: body, date: Date())
        if let i = threads.firstIndex(where: { $0.id == key }) {
            threads[i].messages.append(message)
            threads[i].displayName = displayName
        } else {
            threads.append(MessageThread(id: key, recipients: recipients, displayName: displayName, messages: [message]))
        }
        threads.sort { $0.lastDate > $1.lastDate }
        save()
    }

    func deleteThreads(at offsets: IndexSet) {
        threads.remove(atOffsets: offsets)
        save()
    }

    func deleteThread(id: String) {
        threads.removeAll { $0.id == id }
        save()
    }

    private func save() { FileStore.save(threads, to: Self.file) }
}

// MARK: - MFMessageComposeViewController bridge

struct MessageComposeRequest: Identifiable {
    let id = UUID()
    var recipients: [String]
    var displayName: String
    var body: String
}

/// Wraps the system message composer. The composer itself sends the SMS/iMessage — RetroPhone never
/// sees delivery state, only whether the user tapped Send or Cancel.
struct MessageComposeSheet: UIViewControllerRepresentable {
    var recipients: [String]
    var body: String
    var onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                      didFinishWith result: MessageComposeResult) {
            MainActor.assumeIsolated {
                self.onFinish(result)
            }
        }
    }
}

extension View {
    /// Presents the iOS message composer for `request`; logs the message when the user taps Send.
    func messageComposer(_ request: Binding<MessageComposeRequest?>, onSent: @escaping (MessageComposeRequest) -> Void = { _ in }) -> some View {
        sheet(item: request) { req in
            MessageComposeSheet(recipients: req.recipients, body: req.body) { result in
                request.wrappedValue = nil
                if result == .sent {
                    MessageLogStore.shared.record(recipients: req.recipients, displayName: req.displayName, body: req.body)
                    onSent(req)
                }
            }
            .ignoresSafeArea()
        }
    }
}

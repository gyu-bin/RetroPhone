import SwiftUI

/// iOS 4 Contacts: real contacts from the Contacts framework, sectioned (ㄱ–ㅎ / A–Z) with search.
struct ContactsAppView: View {
    @State private var path: [ContactSummary] = []

    var body: some View {
        NavigationStack(path: $path) {
            ClassicPage(title: L("모든 연락처"), background: AnyView(Color.white),
                        leading: { EmptyView() }, trailing: { EmptyView() }) {
                ContactsBrowser { contact in
                    path.append(contact)
                }
            }
            .navigationDestination(for: ContactSummary.self) { contact in
                ContactDetailView(contact: contact)
            }
        }
    }
}

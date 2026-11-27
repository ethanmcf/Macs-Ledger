import SwiftUI

/// Sync status, and the ledger key: copy it to keep it safe, or paste one to open your ledger on a new phone.
struct CloudSyncView: View {
    @Environment(LedgerStore.self) private var store

    @State private var showsKey = false
    @State private var enteringKey = false
    @State private var newKey = ""
    @State private var keyError: String?

    var body: some View {
        Form {
            Section {
                status
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Dismiss") { store.dismissError() }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Every change is saved on this phone straight away and uploads to Firestore by itself, including changes made offline.")
            }

            Section {
                Group {
                    if showsKey {
                        Text(store.ledgerKey)
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "•", count: 24))
                    }
                }
                .font(.footnote.monospaced())
                Button(showsKey ? "Hide Key" : "Show Key", systemImage: showsKey ? "eye.slash" : "eye") {
                    showsKey.toggle()
                }
                Button("Copy Key", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = store.ledgerKey
                }
            } header: {
                Text("Ledger key")
            } footer: {
                Text("Your data is stored under this key, and anyone who has it can read and change your data. Keep a copy somewhere private, like your password manager. You'll need it on a new phone.")
            }

            Section {
                Button("Use a Different Key…", systemImage: "key") {
                    newKey = ""
                    enteringKey = true
                }
            } footer: {
                Text("On a new phone, paste the key from your old one to see your data. The data under the current key stays in the cloud.")
            }
        }
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Use a different key", isPresented: $enteringKey) {
            TextField("Ledger key", text: $newKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Use Key") {
                do {
                    try store.useLedger(key: newKey)
                } catch {
                    keyError = error.localizedDescription
                }
            }
        } message: {
            Text("The app will show the data stored under the key you paste. Copy the current key first if you might want it back.")
        }
        .alert("Couldn't use that key", isPresented: .constant(keyError != nil)) {
            Button("OK") { keyError = nil }
        } message: {
            Text(keyError ?? "")
        }
    }

    @ViewBuilder
    private var status: some View {
        if store.hasPendingWrites {
            Label(store.isOffline ? "Offline. Changes will upload when you're connected." : "Uploading changes…",
                  systemImage: "arrow.triangle.2.circlepath.icloud")
        } else if store.isOffline {
            Label("Offline. Everything on this phone is up to date as of your last connection.", systemImage: "icloud.slash")
        } else {
            Label("Up to date", systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
        }
    }
}

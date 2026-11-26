import SwiftUI

/// Connect the Google Sheet, see backup status, back up now, or update the app from the sheet.
struct BackupView: View {
    @State private var sync = SyncService.shared
    @State private var url = SyncService.shared.webAppURL
    @State private var token = SyncService.shared.token
    @State private var confirmingPull = false
    @State private var message: String?
    @State private var pullError: String?

    private var hasUnsavedConfig: Bool {
        url.trimmingCharacters(in: .whitespaces) != sync.webAppURL || token.trimmingCharacters(in: .whitespaces) != sync.token
    }

    var body: some View {
        Form {
            Section {
                TextField("https://script.google.com/macros/s/…/exec", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                SecureField("Token", text: $token)
                if hasUnsavedConfig {
                    Button("Save") {
                        sync.saveConfiguration(url: url, token: token)
                        url = sync.webAppURL
                        token = sync.token
                    }
                }
            } header: {
                Text("Google Sheet")
            } footer: {
                Text("""
                One-time setup: create a Google Sheet → Extensions › Apps Script → paste the script from \
                scripts/google-sheet/Code.gs → Project Settings › Script Properties: add TOKEN with a secret of your choice → \
                Deploy › New deployment › Web app (Execute as: Me, Who has access: Anyone) → paste the URL and the same token here.
                """)
            }

            if sync.isConfigured {
                Section("Status") {
                    LabeledContent("Last backed up") {
                        if let date = sync.lastSyncedAt {
                            Text(date, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                    }
                    LabeledContent("Waiting to upload", value: String(sync.pendingCount))
                    if sync.isSyncing {
                        HStack {
                            ProgressView()
                            Text("Syncing…").foregroundStyle(.secondary)
                        }
                    }
                    if let error = sync.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Back Up Now", systemImage: "icloud.and.arrow.up") {
                        Task { await sync.push() }
                    }
                    Button("Back Up Everything", systemImage: "square.stack.3d.up") {
                        Task { await sync.backupEverything() }
                    }
                } footer: {
                    Text("Changes back up automatically, including ones made offline once you're connected again. Use Back Up Everything the first time, to send all your existing data.")
                }

                Section {
                    Button("Update from Google Sheet", systemImage: "icloud.and.arrow.down") {
                        confirmingPull = true
                    }
                } footer: {
                    Text("Brings in rows added or edited in the sheet, and restores everything after a reinstall. To delete something from the sheet, set its deleted column to TRUE rather than removing the row.")
                }
                .disabled(sync.isSyncing)
            }
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sync.refreshPendingCount() }
        .confirmationDialog("Update from Google Sheet?", isPresented: $confirmingPull, titleVisibility: .visible) {
            Button("Update") { runPull() }
        } message: {
            Text("Anything newer in the sheet replaces what's in the app. Changes you've made in the app that haven't uploaded yet are kept.")
        }
        .alert("Updated from Google Sheet", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .alert("Couldn't update", isPresented: .constant(pullError != nil)) {
            Button("OK") { pullError = nil }
        } message: {
            Text(pullError ?? "")
        }
    }

    private func runPull() {
        Task {
            do {
                message = try await sync.pull().description
            } catch {
                pullError = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { BackupView() }
}

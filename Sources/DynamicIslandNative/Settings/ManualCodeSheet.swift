import AppKit
import SwiftUI

struct ManualCodeSheet: View {
    let pending: PendingManualAuth
    @ObservedObject var authStore: AuthStore
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProviderBadgeView(provider: pending.provider.appProvider, size: 24, iconSize: 14)
                Text("Connect \(pending.provider.displayName)").font(.headline)
            }

            Text("Finish signing in in the browser, copy the authorization code shown there, then paste it below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Reopen sign-in page") { NSWorkspace.shared.open(pending.authURL) }
                .buttonStyle(.link)

            TextField("Authorization code", text: $code)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .disabled(authStore.isConnecting(pending.provider))

            if let error = authStore.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { authStore.cancelManualAuth() }
                Spacer()
                if authStore.isConnecting(pending.provider) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Connect", action: submit)
                        .buttonStyle(.borderedProminent)
                        .tint(pending.provider.brandColor)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func submit() {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        authStore.submitManualCode(code)
    }
}

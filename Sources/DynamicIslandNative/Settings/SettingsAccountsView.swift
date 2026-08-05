import SwiftUI

struct SettingsAccountsView: View {
    @ObservedObject var authStore: AuthStore

    var body: some View {
        Form {
            Section("Subscription accounts") {
                ForEach(OAuthProvider.allCases) { provider in
                    accountRow(provider)
                }

                HStack(spacing: 12) {
                    ProviderBadgeView(provider: Provider.all.first(where: { $0.id == "cursor" })!, size: 26, iconSize: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor")
                        Text("Consumer subscription OAuth isn't available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("UNAVAILABLE")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }

            Section {
                Text("OAuth tokens are stored only in this Mac's Keychain. Claude, ChatGPT, and Gemini usage is fetched directly from their subscription APIs; no CLI installation is required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .formStyle(.grouped)
    }

    private func accountSubtitle(for provider: OAuthProvider) -> String {
        if let email = authStore.accountEmail(for: provider) { return email }
        if provider == .gemini { return "Google retired individual Gemini CLI OAuth" }
        return "Not connected"
    }

    private func accountRow(_ provider: OAuthProvider) -> some View {
        HStack(spacing: 12) {
            ProviderBadgeView(provider: provider.appProvider, size: 26, iconSize: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                Text(accountSubtitle(for: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if provider == .gemini {
                if authStore.isConnected(provider) {
                    Button("Disconnect") { authStore.disconnect(provider) }
                } else {
                    Text("UNAVAILABLE")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else if authStore.isConnecting(provider) {
                ProgressView().controlSize(.small)
            } else if authStore.isConnected(provider) {
                Button("Disconnect") { authStore.disconnect(provider) }
            } else {
                Button("Connect") { authStore.connect(provider) }
                    .buttonStyle(.borderedProminent)
                    .tint(provider.brandColor)
            }
        }
        .padding(.vertical, 3)
    }
}

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

    private func accountRow(_ provider: OAuthProvider) -> some View {
        HStack(spacing: 12) {
            ProviderBadgeView(provider: provider.appProvider, size: 26, iconSize: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                Text(authStore.accountEmail(for: provider) ?? "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if authStore.isConnecting(provider) {
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

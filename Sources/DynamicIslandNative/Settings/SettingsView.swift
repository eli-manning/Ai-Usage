import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var authStore: AuthStore

    var body: some View {
        TabView {
            Form {
                Section("Style") {
                    Picker("Notch style", selection: $preferences.style) {
                        ForEach(AppStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(preferences.style.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Text("Both styles read the same live subscription data — switching only changes how it's drawn.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            SettingsAccountsView(authStore: authStore)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
        }
        .frame(width: 520, height: 390)
        .sheet(item: $authStore.pendingManualAuth) { pending in
            ManualCodeSheet(pending: pending, authStore: authStore)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { authStore.lastError = nil }
        } message: {
            Text(authStore.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { authStore.lastError != nil && authStore.pendingManualAuth == nil },
            set: { if !$0 { authStore.lastError = nil } }
        )
    }
}

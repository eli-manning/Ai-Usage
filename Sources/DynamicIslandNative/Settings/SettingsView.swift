import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
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
                Text("Both styles read the same live usage data — switching here only changes how it's drawn.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420, height: 260)
        .formStyle(.grouped)
    }
}

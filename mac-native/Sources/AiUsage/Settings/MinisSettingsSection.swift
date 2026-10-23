import AppKit
import SwiftUI
import UsageCore

/// Settings for the minis: which providers are connected, how the critters
/// behave, and how they get your attention.
struct MinisSettingsSection: View {
    @ObservedObject var minis: MinisController
    @State private var error: String?
    @State private var followUp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(
                title: "Minis",
                caption: "A small critter for every running session, coloured by provider. Each provider's CLI reports to this app through a hook in its own config; nothing leaves your Mac."
            ) {
                VStack(spacing: 12) {
                    SettingRow(title: "Show minis", detail: minis.listening || !minis.config.enabled
                               ? "One per session, while it's open."
                               : "Couldn't listen on port \(HookServer.port) — is another copy running?") {
                        Toggle("", isOn: $minis.config.enabled).switchStyle()
                    }
                    providers
                    if let followUp {
                        Text(followUp).font(.system(size: 10.5)).foregroundStyle(Theme.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error {
                        Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            behaviour
            alerts
        }
    }

    // MARK: - Providers

    private var providers: some View {
        VStack(spacing: 0) {
            ForEach(Array(Provider.all.enumerated()), id: \.element.id) { index, p in
                HStack(spacing: 11) {
                    BrandIconView(d: p.iconPath, size: 17, color: p.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                        Text(status(p.id)).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    if minis.installed[p.id] == true {
                        Button("Test") { minis.test(p.id) }.buttonStyle(PillButtonStyle())
                        Button("Disconnect") { set(p, false) }.buttonStyle(PillButtonStyle())
                    } else if HookInstaller.canInstall(p.id) {
                        Button("Connect") { set(p, true) }.buttonStyle(PillButtonStyle())
                    }
                    Toggle("", isOn: Binding(
                        get: { minis.config.providerOn(p.id) },
                        set: { minis.config.providers[p.id] = $0 })).switchStyle()
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                if index < Provider.all.count - 1 { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1)))
        .disabled(!minis.config.enabled)
        .opacity(minis.config.enabled ? 1 : 0.5)
    }

    private func status(_ id: String) -> String {
        let live = minis.sessions.filter { $0.provider == id }.count
        if minis.installed[id] == true {
            return live == 0 ? "Connected." : "Connected — \(live) session\(live == 1 ? "" : "s") open."
        }
        return HookInstaller.canInstall(id) ? "Not connected." : "CLI hasn't been run on this Mac yet."
    }

    private func set(_ p: Provider, _ on: Bool) {
        do {
            try minis.setInstalled(p.id, on)
            error = nil
            followUp = on ? HookInstaller.targets[p.id]?.followUp.map { "\(p.name): \($0)" } : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Behaviour

    private var behaviour: some View {
        SettingsSection(title: "Mini behaviour", caption: nil) {
            VStack(spacing: 12) {
                SettingRow(title: "Speech", detail: "What the bubble says.") {
                    picker($minis.config.speech, MiniSpeech.allCases, \.title)
                }
                SettingRow(title: "Animation", detail: "Full is Mochi's original poses; Minimal is a status light with eyes.") {
                    picker(bind(\.animation), MiniAnimation.allCases, \.title)
                }
                SettingRow(title: "Movement", detail: "Drag a mini to put it somewhere else.") {
                    picker($minis.config.motion, MiniMotion.allCases, \.title)
                }
                SettingRow(title: "Line up along", detail: nil) {
                    picker($minis.config.placement, MiniPlacement.allCases, \.title)
                }
                SettingRow(title: "Size", detail: nil) {
                    Slider(value: $minis.config.scale, in: 1.5...4, step: 0.5).frame(width: 140)
                }
                SettingRow(title: "Remove idle minis after", detail: "Minis waiting on you always stay.") {
                    picker($minis.config.idleMinutes, [5, 10, 20, 60, 240], { "\(Int($0)) min" })
                }
            }
            .disabled(!minis.config.enabled)
        }
    }

    // MARK: - Alerts

    private var alerts: some View {
        SettingsSection(
            title: "Alerts",
            caption: "An alert holds until you reply in that session, or click the mini or its notification."
        ) {
            VStack(spacing: 12) {
                ForEach(AlertKind.allCases, id: \.self) { kind in
                    SettingRow(title: kind.title, detail: nil) {
                        HStack(spacing: 8) {
                            picker(Binding(get: { minis.config.sound(kind) },
                                           set: { minis.config.sounds[kind.rawValue] = $0 }),
                                   MinisConfig.soundChoices, { $0 })
                            Button { minis.previewSound(kind) } label: { Image(systemName: "speaker.wave.2") }
                                .buttonStyle(PillButtonStyle())
                            Toggle("", isOn: Binding(get: { minis.config.alerts(kind) },
                                                     set: { minis.config.alertOn[kind.rawValue] = $0 })).switchStyle()
                        }
                    }
                }
                SettingRow(title: "Repeat sound", detail: "Until you respond.") {
                    picker($minis.config.repeatSeconds, [0, 15, 30, 60, 120, 300],
                           { $0 == 0 ? "Once" : $0 < 60 ? "Every \(Int($0))s" : "Every \(Int($0 / 60)) min" })
                }
                SettingRow(title: "Volume", detail: nil) {
                    Slider(value: $minis.config.volume, in: 0...1).frame(width: 140)
                }
                SettingRow(title: "Notifications",
                           detail: "To keep them on screen until you act, set AI Usage to Alerts in System Settings.") {
                    HStack(spacing: 8) {
                        Button("Open") {
                            let id = Bundle.main.bundleIdentifier ?? "com.eli.aiusage"
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        Toggle("", isOn: $minis.config.notifications).switchStyle()
                    }
                }
            }
            .disabled(!minis.config.enabled)
        }
    }

    /// `$minis.config.animation` would resolve to Binding's own `animation(_:)`, hence this.
    private func bind<T>(_ key: WritableKeyPath<MinisConfig, T>) -> Binding<T> {
        Binding(get: { minis.config[keyPath: key] }, set: { minis.config[keyPath: key] = $0 })
    }

    private func picker<T: Hashable>(_ selection: Binding<T>, _ options: [T], _ label: @escaping (T) -> String) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// A title and caption on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            control
        }
    }
}

extension Toggle {
    func switchStyle() -> some View {
        labelsHidden().toggleStyle(.switch).tint(Theme.green)
    }
}

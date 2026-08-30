import AppKit
import SwiftUI
import UsageCore

/// First-run onboarding — the native replacement for `wizard.html`.
///
/// Same shape as the original (welcome → detection → other providers → login
/// item → done), with one step added: because this build can render in two
/// places, picking where is part of setting it up.
struct WizardView: View {
    @ObservedObject var usage: UsageService

    @State private var step = 0
    @State private var displayMode = Settings.shared.displayMode
    @State private var launchAtLogin = Settings.shared.launchAtLogin

    var onDisplayModeChange: (DisplayMode) -> Void
    var onFinish: () -> Void

    private var steps: [WizardStep] {
        var all: [WizardStep] = [.welcome, .claude, .providers]
        // No point asking where to draw when only one answer is possible.
        if NotchGeometry.hasHardwareNotch { all.append(.appearance) }
        all.append(contentsOf: [.login, .done])
        return all
    }

    private enum WizardStep { case welcome, claude, providers, appearance, login, done }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 34)

            footer
        }
        .frame(width: 460, height: 480)
        .background(Theme.bg)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch steps[step] {
        case .welcome:
            WizardPane(
                icon: "gauge.with.dots.needle.67percent",
                title: "Welcome to AI Usage",
                message: "Live quota for Claude, Antigravity, Codex and Cursor — read straight from the CLIs you already have installed. Nothing leaves your Mac.")

        case .claude:
            WizardPane(icon: "terminal", title: "Checking Claude Code") {
                DetectionCard(provider: Provider.all[0], status: usage.status("claude"), usage: usage)
            }

        case .providers:
            WizardPane(
                icon: "square.stack.3d.up",
                title: "Other providers",
                subtitle: "Anything not installed is simply skipped — you can add it later."
            ) {
                VStack(spacing: 8) {
                    ForEach(Provider.all.dropFirst()) { provider in
                        DetectionCard(
                            provider: provider, status: usage.status(provider.id), usage: usage)
                    }
                }
            }

        case .appearance:
            WizardPane(
                icon: "menubar.rectangle",
                title: "Where should it live?",
                subtitle: "You can change this any time in Settings."
            ) {
                VStack(spacing: 10) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        DisplayModeRow(
                            mode: mode, isSelected: displayMode == mode,
                            isAvailable: true, unavailableReason: nil
                        ) {
                            displayMode = mode
                            Settings.shared.displayMode = mode
                            onDisplayModeChange(mode)
                        }
                    }
                }
            }

        case .login:
            WizardPane(
                icon: "power",
                title: "Start automatically",
                subtitle: "Usage is only useful if it's already there when you look."
            ) {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        Settings.shared.launchAtLogin = newValue
                        LoginItem.setEnabled(newValue)
                    })
                ) {
                    Text("Open AI Usage when I log in")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text)
                }
                .toggleStyle(.switch)
                .tint(Theme.green)
            }

        case .done:
            WizardPane(
                icon: "checkmark.circle",
                title: "You're all set",
                message: displayMode == .notch
                    ? "Look just under the notch. Click the pill to fan out every provider."
                    : "Look for the badge in your menu bar. Click it any time to see your usage.")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                HStack(spacing: 5) {
                    ForEach(steps.indices, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Theme.text : Theme.dim)
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(PillButtonStyle())
                    }
                    if steps[step] == .claude || steps[step] == .providers {
                        Button("Recheck") { Task { await usage.refresh() } }
                            .buttonStyle(PillButtonStyle())
                    }
                    if step < steps.count - 1 {
                        Button(step == 0 ? "Get started" : "Continue") { step += 1 }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Finish") {
                            Settings.shared.setupComplete = true
                            onFinish()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Pieces

struct WizardPane<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    /// Named `message` rather than `body` — a stored property called `body`
    /// shadows `View`'s own requirement and the type stops conforming.
    var message: String? = nil
    @ViewBuilder var content: Content

    init(icon: String, title: String, subtitle: String? = nil, message: String? = nil,
         @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 16)
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .padding(.top, 18)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One provider's live detection state, with the action that unblocks it.
struct DetectionCard: View {
    let provider: Provider
    let status: ProviderStatus
    @ObservedObject var usage: UsageService

    var body: some View {
        HStack(spacing: 11) {
            BrandIconView(d: provider.iconPath, size: 16, color: provider.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(PillButtonStyle())
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.border, lineWidth: 1)))
    }

    private var label: String {
        switch status.state {
        case .checking: return "Looking…"
        case .notInstalled: return "Not installed."
        case .installed: return "Found it — sign in to read your usage."
        case .loggedIn:
            let pct = usage.primaryPct(provider.id)
            return pct.map { "Signed in — \($0)% used." } ?? "Signed in."
        case .error(let message): return message
        case .disabled: return "Turned off in Settings."
        }
    }

    private var tint: Color {
        switch status.state {
        case .loggedIn: return Theme.green
        case .error: return Theme.red
        case .installed: return Theme.yellow
        default: return Theme.muted
        }
    }

    private var icon: String {
        switch status.state {
        case .loggedIn: return "checkmark.circle.fill"
        case .checking: return "ellipsis.circle"
        default: return "circle.dashed"
        }
    }

    private var action: (title: String, run: () -> Void)? {
        switch status.state {
        case .notInstalled:
            if let command = provider.installCommand {
                return ("Install", { TerminalLauncher.run(command) })
            }
            return nil
        case .installed, .error:
            return provider.loginCommand.map { cmd in ("Log in", { TerminalLauncher.run(cmd) }) }
        default:
            return nil
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 15)
            .padding(.vertical, 6)
            .background(Capsule().fill(configuration.isPressed ? Theme.muted : Theme.text))
            .contentShape(Capsule())
    }
}

import AppKit
import SwiftUI

/// Ported from `notch-limits`' `NotchPanelController` — a panel that sits
/// directly over the physical notch and expands straight down into a card,
/// as opposed to the fan style's `PanelController`/`NotchPanel`, which sits
/// above the notch as a bar sliver. Shares the same injected `UsageService`
/// as the fan style, so switching styles never changes what data is shown.
@MainActor
final class PillPanelController {
    private var panel: NSPanel?
    private var hostingView: PillHostingView<PillRootView>?
    private let viewModel = PillViewModel()

    private let usage: UsageService
    private let onOpenSettings: () -> Void

    init(usage: UsageService, onOpenSettings: @escaping () -> Void) {
        self.usage = usage
        self.onOpenSettings = onOpenSettings

        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        rebuild()
        panel?.orderFrontRegardless()
    }

    /// Orders the panel out without tearing it down — switching back to
    /// this style later is just another `show()`, with whatever pin/expand
    /// state it had intact.
    func hide() {
        panel?.orderOut(nil)
    }

    @objc private func screenConfigurationChanged() {
        guard panel != nil else { return }
        rebuild()
    }

    private func rebuild() {
        guard let geometry = PillNotchGeometry.current() else { return }
        let layout = PillNotchLayout.make(from: geometry)

        let rootView = PillRootView(viewModel: viewModel, usage: usage, layout: layout, onOpenSettings: onOpenSettings)

        if panel == nil {
            let panel = NSPanel(
                contentRect: layout.panelFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Same reasoning as the fan style's `NotchPanel` doc comment —
            // `.mainMenu + 3` is what actually draws at the real menu
            // bar/notch's own layer on this Mac; `.statusBar` (what
            // notch-limits itself uses) sits a level below that.
            panel.level = .mainMenu + 3
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

            let hostingView = PillHostingView(rootView: rootView)
            hostingView.hitTestRegionProvider = { [weak self] in
                guard let self else { return .zero }
                return self.viewModel.isExpanded ? layout.expandedHitRect : layout.collapsedHitRect
            }
            hostingView.hoverRegionProvider = hostingView.hitTestRegionProvider
            hostingView.onHoverChanged = { [weak self] hovering in
                self?.viewModel.hoverChanged(hovering)
            }
            panel.contentView = hostingView

            self.panel = panel
            self.hostingView = hostingView
        } else {
            hostingView?.rootView = rootView
            hostingView?.hitTestRegionProvider = { [weak self] in
                guard let self else { return .zero }
                return self.viewModel.isExpanded ? layout.expandedHitRect : layout.collapsedHitRect
            }
            hostingView?.hoverRegionProvider = hostingView?.hitTestRegionProvider
        }

        panel?.setFrame(layout.panelFrame, display: true)
    }
}

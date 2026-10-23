import AppKit
import WebKit

/// Mochi's panel: a big pixel speech bubble (one of the Resources/web pages) in its own floating window, its tail
/// pointing at whatever opened it. The menu bar dropdown and the mini's panel are both one. This is the window and
/// the messages to and from the page; its owner decides what's in it and does what you click.
///
/// The page implements `panel.show(state, below)`, `panel.update(state)` and `panel.place(tailX, below)`, and posts
/// `{type: 'act' | 'tab' | 'size' | 'close'}` back (see mini-panel.js).
@MainActor
final class BubblePanel: NSObject, WKScriptMessageHandler {

    /// Takes key focus without activating the app, so Escape reaches the page.
    final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let window: KeyPanel
    private let web: Web.View
    private var monitors: [Any] = []
    private var timer: Timer?
    private var size = NSSize(width: 340, height: 300)   // the page reports its real size
    private var anchor = (x: CGFloat(0), top: CGFloat(0), feet: CGFloat(0))
    private var below = false
    private var tab: String?
    var state: () -> [String: Any] = { [:] }
    /// You clicked something: an action name and its argument.
    var act: (String, String?) -> Void = { _, _ in }
    var opened: (Bool) -> Void = { _ in }
    var isOpen: Bool { window.isVisible }

    init(page: String) {
        let cfg = WKWebViewConfiguration()
        web = Web.View(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        window = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless],
                          backing: .buffered, defer: false)
        super.init()
        cfg.userContentController.add(Web.WeakHandler(self), name: "panel")
        Web.load(page, in: web)
        window.contentView = web
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false   // the bubble draws its own pixel shadow
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Opens pointing at its anchor: `x` its middle, `top` just over it, `feet` under it (screen coordinates).
    /// Above if there's room, below if not. Showing it again while it's open closes it.
    func show(x: CGFloat, top: CGFloat, feet: CGFloat) {
        if isOpen { return close() }
        anchor = (x, top, feet)
        below = !fitsAbove(size.height)
        place()
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(web)
        var s = state()
        if let tab { s["tab"] = tab }
        web.evaluateJavaScript("panel.show(\(Web.json(s)), \(below))")
        opened(true)

        // nothing closes a borderless panel by itself: a click anywhere else does
        let outside: (NSEvent) -> Void = { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, e.window !== self.window else { return }
                self.close()
            }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: outside) { monitors.append(m) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// New numbers for the page; it only redraws when something changed.
    func update() {
        guard isOpen else { return }
        web.evaluateJavaScript("panel.update(\(Web.json(state())))")
    }

    func close() {
        guard isOpen else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        timer?.invalidate()
        timer = nil
        window.orderOut(nil)
        opened(false)
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "size":
            size = NSSize(width: body["w"] as? Double ?? size.width, height: body["h"] as? Double ?? size.height)
            if isOpen { place() }
        case "act":
            if let name = body["name"] as? String { act(name, body["arg"] as? String) }
        case "tab":
            tab = body["tab"] as? String
        case "close":
            close()
        default:
            break
        }
    }

    private func screen() -> NSRect {
        let p = NSPoint(x: anchor.x, y: anchor.feet - 1)
        return (NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    }

    private func fitsAbove(_ h: CGFloat) -> Bool { anchor.top + h <= screen().maxY }

    /// Above the anchor if there's room, under it if not; slid sideways to stay on screen, tail on the anchor.
    private func place() {
        let v = screen()
        let x = min(max(anchor.x - size.width / 2, v.minX + 4), v.maxX - size.width - 4)
        let y = min(max(below ? anchor.feet - size.height : anchor.top, v.minY), v.maxY - size.height)
        let tail = min(max(anchor.x - x, 28), size.width - 28)
        web.evaluateJavaScript("panel.place(\(Int(tail)), \(below))")
        window.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
    }
}

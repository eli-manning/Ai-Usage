import AppKit
import WebKit

/// What opens when you right-click the mini: Mochi's panel, a big pixel speech bubble (minis/panel.html) in its own
/// floating window with its tail pointing at the mini. This is the window and the messages to and from the page;
/// `MinisController` decides what's in it and does what you click.
@MainActor
final class MiniPanel: NSObject, WKScriptMessageHandler {

    /// Takes key focus without activating the app, so Escape reaches the page.
    final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let window: KeyPanel
    private let web: MiniWindow.WebView
    private var monitors: [Any] = []
    private var timer: Timer?
    private var size = NSSize(width: 340, height: 300)   // the page reports its real size
    private var mini = (x: CGFloat(0), top: CGFloat(0), feet: CGFloat(0))
    private var below = false
    private var tab: String?
    var state: () -> [String: Any] = { [:] }
    /// You clicked something: an action name and its argument.
    var act: (String, String?) -> Void = { _, _ in }
    /// The mini holds up a gear while it's open.
    var opened: (Bool) -> Void = { _ in }
    var isOpen: Bool { window.isVisible }

    init(webDir: URL?) {
        let cfg = WKWebViewConfiguration()
        web = MiniWindow.WebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        window = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless],
                          backing: .buffered, defer: false)
        super.init()
        cfg.userContentController.add(WeakHandler(self), name: "panel")
        if let webDir { web.loadFileURL(webDir.appendingPathComponent("panel.html"), allowingReadAccessTo: webDir) }
        window.contentView = web
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false   // the bubble draws its own pixel shadow
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Opens pointing at the mini: `x` its middle, `top` just over its head, `feet` under it (screen coordinates).
    /// Right-clicking the mini again closes it.
    func show(x: CGFloat, top: CGFloat, feet: CGFloat) {
        if isOpen { return close() }
        mini = (x, top, feet)
        below = !fitsAbove(size.height)
        place()
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(web)
        var s = state()
        if let tab { s["tab"] = tab }
        web.evaluateJavaScript("panel.show(\(Self.json(s)), \(below))")
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
        web.evaluateJavaScript("panel.update(\(Self.json(state())))")
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
        let p = NSPoint(x: mini.x, y: mini.feet + 1)
        return (NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    }

    private func fitsAbove(_ h: CGFloat) -> Bool { mini.top + h <= screen().maxY }

    /// Above the mini's head if there's room, under its feet if not; slid sideways to stay on screen, tail on the mini.
    private func place() {
        let v = screen()
        let x = min(max(mini.x - size.width / 2, v.minX + 4), v.maxX - size.width - 4)
        let y = min(max(below ? mini.feet - size.height : mini.top, v.minY), v.maxY - size.height)
        let tail = min(max(mini.x - x, 28), size.width - 28)
        web.evaluateJavaScript("panel.place(\(Int(tail)), \(below))")
        window.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
    }

    private static func json(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

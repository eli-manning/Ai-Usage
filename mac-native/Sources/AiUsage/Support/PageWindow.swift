import AppKit
import WebKit

/// A regular window (Settings, the setup wizard) showing one of the app's pages on Mochi's paper.
///
/// Same messages as `BubblePanel`, minus the tail: the app hands the page its state with `page.update(state)`
/// (first call draws it) and the page posts `{type: 'act', name, arg}` or `{type: 'close'}` to `page`.
@MainActor
final class PageWindow: NSObject, WKScriptMessageHandler, NSWindowDelegate {

    let window: NSWindow
    private let web: Web.View
    private var loaded = false
    private var timer: Timer?
    var state: () -> [String: Any] = { [:] }
    /// You clicked something: an action name and its argument.
    var act: (String, String?) -> Void = { _, _ in }
    var closed: () -> Void = {}

    /// The paper the pages are printed on (pet.css's --paper), so the title bar and any overscroll match.
    static let paper = NSColor(red: 1, green: 0.98, blue: 0.953, alpha: 1)

    init(page: String, title: String, size: NSSize) {
        let cfg = WKWebViewConfiguration()
        web = Web.View(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        cfg.userContentController.add(Web.WeakHandler(self), name: "page")
        Web.load(page, in: web)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Self.paper
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = web
        // An accessory-policy app has no Dock icon to restore a window from, so a released window would be
        // unreachable: keep it and reuse it.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func show() {
        // A menu-bar app isn't frontmost, and macOS may decline to activate it, so bring the window up regardless.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        update()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// New state for the page; it only redraws what changed.
    func update() {
        guard loaded, window.isVisible else { return }
        web.evaluateJavaScript("page.update(\(Web.json(state())))")
    }

    func close() { window.close() }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "ready":
            loaded = true
            update()
        case "act":
            if let name = body["name"] as? String { act(name, body["arg"] as? String) }
            update()
        case "close":
            close()
        default:
            break
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            timer?.invalidate()
            timer = nil
            closed()
        }
    }
}

import AppKit
import WebKit
import UsageCore

/// The borderless, always-on-top window the mini lives in.
///
/// Transparent everywhere but the critter and its bubble: the page reports
/// those areas (`hot`), and the window only takes the mouse while the pointer
/// is over one of them, so it never eats clicks meant for what's behind it.
@MainActor
final class MiniWindow: NSObject, WKScriptMessageHandler {

    final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    enum Action { case click, menu, moved }

    let id: String
    let panel: Panel
    private let web: Web.View
    private var hot: [CGRect] = []
    private var ready = false
    private var pending: [String: Any]?
    private var hovering = false
    private var dragOrigin: NSPoint?
    var onAction: ((Action) -> Void)?
    /// Set once the user drags it somewhere: it stops following the row.
    private(set) var pinned = false

    static func size(scale: Double) -> NSSize {
        let s = CGFloat(scale)
        return NSSize(width: max(46 * s, 170), height: max(34 * s, 25 * s + 34))
    }

    init(id: String, scale: Double) {
        self.id = id
        let size = Self.size(scale: scale)
        let cfg = WKWebViewConfiguration()
        web = Web.View(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        panel = Panel(contentRect: NSRect(origin: .zero, size: size),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        cfg.userContentController.add(Web.WeakHandler(self), name: "mini")
        web.setValue(false, forKey: "drawsBackground")
        Web.load("mini.html", in: web)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.contentView = web
    }

    func close() {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "mini")
        panel.orderOut(nil)
        panel.close()
    }

    /// Where its feet go, centred: the row layout and drags both work in feet.
    func place(foot: NSPoint) {
        let f = panel.frame
        let o = NSPoint(x: (foot.x - f.width / 2).rounded(), y: foot.y.rounded())
        if o != f.origin { panel.setFrameOrigin(o) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    var foot: NSPoint { NSPoint(x: panel.frame.midX, y: panel.frame.minY) }

    func resize(scale: Double) {
        let foot = self.foot
        let size = Self.size(scale: scale)
        guard size != panel.frame.size else { return }
        panel.setContentSize(size)
        web.frame = NSRect(origin: .zero, size: size)
        place(foot: foot)
    }

    func update(_ state: [String: Any]) {
        guard ready else { pending = state; return }
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.mini && mini.update(\(json))", completionHandler: nil)
    }

    /// Called often: decides whether the window takes the mouse right now.
    func trackMouse(_ m: NSPoint) {
        let f = panel.frame
        let p = CGPoint(x: m.x - f.minX, y: f.maxY - m.y)
        let inside = hot.contains { $0.insetBy(dx: -2, dy: -2).contains(p) }
        let take = inside || dragOrigin != nil
        if panel.ignoresMouseEvents == take { panel.ignoresMouseEvents = !take }
        if inside != hovering {
            hovering = inside
            web.evaluateJavaScript("window.mini && mini.hover(\(inside))", completionHandler: nil)
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            if let p = pending { pending = nil; update(p) }
        case "hot":
            hot = (body["rects"] as? [[Double]] ?? []).compactMap { r in
                r.count == 4 ? CGRect(x: r[0], y: r[1], width: r[2], height: r[3]) : nil
            }
        case "dragStart":
            dragOrigin = panel.frame.origin
        case "drag":
            guard let o = dragOrigin else { return }
            let dx = body["dx"] as? Double ?? 0, dy = body["dy"] as? Double ?? 0
            panel.setFrameOrigin(NSPoint(x: o.x + dx, y: o.y - dy))
        case "dragEnd":
            dragOrigin = nil
            pinned = true
            onAction?(.moved)
        case "click":
            onAction?(.click)
        case "menu":
            onAction?(.menu)
        default:
            break
        }
    }
}
